/* =============================================================================
   404_load_abrechnung.sql
   core.usp_load_abrechnung: cases, billed GOPs, diagnoses, Honorarbescheide and
   Abschlagszahlungen.

   Load strategy for TRANSACTION data: "delete and reload per quarter".
   A billing delivery always contains complete quarters. For every quarter in the
   delivery, the old rows are deleted (children first, because of the foreign keys)
   and the new ones inserted. Re-running the load gives the same result (idempotent).
   ============================================================================= */
USE KVSim;
GO

CREATE OR ALTER PROCEDURE core.usp_load_abrechnung
    @batch_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @batch_id = COALESCE(@batch_id, meta.fn_latest_batch_id());
    DECLARE @step_id INT, @rows INT = 0;
    EXEC meta.usp_step_start @batch_id = @batch_id, @step_name = N'core.usp_load_abrechnung', @step_id = @step_id OUTPUT;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Quarters contained in this delivery. KVDT-style notation "QJJJJ" (12025) -> "2025Q1".
        DROP TABLE IF EXISTS #quartale;
        SELECT DISTINCT CAST(CONCAT(RIGHT(quartal, 4), 'Q', LEFT(quartal, 1)) AS CHAR(6)) AS quartal_code
        INTO #quartale
        FROM stg.abrechnung_faelle;

        /* ---------- delete old rows of these quarters (children first) ---------- */
        DELETE l FROM core.leistung AS l
        JOIN core.abrechnungsfall AS f ON f.fall_id = l.fall_id
        WHERE f.quartal_code IN (SELECT quartal_code FROM #quartale);

        DELETE d FROM core.fall_diagnose AS d
        JOIN core.abrechnungsfall AS f ON f.fall_id = d.fall_id
        WHERE f.quartal_code IN (SELECT quartal_code FROM #quartale);

        DELETE FROM core.abrechnungsfall WHERE quartal_code IN (SELECT quartal_code FROM #quartale);

        /* ---------- Behandlungsfaelle -------------------------------------------- */
        INSERT INTO core.abrechnungsfall (fallnummer, praxis_id, quartal_code, patient_pseudonym, krankenkasse_id,
                                          versichertenstatus, geschlecht, altersgruppe_code, scheinuntergruppe_code,
                                          tss_vermittlungscode, load_batch_id)
        SELECT s.fallnummer, p.praxis_id, q.quartal_code, s.patientenpseudonym, kk.krankenkasse_id,
               s.versichertenstatus, s.geschlecht, ag.altersgruppe_code, s.scheinuntergruppe,
               s.tss_vermittlungscode, @batch_id
        FROM stg.abrechnung_faelle AS s
        JOIN core.praxis       AS p  ON p.bsnr = s.bsnr
        JOIN core.quartal      AS q  ON q.quartal_code = CONCAT(RIGHT(s.quartal, 4), 'Q', LEFT(s.quartal, 1))
        JOIN core.krankenkasse AS kk ON kk.ik = s.kassen_ik
        -- data minimisation: the year of birth is only used to derive the age group, then dropped
        JOIN core.altersgruppe AS ag
          ON q.jahr - TRY_CAST(s.geburtsjahr AS INT) BETWEEN ag.alter_von AND ISNULL(ag.alter_bis, 200);
        SET @rows += @@ROWCOUNT;

        /* ---------- Leistungen ------------------------------------------------------ */
        INSERT INTO core.leistung (fall_id, positions_nr, leistungsdatum, arzt_id, gop_id, anzahl, punktzahl, load_batch_id)
        SELECT f.fall_id,
               TRY_CAST(s.position AS SMALLINT),
               -- KVDT date format TTMMJJJJ ("28012025") -> JJJJMMTT -> style 112
               TRY_CONVERT(DATE, RIGHT(s.datum, 4) + SUBSTRING(s.datum, 3, 2) + LEFT(s.datum, 2), 112),
               a.arzt_id, g.gop_id,
               TRY_CAST(s.anzahl AS SMALLINT),
               g.punktzahl,                      -- snapshot of the points valid at billing time
               @batch_id
        FROM stg.abrechnung_leistungen AS s
        JOIN core.abrechnungsfall AS f ON f.fallnummer = s.fallnummer
        JOIN core.arzt AS a ON a.lanr = s.lanr
        JOIN core.gop  AS g ON g.gop_code = s.gop;
        SET @rows += @@ROWCOUNT;

        /* ---------- Diagnosen -------------------------------------------------------- */
        INSERT INTO core.fall_diagnose (fall_id, icd_id, diagnosesicherheit, load_batch_id)
        SELECT f.fall_id, i.icd_id, s.sicherheit, @batch_id
        FROM stg.abrechnung_diagnosen AS s
        JOIN core.abrechnungsfall AS f ON f.fallnummer = s.fallnummer
        JOIN core.icd10 AS i ON i.icd_code = s.icd;
        SET @rows += @@ROWCOUNT;

        /* ---------- Honorarbescheide (XML, one file per quarter) ---------------------- */
        DROP TABLE IF EXISTS #bescheid;
        SELECT b.n.value('@nr', 'varchar(20)')                               AS bescheid_nr,
               b.n.value('@bsnr', 'char(9)')                                 AS bsnr,
               h.n.value('@quartal', 'char(6)')                              AS quartal_code,
               b.n.value('@datum', 'date')                                   AS bescheiddatum,
               b.n.value('(Punkte/@angefordert)[1]', 'int')                  AS punkte_angefordert,
               b.n.value('(Punkte/@berichtigt)[1]', 'int')                   AS punkte_berichtigt,
               b.n.value('(Punkte/@mgv)[1]', 'int')                          AS punkte_mgv,
               b.n.value('(Punkte/@egv)[1]', 'int')                          AS punkte_egv,
               b.n.value('(Verguetung/@quote_mgv)[1]', 'decimal(6,4)')       AS quote_mgv,
               b.n.value('(Verguetung/@mgv)[1]', 'decimal(12,2)')            AS betrag_mgv,
               b.n.value('(Verguetung/@egv)[1]', 'decimal(12,2)')            AS betrag_egv,
               b.n.value('(Verguetung/@brutto)[1]', 'decimal(12,2)')         AS honorar_brutto,
               b.n.value('(Abzuege/@verwaltungskosten)[1]', 'decimal(12,2)') AS verwaltungskosten,
               b.n.value('(Abzuege/@abschlaege)[1]', 'decimal(12,2)')        AS abschlaege,
               b.n.value('(Auszahlungsbetrag/text())[1]', 'decimal(12,2)')   AS auszahlungsbetrag
        INTO #bescheid
        FROM stg.honorar_bescheide_xml AS x
        CROSS APPLY x.content.nodes('/Honorarbescheide') AS h(n)
        CROSS APPLY h.n.nodes('Bescheid') AS b(n);

        DELETE FROM core.honorarbescheid WHERE quartal_code IN (SELECT quartal_code FROM #bescheid);
        INSERT INTO core.honorarbescheid (bescheid_nr, praxis_id, quartal_code, bescheiddatum, punkte_angefordert, punkte_berichtigt,
                                          punkte_mgv, punkte_egv, quote_mgv, betrag_mgv, betrag_egv, honorar_brutto,
                                          verwaltungskosten, abschlaege, auszahlungsbetrag, load_batch_id)
        SELECT s.bescheid_nr, p.praxis_id, s.quartal_code, s.bescheiddatum, s.punkte_angefordert, s.punkte_berichtigt,
               s.punkte_mgv, s.punkte_egv, s.quote_mgv, s.betrag_mgv, s.betrag_egv, s.honorar_brutto,
               s.verwaltungskosten, s.abschlaege, s.auszahlungsbetrag, @batch_id
        FROM #bescheid AS s
        JOIN core.praxis AS p ON p.bsnr = s.bsnr;
        SET @rows += @@ROWCOUNT;

        /* ---------- Abschlagszahlungen (finance system CSV) -------------------------- */
        -- Verwendungszweck looks like "Abschlag 2/3 Quartal 1/2025": the quarter and the payment
        -- number are only available inside this free-text field and must be parsed out.
        DROP TABLE IF EXISTS #abschlag;
        SELECT p.praxis_id,
               CAST(CONCAT(RIGHT(s.verwendungszweck, 4), 'Q',
                           SUBSTRING(s.verwendungszweck, CHARINDEX(N'Quartal ', s.verwendungszweck) + 8, 1)) AS CHAR(6)) AS quartal_code,
               TRY_CAST(SUBSTRING(s.verwendungszweck, CHARINDEX(N' ', s.verwendungszweck) + 1, 1) AS TINYINT)          AS abschlag_nr,
               TRY_CONVERT(DATE, s.buchungsdatum, 104)                                                                  AS zahlungsdatum,
               -- German number format "1.234,56": remove thousands separator, then comma -> point.
               -- (TRY_PARSE(s.betrag AS DECIMAL(12,2) USING 'de-DE') would also work, but is much slower.)
               TRY_CAST(REPLACE(REPLACE(s.betrag, '.', ''), ',', '.') AS DECIMAL(12,2))                                AS betrag
        INTO #abschlag
        FROM stg.honorar_abschlaege AS s
        JOIN core.praxis AS p ON p.bsnr = s.bsnr;

        DELETE FROM core.abschlagszahlung WHERE quartal_code IN (SELECT quartal_code FROM #abschlag);
        INSERT INTO core.abschlagszahlung (praxis_id, quartal_code, abschlag_nr, zahlungsdatum, betrag, load_batch_id)
        SELECT praxis_id, quartal_code, abschlag_nr, zahlungsdatum, betrag, @batch_id FROM #abschlag;
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
