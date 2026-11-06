/* =============================================================================
   SOLUTIONS - Level 1: Basics
   Concepts: SELECT, WHERE, ORDER BY, JOIN (INNER / LEFT), GROUP BY, HAVING,
             COUNT / SUM, percentages
   Try the tasks in sql/90_exercises/01_basics.sql first!

   German terms used in this file:
     Fachgruppe   medical specialty (digits 8-9 of the LANR)
     Arztgruppe   group used by the Bedarfsplanung (needs planning), e.g. Hausaerzte
     Teilnahme    a doctor's participation at a practice (Zulassung or Anstellung)
     Fallzahl     number of Behandlungsfaelle (one patient, one practice, one quarter)
     GOP          Gebuehrenordnungsposition = billing code of the EBM fee schedule
     Kassenart    type of health insurer (AOK, Ersatzkasse, ...)
     MVZ          Medizinisches Versorgungszentrum (medical care centre)
   ============================================================================= */
USE KVSim;
GO

/* -----------------------------------------------------------------------------
   1.1  Fachgruppen and their Arztgruppe
   ----------------------------------------------------------------------------- */
-- LEFT JOIN keeps a Fachgruppe even if it has no Arztgruppe (arztgruppe_code IS NULL).
-- An INNER JOIN would silently drop such rows. Always ask: "may the right side be missing?"
SELECT f.fachgruppe_code,
       f.bezeichnung      AS fachgruppe,
       a.bezeichnung      AS arztgruppe,
       a.versorgungsebene
FROM core.fachgruppe AS f
LEFT JOIN core.arztgruppe AS a ON a.arztgruppe_code = f.arztgruppe_code
ORDER BY a.bezeichnung, f.fachgruppe_code;
-- 11 rows. Two Fachgruppen (01 Allgemeinmedizin, 03 Innere Medizin hausaerztlich)
-- belong to the same Arztgruppe "Hausaerzte": the relationship is many-to-one.
GO

/* -----------------------------------------------------------------------------
   1.2  Number of doctors per Fachgruppe
   ----------------------------------------------------------------------------- */
SELECT f.fachgruppe_code,
       f.bezeichnung AS fachgruppe,
       COUNT(*)      AS anzahl_aerzte
FROM core.arzt AS a
JOIN core.fachgruppe AS f ON f.fachgruppe_code = a.fachgruppe_code
GROUP BY f.fachgruppe_code, f.bezeichnung          -- every non-aggregated column must be in GROUP BY
ORDER BY anzahl_aerzte DESC;                       -- ORDER BY may use the column alias
-- 11 rows: Allgemeinmedizin 521, Psychologische Psychotherapie 365, Frauenheilkunde 175, ...
-- Note: this counts everybody in the Arztregister, including applicants without a Teilnahme
-- and doctors who retired in 2025. Task 1.3 shows how to count only ACTIVE doctors.
GO

/* -----------------------------------------------------------------------------
   1.3  Practices in the Landkreis St. Wendel with their number of active doctors
   ----------------------------------------------------------------------------- */
-- core.v_teilnahme_aktuell = all Teilnahmen valid TODAY (with their status).
-- LEFT JOIN + COUNT(column): practices without an active doctor still appear with 0.
-- COUNT(*) would count 1 for them (the row of the practice itself) - a classic mistake.
SELECT p.bsnr,
       p.name                   AS praxis,
       p.ort,
       p.kooperationsform_code,
       COUNT(v.lanr)            AS aktive_aerzte
FROM core.praxis AS p
JOIN core.kreis  AS k ON k.kreis_id = p.kreis_id
LEFT JOIN core.v_teilnahme_aktuell AS v
       ON v.bsnr = p.bsnr
      AND v.status_code = 'AKTIV'      -- filter of the RIGHT table belongs into ON, not WHERE
WHERE k.ags = '10046'                  -- Landkreis St. Wendel
GROUP BY p.bsnr, p.name, p.ort, p.kooperationsform_code
ORDER BY aktive_aerzte DESC, praxis;
-- 84 practices; MVZ St. Wendel has the most active doctors (7).
-- Pitfall: putting "v.status_code = 'AKTIV'" into WHERE would turn the LEFT JOIN into an
-- INNER JOIN (NULL = 'AKTIV' is not true) and practices with 0 doctors would vanish.

-- Alternative with a fixed reference date instead of "today" (reproducible results):
SELECT p.bsnr, p.name AS praxis, COUNT(t.teilnahme_id) AS aktive_aerzte
FROM core.praxis AS p
LEFT JOIN core.fn_teilnahme_am('2025-12-31') AS t ON t.praxis_id = p.praxis_id AND t.status_code = 'AKTIV'
WHERE p.kreis_id = (SELECT kreis_id FROM core.kreis WHERE ags = '10046')
GROUP BY p.bsnr, p.name
ORDER BY aktive_aerzte DESC, praxis;
GO

/* -----------------------------------------------------------------------------
   1.4  Fallzahlen per quarter
   ----------------------------------------------------------------------------- */
SELECT f.quartal_code,
       COUNT(*)                            AS fallzahl,
       COUNT(DISTINCT f.praxis_id)         AS praxen_mit_faellen,
       COUNT(DISTINCT f.patient_pseudonym) AS patienten
FROM core.abrechnungsfall AS f
GROUP BY f.quartal_code
ORDER BY f.quartal_code;
-- 4 rows, about 3,000 cases per quarter (2025Q1: 2,974 ... 2025Q4: 3,048).
-- patienten < fallzahl: a patient visiting two practices in a quarter = two Behandlungsfaelle.
-- Reminder: the billing data is a SAMPLE - a real KV Saarland has millions of cases per quarter.
GO

/* -----------------------------------------------------------------------------
   1.5  Top 10 GOPs by billed points in 2025
   ----------------------------------------------------------------------------- */
SELECT TOP (10)
       g.gop_code,
       g.bezeichnung,
       SUM(l.anzahl)                AS anzahl,
       SUM(l.anzahl * l.punktzahl)  AS punkte     -- points per unit * number of units
FROM core.leistung AS l
JOIN core.gop AS g ON g.gop_id = l.gop_id
WHERE l.leistungsdatum >= '2025-01-01'           -- range predicate (see level 3, task 3.6)
  AND l.leistungsdatum <  '2026-01-01'
GROUP BY g.gop_code, g.bezeichnung
ORDER BY punkte DESC;
-- 10 rows; psychotherapy dominates (35401 Verhaltenstherapie: 5.8 million points)
-- because one session is worth ~945 points, while 03000 is worth 150.
-- Note: TOP without ORDER BY returns an arbitrary 10 rows - always combine them.
GO

/* -----------------------------------------------------------------------------
   1.6  Share of cases per Kassenart
   ----------------------------------------------------------------------------- */
SELECT ka.bezeichnung AS kassenart,
       COUNT(*)       AS faelle,
       -- 100.0 (not 100) forces decimal arithmetic. COUNT(*) * 100 / total would be an
       -- INTEGER division in SQL Server and cut off the decimals.
       CAST(100.0 * COUNT(*) / (SELECT COUNT(*) FROM core.abrechnungsfall) AS DECIMAL(5,1)) AS anteil_pct
FROM core.abrechnungsfall AS f
JOIN core.krankenkasse AS k  ON k.krankenkasse_id = f.krankenkasse_id
JOIN core.kassenart    AS ka ON ka.kassenart_code = k.kassenart_code
GROUP BY ka.bezeichnung
ORDER BY faelle DESC;
-- 6 rows: Ersatzkasse 39.2 %, AOK 31.5 %, IKK 11.1 %, Knappschaft 9.5 %, BKK 7.7 %, LKK 1.2 %.
-- Alternative for the total: SUM(COUNT(*)) OVER () - a window function over the grouped
-- result (introduced in level 2).
GO

/* -----------------------------------------------------------------------------
   1.7  Kreise by number of inhabitants aged 75+
   ----------------------------------------------------------------------------- */
SELECT k.name        AS kreis,
       k.kreisart,
       SUM(CASE WHEN e.altersgruppe_code = '75+' THEN e.anzahl ELSE 0 END)    AS einwohner_75plus,
       SUM(e.anzahl)                                                           AS einwohner_gesamt,
       CAST(100.0 * SUM(CASE WHEN e.altersgruppe_code = '75+' THEN e.anzahl ELSE 0 END)
            / SUM(e.anzahl) AS DECIMAL(4,1))                                   AS anteil_75plus_pct
FROM core.einwohner AS e
JOIN core.kreis AS k ON k.kreis_id = e.kreis_id
WHERE e.stichtag = '2024-12-31'
GROUP BY k.name, k.kreisart
ORDER BY einwohner_75plus DESC;
-- 6 rows: Regionalverband Saarbruecken has the most (41,461) but the second-lowest share
-- (12.6 %); St. Wendel has the fewest (12,251) but the highest SHARE (14.1 %).
-- Absolute and relative numbers tell different stories - report both.
-- The "conditional aggregation" SUM(CASE ...) computes two different sums in one pass.
GO

/* -----------------------------------------------------------------------------
   1.8  Employed doctors (Anstellung) in MVZs
   ----------------------------------------------------------------------------- */
SELECT v.praxis,
       v.lanr,
       CONCAT_WS(N' ', v.titel, v.vorname, v.nachname) AS arzt,   -- skips a NULL titel
       v.fachgruppe,
       v.anrechnungsfaktor
FROM core.v_teilnahme_aktuell AS v
JOIN core.praxis AS p ON p.bsnr = v.bsnr
WHERE v.teilnahmeform_code = 'ANG'
  AND p.kooperationsform_code = 'MVZ'
ORDER BY v.praxis, v.nachname;
-- 168 rows. Second step - one row per MVZ with HAVING:
SELECT v.praxis,
       COUNT(*)                 AS angestellte,
       SUM(v.anrechnungsfaktor) AS summe_anrechnungsfaktor
FROM core.v_teilnahme_aktuell AS v
JOIN core.praxis AS p ON p.bsnr = v.bsnr
WHERE v.teilnahmeform_code = 'ANG' AND p.kooperationsform_code = 'MVZ'
GROUP BY v.praxis
HAVING COUNT(*) >= 6           -- HAVING filters GROUPS (after aggregation), WHERE filters ROWS (before)
ORDER BY angestellte DESC;
-- 20 MVZs with at least 6 employed doctors; "MVZ Saarbruecken 8" is the largest (9 people, 6.75 FTE).
-- Headcount (COUNT) and full-time equivalents (SUM of Anrechnungsfaktor) differ - planning uses the latter.
GO
