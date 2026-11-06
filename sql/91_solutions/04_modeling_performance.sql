/* =============================================================================
   SOLUTIONS - Level 4: Modelling and performance
   Concepts: extending a normalised model, key design, SCD type 2 (classic
             incremental algorithm), columnstore vs. rowstore, incremental loads,
             Row-Level Security
   Try the tasks in sql/90_exercises/04_modeling_performance.sql first!

   IMPORTANT: these solutions change the schema only TEMPORARILY. Every demo either
   runs inside BEGIN TRANSACTION ... ROLLBACK, works on #temp tables, or drops what
   it created at the end. After running this file the database is unchanged.
   (DDL such as CREATE TABLE can be rolled back in SQL Server - unlike in some other
   database systems.)

   German terms used in this file:
     Betriebsstaette (BSNR)        practice site; Hauptbetriebsstaette = main site
     Nebenbetriebsstaette (NBSNR)  additional site of the same practice (branch)
     LANR-Stamm                    first 7 digits of the LANR (6-digit id + check digit),
                                   lifelong; digits 8-9 = Fachgruppe
     Kooperationsform              EP (Einzelpraxis), BAG (joint practice), MVZ
     Bezirksstelle                 regional office of a KV
   ============================================================================= */
USE KVSim;
GO
SET XACT_ABORT ON;   -- any error aborts the batch AND rolls back the open transaction
GO

/* -----------------------------------------------------------------------------
   4.1  Model Nebenbetriebsstaetten (secondary practice sites)
   -----------------------------------------------------------------------------
   Design decisions:
   * core.praxis stays the practice (organisation + main site, BSNR).
   * A new entity core.nebenbetriebsstaette (1:n to praxis) with its own business key
     NBSNR, its own location (ort, kreis) and a validity interval - branches open and close.
   * Where was a service performed? core.leistung gets an OPTIONAL foreign key
     nebenbetriebsstaette_id (NULL = main site). Optional, because most services are
     performed at the main site, and old rows stay valid without migration.
   * Bedarfsplanung keeps counting at the main site (praxis.kreis_id) - a branch does not
     create a planning seat. That rule lives in the queries, not in the model.
   * mart: dim_praxis could get a "standort" level, or a new dim_standort; facts would get
     a standort_key. (Not shown.)                                                       */
BEGIN TRANSACTION;

CREATE TABLE core.nebenbetriebsstaette (
    nebenbetriebsstaette_id INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_nebenbetriebsstaette PRIMARY KEY,
    nbsnr         CHAR(9)       NOT NULL CONSTRAINT uq_nebenbetriebsstaette_nbsnr UNIQUE,
    praxis_id     INT           NOT NULL CONSTRAINT fk_nebenbetriebsstaette_praxis REFERENCES core.praxis (praxis_id),
    strasse       NVARCHAR(120) NULL,
    ort           NVARCHAR(60)  NOT NULL,
    kreis_id      INT           NOT NULL CONSTRAINT fk_nebenbetriebsstaette_kreis REFERENCES core.kreis (kreis_id),
    valid_from    DATE          NOT NULL,
    valid_to      DATE          NOT NULL CONSTRAINT df_nebenbetriebsstaette_valid_to DEFAULT ('9999-12-31'),
    CONSTRAINT ck_nebenbetriebsstaette_nbsnr CHECK (nbsnr LIKE '73[0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT ck_nebenbetriebsstaette_interval CHECK (valid_to > valid_from)
);
CREATE INDEX ix_nebenbetriebsstaette_praxis ON core.nebenbetriebsstaette (praxis_id);

ALTER TABLE core.leistung ADD nebenbetriebsstaette_id INT NULL
    CONSTRAINT fk_leistung_nebenbetriebsstaette REFERENCES core.nebenbetriebsstaette (nebenbetriebsstaette_id);
GO
-- GO ends the batch but NOT the transaction. A new batch is needed because SQL Server compiles
-- a whole batch before running it - and at compile time the new column did not exist yet.

-- test: a branch of MVZ St. Wendel in Tholey, and two services moved there
INSERT INTO core.nebenbetriebsstaette (nbsnr, praxis_id, ort, kreis_id, valid_from)
SELECT '739999901', p.praxis_id, N'Tholey', p.kreis_id, '2025-04-01'
FROM core.praxis AS p WHERE p.bsnr = '736554251';

UPDATE TOP (2) l
   SET nebenbetriebsstaette_id = (SELECT nebenbetriebsstaette_id FROM core.nebenbetriebsstaette WHERE nbsnr = '739999901')
FROM core.leistung AS l
JOIN core.abrechnungsfall AS f ON f.fall_id = l.fall_id
JOIN core.praxis AS p ON p.praxis_id = f.praxis_id
WHERE p.bsnr = '736554251' AND l.leistungsdatum >= '2025-04-01';

-- services per site of the practice: COALESCE turns "no branch" into the main site
SELECT p.bsnr AS hauptbetriebsstaette,
       COALESCE(n.nbsnr, p.bsnr)   AS erbracht_in,
       COALESCE(n.ort, p.ort)      AS ort,
       COUNT(*)                    AS leistungen
FROM core.leistung AS l
JOIN core.abrechnungsfall AS f ON f.fall_id = l.fall_id
JOIN core.praxis AS p ON p.praxis_id = f.praxis_id
LEFT JOIN core.nebenbetriebsstaette AS n ON n.nebenbetriebsstaette_id = l.nebenbetriebsstaette_id
WHERE p.bsnr = '736554251'
GROUP BY p.bsnr, COALESCE(n.nbsnr, p.bsnr), COALESCE(n.ort, p.ort);
-- 2 rows: 108 services at the main site in St. Wendel, 2 at the branch in Tholey.

ROLLBACK TRANSACTION;   -- everything above is undone: table, column and data
GO

/* -----------------------------------------------------------------------------
   4.2  Doctors with two Fachgruppen (one LANR per Fachgruppe)
   -----------------------------------------------------------------------------
   Today: core.arzt has ONE lanr and ONE fachgruppe_code (CHECK: last 2 digits = Fachgruppe).
   Reality: the first 7 digits (LANR-Stamm) identify the PERSON for life; a doctor working
   in two specialties has two LANRs with the same stem, e.g. 1234566 01 and 1234566 23.

   Proposal:
     core.arzt            person; business key lanr_stamm CHAR(7) (no fachgruppe here)
     core.arzt_lanr       one row per LANR: arzt_id, lanr CHAR(9) UNIQUE, fachgruppe_code,
                          valid_from/valid_to (a Fachgruppe can be added later);
                          CHECK LEFT(lanr, 7) = stem of the person -> enforced via FK on a
                          persisted computed column
     core.teilnahme       references arzt (the person works at the practice) ...
     core.leistung        ... but references arzt_lanr: a service is billed under one specific LANR
   Bedarfsplanung counts per Fachgruppe -> the Anrechnungsfaktor would have to be split per
   LANR (e.g. 0.5 Hausarzt + 0.5 Fachinternist) - that belongs to the Teilnahme per LANR. */
BEGIN TRANSACTION;

CREATE TABLE #arzt_neu (                              -- the person
    arzt_id    INT     NOT NULL PRIMARY KEY,
    lanr_stamm CHAR(7) NOT NULL UNIQUE
);
CREATE TABLE #arzt_lanr (                             -- one row per LANR (person x Fachgruppe)
    arzt_lanr_id    INT IDENTITY(1,1) PRIMARY KEY,
    arzt_id         INT     NOT NULL REFERENCES #arzt_neu (arzt_id),   -- (FKs on #temp tables are ignored, shown for the design)
    lanr            CHAR(9) NOT NULL UNIQUE,
    lanr_stamm      AS CAST(LEFT(lanr, 7) AS CHAR(7)) PERSISTED,
    fachgruppe_code AS CAST(RIGHT(lanr, 2) AS CHAR(2)) PERSISTED,      -- derived, can never contradict the LANR
    valid_from      DATE    NOT NULL,
    valid_to        DATE    NOT NULL DEFAULT ('9999-12-31')
);

-- migration from the current model: every doctor -> one person + one LANR
INSERT INTO #arzt_neu (arzt_id, lanr_stamm)
SELECT arzt_id, LEFT(lanr, 7) FROM core.arzt;
INSERT INTO #arzt_lanr (arzt_id, lanr, valid_from)
SELECT arzt_id, lanr, '1900-01-01' FROM core.arzt;

-- a second Fachgruppe for one doctor: same stem, other last two digits (23 = Innere Medizin fachaerztlich)
INSERT INTO #arzt_lanr (arzt_id, lanr, valid_from)
SELECT TOP (1) arzt_id, LEFT(lanr, 7) + '23', '2025-07-01' FROM core.arzt WHERE fachgruppe_code = '03' ORDER BY lanr;

SELECT n.lanr_stamm, l.lanr, l.fachgruppe_code, l.valid_from
FROM #arzt_neu AS n
JOIN #arzt_lanr AS l ON l.arzt_id = n.arzt_id
WHERE n.arzt_id IN (SELECT arzt_id FROM #arzt_lanr GROUP BY arzt_id HAVING COUNT(*) > 1);
-- 2 rows: one person, two LANRs with the same 7-digit stem.
-- Check first: the stem is unique in today's data, so the migration is possible:
SELECT COUNT(*) AS personen, COUNT(DISTINCT LEFT(lanr, 7)) AS stammnummern FROM core.arzt;   -- both 1,789

ROLLBACK TRANSACTION;
DROP TABLE IF EXISTS #arzt_lanr;
DROP TABLE IF EXISTS #arzt_neu;
GO

/* -----------------------------------------------------------------------------
   4.3  Classic incremental SCD type 2 load for dim_praxis
   -----------------------------------------------------------------------------
   mart.dim_praxis is type 1 (attributes are overwritten). Here: the CLASSIC SCD2
   algorithm used when the source has NO history and we only see snapshots:
     load n:  1. close the current version of every member whose tracked attributes changed
              2. insert a new current version for changed AND brand-new members
   (The project's dim_arzt uses a different approach: core already HAS valid-time history,
   so the versions are derived from it. Both are SCD2.)
   Everything runs on #temp tables - the real dimension is not touched.                */
DROP TABLE IF EXISTS #quelle;
DROP TABLE IF EXISTS #dim_praxis_scd2;

SELECT praxis_id, bsnr, name AS praxis_name, kooperationsform_code
INTO #quelle
FROM core.praxis;

CREATE TABLE #dim_praxis_scd2 (
    praxis_key            INT IDENTITY(1,1) PRIMARY KEY,
    praxis_id             INT           NOT NULL,     -- durable key
    bsnr                  CHAR(9)       NOT NULL,
    praxis_name           NVARCHAR(200) NOT NULL,     -- tracked (type 2)
    kooperationsform_code VARCHAR(3)    NOT NULL,     -- tracked (type 2)
    valid_from            DATE          NOT NULL,
    valid_to              DATE          NOT NULL,
    is_current            BIT           NOT NULL
);

DECLARE @ladedatum DATE;

/* ---- load 1 (initial): every member gets its first version -------------------------- */
SET @ladedatum = '2025-01-01';
INSERT INTO #dim_praxis_scd2 (praxis_id, bsnr, praxis_name, kooperationsform_code, valid_from, valid_to, is_current)
SELECT praxis_id, bsnr, praxis_name, kooperationsform_code, @ladedatum, '9999-12-31', 1
FROM #quelle;

/* ---- between the loads the source changes: an Einzelpraxis becomes a BAG --------------- */
UPDATE #quelle
   SET kooperationsform_code = 'BAG',
       praxis_name = N'Gemeinschaftspraxis ' + praxis_name
WHERE bsnr = (SELECT MIN(bsnr) FROM core.praxis WHERE kooperationsform_code = 'EP');

/* ---- load 2 (incremental) ----------------------------------------------------------- */
SET @ladedatum = '2025-10-01';

-- step 1: expire the current version of changed members
UPDATE d
   SET valid_to = @ladedatum, is_current = 0
FROM #dim_praxis_scd2 AS d
JOIN #quelle AS s ON s.praxis_id = d.praxis_id
WHERE d.is_current = 1
  AND EXISTS (SELECT s.praxis_name, s.kooperationsform_code          -- NULL-safe change detection
              EXCEPT
              SELECT d.praxis_name, d.kooperationsform_code);

-- step 2: new current version for every member that now has no current version
--         (= the changed ones from step 1 + members that are new in the source)
INSERT INTO #dim_praxis_scd2 (praxis_id, bsnr, praxis_name, kooperationsform_code, valid_from, valid_to, is_current)
SELECT s.praxis_id, s.bsnr, s.praxis_name, s.kooperationsform_code, @ladedatum, '9999-12-31', 1
FROM #quelle AS s
WHERE NOT EXISTS (SELECT 1 FROM #dim_praxis_scd2 AS d WHERE d.praxis_id = s.praxis_id AND d.is_current = 1);

SELECT praxis_key, bsnr, praxis_name, kooperationsform_code, valid_from, valid_to, is_current
FROM #dim_praxis_scd2
WHERE praxis_id IN (SELECT praxis_id FROM #dim_praxis_scd2 GROUP BY praxis_id HAVING COUNT(*) > 1)
ORDER BY praxis_key;
-- 2 rows: the old EP version (2025-01-01 .. 2025-10-01, is_current 0) and the new BAG
-- version (from 2025-10-01). Facts loaded before October keep pointing to the EP version.
-- Run "load 2" a second time: nothing changes (idempotent), because no attribute differs.

DROP TABLE #dim_praxis_scd2;
DROP TABLE #quelle;
GO

/* -----------------------------------------------------------------------------
   4.4  Columnstore vs. rowstore for a fact table
   -----------------------------------------------------------------------------
   Rowstore stores whole ROWS together on 8 KB pages - ideal to find a few rows by key.
   Columnstore stores each COLUMN separately and compressed - ideal to aggregate a few
   columns over many rows (typical for facts). To make the effect visible we copy
   fact_leistung 10 times (~250,000 rows, "a bigger KV").                               */
DROP TABLE IF EXISTS mart.uebung_leistung_rowstore;
DROP TABLE IF EXISTS mart.uebung_leistung_columnstore;

SELECT f.*
INTO mart.uebung_leistung_rowstore
FROM mart.fact_leistung AS f
CROSS JOIN (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10)) AS v (n);
CREATE CLUSTERED INDEX cx_uebung_leistung_rowstore ON mart.uebung_leistung_rowstore (leistung_id);

SELECT * INTO mart.uebung_leistung_columnstore FROM mart.uebung_leistung_rowstore;
CREATE CLUSTERED COLUMNSTORE INDEX cci_uebung_leistung_columnstore ON mart.uebung_leistung_columnstore;

EXEC sys.sp_spaceused N'mart.uebung_leistung_rowstore';      -- ~24 MB
EXEC sys.sp_spaceused N'mart.uebung_leistung_columnstore';   -- ~2.5 MB: about 10x smaller (compression)

SET STATISTICS IO ON;
SELECT quartal_key, fachgruppe_key, SUM(punkte) AS punkte, SUM(betrag_eur) AS betrag_eur
FROM mart.uebung_leistung_rowstore
GROUP BY quartal_key, fachgruppe_key;                       -- ~3,060 logical reads

SELECT quartal_key, fachgruppe_key, SUM(punkte) AS punkte, SUM(betrag_eur) AS betrag_eur
FROM mart.uebung_leistung_columnstore
GROUP BY quartal_key, fachgruppe_key;                       -- ~33 LOB logical reads
SET STATISTICS IO OFF;
-- Columnstore reads only the 3 needed columns, compressed, and processes them in batches.
-- Trade-offs: single-row lookups and frequent small UPDATEs are slower; very small tables
-- gain little. Rule of thumb: large fact tables -> clustered columnstore; dimensions -> rowstore.
-- Available in all editions since SQL Server 2016 SP1.

DROP TABLE mart.uebung_leistung_rowstore;
DROP TABLE mart.uebung_leistung_columnstore;
GO

/* -----------------------------------------------------------------------------
   4.5  Incremental fact load for one quarter
   -----------------------------------------------------------------------------
   mart.usp_load_facts rebuilds all facts. When a single quarter is corrected (e.g. a
   late Honorarbescheid), it is enough to replace that quarter: DELETE its rows, INSERT
   them again - in ONE transaction so reports never see a half-loaded quarter.
   Requirement: the dimensions are already up to date (mart.usp_load_dimensions).
   The procedure is created inside a transaction and rolled back at the end.         */
BEGIN TRANSACTION;
GO
CREATE OR ALTER PROCEDURE mart.usp_uebung_load_fact_leistung_quartal
    @quartal_code CHAR(6)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @quartal_key INT = (SELECT quartal_key FROM mart.dim_quartal WHERE quartal_code = @quartal_code);
    IF @quartal_key IS NULL
        THROW 50100, N'Unknown quarter.', 1;

    BEGIN TRANSACTION;
        DELETE FROM mart.fact_leistung WHERE quartal_key = @quartal_key;

        INSERT INTO mart.fact_leistung (leistung_id, fallnummer, datum_key, quartal_key, arzt_key, praxis_key, region_key,
                                        fachgruppe_key, kasse_key, gop_key, altersgruppe_key, anzahl, punkte, betrag_eur, pruefzeit_min)
        SELECT l.leistung_id, f.fallnummer,
               CONVERT(INT, CONVERT(CHAR(8), l.leistungsdatum, 112)), @quartal_key,
               COALESCE(da.arzt_key, -1), COALESCE(dp.praxis_key, -1), COALESCE(dr.region_key, -1),
               COALESCE(dfg.fachgruppe_key, -1), COALESCE(dk.kasse_key, -1), COALESCE(dg.gop_key, -1),
               COALESCE(dag.altersgruppe_key, -1),
               l.anzahl, l.anzahl * l.punktzahl,
               CAST(l.anzahl * l.punktzahl * COALESCE(ow.euro_je_punkt, 0) AS DECIMAL(12,2)),
               l.anzahl * g.pruefzeit_min
        FROM core.leistung AS l
        JOIN core.abrechnungsfall AS f ON f.fall_id = l.fall_id
        JOIN core.praxis          AS p ON p.praxis_id = f.praxis_id
        JOIN core.arzt            AS a ON a.arzt_id = l.arzt_id
        JOIN core.gop             AS g ON g.gop_id = l.gop_id
        LEFT JOIN core.orientierungswert AS ow  ON ow.jahr = YEAR(l.leistungsdatum)
        LEFT JOIN mart.dim_arzt          AS da  ON da.arzt_id = l.arzt_id
                                               AND l.leistungsdatum >= da.valid_from AND l.leistungsdatum < da.valid_to
        LEFT JOIN mart.dim_praxis        AS dp  ON dp.praxis_id = f.praxis_id
        LEFT JOIN mart.dim_region        AS dr  ON dr.kreis_id = p.kreis_id
        LEFT JOIN mart.dim_fachgruppe    AS dfg ON dfg.fachgruppe_code = a.fachgruppe_code
        LEFT JOIN mart.dim_krankenkasse  AS dk  ON dk.krankenkasse_id = f.krankenkasse_id
        LEFT JOIN mart.dim_gop           AS dg  ON dg.gop_id = l.gop_id
        LEFT JOIN mart.dim_altersgruppe  AS dag ON dag.altersgruppe_code = f.altersgruppe_code
        WHERE f.quartal_code = @quartal_code;            -- the only difference to the full load
    COMMIT TRANSACTION;
END
GO
DECLARE @vorher INT = (SELECT COUNT(*) FROM mart.fact_leistung WHERE quartal_key = 20252);
EXEC mart.usp_uebung_load_fact_leistung_quartal @quartal_code = '2025Q2';
SELECT @vorher AS zeilen_vorher,
       (SELECT COUNT(*) FROM mart.fact_leistung WHERE quartal_key = 20252) AS zeilen_nachher;
-- same number of rows before and after (6,384 for 2025Q2): the quarter was replaced, not doubled.
-- Note: the procedure's own BEGIN/COMMIT runs NESTED inside our outer transaction here;
-- only the outermost COMMIT/ROLLBACK really ends a transaction in SQL Server.
ROLLBACK TRANSACTION;   -- removes the demo procedure again (and the reload)
GO

/* -----------------------------------------------------------------------------
   4.6  Row-Level Security: a Bezirksstelle sees only its own Kreis
   -----------------------------------------------------------------------------
   Column/table permissions (sql/80_security) decide WHICH tables a user may read.
   Row-Level Security (RLS) decides WHICH ROWS: a filter predicate (an inline function)
   is added automatically to every query on the table - the user cannot bypass it.
   This demo creates everything in a schema "uebung" and drops it again at the end.   */

-- clean up leftovers of an earlier, interrupted run
IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = N'pol_kreis') DROP SECURITY POLICY uebung.pol_kreis;
DROP FUNCTION IF EXISTS uebung.fn_rls_region;
DROP TABLE IF EXISTS uebung.benutzer_kreis;
IF DATABASE_PRINCIPAL_ID(N'u_bezirksstelle_wnd') IS NOT NULL DROP USER u_bezirksstelle_wnd;
IF SCHEMA_ID(N'uebung') IS NOT NULL DROP SCHEMA uebung;
GO
CREATE SCHEMA uebung;
GO
-- which user may see which Kreis
CREATE TABLE uebung.benutzer_kreis (
    benutzer  SYSNAME NOT NULL,
    kreis_ags CHAR(5) NOT NULL,
    CONSTRAINT pk_benutzer_kreis PRIMARY KEY (benutzer, kreis_ags)
);
INSERT INTO uebung.benutzer_kreis VALUES (N'u_bezirksstelle_wnd', '10046');   -- St. Wendel
GO
-- predicate function: returns a row (= access allowed) or nothing (= row hidden).
-- SCHEMABINDING is required: the referenced tables cannot be changed while the policy exists.
CREATE FUNCTION uebung.fn_rls_region (@region_key INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS zugriff
    WHERE IS_MEMBER(N'db_owner') = 1                       -- administrators see everything
       OR EXISTS (SELECT 1
                  FROM uebung.benutzer_kreis AS z
                  JOIN mart.dim_region AS r ON r.ags = z.kreis_ags
                  WHERE z.benutzer = USER_NAME() AND r.region_key = @region_key);
GO
CREATE SECURITY POLICY uebung.pol_kreis
    ADD FILTER PREDICATE uebung.fn_rls_region(region_key) ON mart.fact_abrechnungsfall
    WITH (STATE = ON);
GO
CREATE USER u_bezirksstelle_wnd WITHOUT LOGIN;
GRANT SELECT ON mart.fact_abrechnungsfall TO u_bezirksstelle_wnd;
GRANT SELECT ON mart.dim_region TO u_bezirksstelle_wnd;
GO
-- the same query, two users, two results
SELECT N'dbo' AS benutzer, COUNT(*) AS sichtbare_faelle FROM mart.fact_abrechnungsfall;
EXECUTE AS USER = N'u_bezirksstelle_wnd';
    SELECT USER_NAME() AS benutzer, COUNT(*) AS sichtbare_faelle FROM mart.fact_abrechnungsfall;
    SELECT r.kreis, COUNT(*) AS faelle
    FROM mart.fact_abrechnungsfall AS f
    JOIN mart.dim_region AS r ON r.region_key = f.region_key
    GROUP BY r.kreis;                                      -- only St. Wendel appears
REVERT;
-- dbo sees all 11,994 cases, the Bezirksstelle user only the 919 of St. Wendel.
-- Note: RLS filters the table it is defined on; other tables with the same data
-- (fact_leistung, core tables) need their own predicates or no permission at all.
GO
-- clean up (order matters: policy -> function -> table -> user -> schema)
DROP SECURITY POLICY uebung.pol_kreis;
DROP FUNCTION uebung.fn_rls_region;
DROP TABLE uebung.benutzer_kreis;
DROP USER u_bezirksstelle_wnd;
DROP SCHEMA uebung;
GO
