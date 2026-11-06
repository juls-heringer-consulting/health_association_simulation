/* =============================================================================
   407_load_kommunikation.sql
   core.usp_load_kommunikation: documents from four sources into ONE table, plus
   their links to doctors, practices and procedures.

     source                     linked by
     -------------------------  ---------------------------------------------
     CRM tickets (JSON)         structured fields requester.lanr / .bsnr
     complaints (.txt)          header line "Bezug-BSNR: ..." added at intake
     minutes (Markdown)         file numbers (Aktenzeichen) found IN the text
     notices (inside XML)       the procedure the XML element belongs to
   ============================================================================= */
USE KVSim;
GO

CREATE OR ALTER PROCEDURE core.usp_load_kommunikation
    @batch_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @batch_id = COALESCE(@batch_id, meta.fn_latest_batch_id());
    DECLARE @step_id INT, @rows INT = 0;
    EXEC meta.usp_step_start @batch_id = @batch_id, @step_name = N'core.usp_load_kommunikation', @step_id = @step_id OUTPUT;

    BEGIN TRY
        CREATE TABLE #dok (
            dokumenttyp_code VARCHAR(10), quelle_referenz NVARCHAR(200), titel NVARCHAR(300),
            dokument_datum DATE, kategorie NVARCHAR(40), status VARCHAR(10), inhalt NVARCHAR(MAX));
        CREATE TABLE #bezug (
            quelle_referenz NVARCHAR(200), lanr CHAR(9), bsnr CHAR(9), aktenzeichen VARCHAR(20), bezugsart VARCHAR(12));

        /* ---------- 1. Mitgliederanfragen (CRM JSON) -------------------------------------- */
        SELECT t.*
        INTO #anfrage
        FROM stg.mitgliederservice_anfragen_json AS j
        CROSS APPLY OPENJSON(j.content, '$.tickets')
            WITH (ticket_id  NVARCHAR(30)      '$.ticketId',
                  created_at DATETIMEOFFSET(0) '$.createdAt',
                  topic      NVARCHAR(40)      '$.topic',
                  subject    NVARCHAR(300)     '$.subject',
                  body       NVARCHAR(MAX)     '$.body',
                  status     VARCHAR(10)       '$.status',
                  lanr       CHAR(9)           '$.requester.lanr',
                  bsnr       CHAR(9)           '$.requester.bsnr') AS t;

        INSERT INTO #dok SELECT 'ANFRAGE', ticket_id, subject, CAST(created_at AS DATE), topic, status, body FROM #anfrage;
        INSERT INTO #bezug (quelle_referenz, lanr, bezugsart) SELECT ticket_id, lanr, 'ABSENDER' FROM #anfrage WHERE lanr IS NOT NULL;
        INSERT INTO #bezug (quelle_referenz, bsnr, bezugsart) SELECT ticket_id, bsnr, 'ABSENDER' FROM #anfrage WHERE bsnr IS NOT NULL;

        /* ---------- 2. Beschwerden (text files with header lines) -------------------------- */
        INSERT INTO #dok
        SELECT 'BESCHWERDE', b.source_file,
               core.fn_text_field(b.content, N'Betreff'),
               TRY_CONVERT(DATE, core.fn_text_field(b.content, N'Eingangsdatum'), 104),
               core.fn_text_field(b.content, N'Kategorie'),
               NULL, b.content
        FROM stg.beschwerden_txt AS b;
        INSERT INTO #bezug (quelle_referenz, bsnr, bezugsart)
        SELECT b.source_file, core.fn_text_field(b.content, N'Bezug-BSNR'), 'BETROFFEN'
        FROM stg.beschwerden_txt AS b
        WHERE core.fn_text_field(b.content, N'Bezug-BSNR') IS NOT NULL;

        /* ---------- 3. Sitzungsprotokolle (Markdown with front matter) --------------------- */
        INSERT INTO #dok
        SELECT 'PROTOKOLL', p.source_file,
               CONCAT(N'Niederschrift Zulassungsausschuss ', FORMAT(TRY_CONVERT(DATE, core.fn_text_field(p.content, N'sitzung')), 'dd.MM.yyyy')),
               TRY_CONVERT(DATE, core.fn_text_field(p.content, N'sitzung')),
               N'Zulassungsausschuss', NULL, p.content
        FROM stg.zulassung_protokolle AS p;
        -- link by searching every known file number in the text (fine for small volumes;
        -- at scale one would extract the numbers once, e.g. with a regex in the loader)
        INSERT INTO #bezug (quelle_referenz, aktenzeichen, bezugsart)
        SELECT p.source_file, v.aktenzeichen, 'GEGENSTAND'
        FROM stg.zulassung_protokolle AS p
        JOIN core.zulassungsverfahren AS v ON p.content LIKE N'%' + v.aktenzeichen + N'%';

        /* ---------- 4. Bescheide (free text embedded in the Zulassung XML) ------------------ */
        SELECT v.n.value('@aktenzeichen', 'varchar(20)')                AS aktenzeichen,
               v.n.value('(Antragsteller/@lanr)[1]', 'char(9)')         AS lanr,
               v.n.value('(Bescheid/@datum)[1]', 'date')                AS bescheid_datum,
               v.n.value('(Bescheid/text())[1]', 'nvarchar(max)')       AS bescheid_text
        INTO #bescheid
        FROM stg.zulassung_verfahren_xml AS x
        CROSS APPLY x.content.nodes('/Zulassungsverfahren/Verfahren[Bescheid]') AS v(n);   -- only elements WITH a Bescheid

        INSERT INTO #dok
        SELECT 'BESCHEID', aktenzeichen + N'/Bescheid', N'Bescheid ' + aktenzeichen, bescheid_datum,
               N'Zulassungsausschuss', NULL, bescheid_text
        FROM #bescheid;
        INSERT INTO #bezug (quelle_referenz, aktenzeichen, bezugsart) SELECT aktenzeichen + N'/Bescheid', aktenzeichen, 'GEGENSTAND' FROM #bescheid;
        INSERT INTO #bezug (quelle_referenz, lanr, bezugsart)         SELECT aktenzeichen + N'/Bescheid', lanr, 'BETROFFEN' FROM #bescheid;

        BEGIN TRANSACTION;

        /* ---------- Upsert documents ------------------------------------------------------- */
        UPDATE d
           SET dokumenttyp_code = s.dokumenttyp_code, titel = s.titel, dokument_datum = s.dokument_datum,
               kategorie = s.kategorie, status = s.status, inhalt = s.inhalt,
               inhalt_sha256 = HASHBYTES('SHA2_256', s.inhalt), load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.dokument AS d
        JOIN #dok AS s ON s.quelle_referenz = d.quelle_referenz
        WHERE d.inhalt_sha256 <> HASHBYTES('SHA2_256', s.inhalt)       -- compare fingerprints, not 2 GB texts
           OR EXISTS (SELECT s.titel, s.dokument_datum, s.kategorie, s.status EXCEPT SELECT d.titel, d.dokument_datum, d.kategorie, d.status);
        SET @rows += @@ROWCOUNT;

        INSERT INTO core.dokument (dokumenttyp_code, quelle_referenz, titel, dokument_datum, kategorie, status, inhalt, inhalt_sha256, load_batch_id)
        SELECT s.dokumenttyp_code, s.quelle_referenz, s.titel, s.dokument_datum, s.kategorie, s.status, s.inhalt,
               HASHBYTES('SHA2_256', s.inhalt), @batch_id
        FROM #dok AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.dokument AS d WHERE d.quelle_referenz = s.quelle_referenz);
        SET @rows += @@ROWCOUNT;

        /* ---------- Replace links of all delivered documents -------------------------------- */
        DELETE b FROM core.dokument_bezug AS b
        JOIN core.dokument AS d ON d.dokument_id = b.dokument_id
        WHERE d.quelle_referenz IN (SELECT quelle_referenz FROM #dok);

        INSERT INTO core.dokument_bezug (dokument_id, arzt_id, praxis_id, verfahren_id, bezugsart, load_batch_id)
        SELECT DISTINCT d.dokument_id, a.arzt_id, p.praxis_id, v.verfahren_id, b.bezugsart, @batch_id
        FROM #bezug AS b
        JOIN core.dokument AS d ON d.quelle_referenz = b.quelle_referenz
        LEFT JOIN core.arzt AS a ON a.lanr = b.lanr
        LEFT JOIN core.praxis AS p ON p.bsnr = b.bsnr
        LEFT JOIN core.zulassungsverfahren AS v ON v.aktenzeichen = b.aktenzeichen
        WHERE COALESCE(a.arzt_id, p.praxis_id, v.verfahren_id) IS NOT NULL;
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
