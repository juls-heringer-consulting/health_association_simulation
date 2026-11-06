/* =============================================================================
   503_views.sql
   Reporting views on top of the stars: they hide the joins and give business
   users ready-made, well-named result sets.
   ============================================================================= */
USE KVSim;
GO

-- Fallzahl and Fallwert (EUR per case) per practice, quarter and Fachgruppe
CREATE OR ALTER VIEW mart.v_fallwert_praxis_quartal
AS
SELECT q.quartal_code, p.bsnr, p.praxis_name, p.kooperationsform, r.kreis,
       fg.fachgruppe, fg.arztgruppe,
       COUNT(*)                                        AS fallzahl,
       SUM(f.punkte)                                   AS punkte,
       SUM(f.betrag_eur)                               AS betrag_eur,
       CAST(SUM(f.betrag_eur) / COUNT(*) AS DECIMAL(10,2)) AS fallwert_eur
FROM mart.fact_abrechnungsfall AS f
JOIN mart.dim_quartal    AS q  ON q.quartal_key = f.quartal_key
JOIN mart.dim_praxis     AS p  ON p.praxis_key = f.praxis_key
JOIN mart.dim_region     AS r  ON r.region_key = f.region_key
JOIN mart.dim_fachgruppe AS fg ON fg.fachgruppe_key = f.fachgruppe_key
GROUP BY q.quartal_code, p.bsnr, p.praxis_name, p.kooperationsform, r.kreis, fg.fachgruppe, fg.arztgruppe;
GO

-- Latest official Versorgungsgrad per planning area and Arztgruppe
CREATE OR ALTER VIEW mart.v_versorgung_aktuell
AS
SELECT d.datum AS stichtag, pb.planungsbereich_code, pb.planungsbereich, ag.arztgruppe,
       v.einwohner, v.soll_aerzte, v.ist_aerzte, v.versorgungsgrad_pct, v.status
FROM mart.fact_versorgungsgrad AS v
JOIN mart.dim_datum           AS d  ON d.datum_key = v.stichtag_key
JOIN mart.dim_planungsbereich AS pb ON pb.planungsbereich_key = v.planungsbereich_key
JOIN mart.dim_arztgruppe      AS ag ON ag.arztgruppe_key = v.arztgruppe_key
WHERE v.stichtag_key = (SELECT MAX(stichtag_key) FROM mart.fact_versorgungsgrad);
GO

-- Daily time profile per doctor (basis of the Plausibilitaetspruefung)
CREATE OR ALTER VIEW mart.v_plausi_tagesprofil
AS
SELECT a.lanr, a.arzt_name, a.fachgruppe, d.datum,
       SUM(f.pruefzeit_min)                                   AS pruefzeit_min,
       CAST(SUM(f.pruefzeit_min) / 60.0 AS DECIMAL(6,2))      AS pruefzeit_stunden
FROM mart.fact_leistung AS f
JOIN mart.dim_arzt  AS a ON a.arzt_key = f.arzt_key
JOIN mart.dim_datum AS d ON d.datum_key = f.datum_key
WHERE f.pruefzeit_min IS NOT NULL
GROUP BY a.lanr, a.arzt_name, a.fachgruppe, d.datum;
GO
