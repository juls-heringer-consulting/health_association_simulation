/* =============================================================================
   402_load_arztregister.sql
   core.usp_load_arztregister: Aerzte, Praxen (Betriebsstaetten), Teilnahmen and
   their status history.  Pattern: see 401_load_referenz.sql.

   Master data deletion policy: rows missing from a delivery are NOT deleted in
   core. A register never "forgets" a person; ending a Teilnahme is expressed by
   valid_to / status BEENDET, not by deleting rows.
   ============================================================================= */
USE KVSim;
GO

CREATE OR ALTER PROCEDURE core.usp_load_arztregister
    @batch_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @batch_id = COALESCE(@batch_id, meta.fn_latest_batch_id());
    DECLARE @step_id INT, @rows INT = 0;
    EXEC meta.usp_step_start @batch_id = @batch_id, @step_name = N'core.usp_load_arztregister', @step_id = @step_id OUTPUT;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* ---------- Arzt ------------------------------------------------------- */
        DROP TABLE IF EXISTS #arzt;
        SELECT lanr, efn, titel, vorname, nachname, geschlecht,
               TRY_CAST(geburtsjahr AS SMALLINT) AS geburtsjahr,
               fachgruppe AS fachgruppe_code
        INTO #arzt
        FROM stg.arztregister_aerzte;

        UPDATE a
           SET efn = s.efn, titel = s.titel, vorname = s.vorname, nachname = s.nachname, geschlecht = s.geschlecht,
               geburtsjahr = s.geburtsjahr, fachgruppe_code = s.fachgruppe_code,
               load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.arzt AS a
        JOIN #arzt AS s ON s.lanr = a.lanr
        WHERE EXISTS (SELECT s.efn, s.titel, s.vorname, s.nachname, s.geschlecht, s.geburtsjahr, s.fachgruppe_code
                      EXCEPT
                      SELECT a.efn, a.titel, a.vorname, a.nachname, a.geschlecht, a.geburtsjahr, a.fachgruppe_code);
        SET @rows += @@ROWCOUNT;

        INSERT INTO core.arzt (lanr, efn, titel, vorname, nachname, geschlecht, geburtsjahr, fachgruppe_code, load_batch_id)
        SELECT s.lanr, s.efn, s.titel, s.vorname, s.nachname, s.geschlecht, s.geburtsjahr, s.fachgruppe_code, @batch_id
        FROM #arzt AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.arzt AS a WHERE a.lanr = s.lanr);
        SET @rows += @@ROWCOUNT;

        /* ---------- Praxis (Betriebsstaette) ------------------------------------ */
        DROP TABLE IF EXISTS #praxis;
        SELECT s.bsnr, s.name, s.kooperationsform AS kooperationsform_code, s.strasse, s.ort, k.kreis_id,
               TRY_CONVERT(DATE, s.gruendungsdatum, 104) AS gruendungsdatum
        INTO #praxis
        FROM stg.arztregister_betriebsstaetten AS s
        JOIN core.kreis AS k ON k.ags = s.kreis_ags;    -- surrogate key lookup: business key AGS -> kreis_id

        UPDATE p
           SET name = s.name, kooperationsform_code = s.kooperationsform_code, strasse = s.strasse, ort = s.ort,
               kreis_id = s.kreis_id, gruendungsdatum = s.gruendungsdatum,
               load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.praxis AS p
        JOIN #praxis AS s ON s.bsnr = p.bsnr
        WHERE EXISTS (SELECT s.name, s.kooperationsform_code, s.strasse, s.ort, s.kreis_id, s.gruendungsdatum
                      EXCEPT
                      SELECT p.name, p.kooperationsform_code, p.strasse, p.ort, p.kreis_id, p.gruendungsdatum);
        SET @rows += @@ROWCOUNT;

        INSERT INTO core.praxis (bsnr, name, kooperationsform_code, strasse, ort, kreis_id, gruendungsdatum, load_batch_id)
        SELECT s.bsnr, s.name, s.kooperationsform_code, s.strasse, s.ort, s.kreis_id, s.gruendungsdatum, @batch_id
        FROM #praxis AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.praxis AS p WHERE p.bsnr = s.bsnr);
        SET @rows += @@ROWCOUNT;

        /* ---------- Teilnahme --------------------------------------------------- */
        DROP TABLE IF EXISTS #teilnahme;
        SELECT a.arzt_id, p.praxis_id, s.teilnahmeform AS teilnahmeform_code,
               TRY_CAST(REPLACE(s.anrechnungsfaktor, ',', '.') AS DECIMAL(3,2))   AS anrechnungsfaktor,  -- "0,75" -> 0.75
               TRY_CONVERT(DATE, s.gueltig_ab, 104)                                AS valid_from,
               COALESCE(TRY_CONVERT(DATE, s.gueltig_bis, 104), CAST('9999-12-31' AS DATE)) AS valid_to   -- empty = open end
        INTO #teilnahme
        FROM stg.arztregister_teilnahmen AS s
        JOIN core.arzt   AS a ON a.lanr = s.lanr
        JOIN core.praxis AS p ON p.bsnr = s.bsnr;

        UPDATE t
           SET teilnahmeform_code = s.teilnahmeform_code, anrechnungsfaktor = s.anrechnungsfaktor, valid_to = s.valid_to,
               load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.teilnahme AS t
        JOIN #teilnahme AS s ON s.arzt_id = t.arzt_id AND s.praxis_id = t.praxis_id AND s.valid_from = t.valid_from
        WHERE EXISTS (SELECT s.teilnahmeform_code, s.anrechnungsfaktor, s.valid_to
                      EXCEPT
                      SELECT t.teilnahmeform_code, t.anrechnungsfaktor, t.valid_to);
        SET @rows += @@ROWCOUNT;

        INSERT INTO core.teilnahme (arzt_id, praxis_id, teilnahmeform_code, anrechnungsfaktor, valid_from, valid_to, load_batch_id)
        SELECT s.arzt_id, s.praxis_id, s.teilnahmeform_code, s.anrechnungsfaktor, s.valid_from, s.valid_to, @batch_id
        FROM #teilnahme AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.teilnahme AS t
                          WHERE t.arzt_id = s.arzt_id AND t.praxis_id = s.praxis_id AND t.valid_from = s.valid_from);
        SET @rows += @@ROWCOUNT;

        /* ---------- Teilnahme status history ----------------------------------- */
        -- The source always delivers the COMPLETE history of each Teilnahme, so we
        -- replace the history of every Teilnahme contained in the delivery.
        DROP TABLE IF EXISTS #status;
        SELECT t.teilnahme_id,
               TRY_CONVERT(DATE, s.status_ab, 104) AS valid_from,
               COALESCE(TRY_CONVERT(DATE, s.status_bis, 104), CAST('9999-12-31' AS DATE)) AS valid_to,
               s.status AS status_code
        INTO #status
        FROM stg.arztregister_teilnahme_status AS s
        JOIN core.arzt   AS a ON a.lanr = s.lanr
        JOIN core.praxis AS p ON p.bsnr = s.bsnr
        JOIN core.teilnahme AS t
          ON t.arzt_id = a.arzt_id AND t.praxis_id = p.praxis_id AND t.valid_from = TRY_CONVERT(DATE, s.teilnahme_ab, 104);

        DELETE FROM core.teilnahme_status WHERE teilnahme_id IN (SELECT teilnahme_id FROM #status);
        INSERT INTO core.teilnahme_status (teilnahme_id, valid_from, valid_to, status_code, load_batch_id)
        SELECT teilnahme_id, valid_from, valid_to, status_code, @batch_id FROM #status;
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
