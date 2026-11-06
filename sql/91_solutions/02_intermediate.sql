/* =============================================================================
   SOLUTIONS - Level 2: Intermediate
   Concepts: CTEs (WITH), subqueries, CASE, window functions
             (LAG, SUM/AVG OVER, DENSE_RANK, PERCENTILE_CONT), running totals
   Try the tasks in sql/90_exercises/02_intermediate.sql first!

   German terms used in this file:
     Planungsbereich     planning area of the Bedarfsplanung (needs planning)
     Versorgungsgrad     supply level = Ist / Soll * 100 (actual / target doctors)
     Stichtag            reference date
     Fallwert            EUR per Behandlungsfall (case) = billed amount / number of cases
     TSS                 Terminservicestelle (appointment service, phone 116117)
     Abschlagszahlung    monthly advance payment to a practice during a quarter
     Honorarbescheid     quarterly fee statement of the KV
     Bereitschaftsdienst out-of-hours medical service
     Anrechnungsfaktor   how much of a planning seat a doctor counts (1.0 = full time)
     Fortbildung         continuing medical education (CME points)

   Window functions in one sentence: they compute a value per row from a "window"
   of related rows (PARTITION BY = which rows, ORDER BY = in which order) WITHOUT
   collapsing the rows the way GROUP BY does.
   ============================================================================= */
USE KVSim;
GO

/* -----------------------------------------------------------------------------
   2.1  Hausarzt supply per planning area across the three Stichtage
   ----------------------------------------------------------------------------- */
WITH ha AS (
    SELECT d.datum                 AS stichtag,
           pb.planungsbereich_code,
           pb.planungsbereich,
           v.versorgungsgrad_pct,
           v.status
    FROM mart.fact_versorgungsgrad AS v
    JOIN mart.dim_datum            AS d  ON d.datum_key = v.stichtag_key
    JOIN mart.dim_planungsbereich  AS pb ON pb.planungsbereich_key = v.planungsbereich_key
    JOIN mart.dim_arztgruppe       AS ag ON ag.arztgruppe_key = v.arztgruppe_key
    WHERE ag.arztgruppe_code = 'HA'
)
SELECT stichtag,
       planungsbereich,
       versorgungsgrad_pct,
       status,
       -- LAG = value of the PREVIOUS row in the window (same area, ordered by date).
       -- For the first Stichtag there is no previous row -> NULL.
       versorgungsgrad_pct - LAG(versorgungsgrad_pct) OVER (PARTITION BY planungsbereich_code ORDER BY stichtag) AS veraenderung_pp
FROM ha
ORDER BY planungsbereich_code, stichtag;
-- 18 rows (6 areas x 3 Stichtage). St. Wendel: 72.6 % UNTERVERSORGT on 2025-01-01,
-- 76.3 % on 2025-07-01 (+3.7 pp, two Neuzulassungen) -> no longer below the 75 % threshold.
-- No Hausarzt area is GESPERRT (> 110 %); Saarbruecken comes closest with 107.6 %.

-- Only the latest Stichtag, worst areas first (subquery for "latest"):
SELECT pb.planungsbereich, v.versorgungsgrad_pct, v.status
FROM mart.fact_versorgungsgrad AS v
JOIN mart.dim_planungsbereich AS pb ON pb.planungsbereich_key = v.planungsbereich_key
JOIN mart.dim_arztgruppe      AS ag ON ag.arztgruppe_key = v.arztgruppe_key
WHERE ag.arztgruppe_code = 'HA'
  AND v.stichtag_key = (SELECT MAX(stichtag_key) FROM mart.fact_versorgungsgrad)
ORDER BY v.versorgungsgrad_pct;
GO

/* -----------------------------------------------------------------------------
   2.2  Practices whose Fallwert deviates more than 40 % from their Fachgruppe
   ----------------------------------------------------------------------------- */
WITH praxis_fg AS (            -- step 1: one row per practice and Fachgruppe (whole year 2025)
    SELECT f.praxis_key,
           f.fachgruppe_key,
           COUNT(*)          AS faelle,
           SUM(f.betrag_eur) AS betrag_eur
    FROM mart.fact_abrechnungsfall AS f
    GROUP BY f.praxis_key, f.fachgruppe_key
),
mit_vergleich AS (             -- step 2: add the Fachgruppe value to every row (window function)
    SELECT pf.*,
           pf.betrag_eur / pf.faelle AS fallwert,
           -- weighted Fachgruppe Fallwert: total EUR / total cases of the Fachgruppe.
           -- AVG(fallwert) OVER (...) would give every practice the same weight, so a
           -- practice with 8 cases would count as much as one with 40.
           SUM(pf.betrag_eur) OVER (PARTITION BY pf.fachgruppe_key)
             / SUM(pf.faelle) OVER (PARTITION BY pf.fachgruppe_key) AS fallwert_fachgruppe
    FROM praxis_fg AS pf
    WHERE pf.faelle >= 8       -- too few cases = too much noise (the billing data is a sample)
)
SELECT p.bsnr,
       p.praxis_name,
       fg.fachgruppe,
       m.faelle,
       CAST(m.fallwert AS DECIMAL(10,2))            AS fallwert_eur,
       CAST(m.fallwert_fachgruppe AS DECIMAL(10,2)) AS fallwert_fachgruppe_eur,
       CAST(100.0 * (m.fallwert / m.fallwert_fachgruppe - 1) AS DECIMAL(6,1)) AS abweichung_pct
FROM mit_vergleich AS m
JOIN mart.dim_praxis     AS p  ON p.praxis_key = m.praxis_key
JOIN mart.dim_fachgruppe AS fg ON fg.fachgruppe_key = m.fachgruppe_key
WHERE ABS(m.fallwert / m.fallwert_fachgruppe - 1) > 0.40
ORDER BY abweichung_pct DESC;
-- 36 rows; top: a psychotherapy practice at +222 % (1,467.53 EUR vs. 455.78 EUR),
-- several Hausarzt practices at +80 to +106 % (the generator marks ~2 % of practices as
-- "high billers" - exactly what the Pruefwesen would want to look at).
-- Note: the window WHERE pf.faelle >= 8 is applied BEFORE the window function, so the
-- Fachgruppe average is computed over the filtered practices only.
GO

/* -----------------------------------------------------------------------------
   2.3  Quarter-over-quarter change of Fallzahlen per Arztgruppe
   ----------------------------------------------------------------------------- */
WITH je_quartal AS (
    SELECT q.quartal_code, fg.arztgruppe, COUNT(*) AS fallzahl
    FROM mart.fact_abrechnungsfall AS f
    JOIN mart.dim_quartal    AS q  ON q.quartal_key = f.quartal_key
    JOIN mart.dim_fachgruppe AS fg ON fg.fachgruppe_key = f.fachgruppe_key
    GROUP BY q.quartal_code, fg.arztgruppe
)
SELECT arztgruppe,
       quartal_code,
       fallzahl,
       LAG(fallzahl) OVER (PARTITION BY arztgruppe ORDER BY quartal_code)            AS fallzahl_vorquartal,
       fallzahl - LAG(fallzahl) OVER (PARTITION BY arztgruppe ORDER BY quartal_code) AS veraenderung,
       -- NULLIF avoids division by zero; 100.0 avoids integer division
       CAST(100.0 * (fallzahl - LAG(fallzahl) OVER (PARTITION BY arztgruppe ORDER BY quartal_code))
            / NULLIF(LAG(fallzahl) OVER (PARTITION BY arztgruppe ORDER BY quartal_code), 0) AS DECIMAL(6,1)) AS veraenderung_pct
FROM je_quartal
ORDER BY arztgruppe, quartal_code;
-- 40 rows (10 Arztgruppen x 4 quarters). Hausaerzte: 1,151 -> 1,155 -> 1,069 (-7.4 %, summer) -> 1,119.

/* OPTIONAL, SQL Server 2022+ only: a named window avoids repeating the OVER clause.
   (Not executed here so that this file also runs on SQL Server 2019.)
SELECT arztgruppe, quartal_code, fallzahl,
       fallzahl - LAG(fallzahl) OVER w AS veraenderung
FROM je_quartal
WINDOW w AS (PARTITION BY arztgruppe ORDER BY quartal_code);
*/
GO

/* -----------------------------------------------------------------------------
   2.4  TSS: urgent requests with an appointment within 4 weeks, median waiting time
   ----------------------------------------------------------------------------- */
-- Part A: share within 28 days, per Arztgruppe
SELECT ag.arztgruppe,
       COUNT(*)                                                        AS anfragen_dringend,
       -- SUM() does not accept BIT columns (error 8117) -> cast to INT first
       SUM(CAST(t.ist_vermittelt AS INT))                              AS vermittelt,
       SUM(CASE WHEN t.ist_innerhalb_4_wochen = 1 THEN 1 ELSE 0 END)   AS innerhalb_4_wochen,
       CAST(100.0 * SUM(CASE WHEN t.ist_innerhalb_4_wochen = 1 THEN 1 ELSE 0 END)
            / NULLIF(SUM(CAST(t.ist_vermittelt AS INT)), 0) AS DECIMAL(5,1)) AS quote_4_wochen_pct
FROM mart.fact_tss_anfrage AS t
JOIN mart.dim_arztgruppe AS ag ON ag.arztgruppe_key = t.arztgruppe_key
WHERE t.dringlichkeit = 'DRINGEND'
GROUP BY ag.arztgruppe
ORDER BY quote_4_wochen_pct;
-- 10 rows. Psychotherapeuten worst: only 57.5 % of arranged urgent appointments within
-- 4 weeks; Nervenaerzte 86.4 %, Fachinternisten 88.1 %; most others 100 %.

-- Part B: median waiting time. PERCENTILE_CONT is a window function only: it returns
-- the value on EVERY row, so DISTINCT collapses the duplicates.
SELECT DISTINCT
       ag.arztgruppe,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY t.wartezeit_tage) OVER (PARTITION BY ag.arztgruppe) AS median_wartezeit_tage
FROM mart.fact_tss_anfrage AS t
JOIN mart.dim_arztgruppe AS ag ON ag.arztgruppe_key = t.arztgruppe_key
WHERE t.dringlichkeit = 'DRINGEND' AND t.ist_vermittelt = 1
ORDER BY median_wartezeit_tage DESC;
-- Psychotherapeuten 26.5 days, Nervenaerzte 21, Fachinternisten 20.5 ... Hausaerzte 3.
-- Why the median and not AVG? A few very long waits pull the average up; the median
-- ("half of the patients waited at most ...") is robust against such outliers.
GO

/* -----------------------------------------------------------------------------
   2.5  Running total of Abschlagszahlungen vs. the Honorarbescheid
   ----------------------------------------------------------------------------- */
SELECT p.bsnr,
       z.quartal_code,
       z.abschlag_nr,
       z.zahlungsdatum,
       z.betrag,
       -- running total: all payments of the same practice and quarter up to this row
       SUM(z.betrag) OVER (PARTITION BY z.praxis_id, z.quartal_code
                           ORDER BY z.abschlag_nr
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS abschlaege_kumuliert,
       h.abschlaege        AS abschlaege_laut_bescheid,
       h.honorar_brutto,
       h.auszahlungsbetrag  -- negative = the practice received too much and pays back
FROM core.abschlagszahlung AS z
JOIN core.praxis           AS p ON p.praxis_id = z.praxis_id
JOIN core.honorarbescheid  AS h ON h.praxis_id = z.praxis_id AND h.quartal_code = z.quartal_code
WHERE p.bsnr = '731005057'
ORDER BY z.quartal_code, z.abschlag_nr;
-- For 731005057: 3 payments of 211.00 in 2025Q2 add up to 633.00 = abschlaege in the
-- Bescheid; Restzahlung 57.43. In 2025Q3 the practice got 837.00 in advance but the
-- Bescheid only pays out 838.57 - 2.5 % administration fee -> Rueckforderung of 19.39.
-- ROWS BETWEEN ... is the explicit frame; without it SQL Server uses RANGE, which treats
-- rows with equal ORDER BY values as one group (can give surprising totals).

-- How common are refunds (negative Auszahlung)?
SELECT quartal_code, COUNT(*) AS bescheide,
       SUM(CASE WHEN auszahlungsbetrag < 0 THEN 1 ELSE 0 END) AS rueckforderungen
FROM core.honorarbescheid
GROUP BY quartal_code
ORDER BY quartal_code;
-- about 180 of ~900 Bescheide per quarter end with a refund.
GO

/* -----------------------------------------------------------------------------
   2.6  Bereitschaftsdienst hours per doctor, ranked within each Kreis
   ----------------------------------------------------------------------------- */
WITH stunden AS (
    SELECT r.kreis,
           a.arzt_id,
           SUM(f.dauer_stunden) AS stunden,
           COUNT(*)             AS dienste
    FROM mart.fact_bereitschaftsdienst AS f
    JOIN mart.dim_arzt   AS a ON a.arzt_key = f.arzt_key
    JOIN mart.dim_region AS r ON r.region_key = f.region_key
    GROUP BY r.kreis, a.arzt_id          -- arzt_id, not arzt_key: one doctor can have several SCD2 versions
)
SELECT s.kreis,
       cur.lanr,
       cur.fachgruppe,
       s.dienste,
       s.stunden,
       cur.anrechnungsfaktor,
       CAST(s.stunden / cur.anrechnungsfaktor AS DECIMAL(7,1))                     AS stunden_je_vollzeit,
       DENSE_RANK() OVER (PARTITION BY s.kreis ORDER BY s.stunden DESC)            AS rang_stunden,
       DENSE_RANK() OVER (PARTITION BY s.kreis ORDER BY s.stunden / cur.anrechnungsfaktor DESC) AS rang_je_vollzeit
FROM stunden AS s
JOIN mart.dim_arzt AS cur ON cur.arzt_id = s.arzt_id AND cur.is_current = 1   -- current version for the attributes
ORDER BY s.kreis, rang_stunden;
-- one row per doctor with shifts (~1,250 rows).
-- DENSE_RANK gives equal values the same rank without gaps (1,1,2); RANK would give 1,1,3;
-- ROW_NUMBER always numbers 1,2,3 even for ties.

-- The fairness question behind it: hours per doctor differ a lot between Kreise
SELECT r.kreis,
       COUNT(DISTINCT a.arzt_id)                                          AS aerzte_im_dienst,
       SUM(f.dauer_stunden)                                               AS stunden_gesamt,
       CAST(SUM(f.dauer_stunden) / COUNT(DISTINCT a.arzt_id) AS DECIMAL(6,1)) AS stunden_je_arzt
FROM mart.fact_bereitschaftsdienst AS f
JOIN mart.dim_arzt   AS a ON a.arzt_key = f.arzt_key
JOIN mart.dim_region AS r ON r.region_key = f.region_key
GROUP BY r.kreis
ORDER BY stunden_je_arzt DESC;
-- Every Bereitschaftspraxis needs the same 6,760 hours a year, but rural St. Wendel has
-- far fewer doctors: ~70 h per doctor vs. ~16 h in the Regionalverband Saarbruecken.
GO

/* -----------------------------------------------------------------------------
   2.7  Patients with cases at three or more Hausarzt practices in one quarter
   ----------------------------------------------------------------------------- */
WITH hausarztfaelle AS (
    SELECT f.quartal_code, f.patient_pseudonym, f.praxis_id
    FROM core.abrechnungsfall AS f
    JOIN core.leistung   AS l  ON l.fall_id = f.fall_id AND l.positions_nr = 1   -- Hauptbehandler
    JOIN core.arzt       AS a  ON a.arzt_id = l.arzt_id
    JOIN core.fachgruppe AS fg ON fg.fachgruppe_code = a.fachgruppe_code
    WHERE fg.arztgruppe_code = 'HA'
)
SELECT quartal_code,
       patient_pseudonym,
       COUNT(DISTINCT praxis_id) AS hausarztpraxen
FROM hausarztfaelle
GROUP BY quartal_code, patient_pseudonym
HAVING COUNT(DISTINCT praxis_id) >= 3
ORDER BY quartal_code, hausarztpraxen DESC;
-- 12 rows. Only possible because the pseudonym is STABLE: the same patient always gets the
-- same hash, so cases can be linked across practices without knowing who the person is.
-- (Distribution: 4,056 patient-quarters with 1 Hausarzt practice, 201 with 2, 12 with 3.)
GO

/* -----------------------------------------------------------------------------
   2.8  Doctors below 250 CME points in 2021-2025
   ----------------------------------------------------------------------------- */
WITH seit_vor_2021 AS (             -- doctors participating since before the 5-year period
    SELECT arzt_id
    FROM core.teilnahme
    GROUP BY arzt_id
    HAVING MIN(valid_from) < '2021-01-01'
),
punkte AS (
    SELECT fp.arzt_id, SUM(fp.punkte) AS punkte_5_jahre, COUNT(*) AS jahre_gemeldet
    FROM core.fortbildungspunkte AS fp
    WHERE fp.jahr BETWEEN 2021 AND 2025
    GROUP BY fp.arzt_id
)
SELECT a.lanr,
       CONCAT_WS(N' ', a.titel, a.vorname, a.nachname) AS arzt,
       f.bezeichnung                                   AS fachgruppe,
       COALESCE(p.punkte_5_jahre, 0)                   AS punkte_5_jahre,
       250 - COALESCE(p.punkte_5_jahre, 0)             AS fehlende_punkte
FROM seit_vor_2021 AS s
JOIN core.arzt       AS a ON a.arzt_id = s.arzt_id
JOIN core.fachgruppe AS f ON f.fachgruppe_code = a.fachgruppe_code
LEFT JOIN punkte     AS p ON p.arzt_id = s.arzt_id      -- LEFT: a doctor with NO points at all must appear too
WHERE COALESCE(p.punkte_5_jahre, 0) < 250
ORDER BY punkte_5_jahre;
-- 48 doctors (same number as data-quality rule DQ14). Under § 95d SGB V the KV must cut
-- their fees (10 %, later 25 %) until the points are proven.
GO
