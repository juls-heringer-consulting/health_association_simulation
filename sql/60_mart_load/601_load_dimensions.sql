/* =============================================================================
   601_load_dimensions.sql
   mart.usp_load_dimensions: fills all dimensions from core.
     * type-1 dimensions: upsert by the durable core id -> surrogate keys stay stable
     * dim_arzt (SCD2): one version per Teilnahme, built from the valid-time
       history that core already holds (see concept note 07)
   Call it through mart.usp_load_all (facts must be empty when versions change).
   ============================================================================= */
USE KVSim;
GO

CREATE OR ALTER PROCEDURE mart.usp_load_dimensions
    @batch_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @batch_id = COALESCE(@batch_id, meta.fn_latest_batch_id());
    DECLARE @step_id INT, @rows INT = 0;
    EXEC meta.usp_step_start @batch_id = @batch_id, @step_name = N'mart.usp_load_dimensions', @step_id = @step_id OUTPUT;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* ---------- dim_datum: generated calendar 2024-2026 (static, insert missing days) ---- */
        WITH tage AS (
            SELECT CAST('2024-01-01' AS DATE) AS d
            UNION ALL
            SELECT DATEADD(DAY, 1, d) FROM tage WHERE d < '2026-12-31'
        ),
        feiertage AS (   -- public holidays in the Saarland
            SELECT CAST(datum AS DATE) AS datum, name FROM (VALUES
                ('2024-01-01', N'Neujahr'), ('2024-03-29', N'Karfreitag'), ('2024-04-01', N'Ostermontag'),
                ('2024-05-01', N'Tag der Arbeit'), ('2024-05-09', N'Christi Himmelfahrt'), ('2024-05-20', N'Pfingstmontag'),
                ('2024-05-30', N'Fronleichnam'), ('2024-08-15', N'Mariä Himmelfahrt'), ('2024-10-03', N'Tag der Deutschen Einheit'),
                ('2024-11-01', N'Allerheiligen'), ('2024-12-25', N'1. Weihnachtsfeiertag'), ('2024-12-26', N'2. Weihnachtsfeiertag'),
                ('2025-01-01', N'Neujahr'), ('2025-04-18', N'Karfreitag'), ('2025-04-21', N'Ostermontag'),
                ('2025-05-01', N'Tag der Arbeit'), ('2025-05-29', N'Christi Himmelfahrt'), ('2025-06-09', N'Pfingstmontag'),
                ('2025-06-19', N'Fronleichnam'), ('2025-08-15', N'Mariä Himmelfahrt'), ('2025-10-03', N'Tag der Deutschen Einheit'),
                ('2025-11-01', N'Allerheiligen'), ('2025-12-25', N'1. Weihnachtsfeiertag'), ('2025-12-26', N'2. Weihnachtsfeiertag'),
                ('2026-01-01', N'Neujahr'), ('2026-04-03', N'Karfreitag'), ('2026-04-06', N'Ostermontag'),
                ('2026-05-01', N'Tag der Arbeit'), ('2026-05-14', N'Christi Himmelfahrt'), ('2026-05-25', N'Pfingstmontag'),
                ('2026-06-04', N'Fronleichnam'), ('2026-08-15', N'Mariä Himmelfahrt'), ('2026-10-03', N'Tag der Deutschen Einheit'),
                ('2026-11-01', N'Allerheiligen'), ('2026-12-25', N'1. Weihnachtsfeiertag'), ('2026-12-26', N'2. Weihnachtsfeiertag')
            ) AS v (datum, name)
        )
        INSERT INTO mart.dim_datum (datum_key, datum, jahr, quartal_nr, quartal_code, monat_nr, monat_name, kalenderwoche,
                                    wochentag_nr, wochentag_name, ist_wochenende, ist_feiertag, feiertag_name)
        SELECT CONVERT(INT, CONVERT(CHAR(8), t.d, 112)), t.d, YEAR(t.d), DATEPART(QUARTER, t.d),
               CONCAT(YEAR(t.d), 'Q', DATEPART(QUARTER, t.d)), MONTH(t.d),
               CHOOSE(MONTH(t.d), N'Januar', N'Februar', N'März', N'April', N'Mai', N'Juni', N'Juli',
                                  N'August', N'September', N'Oktober', N'November', N'Dezember'),
               DATEPART(ISO_WEEK, t.d),
               w.nr,   -- 1 = Monday, independent of the server setting SET DATEFIRST
               CHOOSE(w.nr, N'Montag', N'Dienstag', N'Mittwoch', N'Donnerstag', N'Freitag', N'Samstag', N'Sonntag'),
               IIF(w.nr >= 6, 1, 0), IIF(f.datum IS NULL, 0, 1), f.name
        FROM tage AS t
        CROSS APPLY (SELECT DATEDIFF(DAY, '19000101', t.d) % 7 + 1 AS nr) AS w    -- 1900-01-01 was a Monday
        LEFT JOIN feiertage AS f ON f.datum = t.d
        WHERE NOT EXISTS (SELECT 1 FROM mart.dim_datum AS x WHERE x.datum = t.d)
        OPTION (MAXRECURSION 0);    -- the recursive CTE produces > 100 rows
        SET @rows += @@ROWCOUNT;

        /* ---------- dim_quartal ------------------------------------------------------------ */
        INSERT INTO mart.dim_quartal (quartal_key, quartal_code, quartal_label, jahr, quartal_nr, erster_tag, letzter_tag)
        SELECT q.jahr * 10 + q.quartal_nr, q.quartal_code, CONCAT(q.quartal_nr, '/', q.jahr), q.jahr, q.quartal_nr, q.erster_tag, q.letzter_tag
        FROM core.quartal AS q
        WHERE NOT EXISTS (SELECT 1 FROM mart.dim_quartal AS d WHERE d.quartal_code = q.quartal_code);
        SET @rows += @@ROWCOUNT;

        /* ---------- dim_region ------------------------------------------------------------- */
        DROP TABLE IF EXISTS #region;
        SELECT k.kreis_id, k.ags, k.name AS kreis, k.kreisart, k.verwaltungssitz, pb.planungsbereich_code,
               N'Saarland' AS land, k.geo_breite, k.geo_laenge
        INTO #region
        FROM core.kreis AS k
        LEFT JOIN core.planungsbereich_kreis AS pk ON pk.kreis_id = k.kreis_id
        LEFT JOIN core.planungsbereich AS pb ON pb.planungsbereich_id = pk.planungsbereich_id AND pb.typ = 'KREIS'
        WHERE pb.planungsbereich_id IS NOT NULL OR pk.planungsbereich_id IS NULL;

        UPDATE d SET ags = s.ags, kreis = s.kreis, kreisart = s.kreisart, verwaltungssitz = s.verwaltungssitz,
                     planungsbereich_code = s.planungsbereich_code, land = s.land, geo_breite = s.geo_breite, geo_laenge = s.geo_laenge
        FROM mart.dim_region AS d JOIN #region AS s ON s.kreis_id = d.kreis_id;
        INSERT INTO mart.dim_region (kreis_id, ags, kreis, kreisart, verwaltungssitz, planungsbereich_code, land, geo_breite, geo_laenge)
        SELECT s.kreis_id, s.ags, s.kreis, s.kreisart, s.verwaltungssitz, s.planungsbereich_code, s.land, s.geo_breite, s.geo_laenge
        FROM #region AS s WHERE NOT EXISTS (SELECT 1 FROM mart.dim_region AS d WHERE d.kreis_id = s.kreis_id);
        SET @rows += @@ROWCOUNT;

        /* ---------- dim_arztgruppe / dim_fachgruppe -------------------------------------------- */
        UPDATE d SET arztgruppe = s.bezeichnung, versorgungsebene = s.versorgungsebene,
                     planungsbereich_typ = s.planungsbereich_typ, verhaeltniszahl = s.verhaeltniszahl
        FROM mart.dim_arztgruppe AS d JOIN core.arztgruppe AS s ON s.arztgruppe_code = d.arztgruppe_code;
        INSERT INTO mart.dim_arztgruppe (arztgruppe_code, arztgruppe, versorgungsebene, planungsbereich_typ, verhaeltniszahl)
        SELECT s.arztgruppe_code, s.bezeichnung, s.versorgungsebene, s.planungsbereich_typ, s.verhaeltniszahl
        FROM core.arztgruppe AS s WHERE NOT EXISTS (SELECT 1 FROM mart.dim_arztgruppe AS d WHERE d.arztgruppe_code = s.arztgruppe_code);
        SET @rows += @@ROWCOUNT;

        UPDATE d SET fachgruppe = s.bezeichnung, arztgruppe_code = s.arztgruppe_code, arztgruppe = ag.bezeichnung,
                     versorgungsebene = ag.versorgungsebene
        FROM mart.dim_fachgruppe AS d
        JOIN core.fachgruppe AS s ON s.fachgruppe_code = d.fachgruppe_code
        LEFT JOIN core.arztgruppe AS ag ON ag.arztgruppe_code = s.arztgruppe_code;
        INSERT INTO mart.dim_fachgruppe (fachgruppe_code, fachgruppe, arztgruppe_code, arztgruppe, versorgungsebene)
        SELECT s.fachgruppe_code, s.bezeichnung, s.arztgruppe_code, ag.bezeichnung, ag.versorgungsebene
        FROM core.fachgruppe AS s
        LEFT JOIN core.arztgruppe AS ag ON ag.arztgruppe_code = s.arztgruppe_code
        WHERE NOT EXISTS (SELECT 1 FROM mart.dim_fachgruppe AS d WHERE d.fachgruppe_code = s.fachgruppe_code);
        SET @rows += @@ROWCOUNT;

        /* ---------- dim_praxis (type 1) --------------------------------------------------------- */
        DROP TABLE IF EXISTS #praxis;
        SELECT p.praxis_id, p.bsnr, p.name AS praxis_name, p.kooperationsform_code, kf.bezeichnung AS kooperationsform,
               p.ort, k.name AS kreis, p.gruendungsdatum
        INTO #praxis
        FROM core.praxis AS p
        JOIN core.kooperationsform AS kf ON kf.kooperationsform_code = p.kooperationsform_code
        JOIN core.kreis AS k ON k.kreis_id = p.kreis_id;

        UPDATE d SET bsnr = s.bsnr, praxis_name = s.praxis_name, kooperationsform_code = s.kooperationsform_code,
                     kooperationsform = s.kooperationsform, ort = s.ort, kreis = s.kreis, gruendungsdatum = s.gruendungsdatum
        FROM mart.dim_praxis AS d JOIN #praxis AS s ON s.praxis_id = d.praxis_id;
        INSERT INTO mart.dim_praxis (praxis_id, bsnr, praxis_name, kooperationsform_code, kooperationsform, ort, kreis, gruendungsdatum)
        SELECT s.praxis_id, s.bsnr, s.praxis_name, s.kooperationsform_code, s.kooperationsform, s.ort, s.kreis, s.gruendungsdatum
        FROM #praxis AS s WHERE NOT EXISTS (SELECT 1 FROM mart.dim_praxis AS d WHERE d.praxis_id = s.praxis_id);
        SET @rows += @@ROWCOUNT;

        /* ---------- dim_krankenkasse, dim_gop, dim_altersgruppe, dim_planungsbereich ------------- */
        UPDATE d SET ik = s.ik, krankenkasse = s.name, kassenart_code = s.kassenart_code, kassenart = ka.bezeichnung
        FROM mart.dim_krankenkasse AS d
        JOIN core.krankenkasse AS s ON s.krankenkasse_id = d.krankenkasse_id
        JOIN core.kassenart AS ka ON ka.kassenart_code = s.kassenart_code;
        INSERT INTO mart.dim_krankenkasse (krankenkasse_id, ik, krankenkasse, kassenart_code, kassenart)
        SELECT s.krankenkasse_id, s.ik, s.name, s.kassenart_code, ka.bezeichnung
        FROM core.krankenkasse AS s JOIN core.kassenart AS ka ON ka.kassenart_code = s.kassenart_code
        WHERE NOT EXISTS (SELECT 1 FROM mart.dim_krankenkasse AS d WHERE d.krankenkasse_id = s.krankenkasse_id);
        SET @rows += @@ROWCOUNT;

        DROP TABLE IF EXISTS #gop;
        SELECT g.gop_id, g.gop_code, g.bezeichnung AS gop, g.kapitel_nr, k.bezeichnung AS kapitel, k.bereich AS ebm_bereich,
               g.punktzahl, g.pruefzeit_min, g.ist_extrabudgetaer, qs.bezeichnung AS qs_bereich
        INTO #gop
        FROM core.gop AS g
        JOIN core.ebm_kapitel AS k ON k.kapitel_nr = g.kapitel_nr
        LEFT JOIN core.qs_bereich AS qs ON qs.qs_bereich_code = g.qs_bereich_code;

        UPDATE d SET gop_code = s.gop_code, gop = s.gop, kapitel_nr = s.kapitel_nr, kapitel = s.kapitel, ebm_bereich = s.ebm_bereich,
                     punktzahl = s.punktzahl, pruefzeit_min = s.pruefzeit_min, ist_extrabudgetaer = s.ist_extrabudgetaer, qs_bereich = s.qs_bereich
        FROM mart.dim_gop AS d JOIN #gop AS s ON s.gop_id = d.gop_id;
        INSERT INTO mart.dim_gop (gop_id, gop_code, gop, kapitel_nr, kapitel, ebm_bereich, punktzahl, pruefzeit_min, ist_extrabudgetaer, qs_bereich)
        SELECT s.gop_id, s.gop_code, s.gop, s.kapitel_nr, s.kapitel, s.ebm_bereich, s.punktzahl, s.pruefzeit_min, s.ist_extrabudgetaer, s.qs_bereich
        FROM #gop AS s WHERE NOT EXISTS (SELECT 1 FROM mart.dim_gop AS d WHERE d.gop_id = s.gop_id);
        SET @rows += @@ROWCOUNT;

        UPDATE d SET altersgruppe = s.bezeichnung, sortierung = s.sortierung
        FROM mart.dim_altersgruppe AS d JOIN core.altersgruppe AS s ON s.altersgruppe_code = d.altersgruppe_code;
        INSERT INTO mart.dim_altersgruppe (altersgruppe_code, altersgruppe, sortierung)
        SELECT s.altersgruppe_code, s.bezeichnung, s.sortierung FROM core.altersgruppe AS s
        WHERE NOT EXISTS (SELECT 1 FROM mart.dim_altersgruppe AS d WHERE d.altersgruppe_code = s.altersgruppe_code);
        SET @rows += @@ROWCOUNT;

        UPDATE d SET planungsbereich_code = s.planungsbereich_code, planungsbereich = s.name, typ = s.typ
        FROM mart.dim_planungsbereich AS d JOIN core.planungsbereich AS s ON s.planungsbereich_id = d.planungsbereich_id;
        INSERT INTO mart.dim_planungsbereich (planungsbereich_id, planungsbereich_code, planungsbereich, typ)
        SELECT s.planungsbereich_id, s.planungsbereich_code, s.name, s.typ FROM core.planungsbereich AS s
        WHERE NOT EXISTS (SELECT 1 FROM mart.dim_planungsbereich AS d WHERE d.planungsbereich_id = s.planungsbereich_id);
        SET @rows += @@ROWCOUNT;

        /* ---------- dim_arzt (SCD type 2) ---------------------------------------------------- */
        -- One version per Teilnahme (core.teilnahme already holds the valid-time history).
        -- Doctors without any Teilnahme (e.g. applicants) get one version 1900-01-01 .. 9999-12-31.
        DROP TABLE IF EXISTS #version;
        SELECT a.arzt_id, a.lanr,
               CONCAT_WS(N' ', a.titel, a.vorname, a.nachname)   AS arzt_name,   -- CONCAT_WS skips NULL parts
               a.geschlecht, a.geburtsjahr, a.fachgruppe_code, fg.bezeichnung AS fachgruppe,
               p.bsnr AS praxis_bsnr, p.name AS praxis_name, t.teilnahmeform_code, t.anrechnungsfaktor,
               COALESCE(t.valid_from, CAST('1900-01-01' AS DATE)) AS valid_from,
               COALESCE(t.valid_to,   CAST('9999-12-31' AS DATE)) AS valid_to
        INTO #version
        FROM core.arzt AS a
        JOIN core.fachgruppe AS fg ON fg.fachgruppe_code = a.fachgruppe_code
        LEFT JOIN core.teilnahme AS t ON t.arzt_id = a.arzt_id
        LEFT JOIN core.praxis AS p ON p.praxis_id = t.praxis_id;

        DROP TABLE IF EXISTS #v;
        SELECT v.*,
               -- is_current = newest version of the doctor (also for doctors who have retired)
               CAST(IIF(ROW_NUMBER() OVER (PARTITION BY v.arzt_id ORDER BY v.valid_from DESC) = 1, 1, 0) AS BIT) AS is_current
        INTO #v
        FROM #version AS v;

        -- versions that no longer exist in core (facts are empty at this point, see usp_load_all)
        DELETE d FROM mart.dim_arzt AS d
        WHERE d.arzt_key <> -1
          AND NOT EXISTS (SELECT 1 FROM #v AS v WHERE v.arzt_id = d.arzt_id AND v.valid_from = d.valid_from);

        UPDATE d SET lanr = s.lanr, arzt_name = s.arzt_name, geschlecht = s.geschlecht, geburtsjahr = s.geburtsjahr,
                     fachgruppe_code = s.fachgruppe_code, fachgruppe = s.fachgruppe, praxis_bsnr = s.praxis_bsnr,
                     praxis_name = s.praxis_name, teilnahmeform_code = s.teilnahmeform_code,
                     anrechnungsfaktor = s.anrechnungsfaktor, valid_to = s.valid_to, is_current = s.is_current
        FROM mart.dim_arzt AS d
        JOIN #v AS s ON s.arzt_id = d.arzt_id AND s.valid_from = d.valid_from
        WHERE EXISTS (SELECT s.lanr, s.arzt_name, s.geschlecht, s.geburtsjahr, s.fachgruppe_code, s.fachgruppe, s.praxis_bsnr,
                             s.praxis_name, s.teilnahmeform_code, s.anrechnungsfaktor, s.valid_to, s.is_current
                      EXCEPT
                      SELECT d.lanr, d.arzt_name, d.geschlecht, d.geburtsjahr, d.fachgruppe_code, d.fachgruppe, d.praxis_bsnr,
                             d.praxis_name, d.teilnahmeform_code, d.anrechnungsfaktor, d.valid_to, d.is_current);
        SET @rows += @@ROWCOUNT;

        INSERT INTO mart.dim_arzt (arzt_id, lanr, arzt_name, geschlecht, geburtsjahr, fachgruppe_code, fachgruppe, praxis_bsnr,
                                   praxis_name, teilnahmeform_code, anrechnungsfaktor, valid_from, valid_to, is_current)
        SELECT s.arzt_id, s.lanr, s.arzt_name, s.geschlecht, s.geburtsjahr, s.fachgruppe_code, s.fachgruppe, s.praxis_bsnr,
               s.praxis_name, s.teilnahmeform_code, s.anrechnungsfaktor, s.valid_from, s.valid_to, s.is_current
        FROM #v AS s
        WHERE NOT EXISTS (SELECT 1 FROM mart.dim_arzt AS d WHERE d.arzt_id = s.arzt_id AND d.valid_from = s.valid_from);
        SET @rows += @@ROWCOUNT;

        COMMIT TRANSACTION;
        EXEC meta.usp_step_end @step_id = @step_id, @status = 'OK', @rows_affected = @rows;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC meta.usp_step_end @step_id = @step_id, @status = 'FAILED', @message = @msg;
        THROW;
    END CATCH
END
GO
