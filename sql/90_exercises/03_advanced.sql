/* =============================================================================
   EXERCISES - Level 3: Advanced
   -----------------------------------------------------------------------------
   SQL concepts : time-validity ("as-of") queries, NOT EXISTS, FULL OUTER JOIN,
                  reconciliation, gaps and islands, SARGability, indexes, execution
                  plans, recursive CTEs, spatial data (geography)
   Main objects : core.teilnahme, core.teilnahme_status, core.fn_teilnahme_am,
                  mart.v_plausi_tagesprofil, mart.fact_leistung, core.qs_genehmigung,
                  core.honorarbescheid, core.versorgungsgrad, core.zulassungsverfahren(_status),
                  mart.dim_arzt, core.kreis, core.notfallpraxis
   Solutions    : sql/91_solutions/03_advanced.sql  (try first!)

   German terms used in this file:
     BSNR                    Betriebsstaettennummer (practice number)
     Status AKTIV/RUHEND/BEENDET  active / suspended / ended participation
     Plausibilitaetspruefung check of billed time. Every GOP has a Pruefzeit (standard
                             minutes). Suspicious: more than 12 hours on at least 3 days
                             of a quarter (Tagesprofil) or more than 780 hours per quarter
                             (Quartalsprofil)
     QS-Genehmigung          permit required to bill certain services (ultrasound, ...)
     punkte_berichtigt       points removed by the KV (sachlich-rechnerische Berichtigung)
     Nachbesetzung           succession of a doctor on a practice seat
     Bereitschaftspraxis     out-of-hours practice

   THE INTERVAL RULE: valid_from inclusive, valid_to EXCLUSIVE, open end = 9999-12-31.
   "valid on day D"  <=>  D >= valid_from AND D < valid_to   (not BETWEEN!)
   ============================================================================= */
USE KVSim;
GO

/* -----------------------------------------------------------------------------
   3.1  Who worked at a practice on a given day?
   Scenario : A Zulassungsausschuss member asks who worked at the practices with BSNR
              733392590 and 738423693 on 2025-06-30 - and with which status.
   Task     : List BSNR, LANR, name, Teilnahmeform, Anrechnungsfaktor and the status
              valid on that day. Then run the same for 2025-07-01: what changes and why
              is there never a doctor counted twice on the day of a change?
   Hints    : core.teilnahme + core.teilnahme_status, both filtered with the interval rule.
              Shortcut: core.fn_teilnahme_am(@stichtag).
   Expected : 6 rows for 2025-06-30, one doctor with status RUHEND
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   3.2  Plausibilitaetspruefung: time profiles
   Scenario : The Pruefwesen runs the quarterly time-plausibility check.
   Task     : (a) Tagesprofil: per doctor the number of days with services, the number of
              days above 12 hours and the maximum hours on one day - only doctors with at
              least 3 days above 12 hours.
              (b) Quartalsprofil: hours per doctor and quarter, ranked within the
              Fachgruppe; show the top 20.
   Hints    : mart.v_plausi_tagesprofil (a), mart.fact_leistung.pruefzeit_min (b).
              RANK() OVER (... ORDER BY SUM(...) DESC) works on aggregates.
   Think    : The billing data is a SAMPLE (a few cases per doctor). Why does (b) never
              come close to 780 h? Look at how the suspicious days in (a) come about
              (core.leistung.anzahl) - is that real behaviour or a property of the data?
   Expected : (a) 1 doctor, (b) maximum around 53 hours
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   3.3  QS services without permit - and did the KV correct them?
   Scenario : The QS department checks whether GOPs that require a QS-Genehmigung were
              billed by doctors without a valid permit ON THE SERVICE DATE. The Abrechnung
              wants to know whether exactly these points were removed in the Bescheide.
   Task     : (a) List the billing lines without valid permit (BSNR, LANR, date, GOP,
              QS area, points, quarter).
              (b) Per practice and quarter compare the points of (a) with
              core.honorarbescheid.punkte_berichtigt and mark OK / ABWEICHUNG.
   Hints    : core.gop.qs_bereich_code IS NOT NULL; NOT EXISTS (... core.qs_genehmigung
              with the interval rule). (b): FULL OUTER JOIN shows mismatches in both directions.
   Expected : (a) 20 lines, (b) 20 rows, all OK
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   3.4  Recompute the Versorgungsgrad
   Scenario : The official Versorgungsgrade come as an Excel file from the Bedarfsplanung.
              Before the Landesausschuss decides, the DWH team checks them against the
              Arztregister.
   Task     : Recompute "Ist" (sum of Anrechnungsfaktoren of all Teilnahmen valid on the
              Stichtag, status AKTIV or RUHEND) per planning area, Arztgruppe and
              Stichtag, and list all rows where it differs from core.versorgungsgrad.
   Hints    : core.versorgungsgrad -> planungsbereich_kreis -> praxis -> teilnahme ->
              arzt -> fachgruppe (arztgruppe_code). A Kreis belongs to two planning areas!
   Expected : 0 rows (remove the filter to see all 165 comparisons)
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   3.5  Gaps and islands
   Scenario : HR-like questions on the register.
   Task     : (a) All RUHEND periods with their length in days, longest first.
              (b) Doctors who changed practice without interruption: merge consecutive
              Teilnahmen of the same doctor (next valid_from = previous valid_to) into
              one "island" and list the islands that consist of more than one Teilnahme.
              (c) Compare with mart.dim_arzt: which doctors have more than one version?
   Hints    : (a) DATEDIFF - with an exclusive end no "+1" is needed.
              (b) LAG to flag the start of a new island, running SUM of the flags = island
              number, then GROUP BY. (c) STRING_AGG ... WITHIN GROUP (ORDER BY ...).
   Expected : (a) 14 rows, (b) 20 rows, (c) 20 rows
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   3.6  SARGability, indexes and the execution plan
   Scenario : A report "points in March 2025" is slow on the production server.
   Task     : Compare two versions of the same query:
                (1) WHERE YEAR(leistungsdatum) = 2025 AND MONTH(leistungsdatum) = 3
                (2) WHERE leistungsdatum >= '2025-03-01' AND leistungsdatum < '2025-04-01'
              Measure the logical reads (SET STATISTICS IO ON) and look at the actual
              execution plan (Ctrl+M in SSMS). Then create an index that covers query (2),
              measure again - and DROP the index at the end.
   Hints    : CREATE INDEX ... ON core.leistung (leistungsdatum) INCLUDE (anzahl, punktzahl)
   Expected : same result for both (1,713,134 points); with the index (2) needs far fewer
              reads than (1). Why can (1) not seek?
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   3.7  Recursive CTEs
   Scenario : (a) The Zulassung department wants the complete status path of every
              procedure as one text ("EINGANG > IN_PRUEFUNG > ...").
              (b) Which doctors held a seat one after the other (Nachbesetzung)?
   Task     : (a) Recursive CTE: anchor = first status of each procedure, recursion = the
              status whose valid_from equals the previous valid_to. Show only the last
              step per procedure.
              (b) Recursive CTE over core.teilnahme: start with Zulassungen that are not a
              Nachbesetzung, follow successors at the same practice starting on the day the
              predecessor ended and confirmed by a NACHBESETZUNG procedure.
   Hints    : WITH cte AS (anchor UNION ALL recursive part). OPTION (MAXRECURSION n).
   Expected : (a) 126 rows, (b) 62 rows (31 handovers)
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   3.8  Spatial queries
   Scenario : The Versorgungsmanagement plans backups for the Bereitschaftspraxen.
   Task     : (a) Straight-line distance in km between all pairs of Kreis seats.
              (b) For every Kreis the nearest Bereitschaftspraxis in ANOTHER Kreis.
   Hints    : geography::Point(latitude, longitude, 4326) from core.kreis (geo_breite,
              geo_laenge); .STDistance() returns metres. (b): CROSS APPLY with TOP (1).
              Assume each Bereitschaftspraxis is located at its Kreis seat.
   Expected : (a) 15 pairs, (b) 6 rows
   ----------------------------------------------------------------------------- */



