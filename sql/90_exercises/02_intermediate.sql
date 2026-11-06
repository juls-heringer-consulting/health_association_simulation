/* =============================================================================
   EXERCISES - Level 2: Intermediate
   -----------------------------------------------------------------------------
   SQL concepts : CTEs (WITH), subqueries, CASE, window functions (LAG, SUM/AVG OVER,
                  DENSE_RANK, PERCENTILE_CONT), running totals, NULLIF
   Main objects : mart.fact_versorgungsgrad, mart.fact_abrechnungsfall, mart.fact_tss_anfrage,
                  mart.fact_bereitschaftsdienst, mart.dim_* ; core.abschlagszahlung,
                  core.honorarbescheid, core.fortbildungspunkte, core.teilnahme
   Solutions    : sql/91_solutions/02_intermediate.sql  (try first!)

   German terms used in this file:
     Planungsbereich     planning area of the Bedarfsplanung
     Versorgungsgrad     supply level = Ist / Soll * 100 (actual / target number of doctors);
                         > 110 % = area closed (GESPERRT), < 75 % (Hausaerzte) = undersupplied
     Stichtag            reference date
     Fallwert            EUR per Behandlungsfall = billed amount / number of cases
     TSS                 Terminservicestelle (appointment service, phone 116117)
     Abschlagszahlung    monthly advance payment to a practice during a quarter
     Honorarbescheid     quarterly fee statement of the KV
     Bereitschaftsdienst out-of-hours medical service
     Anrechnungsfaktor   how much of a planning seat a doctor counts (1.0 = full time)
     Fortbildungspunkte  continuing medical education (CME) points
   ============================================================================= */
USE KVSim;
GO

/* -----------------------------------------------------------------------------
   2.1  Hausarzt supply across the three Stichtage
   Scenario : The Bedarfsplanung department prepares the next meeting of the
              Landesausschuss and asks: which Hausarzt planning areas are below target,
              and how did the Versorgungsgrad develop over the year?
   Task     : For Arztgruppe 'HA' list every planning area and Stichtag with
              Versorgungsgrad and status, plus the change in percentage points compared
              with the previous Stichtag of the same area. Then (second query) show only
              the latest Stichtag, worst area first.
   Hints    : mart.fact_versorgungsgrad + dim_datum, dim_planungsbereich, dim_arztgruppe.
              LAG(...) OVER (PARTITION BY ... ORDER BY ...). "Latest" = MAX(stichtag_key).
   Expected : 18 rows (6 areas x 3 dates); the first date of each area has no change (NULL)
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   2.2  Practices with an unusual Fallwert
   Scenario : The Pruefwesen (audit department) looks for practices whose average value
              per case differs strongly from their peers.
   Task     : For 2025, compute per practice and Fachgruppe the number of cases and the
              Fallwert (EUR per case). Compare it with the Fallwert of the whole
              Fachgruppe and list all practices that deviate by more than 40 % (up or
              down). Ignore practices with fewer than 8 cases.
   Hints    : mart.fact_abrechnungsfall (betrag_eur, fachgruppe_key). Two CTEs: first
              aggregate per practice, then add the Fachgruppe value with
              SUM(...) OVER (PARTITION BY fachgruppe_key). Weighted or unweighted average -
              which is fairer?
   Expected : about 35 rows; bsnr, praxis_name, fachgruppe, faelle, fallwert,
              fallwert_fachgruppe, abweichung_pct
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   2.3  Fallzahlen quarter over quarter
   Scenario : Controlling wants the development of Fallzahlen per Arztgruppe.
   Task     : Per Arztgruppe and quarter: Fallzahl, the Fallzahl of the previous quarter,
              the absolute and the percentage change.
   Hints    : aggregate in a CTE first, then LAG(). Avoid integer division and division
              by zero (NULLIF).
   Expected : 40 rows (10 Arztgruppen x 4 quarters)
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   2.4  TSS: urgent appointments within four weeks
   Scenario : The law requires that the Terminservicestelle arranges urgent specialist
              appointments within four weeks. The Versorgungsmanagement wants to know
              where this works.
   Task     : (a) For requests with dringlichkeit 'DRINGEND', per Arztgruppe: number of
              requests, number arranged (ist_vermittelt), number within 4 weeks and the
              share within 4 weeks (of the arranged ones).
              (b) The median waiting time per Arztgruppe for arranged urgent requests.
   Hints    : mart.fact_tss_anfrage. SUM() does not work on BIT columns - why, and what can
              you do? Median: PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ...) OVER (...).
   Expected : (a) 10 rows, (b) 10 rows; Psychotherapeuten have the longest waits
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   2.5  Abschlagszahlungen: running total vs. Honorarbescheid
   Scenario : A practice (BSNR 731005057) calls the Mitgliederservice: "Why do I have to
              pay money back for 2025Q3?"
   Task     : Show its advance payments per quarter with a running total within the
              quarter, next to the Abschlaege stated in the Honorarbescheid, the gross
              fee and the remaining payment (Auszahlungsbetrag). Then count per quarter
              how many Bescheide end with a negative payment (refund).
   Hints    : core.abschlagszahlung + core.honorarbescheid;
              SUM(...) OVER (PARTITION BY ... ORDER BY ... ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
   Expected : 9-12 rows for the practice; about 180 refunds per quarter overall
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   2.6  Bereitschaftsdienst workload
   Scenario : Doctors from rural areas complain that they have to do far more
              out-of-hours shifts than colleagues in the city.
   Task     : (a) Per Kreis and doctor: number of shifts and hours, the rank of the doctor
              within the Kreis by hours (DENSE_RANK), and the hours per full-time
              equivalent (hours / Anrechnungsfaktor) with its own rank.
              (b) Per Kreis: doctors on duty, total hours, hours per doctor.
   Hints    : mart.fact_bereitschaftsdienst + dim_arzt + dim_region. A doctor may have
              several dim_arzt versions (SCD2) - group by arzt_id, take attributes from
              the current version (is_current = 1).
   Expected : (a) about 1,250 rows, (b) 6 rows - is the complaint justified?
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   2.7  Patients visiting many Hausarzt practices
   Scenario : The Pruefwesen wants to know how often patients see three or more
              different Hausarzt practices in the same quarter ("doctor hopping").
   Task     : List quarter, patient pseudonym and the number of different Hausarzt
              practices for all cases with >= 3 practices.
   Hints    : core.abrechnungsfall; the Hausarzt is the doctor of the first billing
              line (core.leistung.positions_nr = 1) -> core.arzt -> core.fachgruppe
              (arztgruppe_code 'HA'). HAVING COUNT(DISTINCT ...).
   Expected : about a dozen rows. Why can we link cases of one patient at all, if we do
              not know who the patient is?
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   2.8  Doctors behind on their Fortbildung
   Scenario : § 95d SGB V requires 250 CME points every five years. The QS department
              needs the list of doctors who are short of points for 2021-2025.
   Task     : For doctors participating since before 2021-01-01: total points 2021-2025
              and missing points, only those below 250.
   Hints    : core.teilnahme (MIN(valid_from) per doctor), core.fortbildungspunkte.
              A doctor without ANY reported points must also appear (LEFT JOIN, COALESCE).
   Expected : about 50 rows
   ----------------------------------------------------------------------------- */



