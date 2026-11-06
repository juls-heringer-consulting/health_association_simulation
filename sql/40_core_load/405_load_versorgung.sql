/* =============================================================================
   405_load_versorgung.sql
   core.usp_load_versorgung: TSS requests (JSON API pages), Bereitschaftspraxen
   and the Bereitschaftsdienst rota (CSV).
   ============================================================================= */
USE KVSim;
GO

CREATE OR ALTER PROCEDURE core.usp_load_versorgung
    @batch_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @batch_id = COALESCE(@batch_id, meta.fn_latest_batch_id());
    DECLARE @step_id INT, @rows INT = 0;
    EXEC meta.usp_step_start @batch_id = @batch_id, @step_name = N'core.usp_load_versorgung', @step_id = @step_id OUTPUT;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* ---------- TSS requests: OPENJSON turns the "items" array into rows -------- */
        DROP TABLE IF EXISTS #tss;
        SELECT i.id                       AS tss_anfrage_uuid,
               i.created_at               AS eingang_zeitpunkt,
               i.channel                  AS kanal,
               m.arztgruppe_code,
               i.dringlichkeit,
               k.kreis_id                 AS patient_kreis_id,
               ag.altersgruppe_code       AS patient_altersgruppe_code,
               i.status,
               p.praxis_id,
               i.termin_start             AS termin_zeitpunkt,
               i.vermittlungscode,
               i.wahrgenommen             AS termin_wahrgenommen
        INTO #tss
        FROM stg.tss_anfragen_json AS j
        CROSS APPLY OPENJSON(j.content, '$.items')
            WITH (id               UNIQUEIDENTIFIER  '$.id',
                  created_at       DATETIMEOFFSET(0) '$.createdAt',
                  channel          VARCHAR(10)       '$.channel',
                  fachgebiet       NVARCHAR(60)      '$.fachgebiet',
                  dringlichkeit    VARCHAR(10)       '$.dringlichkeit',
                  kreis_ags        CHAR(5)           '$.patient.kreisAgs',
                  alter_jahre      INT               '$.patient.alter',        -- ALTER is a keyword -> rename
                  status           VARCHAR(20)       '$.status',
                  termin_bsnr      CHAR(9)           '$.termin.bsnr',          -- "termin": null -> all NULL
                  termin_start     DATETIMEOFFSET(0) '$.termin.start',
                  vermittlungscode CHAR(14)          '$.termin.vermittlungscode',
                  wahrgenommen     BIT               '$.termin.wahrgenommen') AS i
        JOIN core.tss_fachgebiet AS m  ON m.tss_fachgebiet = i.fachgebiet
        JOIN core.kreis          AS k  ON k.ags = i.kreis_ags
        JOIN core.altersgruppe   AS ag ON i.alter_jahre BETWEEN ag.alter_von AND ISNULL(ag.alter_bis, 200)
        LEFT JOIN core.praxis    AS p  ON p.bsnr = i.termin_bsnr;

        UPDATE t
           SET eingang_zeitpunkt = s.eingang_zeitpunkt, kanal = s.kanal, arztgruppe_code = s.arztgruppe_code,
               dringlichkeit = s.dringlichkeit, patient_kreis_id = s.patient_kreis_id,
               patient_altersgruppe_code = s.patient_altersgruppe_code, status = s.status, praxis_id = s.praxis_id,
               termin_zeitpunkt = s.termin_zeitpunkt, vermittlungscode = s.vermittlungscode,
               termin_wahrgenommen = s.termin_wahrgenommen, load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.tss_anfrage AS t
        JOIN #tss AS s ON s.tss_anfrage_uuid = t.tss_anfrage_uuid
        WHERE EXISTS (SELECT s.eingang_zeitpunkt, s.kanal, s.arztgruppe_code, s.dringlichkeit, s.patient_kreis_id,
                             s.patient_altersgruppe_code, s.status, s.praxis_id, s.termin_zeitpunkt, s.vermittlungscode, s.termin_wahrgenommen
                      EXCEPT
                      SELECT t.eingang_zeitpunkt, t.kanal, t.arztgruppe_code, t.dringlichkeit, t.patient_kreis_id,
                             t.patient_altersgruppe_code, t.status, t.praxis_id, t.termin_zeitpunkt, t.vermittlungscode, t.termin_wahrgenommen);
        SET @rows += @@ROWCOUNT;

        INSERT INTO core.tss_anfrage (tss_anfrage_uuid, eingang_zeitpunkt, kanal, arztgruppe_code, dringlichkeit, patient_kreis_id,
                                      patient_altersgruppe_code, status, praxis_id, termin_zeitpunkt, vermittlungscode,
                                      termin_wahrgenommen, load_batch_id)
        SELECT s.tss_anfrage_uuid, s.eingang_zeitpunkt, s.kanal, s.arztgruppe_code, s.dringlichkeit, s.patient_kreis_id,
               s.patient_altersgruppe_code, s.status, s.praxis_id, s.termin_zeitpunkt, s.vermittlungscode,
               s.termin_wahrgenommen, @batch_id
        FROM #tss AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.tss_anfrage AS t WHERE t.tss_anfrage_uuid = s.tss_anfrage_uuid);
        SET @rows += @@ROWCOUNT;

        /* ---------- Bereitschaftsdienstpraxen ------------------------------------------- */
        DROP TABLE IF EXISTS #np;
        SELECT s.kennung, s.name, s.ort, k.kreis_id INTO #np
        FROM stg.bd_bereitschaftspraxen AS s JOIN core.kreis AS k ON k.ags = s.kreis_ags;

        UPDATE t SET name = s.name, ort = s.ort, kreis_id = s.kreis_id, load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.notfallpraxis AS t JOIN #np AS s ON s.kennung = t.kennung
        WHERE EXISTS (SELECT s.name, s.ort, s.kreis_id EXCEPT SELECT t.name, t.ort, t.kreis_id);
        INSERT INTO core.notfallpraxis (kennung, name, ort, kreis_id, load_batch_id)
        SELECT s.kennung, s.name, s.ort, s.kreis_id, @batch_id FROM #np AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.notfallpraxis AS t WHERE t.kennung = s.kennung);

        /* ---------- Dienstplan --------------------------------------------------------- */
        -- The rota stores a date plus "18:00" - "08:00". An end time at or before the start
        -- time means the shift ends on the NEXT day.
        DROP TABLE IF EXISTS #dienst;
        SELECT s.dienst_id AS dienst_nr, np.notfallpraxis_id,
               DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), x.t_beginn), CAST(x.tag AS DATETIME2(0))) AS beginn,
               DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), x.t_ende),
                       CAST(DATEADD(DAY, IIF(x.t_ende <= x.t_beginn, 1, 0), x.tag) AS DATETIME2(0)))           AS ende,
               a.arzt_id, ag.arzt_id AS getauscht_von_arzt_id
        INTO #dienst
        FROM stg.bd_dienstplan AS s
        CROSS APPLY (SELECT TRY_CONVERT(DATE, s.datum, 104)    AS tag,
                            TRY_CONVERT(TIME(0), s.beginn)     AS t_beginn,
                            TRY_CONVERT(TIME(0), s.ende)       AS t_ende) AS x
        JOIN core.notfallpraxis AS np ON np.kennung = s.kennung
        JOIN core.arzt AS a ON a.lanr = s.lanr
        LEFT JOIN core.arzt AS ag ON ag.lanr = s.getauscht_von_lanr;

        UPDATE t SET notfallpraxis_id = s.notfallpraxis_id, beginn = s.beginn, ende = s.ende, arzt_id = s.arzt_id,
                     getauscht_von_arzt_id = s.getauscht_von_arzt_id, load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.bereitschaftsdienst AS t JOIN #dienst AS s ON s.dienst_nr = t.dienst_nr
        WHERE EXISTS (SELECT s.notfallpraxis_id, s.beginn, s.ende, s.arzt_id, s.getauscht_von_arzt_id
                      EXCEPT
                      SELECT t.notfallpraxis_id, t.beginn, t.ende, t.arzt_id, t.getauscht_von_arzt_id);
        SET @rows += @@ROWCOUNT;

        INSERT INTO core.bereitschaftsdienst (dienst_nr, notfallpraxis_id, beginn, ende, arzt_id, getauscht_von_arzt_id, load_batch_id)
        SELECT s.dienst_nr, s.notfallpraxis_id, s.beginn, s.ende, s.arzt_id, s.getauscht_von_arzt_id, @batch_id
        FROM #dienst AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.bereitschaftsdienst AS t WHERE t.dienst_nr = s.dienst_nr);
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
