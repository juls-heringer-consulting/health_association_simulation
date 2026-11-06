/* =============================================================================
   401_load_referenz.sql
   core.usp_load_referenz: region, population, insurers, physician groups,
   EBM catalogue, ICD-10.

   PATTERN used by all core load procedures (read this one first):
     1. Read staging into a #temp table with proper data types (TRY_CONVERT:
        returns NULL instead of failing on bad input - bad rows are then caught by
        NOT NULL constraints or by the data-quality checks in sql/70_quality).
     2. UPSERT into core:
          UPDATE rows whose business key exists AND whose values changed
          INSERT rows whose business key does not exist yet
        Change detection uses  EXISTS (SELECT new values EXCEPT SELECT old values),
        which - unlike "a <> b" - also treats NULL vs. value as a change.
     3. Everything inside one transaction: the step either completes or leaves
        core untouched (SET XACT_ABORT ON + TRY/CATCH + ROLLBACK).
     4. Log start/end/row count in meta.load_step.
   Why not MERGE? MERGE works, but it has a long list of known pitfalls; separate
   UPDATE + INSERT statements are easier to read, debug and reason about.
   ============================================================================= */
USE KVSim;
GO

CREATE OR ALTER PROCEDURE core.usp_load_referenz
    @batch_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @batch_id = COALESCE(@batch_id, meta.fn_latest_batch_id());
    DECLARE @step_id INT, @rows INT = 0;
    EXEC meta.usp_step_start @batch_id = @batch_id, @step_name = N'core.usp_load_referenz', @step_id = @step_id OUTPUT;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* ---------- Kreis (from GeoJSON) ------------------------------------- */
        DROP TABLE IF EXISTS #kreis;
        SELECT f.ags, f.name, f.kreisart, f.verwaltungssitz, f.geo_breite, f.geo_laenge
        INTO #kreis
        FROM stg.statistik_kreise_geojson AS g
        CROSS APPLY OPENJSON(g.content, '$.features')
            WITH (ags             CHAR(5)       '$.properties.AGS',
                  name            NVARCHAR(100) '$.properties.GEN',
                  kreisart        NVARCHAR(30)  '$.properties.BEZ',
                  verwaltungssitz NVARCHAR(60)  '$.properties.SITZ',
                  geo_laenge      DECIMAL(8,5)  '$.geometry.coordinates[0]',   -- GeoJSON order is (lon, lat)!
                  geo_breite      DECIMAL(8,5)  '$.geometry.coordinates[1]') AS f;

        UPDATE k
           SET name = s.name, kreisart = s.kreisart, verwaltungssitz = s.verwaltungssitz,
               geo_breite = s.geo_breite, geo_laenge = s.geo_laenge,
               load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.kreis AS k
        JOIN #kreis AS s ON s.ags = k.ags
        WHERE EXISTS (SELECT s.name, s.kreisart, s.verwaltungssitz, s.geo_breite, s.geo_laenge
                      EXCEPT
                      SELECT k.name, k.kreisart, k.verwaltungssitz, k.geo_breite, k.geo_laenge);
        SET @rows += @@ROWCOUNT;

        INSERT INTO core.kreis (ags, name, kreisart, verwaltungssitz, geo_breite, geo_laenge, load_batch_id)
        SELECT s.ags, s.name, s.kreisart, s.verwaltungssitz, s.geo_breite, s.geo_laenge, @batch_id
        FROM #kreis AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.kreis AS k WHERE k.ags = s.ags);
        SET @rows += @@ROWCOUNT;

        /* ---------- Einwohner (statistics office CSV) ------------------------ */
        DROP TABLE IF EXISTS #einwohner;
        SELECT k.kreis_id,
               TRY_CONVERT(DATE, s.stichtag, 104)            AS stichtag,       -- style 104 = dd.mm.yyyy
               ag.altersgruppe_code,
               CASE s.geschlecht WHEN N'weiblich' THEN 'w' WHEN N'männlich' THEN 'm' END AS geschlecht,
               TRY_CAST(REPLACE(s.anzahl, '.', '') AS INT)   AS anzahl          -- "7.920" -> 7920
        INTO #einwohner
        FROM stg.statistik_bevoelkerung AS s
        JOIN core.kreis        AS k  ON k.ags = s.ags
        JOIN core.altersgruppe AS ag ON ag.statistik_bezeichnung = s.altersgruppe;   -- map the office's labels

        -- measurement data per reference date: replace the reference dates delivered
        DELETE FROM core.einwohner WHERE stichtag IN (SELECT stichtag FROM #einwohner);
        INSERT INTO core.einwohner (kreis_id, stichtag, altersgruppe_code, geschlecht, anzahl, load_batch_id)
        SELECT kreis_id, stichtag, altersgruppe_code, geschlecht, anzahl, @batch_id FROM #einwohner;
        SET @rows += @@ROWCOUNT;

        /* ---------- Krankenkassen ------------------------------------------------ */
        DROP TABLE IF EXISTS #kasse;
        SELECT ik, name, kassenart AS kassenart_code INTO #kasse FROM stg.kassen_krankenkassen;

        UPDATE k SET name = s.name, kassenart_code = s.kassenart_code, load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.krankenkasse AS k JOIN #kasse AS s ON s.ik = k.ik
        WHERE EXISTS (SELECT s.name, s.kassenart_code EXCEPT SELECT k.name, k.kassenart_code);
        SET @rows += @@ROWCOUNT;

        INSERT INTO core.krankenkasse (ik, name, kassenart_code, load_batch_id)
        SELECT s.ik, s.name, s.kassenart_code, @batch_id FROM #kasse AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.krankenkasse AS k WHERE k.ik = s.ik);
        SET @rows += @@ROWCOUNT;

        /* ---------- Arztgruppen (Bedarfsplanung workbook) ------------------------ */
        DROP TABLE IF EXISTS #arztgruppe;
        SELECT code AS arztgruppe_code, arztgruppe AS bezeichnung, versorgungsebene,
               planungsbereichstyp AS planungsbereich_typ,
               TRY_CAST(verhaeltniszahl AS INT) AS verhaeltniszahl,
               -- rule of the Bedarfsplanungs-Richtlinie (simplified): 75 % for Hausaerzte, 50 % otherwise
               CAST(IIF(versorgungsebene = N'hausärztliche Versorgung', 75.0, 50.0) AS DECIMAL(5,1)) AS schwelle_unterversorgung_pct
        INTO #arztgruppe
        FROM stg.bedarfsplanung_arztgruppen;

        UPDATE a SET bezeichnung = s.bezeichnung, versorgungsebene = s.versorgungsebene,
                     planungsbereich_typ = s.planungsbereich_typ, verhaeltniszahl = s.verhaeltniszahl,
                     schwelle_unterversorgung_pct = s.schwelle_unterversorgung_pct,
                     load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.arztgruppe AS a JOIN #arztgruppe AS s ON s.arztgruppe_code = a.arztgruppe_code
        WHERE EXISTS (SELECT s.bezeichnung, s.versorgungsebene, s.planungsbereich_typ, s.verhaeltniszahl, s.schwelle_unterversorgung_pct
                      EXCEPT
                      SELECT a.bezeichnung, a.versorgungsebene, a.planungsbereich_typ, a.verhaeltniszahl, a.schwelle_unterversorgung_pct);
        SET @rows += @@ROWCOUNT;

        INSERT INTO core.arztgruppe (arztgruppe_code, bezeichnung, versorgungsebene, planungsbereich_typ, verhaeltniszahl, schwelle_unterversorgung_pct, load_batch_id)
        SELECT s.arztgruppe_code, s.bezeichnung, s.versorgungsebene, s.planungsbereich_typ, s.verhaeltniszahl, s.schwelle_unterversorgung_pct, @batch_id
        FROM #arztgruppe AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.arztgruppe AS a WHERE a.arztgruppe_code = s.arztgruppe_code);
        SET @rows += @@ROWCOUNT;

        /* ---------- Fachgruppen (KBV list + mapping from the workbook) ------------ */
        -- The workbook stores several Fachgruppen in ONE cell ("01, 03") - a violation of the
        -- first normal form. STRING_SPLIT turns the list into one row per value.
        DROP TABLE IF EXISTS #fachgruppe;
        SELECT k.schluessel AS fachgruppe_code, k.bezeichnung, m.arztgruppe_code
        INTO #fachgruppe
        FROM stg.kbv_arztgruppenschluessel AS k
        LEFT JOIN (
            SELECT LTRIM(RTRIM(v.value)) AS fachgruppe_code, a.code AS arztgruppe_code
            FROM stg.bedarfsplanung_arztgruppen AS a
            CROSS APPLY STRING_SPLIT(a.fachgruppenschluessel, ',') AS v
        ) AS m ON m.fachgruppe_code = k.schluessel;

        UPDATE f SET bezeichnung = s.bezeichnung, arztgruppe_code = s.arztgruppe_code, load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.fachgruppe AS f JOIN #fachgruppe AS s ON s.fachgruppe_code = f.fachgruppe_code
        WHERE EXISTS (SELECT s.bezeichnung, s.arztgruppe_code EXCEPT SELECT f.bezeichnung, f.arztgruppe_code);
        SET @rows += @@ROWCOUNT;

        INSERT INTO core.fachgruppe (fachgruppe_code, bezeichnung, arztgruppe_code, load_batch_id)
        SELECT s.fachgruppe_code, s.bezeichnung, s.arztgruppe_code, @batch_id FROM #fachgruppe AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.fachgruppe AS f WHERE f.fachgruppe_code = s.fachgruppe_code);
        SET @rows += @@ROWCOUNT;

        /* ---------- TSS specialty mapping (reference data owned by the DWH team) --- */
        DROP TABLE IF EXISTS #tss_map;
        SELECT v.tss_fachgebiet, v.arztgruppe_code
        INTO #tss_map
        FROM (VALUES (N'Hausarzt', 'HA'), (N'Kinder- und Jugendmedizin', 'KI'), (N'Augenheilkunde', 'AU'),
                     (N'Frauenheilkunde', 'FR'), (N'Hals-Nasen-Ohren-Heilkunde', 'HN'), (N'Dermatologie', 'HT'),
                     (N'Orthopädie', 'OR'), (N'Neurologie/Nervenheilkunde', 'NE'), (N'Psychotherapie', 'PT'),
                     (N'Innere Medizin', 'FI')) AS v (tss_fachgebiet, arztgruppe_code);

        UPDATE m SET arztgruppe_code = s.arztgruppe_code, loaded_at = SYSDATETIME()
        FROM core.tss_fachgebiet AS m JOIN #tss_map AS s ON s.tss_fachgebiet = m.tss_fachgebiet
        WHERE m.arztgruppe_code <> s.arztgruppe_code;
        INSERT INTO core.tss_fachgebiet (tss_fachgebiet, arztgruppe_code)
        SELECT s.tss_fachgebiet, s.arztgruppe_code FROM #tss_map AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.tss_fachgebiet AS m WHERE m.tss_fachgebiet = s.tss_fachgebiet);

        /* ---------- EBM catalogue (XML) ------------------------------------------ */
        -- nodes() turns every matching XML element into a row; value() reads one item from it.
        DROP TABLE IF EXISTS #kapitel;
        SELECT k.n.value('@nr', 'tinyint')                  AS kapitel_nr,
               k.n.value('@bereich', 'varchar(5)')          AS bereich,
               k.n.value('@bezeichnung', 'nvarchar(100)')   AS bezeichnung
        INTO #kapitel
        FROM stg.kbv_ebm_xml AS x
        CROSS APPLY x.content.nodes('/EBM/Kapitel') AS k(n);

        UPDATE t SET bereich = s.bereich, bezeichnung = s.bezeichnung, load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.ebm_kapitel AS t JOIN #kapitel AS s ON s.kapitel_nr = t.kapitel_nr
        WHERE EXISTS (SELECT s.bereich, s.bezeichnung EXCEPT SELECT t.bereich, t.bezeichnung);
        INSERT INTO core.ebm_kapitel (kapitel_nr, bereich, bezeichnung, load_batch_id)
        SELECT s.kapitel_nr, s.bereich, s.bezeichnung, @batch_id FROM #kapitel AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.ebm_kapitel AS t WHERE t.kapitel_nr = s.kapitel_nr);

        DROP TABLE IF EXISTS #gop;
        SELECT g.n.value('@code', 'char(5)')                         AS gop_code,
               g.n.value('(Titel/text())[1]', 'nvarchar(200)')        AS bezeichnung,
               k.n.value('@nr', 'tinyint')                            AS kapitel_nr,
               g.n.value('@punkte', 'int')                            AS punktzahl,
               g.n.value('@pruefzeit_min', 'smallint')                AS pruefzeit_min,      -- missing attribute -> NULL
               CAST(IIF(g.n.value('@extrabudgetaer', 'varchar(4)') = 'ja', 1, 0) AS BIT) AS ist_extrabudgetaer,
               g.n.value('@qs_bereich', 'varchar(5)')                 AS qs_bereich_code
        INTO #gop
        FROM stg.kbv_ebm_xml AS x
        CROSS APPLY x.content.nodes('/EBM/Kapitel') AS k(n)
        CROSS APPLY k.n.nodes('GOP') AS g(n);

        UPDATE t SET bezeichnung = s.bezeichnung, kapitel_nr = s.kapitel_nr, punktzahl = s.punktzahl,
                     pruefzeit_min = s.pruefzeit_min, ist_extrabudgetaer = s.ist_extrabudgetaer,
                     qs_bereich_code = s.qs_bereich_code, load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.gop AS t JOIN #gop AS s ON s.gop_code = t.gop_code
        WHERE EXISTS (SELECT s.bezeichnung, s.kapitel_nr, s.punktzahl, s.pruefzeit_min, s.ist_extrabudgetaer, s.qs_bereich_code
                      EXCEPT
                      SELECT t.bezeichnung, t.kapitel_nr, t.punktzahl, t.pruefzeit_min, t.ist_extrabudgetaer, t.qs_bereich_code);
        SET @rows += @@ROWCOUNT;

        INSERT INTO core.gop (gop_code, bezeichnung, kapitel_nr, punktzahl, pruefzeit_min, ist_extrabudgetaer, qs_bereich_code, load_batch_id)
        SELECT s.gop_code, s.bezeichnung, s.kapitel_nr, s.punktzahl, s.pruefzeit_min, s.ist_extrabudgetaer, s.qs_bereich_code, @batch_id
        FROM #gop AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.gop AS t WHERE t.gop_code = s.gop_code);
        SET @rows += @@ROWCOUNT;

        DROP TABLE IF EXISTS #ow;
        SELECT o.n.value('@jahr', 'smallint') AS jahr, o.n.value('@euro_je_punkt', 'decimal(9,6)') AS euro_je_punkt
        INTO #ow
        FROM stg.kbv_ebm_xml AS x
        CROSS APPLY x.content.nodes('/EBM/Orientierungswert') AS o(n);

        UPDATE t SET euro_je_punkt = s.euro_je_punkt, load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.orientierungswert AS t JOIN #ow AS s ON s.jahr = t.jahr
        WHERE t.euro_je_punkt <> s.euro_je_punkt;
        INSERT INTO core.orientierungswert (jahr, euro_je_punkt, load_batch_id)
        SELECT s.jahr, s.euro_je_punkt, @batch_id FROM #ow AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.orientierungswert AS t WHERE t.jahr = s.jahr);

        /* ---------- ICD-10-GM ------------------------------------------------------- */
        DROP TABLE IF EXISTS #icd;
        SELECT code AS icd_code, titel AS bezeichnung, kapitel INTO #icd FROM stg.bfarm_icd10;

        UPDATE t SET bezeichnung = s.bezeichnung, kapitel = s.kapitel, load_batch_id = @batch_id, loaded_at = SYSDATETIME()
        FROM core.icd10 AS t JOIN #icd AS s ON s.icd_code = t.icd_code
        WHERE EXISTS (SELECT s.bezeichnung, s.kapitel EXCEPT SELECT t.bezeichnung, t.kapitel);
        SET @rows += @@ROWCOUNT;
        INSERT INTO core.icd10 (icd_code, bezeichnung, kapitel, load_batch_id)
        SELECT s.icd_code, s.bezeichnung, s.kapitel, @batch_id FROM #icd AS s
        WHERE NOT EXISTS (SELECT 1 FROM core.icd10 AS t WHERE t.icd_code = s.icd_code);
        SET @rows += @@ROWCOUNT;

        COMMIT TRANSACTION;
        EXEC meta.usp_step_end @step_id = @step_id, @status = 'OK', @rows_affected = @rows;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC meta.usp_step_end @step_id = @step_id, @status = 'FAILED', @message = @msg;
        THROW;   -- re-raise the original error to the caller
    END CATCH
END
GO
