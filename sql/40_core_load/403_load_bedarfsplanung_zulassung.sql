/* =============================================================================
   403_load_bedarfsplanung_zulassung.sql
   core.usp_load_bedarfsplanung : Planungsbereiche and Versorgungsgrade (Excel)
   core.usp_load_zulassung      : Zulassungsverfahren and status history (XML)
   ============================================================================= */
USE KVSim;
GO

CREATE OR ALTER PROCEDURE core.usp_load_bedarfsplanung
    @batch_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @batch_id = COALESCE(@batch_id, meta.fn_latest_batch_id());
    DECLARE @step_id INT, @rows INT = 0;
    EXEC meta.usp_step_start @batch_id = @batch_id, @step_name = N'core.usp_load_bedarfsplanung', @step_id = @step_id OUTPUT;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* ---------- Planungsbereich ---------------------------------------------- */
        DROP TABLE IF EXISTS #pb;
        SELECT pb_code AS planungsbereich_code, planungsbereich AS name, typ INTO #pb
        FROM stg.bedarfsplanung_planungsbereiche;

        UPDATE t SET name = s.name, typ = s.typ, load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.planungsbereich AS t JOIN #pb AS s ON s.planungsbereich_code = t.planungsbereich_code
        WHERE EXISTS (SELECT s.name, s.typ EXCEPT SELECT t.name, t.typ);
        SET @rows += @@ROWCOUNT;
        INSERT INTO core.planungsbereich (planungsbereich_code, name, typ, load_batch_id)
        SELECT s.planungsbereich_code, s.name, s.typ, @batch_id FROM #pb AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.planungsbereich AS t WHERE t.planungsbereich_code = s.planungsbereich_code);
        SET @rows += @@ROWCOUNT;

        -- "10041, 10042, ..." in one cell -> one row per Kreis
        DROP TABLE IF EXISTS #pb_kreis;
        SELECT DISTINCT pb.planungsbereich_id, k.kreis_id
        INTO #pb_kreis
        FROM stg.bedarfsplanung_planungsbereiche AS s
        CROSS APPLY STRING_SPLIT(s.kreise_ags, ',') AS v
        JOIN core.planungsbereich AS pb ON pb.planungsbereich_code = s.pb_code
        JOIN core.kreis AS k ON k.ags = LTRIM(RTRIM(v.value));

        DELETE FROM core.planungsbereich_kreis WHERE planungsbereich_id IN (SELECT planungsbereich_id FROM #pb_kreis);
        INSERT INTO core.planungsbereich_kreis (planungsbereich_id, kreis_id, load_batch_id)
        SELECT planungsbereich_id, kreis_id, @batch_id FROM #pb_kreis;
        SET @rows += @@ROWCOUNT;

        /* ---------- Versorgungsgrad ------------------------------------------------ */
        DROP TABLE IF EXISTS #vg;
        SELECT pb.planungsbereich_id,
               s.arztgruppe                              AS arztgruppe_code,
               TRY_CONVERT(DATE, s.stichtag)             AS stichtag,       -- loader wrote ISO dates (yyyy-mm-dd)
               TRY_CAST(s.einwohner AS INT)              AS einwohner,
               TRY_CAST(s.verhaeltniszahl AS INT)        AS verhaeltniszahl,
               TRY_CAST(s.soll AS DECIMAL(7,2))          AS soll_aerzte,
               TRY_CAST(s.ist AS DECIMAL(7,2))           AS ist_aerzte,
               -- Excel stores "108,3 %" as the fraction 1.083 -> multiply by 100
               CAST(ROUND(TRY_CAST(s.versorgungsgrad AS FLOAT) * 100, 1) AS DECIMAL(6,1)) AS versorgungsgrad_pct,
               s.status
        INTO #vg
        FROM stg.bedarfsplanung_versorgungsgrade AS s
        JOIN core.planungsbereich AS pb ON pb.planungsbereich_code = s.pb_code;

        DELETE FROM core.versorgungsgrad WHERE stichtag IN (SELECT stichtag FROM #vg);
        INSERT INTO core.versorgungsgrad (planungsbereich_id, arztgruppe_code, stichtag, einwohner, verhaeltniszahl,
                                          soll_aerzte, ist_aerzte, versorgungsgrad_pct, status, load_batch_id)
        SELECT planungsbereich_id, arztgruppe_code, stichtag, einwohner, verhaeltniszahl,
               soll_aerzte, ist_aerzte, versorgungsgrad_pct, status, @batch_id
        FROM #vg;
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

CREATE OR ALTER PROCEDURE core.usp_load_zulassung
    @batch_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @batch_id = COALESCE(@batch_id, meta.fn_latest_batch_id());
    DECLARE @step_id INT, @rows INT = 0;
    EXEC meta.usp_step_start @batch_id = @batch_id, @step_name = N'core.usp_load_zulassung', @step_id = @step_id OUTPUT;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* ---------- Shred the XML: one row per <Verfahren> -------------------------- */
        DROP TABLE IF EXISTS #verfahren;
        SELECT v.n.value('@aktenzeichen', 'varchar(20)')                 AS aktenzeichen,
               v.n.value('@art', 'varchar(15)')                          AS verfahrensart,
               v.n.value('(Antragsteller/@lanr)[1]', 'char(9)')          AS lanr,
               v.n.value('(Betriebsstaette/@bsnr)[1]', 'char(9)')        AS bsnr,          -- optional element
               v.n.value('(Planungsbereich/text())[1]', 'varchar(10)')   AS planungsbereich_code,
               v.n.value('(Antragsdatum/text())[1]', 'date')             AS antragsdatum,
               v.n.value('(Sitzung/text())[1]', 'date')                  AS sitzungsdatum,
               v.n.value('(Ergebnis/text())[1]', 'varchar(16)')          AS ergebnis,
               v.n.value('(Ergebnis/@wirksam_ab)[1]', 'date')            AS wirksam_ab,
               v.n.value('(Ergebnis/@wirksam_bis)[1]', 'date')           AS wirksam_bis
        INTO #verfahren
        FROM stg.zulassung_verfahren_xml AS x
        CROSS APPLY x.content.nodes('/Zulassungsverfahren/Verfahren') AS v(n);

        -- resolve business keys to surrogate keys
        DROP TABLE IF EXISTS #v;
        SELECT s.*, a.arzt_id, p.praxis_id, pb.planungsbereich_id, tl.teilnahme_id
        INTO #v
        FROM #verfahren AS s
        JOIN core.arzt AS a ON a.lanr = s.lanr
        LEFT JOIN core.praxis AS p ON p.bsnr = s.bsnr
        JOIN core.planungsbereich AS pb ON pb.planungsbereich_code = s.planungsbereich_code
        -- the Teilnahme that the decision created/changed: same doctor and practice, and the
        -- effective date lies within (or exactly at the end of) the Teilnahme
        OUTER APPLY (
            SELECT TOP (1) t.teilnahme_id
            FROM core.teilnahme AS t
            WHERE t.arzt_id = a.arzt_id AND t.praxis_id = p.praxis_id
              AND s.wirksam_ab BETWEEN t.valid_from AND t.valid_to
            ORDER BY t.valid_from DESC
        ) AS tl;

        UPDATE t
           SET verfahrensart = s.verfahrensart, arzt_id = s.arzt_id, praxis_id = s.praxis_id,
               planungsbereich_id = s.planungsbereich_id, antragsdatum = s.antragsdatum, sitzungsdatum = s.sitzungsdatum,
               ergebnis = s.ergebnis, wirksam_ab = s.wirksam_ab, wirksam_bis = s.wirksam_bis, teilnahme_id = s.teilnahme_id,
               load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.zulassungsverfahren AS t
        JOIN #v AS s ON s.aktenzeichen = t.aktenzeichen
        WHERE EXISTS (SELECT s.verfahrensart, s.arzt_id, s.praxis_id, s.planungsbereich_id, s.antragsdatum, s.sitzungsdatum,
                             s.ergebnis, s.wirksam_ab, s.wirksam_bis, s.teilnahme_id
                      EXCEPT
                      SELECT t.verfahrensart, t.arzt_id, t.praxis_id, t.planungsbereich_id, t.antragsdatum, t.sitzungsdatum,
                             t.ergebnis, t.wirksam_ab, t.wirksam_bis, t.teilnahme_id);
        SET @rows += @@ROWCOUNT;

        INSERT INTO core.zulassungsverfahren (aktenzeichen, verfahrensart, arzt_id, praxis_id, planungsbereich_id, antragsdatum,
                                              sitzungsdatum, ergebnis, wirksam_ab, wirksam_bis, teilnahme_id, load_batch_id)
        SELECT s.aktenzeichen, s.verfahrensart, s.arzt_id, s.praxis_id, s.planungsbereich_id, s.antragsdatum,
               s.sitzungsdatum, s.ergebnis, s.wirksam_ab, s.wirksam_bis, s.teilnahme_id, @batch_id
        FROM #v AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.zulassungsverfahren AS t WHERE t.aktenzeichen = s.aktenzeichen);
        SET @rows += @@ROWCOUNT;

        /* ---------- Status history ------------------------------------------------ */
        -- The XML only says "status X since date D". LEAD() looks at the NEXT row of the
        -- same procedure (ordered by date) and gives us the end of each status period.
        DROP TABLE IF EXISTS #status;
        SELECT v.n.value('@aktenzeichen', 'varchar(20)') AS aktenzeichen,
               s.n.value('@code', 'varchar(20)')          AS status_code,
               s.n.value('@ab', 'date')                   AS valid_from
        INTO #status
        FROM stg.zulassung_verfahren_xml AS x
        CROSS APPLY x.content.nodes('/Zulassungsverfahren/Verfahren') AS v(n)
        CROSS APPLY v.n.nodes('Statusverlauf/Status') AS s(n);

        DELETE FROM core.zulassungsverfahren_status
        WHERE verfahren_id IN (SELECT z.verfahren_id FROM core.zulassungsverfahren AS z JOIN #status AS s ON s.aktenzeichen = z.aktenzeichen);

        INSERT INTO core.zulassungsverfahren_status (verfahren_id, valid_from, valid_to, status_code, load_batch_id)
        SELECT z.verfahren_id, s.valid_from,
               LEAD(s.valid_from, 1, CAST('9999-12-31' AS DATE)) OVER (PARTITION BY s.aktenzeichen ORDER BY s.valid_from),
               s.status_code, @batch_id
        FROM #status AS s
        JOIN core.zulassungsverfahren AS z ON z.aktenzeichen = s.aktenzeichen;
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
