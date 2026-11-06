/* =============================================================================
   602_load_facts.sql
   mart.usp_load_facts: full rebuild of all fact tables from core.
   At this data volume a full refresh takes seconds and is the simplest correct
   strategy. (An incremental load per quarter is an exercise in sql/90_exercises.)

   Dimension lookups use LEFT JOIN + COALESCE(key, -1): a fact row whose
   dimension member is missing points to "unknown" instead of being lost.
   ============================================================================= */
USE KVSim;
GO

CREATE OR ALTER PROCEDURE mart.usp_load_facts
    @batch_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @batch_id = COALESCE(@batch_id, meta.fn_latest_batch_id());
    DECLARE @step_id INT, @rows INT = 0;
    EXEC meta.usp_step_start @batch_id = @batch_id, @step_name = N'mart.usp_load_facts', @step_id = @step_id OUTPUT;

    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE mart.fact_leistung;
        TRUNCATE TABLE mart.fact_abrechnungsfall;
        TRUNCATE TABLE mart.fact_honorar_quartal;
        TRUNCATE TABLE mart.fact_versorgungsgrad;
        TRUNCATE TABLE mart.fact_tss_anfrage;
        TRUNCATE TABLE mart.fact_bereitschaftsdienst;

        /* ---------- fact_leistung ---------------------------------------------------------- */
        INSERT INTO mart.fact_leistung (leistung_id, fallnummer, datum_key, quartal_key, arzt_key, praxis_key, region_key,
                                        fachgruppe_key, kasse_key, gop_key, altersgruppe_key, anzahl, punkte, betrag_eur, pruefzeit_min)
        SELECT l.leistung_id, f.fallnummer,
               CONVERT(INT, CONVERT(CHAR(8), l.leistungsdatum, 112)),            -- date -> yyyymmdd key
               COALESCE(dq.quartal_key, -1),
               COALESCE(da.arzt_key, -1),
               COALESCE(dp.praxis_key, -1),
               COALESCE(dr.region_key, -1),
               COALESCE(dfg.fachgruppe_key, -1),
               COALESCE(dk.kasse_key, -1),
               COALESCE(dg.gop_key, -1),
               COALESCE(dag.altersgruppe_key, -1),
               l.anzahl,
               l.anzahl * l.punktzahl,
               CAST(l.anzahl * l.punktzahl * COALESCE(ow.euro_je_punkt, 0) AS DECIMAL(12,2)),
               l.anzahl * g.pruefzeit_min
        FROM core.leistung AS l
        JOIN core.abrechnungsfall AS f ON f.fall_id = l.fall_id
        JOIN core.praxis          AS p ON p.praxis_id = f.praxis_id
        JOIN core.arzt            AS a ON a.arzt_id = l.arzt_id
        JOIN core.gop             AS g ON g.gop_id = l.gop_id
        LEFT JOIN core.orientierungswert AS ow  ON ow.jahr = YEAR(l.leistungsdatum)
        LEFT JOIN mart.dim_quartal       AS dq  ON dq.quartal_code = f.quartal_code
        -- SCD2 lookup: the version of the doctor that was valid on the day of the service
        LEFT JOIN mart.dim_arzt          AS da  ON da.arzt_id = l.arzt_id
                                               AND l.leistungsdatum >= da.valid_from AND l.leistungsdatum < da.valid_to
        LEFT JOIN mart.dim_praxis        AS dp  ON dp.praxis_id = f.praxis_id
        LEFT JOIN mart.dim_region        AS dr  ON dr.kreis_id = p.kreis_id
        LEFT JOIN mart.dim_fachgruppe    AS dfg ON dfg.fachgruppe_code = a.fachgruppe_code
        LEFT JOIN mart.dim_krankenkasse  AS dk  ON dk.krankenkasse_id = f.krankenkasse_id
        LEFT JOIN mart.dim_gop           AS dg  ON dg.gop_id = l.gop_id
        LEFT JOIN mart.dim_altersgruppe  AS dag ON dag.altersgruppe_code = f.altersgruppe_code;
        SET @rows += @@ROWCOUNT;

        /* ---------- fact_abrechnungsfall ---------------------------------------------------- */
        WITH leist AS (
            SELECT fall_id, COUNT(*) AS anzahl_leistungen, SUM(anzahl * punktzahl) AS punkte
            FROM core.leistung GROUP BY fall_id
        ),
        haupt AS (   -- "Hauptbehandler": the doctor of the first billing line
            SELECT fall_id, arzt_id, leistungsdatum FROM core.leistung WHERE positions_nr = 1
        ),
        diag AS (
            SELECT fall_id, COUNT(*) AS anzahl_diagnosen FROM core.fall_diagnose GROUP BY fall_id
        )
        INSERT INTO mart.fact_abrechnungsfall (fall_id, fallnummer, quartal_key, praxis_key, region_key, arzt_key, fachgruppe_key,
                                               kasse_key, altersgruppe_key, versichertenstatus, scheinuntergruppe, ist_tss_fall,
                                               anzahl_leistungen, anzahl_diagnosen, punkte, betrag_eur)
        SELECT f.fall_id, f.fallnummer,
               COALESCE(dq.quartal_key, -1), COALESCE(dp.praxis_key, -1), COALESCE(dr.region_key, -1),
               COALESCE(da.arzt_key, -1), COALESCE(dfg.fachgruppe_key, -1), COALESCE(dk.kasse_key, -1),
               COALESCE(dag.altersgruppe_key, -1),
               f.versichertenstatus, f.scheinuntergruppe_code, IIF(f.tss_vermittlungscode IS NULL, 0, 1),
               COALESCE(leist.anzahl_leistungen, 0), COALESCE(diag.anzahl_diagnosen, 0), COALESCE(leist.punkte, 0),
               CAST(COALESCE(leist.punkte, 0) * COALESCE(ow.euro_je_punkt, 0) AS DECIMAL(12,2))
        FROM core.abrechnungsfall AS f
        JOIN core.quartal AS q ON q.quartal_code = f.quartal_code
        JOIN core.praxis  AS p ON p.praxis_id = f.praxis_id
        LEFT JOIN leist ON leist.fall_id = f.fall_id
        LEFT JOIN haupt ON haupt.fall_id = f.fall_id
        LEFT JOIN diag  ON diag.fall_id = f.fall_id
        LEFT JOIN core.arzt              AS a   ON a.arzt_id = haupt.arzt_id
        LEFT JOIN core.orientierungswert AS ow  ON ow.jahr = q.jahr
        LEFT JOIN mart.dim_quartal       AS dq  ON dq.quartal_code = f.quartal_code
        LEFT JOIN mart.dim_praxis        AS dp  ON dp.praxis_id = f.praxis_id
        LEFT JOIN mart.dim_region        AS dr  ON dr.kreis_id = p.kreis_id
        LEFT JOIN mart.dim_arzt          AS da  ON da.arzt_id = haupt.arzt_id
                                               AND haupt.leistungsdatum >= da.valid_from AND haupt.leistungsdatum < da.valid_to
        LEFT JOIN mart.dim_fachgruppe    AS dfg ON dfg.fachgruppe_code = a.fachgruppe_code
        LEFT JOIN mart.dim_krankenkasse  AS dk  ON dk.krankenkasse_id = f.krankenkasse_id
        LEFT JOIN mart.dim_altersgruppe  AS dag ON dag.altersgruppe_code = f.altersgruppe_code;
        SET @rows += @@ROWCOUNT;

        /* ---------- fact_honorar_quartal ------------------------------------------------------ */
        WITH gezahlt AS (
            SELECT praxis_id, quartal_code, SUM(betrag) AS betrag FROM core.abschlagszahlung GROUP BY praxis_id, quartal_code
        ),
        faelle AS (
            SELECT praxis_id, quartal_code, COUNT(*) AS anzahl FROM core.abrechnungsfall GROUP BY praxis_id, quartal_code
        )
        INSERT INTO mart.fact_honorar_quartal (quartal_key, praxis_key, region_key, anzahl_faelle, punkte_angefordert,
                                               punkte_berichtigt, punkte_mgv, punkte_egv, betrag_mgv, betrag_egv, honorar_brutto,
                                               verwaltungskosten, abschlaege_laut_bescheid, abschlaege_gezahlt, auszahlungsbetrag)
        SELECT COALESCE(dq.quartal_key, -1), COALESCE(dp.praxis_key, -1), COALESCE(dr.region_key, -1),
               COALESCE(fa.anzahl, 0), h.punkte_angefordert, h.punkte_berichtigt, h.punkte_mgv, h.punkte_egv,
               h.betrag_mgv, h.betrag_egv, h.honorar_brutto, h.verwaltungskosten, h.abschlaege, COALESCE(gz.betrag, 0),
               h.auszahlungsbetrag
        FROM core.honorarbescheid AS h
        JOIN core.praxis AS p ON p.praxis_id = h.praxis_id
        LEFT JOIN gezahlt AS gz ON gz.praxis_id = h.praxis_id AND gz.quartal_code = h.quartal_code
        LEFT JOIN faelle  AS fa ON fa.praxis_id = h.praxis_id AND fa.quartal_code = h.quartal_code
        LEFT JOIN mart.dim_quartal AS dq ON dq.quartal_code = h.quartal_code
        LEFT JOIN mart.dim_praxis  AS dp ON dp.praxis_id = h.praxis_id
        LEFT JOIN mart.dim_region  AS dr ON dr.kreis_id = p.kreis_id;
        SET @rows += @@ROWCOUNT;

        /* ---------- fact_versorgungsgrad (official + recomputed) --------------------------------- */
        INSERT INTO mart.fact_versorgungsgrad (stichtag_key, planungsbereich_key, arztgruppe_key, einwohner, soll_aerzte,
                                               ist_aerzte, ist_aerzte_berechnet, versorgungsgrad_pct, status)
        SELECT CONVERT(INT, CONVERT(CHAR(8), v.stichtag, 112)),
               COALESCE(dpb.planungsbereich_key, -1), COALESCE(dag.arztgruppe_key, -1),
               v.einwohner, v.soll_aerzte, v.ist_aerzte, COALESCE(ber.ist, 0), v.versorgungsgrad_pct, v.status
        FROM core.versorgungsgrad AS v
        LEFT JOIN mart.dim_planungsbereich AS dpb ON dpb.planungsbereich_id = v.planungsbereich_id
        LEFT JOIN mart.dim_arztgruppe      AS dag ON dag.arztgruppe_code = v.arztgruppe_code
        -- recompute "Ist" from the register: all Teilnahmen valid on the Stichtag in this area and group
        OUTER APPLY (
            SELECT SUM(t.anrechnungsfaktor) AS ist
            FROM core.teilnahme AS t
            JOIN core.arzt AS a ON a.arzt_id = t.arzt_id
            JOIN core.fachgruppe AS fg ON fg.fachgruppe_code = a.fachgruppe_code
            JOIN core.praxis AS p ON p.praxis_id = t.praxis_id
            JOIN core.planungsbereich_kreis AS pk ON pk.kreis_id = p.kreis_id
            WHERE pk.planungsbereich_id = v.planungsbereich_id
              AND fg.arztgruppe_code = v.arztgruppe_code
              AND v.stichtag >= t.valid_from AND v.stichtag < t.valid_to
        ) AS ber;
        SET @rows += @@ROWCOUNT;

        /* ---------- fact_tss_anfrage ------------------------------------------------------------ */
        INSERT INTO mart.fact_tss_anfrage (anfrage_id, eingang_datum_key, termin_datum_key, arztgruppe_key, patient_region_key,
                                           altersgruppe_key, praxis_key, kanal, dringlichkeit, status, ist_vermittelt,
                                           wartezeit_tage, ist_innerhalb_4_wochen, termin_wahrgenommen, anzahl_anfragen)
        SELECT t.anfrage_id,
               CONVERT(INT, CONVERT(CHAR(8), CAST(t.eingang_zeitpunkt AS DATE), 112)),
               COALESCE(CONVERT(INT, CONVERT(CHAR(8), CAST(t.termin_zeitpunkt AS DATE), 112)), -1),
               COALESCE(dag.arztgruppe_key, -1), COALESCE(dr.region_key, -1), COALESCE(dal.altersgruppe_key, -1),
               COALESCE(dp.praxis_key, -1),
               t.kanal, t.dringlichkeit, t.status, IIF(t.status = 'VERMITTELT', 1, 0), t.wartezeit_tage,
               CASE WHEN t.wartezeit_tage IS NULL THEN NULL WHEN t.wartezeit_tage <= 28 THEN 1 ELSE 0 END,
               t.termin_wahrgenommen, 1
        FROM core.tss_anfrage AS t
        LEFT JOIN mart.dim_arztgruppe   AS dag ON dag.arztgruppe_code = t.arztgruppe_code
        LEFT JOIN mart.dim_region       AS dr  ON dr.kreis_id = t.patient_kreis_id
        LEFT JOIN mart.dim_altersgruppe AS dal ON dal.altersgruppe_code = t.patient_altersgruppe_code
        LEFT JOIN mart.dim_praxis       AS dp  ON dp.praxis_id = t.praxis_id;
        SET @rows += @@ROWCOUNT;

        /* ---------- fact_bereitschaftsdienst ------------------------------------------------------ */
        INSERT INTO mart.fact_bereitschaftsdienst (dienst_id, datum_key, arzt_key, region_key, notfallpraxis_kennung,
                                                   dauer_stunden, ist_wochenende_feiertag, ist_getauscht)
        SELECT b.dienst_id, dd.datum_key, COALESCE(da.arzt_key, -1), COALESCE(dr.region_key, -1), np.kennung,
               b.dauer_stunden, IIF(dd.ist_wochenende = 1 OR dd.ist_feiertag = 1, 1, 0), IIF(b.getauscht_von_arzt_id IS NULL, 0, 1)
        FROM core.bereitschaftsdienst AS b
        JOIN core.notfallpraxis AS np ON np.notfallpraxis_id = b.notfallpraxis_id
        JOIN mart.dim_datum     AS dd ON dd.datum = CAST(b.beginn AS DATE)
        LEFT JOIN mart.dim_arzt   AS da ON da.arzt_id = b.arzt_id
                                       AND CAST(b.beginn AS DATE) >= da.valid_from AND CAST(b.beginn AS DATE) < da.valid_to
        LEFT JOIN mart.dim_region AS dr ON dr.kreis_id = np.kreis_id;
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
