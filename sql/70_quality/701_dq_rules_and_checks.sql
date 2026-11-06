/* =============================================================================
   701_dq_rules_and_checks.sql
   Data-quality rule catalogue (meta.dq_rule) and the procedure that runs all
   checks and stores the results (meta.dq_result).

   Every rule counts "failed rows". 0 = PASS. Categories:
     VALIDITY        a value has the wrong format (check digits, codes)
     CONSISTENCY     rows contradict each other (overlaps, dates, references)
     COMPLETENESS    something got lost between layers
     RECONCILIATION  two independent sources must agree (Bescheid vs. lines)
     BUSINESS_RULE   not a data error but a FINDING for a KV department
                     (e.g. GOP billed without permit) - these are expected > 0.

   Usage:  EXEC meta.usp_run_dq_checks;   then look at meta.v_dq_latest
   ============================================================================= */
USE KVSim;
GO

/* ---------- rule catalogue (re-runnable upsert) ------------------------------------- */
-- For a small static list, MERGE (update-or-insert in one statement) is fine and short.
-- The load procedures use separate UPDATE + INSERT instead - see 401_load_referenz.sql.
MERGE INTO meta.dq_rule AS t
USING (VALUES
 ('DQ01', N'LANR check digit invalid',                                   'VALIDITY',       'ERROR',   N'core.arzt',               N'Digit 7 of the LANR must equal the check digit computed from digits 1-6 (weights 4,9,4,9,4,9).'),
 ('DQ02', N'BSNR outside KV Saarland',                                   'VALIDITY',       'ERROR',   N'core.praxis',             N'Every BSNR of this KV must start with the KV code 73.'),
 ('DQ03', N'Overlapping Teilnahmen of one doctor',                       'CONSISTENCY',    'ERROR',   N'core.teilnahme',          N'This model allows one Teilnahme per doctor at a time; overlapping intervals would double-count Anrechnungsfaktoren.'),
 ('DQ04', N'Status history with gaps or overlaps',                       'CONSISTENCY',    'ERROR',   N'core.teilnahme_status',   N'Status periods must start at the Teilnahme start and follow each other without gap or overlap.'),
 ('DQ05', N'Service by a doctor not active at the practice',             'CONSISTENCY',    'ERROR',   N'core.leistung',           N'The billing doctor needs an AKTIV Teilnahme at the practice on the service date.'),
 ('DQ06', N'Service date outside the quarter of the case',               'CONSISTENCY',    'ERROR',   N'core.leistung',           N'A Behandlungsfall belongs to one quarter; all its services must lie in that quarter.'),
 ('DQ07', N'Billing rows lost between stg and core',                     'COMPLETENESS',   'ERROR',   N'stg.abrechnung_* -> core', N'Rows in staging that did not reach core (e.g. unknown LANR, GOP or ICD in the lookups).'),
 ('DQ08', N'Documents without any link',                                 'COMPLETENESS',   'WARNING', N'core.dokument',           N'Every document should be linked to at least one doctor, practice or procedure.'),
 ('DQ09', N'Honorarbescheid points differ from billed points',           'RECONCILIATION', 'ERROR',   N'core.honorarbescheid',    N'Requested points in the Bescheid must equal the sum of anzahl * punktzahl of the billing lines.'),
 ('DQ10', N'Advance payments differ from the Bescheid',                  'RECONCILIATION', 'ERROR',   N'core.abschlagszahlung',   N'Payments booked in the finance system must equal the Abschlaege stated in the Bescheid.'),
 ('DQ11', N'Official Versorgungsgrad differs from the register',         'RECONCILIATION', 'ERROR',   N'core.versorgungsgrad',    N'Ist (sum of Anrechnungsfaktoren on the Stichtag) recomputed from core.teilnahme must match the decided figure.'),
 ('DQ12', N'QS-GOP billed without valid Genehmigung',                    'BUSINESS_RULE',  'WARNING', N'core.leistung',           N'Finding for the QS department: GOPs that require a permit, billed by a doctor without a valid permit on that day.'),
 ('DQ13', N'Corrected points differ from QS findings',                   'RECONCILIATION', 'ERROR',   N'core.honorarbescheid',    N'punkte_berichtigt in the Bescheid should equal the points of the QS findings (DQ12) of that practice and quarter.'),
 ('DQ14', N'Fortbildung below 250 points (2021-2025)',                   'BUSINESS_RULE',  'INFO',    N'core.fortbildungspunkte', N'Doctors participating since before 2021 with fewer than 250 CME points in the 5-year period (§ 95d SGB V).'),
 ('DQ15', N'Prescriptions > 125 % of Richtgröße without audit',          'BUSINESS_RULE',  'WARNING', N'core.verordnung',         N'Practice-quarters whose prescription costs exceed 125 % of the Richtgrößenvolumen but have no Prüfverfahren.'),
 ('DQ16', N'TSS appointment before the request',                         'CONSISTENCY',    'ERROR',   N'core.tss_anfrage',        N'An appointment cannot be earlier than the request that arranged it.'),
 ('DQ17', N'Out-of-hours shift by a doctor not eligible',                'CONSISTENCY',    'ERROR',   N'core.bereitschaftsdienst',N'The doctor must be AKTIV at a practice in the Kreis of the Bereitschaftspraxis that day, and not a psychotherapist.'),
 ('DQ18', N'TSS code in billing without TSS request',                    'CONSISTENCY',    'ERROR',   N'core.abrechnungsfall',    N'Every Vermittlungscode on a billing case must exist in the TSS data.')
) AS s (rule_code, rule_name, category, severity, checked_object, description)
ON t.rule_code = s.rule_code
WHEN MATCHED THEN UPDATE SET rule_name = s.rule_name, category = s.category, severity = s.severity,
                             checked_object = s.checked_object, description = s.description
WHEN NOT MATCHED THEN INSERT (rule_code, rule_name, category, severity, checked_object, description)
                      VALUES (s.rule_code, s.rule_name, s.category, s.severity, s.checked_object, s.description);
GO

-- Results of the most recent run, with the rule description
CREATE OR ALTER VIEW meta.v_dq_latest
AS
SELECT r.run_id, r.rule_code, d.rule_name, d.category, d.severity, r.failed_rows, r.result, r.checked_at
FROM meta.dq_result AS r
JOIN meta.dq_rule AS d ON d.rule_code = r.rule_code
WHERE r.run_id = (SELECT MAX(run_id) FROM meta.dq_result);
GO

/* ---------- the checks --------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE meta.usp_run_dq_checks
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id INT;
    INSERT INTO meta.dq_run (batch_id) VALUES (meta.fn_latest_batch_id());
    SET @run_id = CAST(SCOPE_IDENTITY() AS INT);

    DECLARE @r TABLE (rule_code VARCHAR(10) PRIMARY KEY, failed_rows INT NOT NULL);

    -- DQ01: LANR check digit
    INSERT INTO @r SELECT 'DQ01', COUNT(*) FROM core.arzt
    WHERE core.fn_lanr_pruefziffer(lanr) <> CAST(SUBSTRING(lanr, 7, 1) AS TINYINT);

    -- DQ02: BSNR prefix
    INSERT INTO @r SELECT 'DQ02', COUNT(*) FROM core.praxis WHERE LEFT(bsnr, 2) <> '73';

    -- DQ03: overlapping intervals: a starts before b ends AND b starts before a ends
    INSERT INTO @r SELECT 'DQ03', COUNT(*)
    FROM core.teilnahme AS a
    JOIN core.teilnahme AS b
      ON b.arzt_id = a.arzt_id AND a.teilnahme_id < b.teilnahme_id
     AND a.valid_from < b.valid_to AND b.valid_from < a.valid_to;

    -- DQ04: gapless status history (LAG = value of the previous row)
    WITH s AS (
        SELECT teilnahme_id, valid_from,
               LAG(valid_to) OVER (PARTITION BY teilnahme_id ORDER BY valid_from)  AS prev_valid_to,
               ROW_NUMBER()  OVER (PARTITION BY teilnahme_id ORDER BY valid_from)  AS rn
        FROM core.teilnahme_status
    )
    INSERT INTO @r SELECT 'DQ04',
        (SELECT COUNT(*) FROM s JOIN core.teilnahme AS t ON t.teilnahme_id = s.teilnahme_id
         WHERE (s.rn = 1 AND s.valid_from <> t.valid_from) OR (s.rn > 1 AND s.valid_from <> s.prev_valid_to))
      + (SELECT COUNT(*) FROM core.teilnahme AS t
         WHERE NOT EXISTS (SELECT 1 FROM core.teilnahme_status AS x WHERE x.teilnahme_id = t.teilnahme_id));

    -- DQ05: billing doctor active at the practice on the service date
    INSERT INTO @r SELECT 'DQ05', COUNT(*)
    FROM core.leistung AS l
    JOIN core.abrechnungsfall AS f ON f.fall_id = l.fall_id
    WHERE NOT EXISTS (
        SELECT 1 FROM core.teilnahme AS t
        JOIN core.teilnahme_status AS s ON s.teilnahme_id = t.teilnahme_id
        WHERE t.arzt_id = l.arzt_id AND t.praxis_id = f.praxis_id AND s.status_code = 'AKTIV'
          AND l.leistungsdatum >= s.valid_from AND l.leistungsdatum < s.valid_to);

    -- DQ06: service date within the quarter
    INSERT INTO @r SELECT 'DQ06', COUNT(*)
    FROM core.leistung AS l
    JOIN core.abrechnungsfall AS f ON f.fall_id = l.fall_id
    JOIN core.quartal AS q ON q.quartal_code = f.quartal_code
    WHERE l.leistungsdatum NOT BETWEEN q.erster_tag AND q.letzter_tag;

    -- DQ07: completeness stg -> core for the quarters in staging
    INSERT INTO @r SELECT 'DQ07',
        ABS((SELECT COUNT(*) FROM stg.abrechnung_faelle)
          - (SELECT COUNT(*) FROM core.abrechnungsfall AS f
             WHERE f.quartal_code IN (SELECT CONCAT(RIGHT(quartal, 4), 'Q', LEFT(quartal, 1)) FROM stg.abrechnung_faelle)))
      + ABS((SELECT COUNT(*) FROM stg.abrechnung_leistungen)
          - (SELECT COUNT(*) FROM core.leistung AS l JOIN core.abrechnungsfall AS f ON f.fall_id = l.fall_id
             WHERE f.quartal_code IN (SELECT CONCAT(RIGHT(quartal, 4), 'Q', LEFT(quartal, 1)) FROM stg.abrechnung_faelle)))
      + ABS((SELECT COUNT(*) FROM stg.abrechnung_diagnosen)
          - (SELECT COUNT(*) FROM core.fall_diagnose AS d JOIN core.abrechnungsfall AS f ON f.fall_id = d.fall_id
             WHERE f.quartal_code IN (SELECT CONCAT(RIGHT(quartal, 4), 'Q', LEFT(quartal, 1)) FROM stg.abrechnung_faelle)));

    -- DQ08: documents without links
    INSERT INTO @r SELECT 'DQ08', COUNT(*) FROM core.dokument AS d
    WHERE NOT EXISTS (SELECT 1 FROM core.dokument_bezug AS b WHERE b.dokument_id = d.dokument_id);

    -- DQ09: Bescheid points vs. billing lines
    INSERT INTO @r SELECT 'DQ09', COUNT(*)
    FROM core.honorarbescheid AS h
    LEFT JOIN (
        SELECT f.praxis_id, f.quartal_code, SUM(l.anzahl * l.punktzahl) AS punkte
        FROM core.leistung AS l JOIN core.abrechnungsfall AS f ON f.fall_id = l.fall_id
        GROUP BY f.praxis_id, f.quartal_code
    ) AS x ON x.praxis_id = h.praxis_id AND x.quartal_code = h.quartal_code
    WHERE h.punkte_angefordert <> COALESCE(x.punkte, 0);

    -- DQ10: payments vs. Bescheid
    INSERT INTO @r SELECT 'DQ10', COUNT(*)
    FROM core.honorarbescheid AS h
    LEFT JOIN (SELECT praxis_id, quartal_code, SUM(betrag) AS betrag FROM core.abschlagszahlung GROUP BY praxis_id, quartal_code) AS z
      ON z.praxis_id = h.praxis_id AND z.quartal_code = h.quartal_code
    WHERE h.abschlaege <> COALESCE(z.betrag, 0);

    -- DQ11: official Ist vs. register
    INSERT INTO @r SELECT 'DQ11', COUNT(*)
    FROM core.versorgungsgrad AS v
    OUTER APPLY (
        SELECT SUM(t.anrechnungsfaktor) AS ist
        FROM core.teilnahme AS t
        JOIN core.arzt AS a ON a.arzt_id = t.arzt_id
        JOIN core.fachgruppe AS fg ON fg.fachgruppe_code = a.fachgruppe_code
        JOIN core.praxis AS p ON p.praxis_id = t.praxis_id
        JOIN core.planungsbereich_kreis AS pk ON pk.kreis_id = p.kreis_id
        WHERE pk.planungsbereich_id = v.planungsbereich_id AND fg.arztgruppe_code = v.arztgruppe_code
          AND v.stichtag >= t.valid_from AND v.stichtag < t.valid_to
    ) AS ber
    WHERE v.ist_aerzte <> COALESCE(ber.ist, 0);

    -- DQ12: QS-GOP without valid permit (findings)
    INSERT INTO @r SELECT 'DQ12', COUNT(*)
    FROM core.leistung AS l
    JOIN core.gop AS g ON g.gop_id = l.gop_id
    WHERE g.qs_bereich_code IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM core.qs_genehmigung AS q
                      WHERE q.arzt_id = l.arzt_id AND q.qs_bereich_code = g.qs_bereich_code
                        AND l.leistungsdatum >= q.valid_from AND l.leistungsdatum < q.valid_to);

    -- DQ13: corrected points in the Bescheid vs. our own QS findings
    WITH befund AS (
        SELECT f.praxis_id, f.quartal_code, SUM(l.anzahl * l.punktzahl) AS punkte
        FROM core.leistung AS l
        JOIN core.abrechnungsfall AS f ON f.fall_id = l.fall_id
        JOIN core.gop AS g ON g.gop_id = l.gop_id
        WHERE g.qs_bereich_code IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM core.qs_genehmigung AS q
                          WHERE q.arzt_id = l.arzt_id AND q.qs_bereich_code = g.qs_bereich_code
                            AND l.leistungsdatum >= q.valid_from AND l.leistungsdatum < q.valid_to)
        GROUP BY f.praxis_id, f.quartal_code
    )
    INSERT INTO @r SELECT 'DQ13', COUNT(*)
    FROM core.honorarbescheid AS h
    LEFT JOIN befund AS b ON b.praxis_id = h.praxis_id AND b.quartal_code = h.quartal_code
    WHERE h.punkte_berichtigt <> COALESCE(b.punkte, 0);

    -- DQ14: CME points
    INSERT INTO @r SELECT 'DQ14', COUNT(*)
    FROM (
        SELECT fp.arzt_id
        FROM core.fortbildungspunkte AS fp
        WHERE fp.jahr BETWEEN 2021 AND 2025
          AND fp.arzt_id IN (SELECT arzt_id FROM core.teilnahme GROUP BY arzt_id HAVING MIN(valid_from) < '2021-01-01')
        GROUP BY fp.arzt_id
        HAVING SUM(fp.punkte) < 250
    ) AS x;

    -- DQ15: prescriptions above 125 % of the Richtgroessenvolumen without audit
    WITH rgv AS (
        SELECT f.praxis_id, f.quartal_code, r.verordnungsart, SUM(r.euro_je_fall) AS volumen
        FROM core.abrechnungsfall AS f
        JOIN core.leistung AS l ON l.fall_id = f.fall_id AND l.positions_nr = 1    -- Hauptbehandler
        JOIN core.arzt AS a ON a.arzt_id = l.arzt_id
        JOIN core.fachgruppe AS fg ON fg.fachgruppe_code = a.fachgruppe_code
        JOIN core.quartal AS q ON q.quartal_code = f.quartal_code
        JOIN core.richtgroesse AS r ON r.arztgruppe_code = fg.arztgruppe_code AND r.jahr = q.jahr
        GROUP BY f.praxis_id, f.quartal_code, r.verordnungsart
    )
    INSERT INTO @r SELECT 'DQ15', COUNT(*)
    FROM core.verordnung AS v
    JOIN rgv ON rgv.praxis_id = v.praxis_id AND rgv.quartal_code = v.quartal_code AND rgv.verordnungsart = v.verordnungsart
    WHERE v.brutto_betrag > 1.25 * rgv.volumen
      AND NOT EXISTS (SELECT 1 FROM core.pruefverfahren AS p
                      WHERE p.praxis_id = v.praxis_id AND p.quartal_code = v.quartal_code
                        AND p.pruefgegenstand = IIF(v.verordnungsart = 'A', 'ARZNEIMITTEL', 'HEILMITTEL'));

    -- DQ16: appointment before request
    INSERT INTO @r SELECT 'DQ16', COUNT(*) FROM core.tss_anfrage WHERE termin_zeitpunkt < eingang_zeitpunkt;

    -- DQ17: eligible out-of-hours doctor
    INSERT INTO @r SELECT 'DQ17', COUNT(*)
    FROM core.bereitschaftsdienst AS b
    JOIN core.notfallpraxis AS np ON np.notfallpraxis_id = b.notfallpraxis_id
    JOIN core.arzt AS a ON a.arzt_id = b.arzt_id
    WHERE a.fachgruppe_code = '68'
       OR NOT EXISTS (
            SELECT 1 FROM core.teilnahme AS t
            JOIN core.teilnahme_status AS s ON s.teilnahme_id = t.teilnahme_id
            JOIN core.praxis AS p ON p.praxis_id = t.praxis_id
            WHERE t.arzt_id = b.arzt_id AND p.kreis_id = np.kreis_id AND s.status_code = 'AKTIV'
              AND CAST(b.beginn AS DATE) >= s.valid_from AND CAST(b.beginn AS DATE) < s.valid_to);

    -- DQ18: TSS codes in billing must exist in TSS data
    INSERT INTO @r SELECT 'DQ18', COUNT(*)
    FROM core.abrechnungsfall AS f
    WHERE f.tss_vermittlungscode IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM core.tss_anfrage AS t WHERE t.vermittlungscode = f.tss_vermittlungscode);

    INSERT INTO meta.dq_result (run_id, rule_code, failed_rows, result)
    SELECT @run_id, rule_code, failed_rows, IIF(failed_rows = 0, 'PASS', 'FAIL') FROM @r;
    UPDATE meta.dq_run SET finished_at = SYSDATETIME() WHERE run_id = @run_id;

    SELECT * FROM meta.v_dq_latest ORDER BY rule_code;
END
GO
