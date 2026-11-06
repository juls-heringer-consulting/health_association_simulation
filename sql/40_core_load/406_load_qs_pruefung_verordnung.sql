/* =============================================================================
   406_load_qs_pruefung_verordnung.sql
   core.usp_load_qs_pruefung_verordnung: QS-Genehmigungen, Fortbildungspunkte,
   Pruefverfahren (XML), Verordnungen (fixed-width) and Richtgroessen.
   ============================================================================= */
USE KVSim;
GO

CREATE OR ALTER PROCEDURE core.usp_load_qs_pruefung_verordnung
    @batch_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @batch_id = COALESCE(@batch_id, meta.fn_latest_batch_id());
    DECLARE @step_id INT, @rows INT = 0;
    EXEC meta.usp_step_start @batch_id = @batch_id, @step_name = N'core.usp_load_qs_pruefung_verordnung', @step_id = @step_id OUTPUT;

    BEGIN TRY
        /* ---------- Control totals of the fixed-width file (checked BEFORE loading) ---- */
        -- Mainframe-style files end with a trailer record (TR) that repeats the number of
        -- data records and the sum of the amounts. If they do not match, the file is
        -- incomplete or corrupt and must be rejected as a whole.
        DECLARE @tr_anzahl INT, @tr_cent BIGINT, @vo_anzahl INT, @vo_cent BIGINT;
        SELECT @tr_anzahl = TRY_CAST(SUBSTRING(zeile, 3, 7) AS INT),
               @tr_cent   = TRY_CAST(SUBSTRING(zeile, 10, 13) AS BIGINT)
        FROM stg.verordnung_zeilen WHERE LEFT(zeile, 2) = 'TR';
        SELECT @vo_anzahl = COUNT(*), @vo_cent = SUM(TRY_CAST(SUBSTRING(zeile, 25, 11) AS BIGINT))
        FROM stg.verordnung_zeilen WHERE LEFT(zeile, 2) = 'VO';
        IF @tr_anzahl IS NULL OR @tr_anzahl <> @vo_anzahl OR @tr_cent <> @vo_cent
            THROW 50010, N'Verordnungsdatei rejected: trailer control totals do not match the data records.', 1;

        BEGIN TRANSACTION;

        /* ---------- QS-Genehmigungen: full snapshot -> replace all ----------------------- */
        IF EXISTS (SELECT 1 FROM stg.qs_genehmigungen)          -- never wipe core with an empty delivery
        BEGIN
            DELETE FROM core.qs_genehmigung;
            INSERT INTO core.qs_genehmigung (arzt_id, qs_bereich_code, valid_from, valid_to, load_batch_id)
            SELECT a.arzt_id, s.leistungsbereich,
                   TRY_CONVERT(DATE, s.genehmigt_ab, 104),
                   COALESCE(TRY_CONVERT(DATE, s.genehmigt_bis, 104), CAST('9999-12-31' AS DATE)),
                   @batch_id
            FROM stg.qs_genehmigungen AS s
            JOIN core.arzt AS a ON a.lanr = s.lanr;
            SET @rows += @@ROWCOUNT;
        END

        /* ---------- Fortbildungspunkte: keyed by EFN, not LANR -> key mapping via core.arzt -- */
        IF EXISTS (SELECT 1 FROM stg.kammer_fortbildungspunkte)
        BEGIN
            DELETE FROM core.fortbildungspunkte;
            INSERT INTO core.fortbildungspunkte (arzt_id, jahr, punkte, load_batch_id)
            SELECT a.arzt_id, TRY_CAST(s.jahr AS SMALLINT), TRY_CAST(s.punkte AS SMALLINT), @batch_id
            FROM stg.kammer_fortbildungspunkte AS s
            JOIN core.arzt AS a ON a.efn = s.efn;
            SET @rows += @@ROWCOUNT;
        END

        /* ---------- Pruefverfahren (XML) ------------------------------------------------- */
        DROP TABLE IF EXISTS #pv;
        SELECT v.n.value('@aktenzeichen', 'varchar(20)')                AS aktenzeichen,
               p.praxis_id,
               -- the Pruefungsstelle writes quarters as "1/2025"
               CAST(CONCAT(RIGHT(q.quartal, 4), 'Q', LEFT(q.quartal, 1)) AS CHAR(6)) AS quartal_code,
               v.n.value('(Gegenstand/text())[1]', 'varchar(15)')       AS pruefgegenstand,
               v.n.value('(Anlass/text())[1]', 'varchar(15)')           AS anlass,
               v.n.value('(Eingeleitet/text())[1]', 'date')             AS eingeleitet_am,
               v.n.value('(Status/text())[1]', 'varchar(15)')           AS status,
               v.n.value('(Abgeschlossen/text())[1]', 'date')           AS abgeschlossen_am,
               v.n.value('(Massnahme/text())[1]', 'varchar(15)')        AS massnahme,
               v.n.value('(Massnahme/@betrag)[1]', 'decimal(12,2)')     AS nachforderung_betrag
        INTO #pv
        FROM stg.pruefung_verfahren_xml AS x
        CROSS APPLY x.content.nodes('/Pruefverfahren/Verfahren') AS v(n)
        CROSS APPLY (SELECT v.n.value('(Quartal/text())[1]', 'varchar(10)') AS quartal) AS q
        JOIN core.praxis AS p ON p.bsnr = v.n.value('(BSNR/text())[1]', 'char(9)');

        UPDATE t SET praxis_id = s.praxis_id, quartal_code = s.quartal_code, pruefgegenstand = s.pruefgegenstand,
                     anlass = s.anlass, eingeleitet_am = s.eingeleitet_am, status = s.status,
                     abgeschlossen_am = s.abgeschlossen_am, massnahme = s.massnahme,
                     nachforderung_betrag = s.nachforderung_betrag, load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.pruefverfahren AS t JOIN #pv AS s ON s.aktenzeichen = t.aktenzeichen
        WHERE EXISTS (SELECT s.praxis_id, s.quartal_code, s.pruefgegenstand, s.anlass, s.eingeleitet_am, s.status,
                             s.abgeschlossen_am, s.massnahme, s.nachforderung_betrag
                      EXCEPT
                      SELECT t.praxis_id, t.quartal_code, t.pruefgegenstand, t.anlass, t.eingeleitet_am, t.status,
                             t.abgeschlossen_am, t.massnahme, t.nachforderung_betrag);
        SET @rows += @@ROWCOUNT;

        INSERT INTO core.pruefverfahren (aktenzeichen, praxis_id, quartal_code, pruefgegenstand, anlass, eingeleitet_am,
                                         status, abgeschlossen_am, massnahme, nachforderung_betrag, load_batch_id)
        SELECT s.aktenzeichen, s.praxis_id, s.quartal_code, s.pruefgegenstand, s.anlass, s.eingeleitet_am,
               s.status, s.abgeschlossen_am, s.massnahme, s.nachforderung_betrag, @batch_id
        FROM #pv AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.pruefverfahren AS t WHERE t.aktenzeichen = s.aktenzeichen);
        SET @rows += @@ROWCOUNT;

        /* ---------- Verordnungen (fixed-width records) ------------------------------------ */
        -- Record layout "VO": pos 1-2 type | 3-11 BSNR | 12-16 YYYYQ | 17 type A/H | 18-24 count | 25-35 amount in cent
        DROP TABLE IF EXISTS #vo;
        SELECT p.praxis_id,
               CAST(CONCAT(SUBSTRING(z.zeile, 12, 4), 'Q', SUBSTRING(z.zeile, 16, 1)) AS CHAR(6)) AS quartal_code,
               SUBSTRING(z.zeile, 17, 1)                                         AS verordnungsart,
               TRY_CAST(SUBSTRING(z.zeile, 18, 7) AS INT)                        AS anzahl_verordnungen,
               TRY_CAST(SUBSTRING(z.zeile, 25, 11) AS DECIMAL(13,0)) / 100       AS brutto_betrag
        INTO #vo
        FROM stg.verordnung_zeilen AS z
        JOIN core.praxis AS p ON p.bsnr = SUBSTRING(z.zeile, 3, 9)
        WHERE LEFT(z.zeile, 2) = 'VO';

        DELETE FROM core.verordnung WHERE quartal_code IN (SELECT quartal_code FROM #vo);
        INSERT INTO core.verordnung (praxis_id, quartal_code, verordnungsart, anzahl_verordnungen, brutto_betrag, load_batch_id)
        SELECT praxis_id, quartal_code, verordnungsart, anzahl_verordnungen, brutto_betrag, @batch_id FROM #vo;
        SET @rows += @@ROWCOUNT;

        /* ---------- Richtgroessen ---------------------------------------------------------- */
        DROP TABLE IF EXISTS #rg;
        SELECT arztgruppe AS arztgruppe_code, TRY_CAST(jahr AS SMALLINT) AS jahr, verordnungsart,
               TRY_CAST(REPLACE(richtgroesse_eur_je_fall, ',', '.') AS DECIMAL(8,2)) AS euro_je_fall
        INTO #rg
        FROM stg.verordnung_richtgroessen;

        UPDATE t SET euro_je_fall = s.euro_je_fall, load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.richtgroesse AS t
        JOIN #rg AS s ON s.arztgruppe_code = t.arztgruppe_code AND s.jahr = t.jahr AND s.verordnungsart = t.verordnungsart
        WHERE t.euro_je_fall <> s.euro_je_fall;
        INSERT INTO core.richtgroesse (arztgruppe_code, jahr, verordnungsart, euro_je_fall, load_batch_id)
        SELECT s.arztgruppe_code, s.jahr, s.verordnungsart, s.euro_je_fall, @batch_id FROM #rg AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.richtgroesse AS t
                          WHERE t.arztgruppe_code = s.arztgruppe_code AND t.jahr = s.jahr AND t.verordnungsart = s.verordnungsart);
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
