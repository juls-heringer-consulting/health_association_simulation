/* =============================================================================
   EXERCISES - Level 1: Basics
   -----------------------------------------------------------------------------
   SQL concepts : SELECT, WHERE, ORDER BY, JOIN (INNER / LEFT), GROUP BY, HAVING,
                  COUNT / SUM, percentages
   Main objects : core.fachgruppe, core.arztgruppe, core.arzt, core.praxis, core.kreis,
                  core.v_teilnahme_aktuell, core.abrechnungsfall, core.leistung, core.gop,
                  core.krankenkasse, core.kassenart, core.einwohner
   Solutions    : sql/91_solutions/01_basics.sql  (try first!)

   German terms used in this file:
     Fachgruppe   medical specialty (digits 8-9 of the LANR, the doctor's number)
     Arztgruppe   group used by the Bedarfsplanung (needs planning), e.g. Hausaerzte
     Teilnahme    a doctor's participation at a practice (Zulassung = licence as
                  Vertragsarzt, Anstellung = employed)
     Fallzahl     number of Behandlungsfaelle (one patient, one practice, one quarter)
     GOP          Gebuehrenordnungsposition = billing code of the EBM fee schedule
     Kassenart    type of health insurer (AOK, Ersatzkasse, BKK, ...)
     MVZ          Medizinisches Versorgungszentrum (medical care centre)
   ============================================================================= */
USE KVSim;
GO

/* -----------------------------------------------------------------------------
   1.1  Fachgruppen and their Arztgruppe
   Scenario : A new colleague in the Arztregister asks how the specialty codes of the
              LANR relate to the groups of the Bedarfsplanung.
   Task     : List every Fachgruppe (code and name) with the name of its Arztgruppe and
              the Versorgungsebene (level of care). Sort by Arztgruppe.
   Hints    : core.fachgruppe has arztgruppe_code. Think about INNER vs. LEFT JOIN:
              what should happen to a Fachgruppe without Arztgruppe?
   Expected : 11 rows; columns fachgruppe_code, fachgruppe, arztgruppe, versorgungsebene
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   1.2  Number of doctors per Fachgruppe
   Scenario : For the annual report the communications department needs the number of
              doctors and psychotherapists per specialty.
   Task     : Count the persons in core.arzt per Fachgruppe, largest group first.
   Hints    : GROUP BY + COUNT(*). Every column in SELECT that is not aggregated must
              appear in GROUP BY.
   Expected : 11 rows; the largest group has about 520 persons
   Think    : does this count only ACTIVE doctors? (compare with 1.3)
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   1.3  Practices in the Landkreis St. Wendel and their active doctors
   Scenario : The Bezirksstelle (regional office) St. Wendel wants a list of all
              practices in its Kreis with the number of currently active doctors.
   Task     : For every practice in the Kreis with AGS '10046' show BSNR, name, place,
              Kooperationsform and the number of doctors with status AKTIV today.
              Practices without an active doctor must appear with 0.
   Hints    : core.v_teilnahme_aktuell (who works where today, with status_code).
              LEFT JOIN + COUNT(<column of the right table>). Where must the condition
              status_code = 'AKTIV' go - ON or WHERE?
   Expected : 84 rows; columns bsnr, praxis, ort, kooperationsform_code, aktive_aerzte
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   1.4  Fallzahlen per quarter
   Scenario : The Abrechnung (billing) department wants to see how many
              Behandlungsfaelle were billed per quarter in 2025.
   Task     : Per quarter: number of cases, number of practices with cases, number of
              different patients.
   Hints    : core.abrechnungsfall; COUNT(DISTINCT ...)
   Expected : 4 rows, about 3,000 cases per quarter
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   1.5  Top 10 GOPs by points
   Scenario : Which billing codes generated the most points in 2025?
   Task     : Show the 10 GOPs with the highest sum of points (anzahl * punktzahl) for
              services in 2025, with code, title, number of units and points.
   Hints    : core.leistung + core.gop; TOP (10) needs an ORDER BY. Filter the date with
              a range (>= and <), not with YEAR().
   Expected : 10 rows; the top GOP has about 5.8 million points
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   1.6  Share of cases per Kassenart
   Scenario : Controlling asks: which types of insurers pay for our cases?
   Task     : Number of cases and percentage share (one decimal) per Kassenart.
   Hints    : core.abrechnungsfall -> core.krankenkasse -> core.kassenart.
              Careful: 100 * 3 / 7 is an INTEGER division in SQL Server.
   Expected : 6 rows; the shares add up to 100 %
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   1.7  Kreise by inhabitants aged 75 and older
   Scenario : The Versorgungsmanagement plans home visits and wants to know where many
              very old people live.
   Task     : Per Kreis: inhabitants aged 75+, total inhabitants and the share of 75+
              in percent. Sort by the number of inhabitants aged 75+.
   Hints    : core.einwohner (altersgruppe_code '75+'); SUM(CASE WHEN ... THEN ... ELSE 0 END)
              computes a conditional sum and a total in the same query.
   Expected : 6 rows. Compare: is the Kreis with the most old people also the one with
              the highest share?
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   1.8  Employed doctors in MVZs
   Scenario : The Zulassung (licensing) department reviews employment in MVZs.
   Task     : (a) List all currently employed doctors (teilnahmeform_code 'ANG') working
              in an MVZ with MVZ name, LANR, name, Fachgruppe and Anrechnungsfaktor.
              (b) One row per MVZ with the number of employed doctors and the sum of their
              Anrechnungsfaktoren - only MVZs with at least 6 employed doctors.
   Hints    : core.v_teilnahme_aktuell + core.praxis (kooperationsform_code 'MVZ').
              (b): HAVING filters groups.
   Expected : (a) 168 rows, (b) 20 rows
   ----------------------------------------------------------------------------- */



