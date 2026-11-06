/* =============================================================================
   SOLUTIONS - Level 3: Advanced
   Concepts: time validity ("as-of") queries with half-open intervals, NOT EXISTS,
             reconciliation, gaps and islands, SARGability, indexes and execution
             plans, recursive CTEs, spatial data (geography)
   Try the tasks in sql/90_exercises/03_advanced.sql first!

   German terms used in this file:
     BSNR                   Betriebsstaettennummer (practice number)
     Teilnahme / Status     a doctor's participation at a practice; status AKTIV,
                            RUHEND (suspended) or BEENDET (ended)
     Plausibilitaetspruefung  check of billed time: every GOP has a Pruefzeit
                            (standard minutes). Suspicious: > 12 h on at least 3 days
                            of a quarter (Tagesprofil) or > 780 h per quarter
                            (Quartalsprofil)
     QS-Genehmigung         permit required to bill certain services (e.g. ultrasound)
     sachlich-rechnerische Berichtigung  correction of billed points by the KV
     Versorgungsgrad / Ist  supply level; Ist = sum of Anrechnungsfaktoren
     Zulassungsverfahren    licensing procedure; Nachbesetzung = succession on a seat
     Bereitschaftspraxis    out-of-hours practice

   THE INTERVAL RULE OF THIS PROJECT
     valid_from is INCLUSIVE, valid_to is EXCLUSIVE:   [valid_from, valid_to)
     "valid on day D"  <=>  D >= valid_from AND D < valid_to
     Do NOT use BETWEEN for these columns: BETWEEN includes the end date, and on the
     day of a change two rows would match.
   ============================================================================= */
USE KVSim;
GO

/* -----------------------------------------------------------------------------
   3.1  As-of query: who worked at a practice on a given day, with which status?
   ----------------------------------------------------------------------------- */
DECLARE @stichtag DATE = '2025-06-30';

SELECT p.bsnr,
       a.lanr,
       CONCAT_WS(N' ', a.titel, a.vorname, a.nachname) AS arzt,
       t.teilnahmeform_code,
       t.anrechnungsfaktor,
       s.status_code,
       t.valid_from AS teilnahme_ab,
       t.valid_to   AS teilnahme_bis
FROM core.teilnahme AS t
JOIN core.teilnahme_status AS s
  ON s.teilnahme_id = t.teilnahme_id
 AND @stichtag >= s.valid_from AND @stichtag < s.valid_to     -- the status valid on that day
JOIN core.arzt   AS a ON a.arzt_id = t.arzt_id
JOIN core.praxis AS p ON p.praxis_id = t.praxis_id
WHERE p.bsnr IN ('733392590', '738423693')
  AND @stichtag >= t.valid_from AND @stichtag < t.valid_to      -- the Teilnahme valid on that day
ORDER BY p.bsnr, a.lanr;
-- 6 rows. In 733392590 (BAG of Nervenaerzte) Dr. Schlosser is still AKTIV on 2025-06-30;
-- in 738423693 Dr. Wulf has the status RUHEND (suspended 2025-05-01 .. 2025-10-01).
-- Change @stichtag to '2025-07-01': Schlosser disappears and his successor Bruder appears -
-- exactly one row per seat on the day of the change, thanks to the exclusive valid_to.

-- The same with the reusable inline function (a "parameterised view"):
SELECT p.bsnr, a.lanr, a.nachname, t.status_code
FROM core.fn_teilnahme_am('2025-07-01') AS t
JOIN core.arzt   AS a ON a.arzt_id = t.arzt_id
JOIN core.praxis AS p ON p.praxis_id = t.praxis_id
WHERE p.bsnr = '733392590'
ORDER BY a.lanr;
GO

/* -----------------------------------------------------------------------------
   3.2  Plausibilitaetspruefung: time profiles per day and per quarter
   ----------------------------------------------------------------------------- */
-- Tagesprofil: hours of Pruefzeit per doctor and day; doctors with >= 3 days above 12 h
WITH tage AS (
    SELECT lanr, arzt_name, fachgruppe, datum, pruefzeit_stunden
    FROM mart.v_plausi_tagesprofil
)
SELECT lanr, arzt_name, fachgruppe,
       COUNT(*)                                                       AS tage_mit_leistungen,
       SUM(CASE WHEN pruefzeit_stunden > 12 THEN 1 ELSE 0 END)        AS tage_ueber_12h,
       MAX(pruefzeit_stunden)                                         AS max_stunden_an_einem_tag
FROM tage
GROUP BY lanr, arzt_name, fachgruppe
HAVING SUM(CASE WHEN pruefzeit_stunden > 12 THEN 1 ELSE 0 END) >= 3
ORDER BY tage_ueber_12h DESC;
-- 1 doctor (a psychotherapist with 3 such days). Overall 32 days above 12 h by 28 doctors,
-- all psychotherapists. CAUTION, simulation artefact: the generator books a series of
-- sessions (GOP 35401, up to 12 x 70 min) as ONE line with anzahl > 1 on ONE date. In real
-- billing every session has its own date - so these "findings" are partly caused by the
-- data generator. Always ask how a suspicious pattern was produced before accusing anyone!

-- Quartalsprofil: hours per doctor and quarter, ranked within the Fachgruppe
SELECT a.lanr,
       a.fachgruppe,
       q.quartal_code,
       CAST(SUM(f.pruefzeit_min) / 60.0 AS DECIMAL(7,2))                                     AS stunden_quartal,
       RANK() OVER (PARTITION BY a.fachgruppe, q.quartal_code ORDER BY SUM(f.pruefzeit_min) DESC) AS rang_in_fachgruppe
FROM mart.fact_leistung AS f
JOIN mart.dim_arzt    AS a ON a.arzt_key = f.arzt_key
JOIN mart.dim_quartal AS q ON q.quartal_key = f.quartal_key
WHERE f.pruefzeit_min IS NOT NULL
GROUP BY a.lanr, a.fachgruppe, q.quartal_code
ORDER BY stunden_quartal DESC
OFFSET 0 ROWS FETCH NEXT 20 ROWS ONLY;          -- standard SQL alternative to TOP (20)
-- Maximum about 53 h per quarter - far below 780 h. The billing data is a SAMPLE (about
-- 3 cases per doctor and quarter instead of hundreds), so absolute thresholds never fire.
-- With sample data, use RELATIVE measures (rank, deviation from the Fachgruppe) instead.
-- Window functions can be applied to aggregates: RANK() OVER (... ORDER BY SUM(...)).
GO

/* -----------------------------------------------------------------------------
   3.3  QS-GOPs billed without a valid Genehmigung - and the Honorarbescheid
   ----------------------------------------------------------------------------- */
-- Part A: the findings. NOT EXISTS reads like the business rule:
-- "there is NO permit of this doctor for this QS area that was valid on the service date".
SELECT p.bsnr,
       a.lanr,
       l.leistungsdatum,
       g.gop_code,
       g.qs_bereich_code,
       l.anzahl * l.punktzahl AS punkte,
       f.quartal_code
FROM core.leistung AS l
JOIN core.gop             AS g ON g.gop_id = l.gop_id
JOIN core.abrechnungsfall AS f ON f.fall_id = l.fall_id
JOIN core.praxis          AS p ON p.praxis_id = f.praxis_id
JOIN core.arzt            AS a ON a.arzt_id = l.arzt_id
WHERE g.qs_bereich_code IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM core.qs_genehmigung AS q
        WHERE q.arzt_id = l.arzt_id
          AND q.qs_bereich_code = g.qs_bereich_code
          AND l.leistungsdatum >= q.valid_from AND l.leistungsdatum < q.valid_to)
ORDER BY l.leistungsdatum;
-- 20 lines, 14,380 points (AKU 10, US 8, HKS 1, KOLO 1). 2 of them come from doctors who
-- HAD a permit, just not on that day (it started later or had expired) - a pure
-- "does a permit exist?" check without the date condition would miss them.
-- Why NOT EXISTS and not LEFT JOIN ... WHERE q.arzt_id IS NULL? Both work; NOT EXISTS
-- cannot multiply rows (a doctor with two permits would duplicate rows in a LEFT JOIN).

-- Part B: did the KV correct exactly these points? Compare with punkte_berichtigt.
WITH befund AS (
    SELECT f.praxis_id, f.quartal_code, SUM(l.anzahl * l.punktzahl) AS punkte_ohne_genehmigung
    FROM core.leistung AS l
    JOIN core.gop             AS g ON g.gop_id = l.gop_id
    JOIN core.abrechnungsfall AS f ON f.fall_id = l.fall_id
    WHERE g.qs_bereich_code IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM core.qs_genehmigung AS q
                      WHERE q.arzt_id = l.arzt_id AND q.qs_bereich_code = g.qs_bereich_code
                        AND l.leistungsdatum >= q.valid_from AND l.leistungsdatum < q.valid_to)
    GROUP BY f.praxis_id, f.quartal_code
)
SELECT p.bsnr, h.quartal_code, h.punkte_berichtigt, b.punkte_ohne_genehmigung,
       CASE WHEN h.punkte_berichtigt = COALESCE(b.punkte_ohne_genehmigung, 0) THEN 'OK' ELSE 'ABWEICHUNG' END AS abgleich
FROM core.honorarbescheid AS h
JOIN core.praxis AS p ON p.praxis_id = h.praxis_id
-- FULL OUTER JOIN shows both: corrections without finding AND findings without correction
FULL OUTER JOIN befund AS b ON b.praxis_id = h.praxis_id AND b.quartal_code = h.quartal_code
WHERE h.punkte_berichtigt > 0 OR b.punkte_ohne_genehmigung IS NOT NULL;
-- 20 Bescheide, all 'OK': the corrections in the Bescheide match our own findings
-- (the same check runs automatically as data-quality rule DQ13).
GO

/* -----------------------------------------------------------------------------
   3.4  Recompute the Versorgungsgrad from the register and compare
   ----------------------------------------------------------------------------- */
-- Ist = sum of Anrechnungsfaktoren of all Teilnahmen valid on the Stichtag
-- (AKTIV or RUHEND - a suspended Zulassung still occupies the seat), per planning area
-- and Arztgruppe. A Kreis belongs to two planning areas (its own KREIS area and the
-- ROR area for Fachinternisten), the arztgruppe/planungsbereich combination picks the right one.
WITH ist_berechnet AS (
    SELECT v.planungsbereich_id, v.arztgruppe_code, v.stichtag,
           SUM(t.anrechnungsfaktor) AS ist_aerzte
    FROM core.versorgungsgrad AS v
    JOIN core.planungsbereich_kreis AS pk ON pk.planungsbereich_id = v.planungsbereich_id
    JOIN core.praxis     AS p  ON p.kreis_id = pk.kreis_id
    JOIN core.teilnahme  AS t  ON t.praxis_id = p.praxis_id
                              AND v.stichtag >= t.valid_from AND v.stichtag < t.valid_to
    JOIN core.arzt       AS a  ON a.arzt_id = t.arzt_id
    JOIN core.fachgruppe AS fg ON fg.fachgruppe_code = a.fachgruppe_code
                              AND fg.arztgruppe_code = v.arztgruppe_code
    GROUP BY v.planungsbereich_id, v.arztgruppe_code, v.stichtag
)
SELECT v.stichtag,
       pb.planungsbereich_code,
       v.arztgruppe_code,
       v.soll_aerzte,
       v.ist_aerzte                                                       AS ist_offiziell,
       COALESCE(b.ist_aerzte, 0)                                          AS ist_berechnet,
       v.versorgungsgrad_pct                                              AS vg_offiziell,
       CAST(ROUND(100.0 * COALESCE(b.ist_aerzte, 0) / v.soll_aerzte, 1) AS DECIMAL(6,1)) AS vg_berechnet
FROM core.versorgungsgrad AS v
JOIN core.planungsbereich AS pb ON pb.planungsbereich_id = v.planungsbereich_id
LEFT JOIN ist_berechnet   AS b  ON b.planungsbereich_id = v.planungsbereich_id
                               AND b.arztgruppe_code = v.arztgruppe_code
                               AND b.stichtag = v.stichtag
WHERE v.ist_aerzte <> COALESCE(b.ist_aerzte, 0)
ORDER BY v.stichtag, pb.planungsbereich_code;
-- 0 rows: the official figures (Excel of the Bedarfsplanung) and the register agree for
-- all 165 combinations. Remove the WHERE clause to see all rows, e.g. St. Wendel
-- Hausaerzte on 2026-01-01: Soll 54.07, Ist 41.25, 76.3 %.
-- In real life such a reconciliation usually finds differences (late register updates,
-- special rules for counting) - that is why it is worth automating (rule DQ11).
GO

/* -----------------------------------------------------------------------------
   3.5  Gaps and islands
   ----------------------------------------------------------------------------- */
-- Part A: suspension periods (RUHEND) and their length
SELECT a.lanr, p.bsnr, s.valid_from AS ruhend_ab, s.valid_to AS ruhend_bis_exklusiv,
       DATEDIFF(DAY, s.valid_from, s.valid_to) AS tage   -- exclusive end: no "+ 1" needed
FROM core.teilnahme_status AS s
JOIN core.teilnahme AS t ON t.teilnahme_id = s.teilnahme_id
JOIN core.arzt      AS a ON a.arzt_id = t.arzt_id
JOIN core.praxis    AS p ON p.praxis_id = t.praxis_id
WHERE s.status_code = 'RUHEND'
ORDER BY tage DESC;
-- 14 periods, 59 to 153 days (average 106).

-- Part B: "islands" of continuous participation across practices.
-- A doctor who moves from practice A (until 2025-06-01) to practice B (from 2025-06-01)
-- has two Teilnahmen but one continuous working period. Classic pattern:
--   1. flag the rows that START a new island (no direct predecessor)
--   2. running SUM of the flags = island number
--   3. GROUP BY island
WITH flags AS (
    SELECT arzt_id, praxis_id, valid_from, valid_to,
           CASE WHEN LAG(valid_to) OVER (PARTITION BY arzt_id ORDER BY valid_from) = valid_from
                THEN 0 ELSE 1 END AS beginnt_neue_insel
    FROM core.teilnahme
),
inseln AS (
    SELECT *,
           SUM(beginnt_neue_insel) OVER (PARTITION BY arzt_id ORDER BY valid_from
                                         ROWS UNBOUNDED PRECEDING) AS insel_nr
    FROM flags
)
SELECT a.lanr,
       i.insel_nr,
       MIN(i.valid_from)          AS taetig_seit,
       MAX(i.valid_to)            AS taetig_bis_exklusiv,
       COUNT(*)                   AS teilnahmen,
       COUNT(DISTINCT i.praxis_id) AS praxen
FROM inseln AS i
JOIN core.arzt AS a ON a.arzt_id = i.arzt_id
GROUP BY a.lanr, i.insel_nr
HAVING COUNT(*) > 1
ORDER BY a.lanr;
-- 20 doctors changed practice without interruption in 2025.

-- Part C: the same 20 doctors appear as SCD2 dimension members with more than one version
SELECT lanr, COUNT(*) AS versionen,
       STRING_AGG(CONCAT(praxis_bsnr, N' ab ', CONVERT(CHAR(10), valid_from, 104)), N' | ')
           WITHIN GROUP (ORDER BY valid_from) AS verlauf
FROM mart.dim_arzt
WHERE arzt_key <> -1
GROUP BY lanr
HAVING COUNT(*) > 1
ORDER BY lanr;
-- 20 rows - core history and mart history agree.
GO

/* -----------------------------------------------------------------------------
   3.6  SARGability, indexes and execution plans
   ----------------------------------------------------------------------------- */
-- Run this block in SSMS with "Include Actual Execution Plan" (Ctrl+M) and look at the
-- "Messages" tab for the logical reads (= 8 KB pages read from memory).
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- (1) function on the column: NOT SARGable ("Search ARGument ABLE")
SELECT SUM(anzahl * punktzahl) AS punkte_maerz
FROM core.leistung
WHERE YEAR(leistungsdatum) = 2025 AND MONTH(leistungsdatum) = 3;

-- (2) range on the bare column: SARGable
SELECT SUM(anzahl * punktzahl) AS punkte_maerz
FROM core.leistung
WHERE leistungsdatum >= '2025-03-01' AND leistungsdatum < '2025-04-01';
-- Without a suitable index both scan the whole table (~163 logical reads).

-- an index that covers the query: key = filter column, INCLUDE = the columns we SUM
CREATE INDEX ix_uebung_leistung_datum ON core.leistung (leistungsdatum) INCLUDE (anzahl, punktzahl);

SELECT SUM(anzahl * punktzahl) AS punkte_maerz      -- (1) again: Index SCAN, ~74 reads
FROM core.leistung
WHERE YEAR(leistungsdatum) = 2025 AND MONTH(leistungsdatum) = 3;

SELECT SUM(anzahl * punktzahl) AS punkte_maerz      -- (2) again: Index SEEK, ~12 reads
FROM core.leistung
WHERE leistungsdatum >= '2025-03-01' AND leistungsdatum < '2025-04-01';
-- Same result (1,713,134 points), 6x fewer reads than (1) and 13x fewer than without index.
-- The optimizer cannot use the index order for YEAR(x) = 2025 because it would have to
-- compute YEAR() for every row first - so it reads the whole (smaller) index.

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- clean up: this index was only for the exercise (every index costs space and slows writes)
DROP INDEX ix_uebung_leistung_datum ON core.leistung;
-- Which indexes exist, and are they used? (usage counters reset when the server restarts)
SELECT i.name, s.user_seeks, s.user_scans, s.user_lookups, s.user_updates
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_index_usage_stats AS s
       ON s.object_id = i.object_id AND s.index_id = i.index_id AND s.database_id = DB_ID()
WHERE i.object_id = OBJECT_ID(N'core.leistung');
GO

/* -----------------------------------------------------------------------------
   3.7  Recursive CTEs: status chain of a procedure and succession on a seat
   ----------------------------------------------------------------------------- */
-- Part A: walk the status chain of each Zulassungsverfahren step by step.
-- A recursive CTE has an ANCHOR (the start rows) and a RECURSIVE part that joins the
-- previous result to the next row - here: the status that starts when the previous ends.
WITH kette AS (
    SELECT s.verfahren_id, s.status_code, s.valid_from, s.valid_to,
           1 AS schritt,
           CAST(s.status_code AS NVARCHAR(400)) AS pfad
    FROM core.zulassungsverfahren_status AS s
    WHERE NOT EXISTS (SELECT 1 FROM core.zulassungsverfahren_status AS vorher      -- first status
                      WHERE vorher.verfahren_id = s.verfahren_id AND vorher.valid_to = s.valid_from)
    UNION ALL
    SELECT n.verfahren_id, n.status_code, n.valid_from, n.valid_to,
           k.schritt + 1,
           CAST(k.pfad + N' > ' + n.status_code AS NVARCHAR(400))
    FROM kette AS k
    JOIN core.zulassungsverfahren_status AS n
      ON n.verfahren_id = k.verfahren_id AND n.valid_from = k.valid_to
)
SELECT v.aktenzeichen, v.verfahrensart, v.ergebnis, k.schritt AS anzahl_status, k.pfad
FROM kette AS k
JOIN core.zulassungsverfahren AS v ON v.verfahren_id = k.verfahren_id
WHERE k.valid_to = '9999-12-31'          -- keep only the last step = the complete path
ORDER BY v.aktenzeichen
OPTION (MAXRECURSION 20);                -- safety net against endless loops
-- 126 rows, e.g. ZA-2024-0002: EINGANG > IN_PRUEFUNG > TERMINIERT > ENTSCHIEDEN >
-- BESCHEID_VERSANDT > BESTANDSKRAEFTIG. Rejected procedures may end with WIDERSPRUCH.

-- Part B: who held a seat over time? Start with Teilnahmen that are not a Nachbesetzung,
-- then follow successors: same practice, starting the day the predecessor ended, and
-- confirmed by a NACHBESETZUNG procedure.
WITH nachfolge AS (
    SELECT t.teilnahme_id, t.praxis_id, t.arzt_id, t.valid_from, t.valid_to, 1 AS generation
    FROM core.teilnahme AS t
    WHERE t.teilnahmeform_code = 'ZUL'
      AND NOT EXISTS (SELECT 1 FROM core.zulassungsverfahren AS z
                      WHERE z.teilnahme_id = t.teilnahme_id AND z.verfahrensart = 'NACHBESETZUNG')
    UNION ALL
    SELECT n.teilnahme_id, n.praxis_id, n.arzt_id, n.valid_from, n.valid_to, v.generation + 1
    FROM nachfolge AS v
    JOIN core.teilnahme AS n ON n.praxis_id = v.praxis_id AND n.valid_from = v.valid_to
    JOIN core.zulassungsverfahren AS z ON z.teilnahme_id = n.teilnahme_id AND z.verfahrensart = 'NACHBESETZUNG'
)
SELECT p.bsnr, n.generation, a.lanr, a.nachname, n.valid_from, n.valid_to
FROM nachfolge AS n
JOIN core.praxis AS p ON p.praxis_id = n.praxis_id
JOIN core.arzt   AS a ON a.arzt_id = n.arzt_id
WHERE n.praxis_id IN (SELECT praxis_id FROM nachfolge WHERE generation > 1)
  AND (n.generation > 1 OR n.valid_to < '9999-12-31')
ORDER BY p.bsnr, n.generation;
-- 62 rows = 31 seats handed over in 2025 (predecessor + successor). Chains are only two
-- generations long because the simulation starts in 2025; with a full register history
-- the same query would follow a seat back for decades.
GO

/* -----------------------------------------------------------------------------
   3.8  Spatial: distances between the Kreis seats, nearest other Bereitschaftspraxis
   ----------------------------------------------------------------------------- */
-- geography::Point(latitude, longitude, SRID). SRID 4326 = WGS84 (GPS coordinates).
-- STDistance returns metres along the earth's surface (not a flat-map distance).
WITH sitz AS (
    SELECT kreis_id, name, verwaltungssitz,
           geography::Point(geo_breite, geo_laenge, 4326) AS punkt
    FROM core.kreis
)
SELECT a.verwaltungssitz AS von,
       b.verwaltungssitz AS nach,
       CAST(a.punkt.STDistance(b.punkt) / 1000.0 AS DECIMAL(6,1)) AS km_luftlinie
FROM sitz AS a
JOIN sitz AS b ON a.kreis_id < b.kreis_id      -- "<" lists every pair once (not A-B and B-A)
ORDER BY km_luftlinie DESC;
-- 15 pairs; farthest Merzig - Homburg 52.5 km, closest Ottweiler - St. Wendel 7.3 km.

-- If the own Bereitschaftspraxis is closed, which one is the nearest OTHER one?
-- (Approximation: every Bereitschaftspraxis is placed at the seat of its Kreis.)
WITH sitz AS (
    SELECT kreis_id, name, geography::Point(geo_breite, geo_laenge, 4326) AS punkt
    FROM core.kreis
)
SELECT s.name AS kreis, n.kennung, n.km
FROM sitz AS s
CROSS APPLY (                                   -- "for each Kreis, run this TOP (1) query"
    SELECT TOP (1) np.kennung,
           CAST(s.punkt.STDistance(z.punkt) / 1000.0 AS DECIMAL(6,1)) AS km
    FROM core.notfallpraxis AS np
    JOIN sitz AS z ON z.kreis_id = np.kreis_id
    WHERE np.kreis_id <> s.kreis_id
    ORDER BY s.punkt.STDistance(z.punkt)
) AS n
ORDER BY n.km DESC;
-- 6 rows; Saarbruecken's nearest alternative is Saarlouis (19.8 km), Neunkirchen and
-- St. Wendel cover each other (7.3 km).
GO
