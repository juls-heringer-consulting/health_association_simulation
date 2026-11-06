# Data quality report

Checks: [`sql/70_quality/701_dq_rules_and_checks.sql`](../sql/70_quality/701_dq_rules_and_checks.sql)
Run: `EXEC meta.usp_run_dq_checks;` - results in `meta.dq_result`, latest run in `meta.v_dq_latest`.

## Result of the reference build (seed 20250101, run 2)

| Rule | Check | Category | Severity | Failed rows | Result |
|---|---|---|---|---|---|
| DQ01 | LANR check digit invalid | Validity | Error | 0 | PASS |
| DQ02 | BSNR outside KV Saarland | Validity | Error | 0 | PASS |
| DQ03 | Overlapping Teilnahmen of one doctor | Consistency | Error | 0 | PASS |
| DQ04 | Status history with gaps or overlaps | Consistency | Error | 0 | PASS |
| DQ05 | Service by a doctor not active at the practice | Consistency | Error | 0 | PASS |
| DQ06 | Service date outside the quarter of the case | Consistency | Error | 0 | PASS |
| DQ07 | Billing rows lost between stg and core | Completeness | Error | 0 | PASS |
| DQ08 | Documents without any link | Completeness | Warning | 0 | PASS |
| DQ09 | Honorarbescheid points differ from billed points | Reconciliation | Error | 0 | PASS |
| DQ10 | Advance payments differ from the Bescheid | Reconciliation | Error | 0 | PASS |
| DQ11 | Official Versorgungsgrad differs from the register | Reconciliation | Error | 0 | PASS |
| DQ12 | QS-GOP billed without valid Genehmigung | Business rule | Warning | **20** | finding |
| DQ13 | Corrected points differ from QS findings | Reconciliation | Error | 0 | PASS |
| DQ14 | Fortbildung below 250 points (2021-2025) | Business rule | Info | **48** | finding |
| DQ15 | Prescriptions > 125 % of Richtgröße without audit | Business rule | Warning | 0 | PASS |
| DQ16 | TSS appointment before the request | Consistency | Error | 0 | PASS |
| DQ17 | Out-of-hours shift by a doctor not eligible | Consistency | Error | 0 | PASS |
| DQ18 | TSS code in billing without TSS request | Consistency | Error | 0 | PASS |

## Interpretation

- **All integrity, completeness and reconciliation rules pass.** Nothing was lost between
  staging and core, and the independent sources agree with each other: Honorarbescheide
  match the billing lines (DQ09), payments match the Bescheide (DQ10), and the decided
  Versorgungsgrade match the register (DQ11).
- **DQ12 (20 lines)** is a real *finding*, not a data error: GOPs that need a QS permit were
  billed by doctors without a valid permit on that day. **DQ13 passes**, which shows that
  the KV already removed exactly these points in the Honorarbescheid
  (`punkte_berichtigt`). Two independent paths lead to the same answer.
- **DQ14 (48 doctors)** is a list for the QS department: fewer than 250 CME points in
  2021-2025 (§ 95d SGB V). In reality this triggers reminders and, later, fee reductions.

## A bug the checks found

In the first build, **DQ16 failed with 4 rows**: the appointment service had booked
same-day appointments *before* the request came in (an urgent request at 17:45 received
a 09:00 slot of the same day). The source data was wrong - here because of a bug in the
generator. The generator was fixed and DQ16 now passes. This is exactly the job of a
consistency rule: it does not need to know *why* data is wrong, only *that* two facts
cannot both be true.

## How to investigate a failing rule

Each rule in the procedure is a `COUNT(*)` query. Copy its `FROM ... WHERE ...` part and
replace `COUNT(*)` with the columns you want to see. Example for DQ12:

```sql
SELECT a.lanr, g.gop_code, g.qs_bereich_code, l.leistungsdatum, p.bsnr
FROM core.leistung AS l
JOIN core.gop AS g ON g.gop_id = l.gop_id
JOIN core.arzt AS a ON a.arzt_id = l.arzt_id
JOIN core.abrechnungsfall AS f ON f.fall_id = l.fall_id
JOIN core.praxis AS p ON p.praxis_id = f.praxis_id
WHERE g.qs_bereich_code IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM core.qs_genehmigung AS q
                  WHERE q.arzt_id = l.arzt_id AND q.qs_bereich_code = g.qs_bereich_code
                    AND l.leistungsdatum >= q.valid_from AND l.leistungsdatum < q.valid_to);
```

## Known simulation artefacts (found while building the exercises)

These are weaknesses of the *generator*, not of the warehouse. They are candidates for the
next version:

| Artefact | Effect | Fix idea |
|---|---|---|
| Repeated sessions (e.g. psychotherapy 35401, up to 10 × 70 min) are billed as **one line with `anzahl` > 1 on one date** | 32 doctor-days exceed 12 h of Prüfzeit; one psychotherapist hits the Plausi day rule (explained in solution 3.2) | spread repeated sessions over separate lines and dates |
| Only ~3 cases per practice and quarter (sample, A-30) | quarterly Fallwerte are noisy; exercise 2.2 uses the whole year and a minimum of 8 cases | raise `cases_per_fte_quarter` for statistics exercises |
| Waiting times of the TSS are short for most groups | almost all urgent appointments fall within 4 weeks except Psychotherapie, Nervenärzte, Fachinternisten | calibrate `TSS_WARTEZEIT_BASIS_TAGE` |
| Bereitschaftspraxen have no own coordinates | spatial exercise uses the Kreis seat (e.g. Ottweiler for Neunkirchen) | add coordinates per practice |
| BIT flags in fact tables (`ist_vermittelt`, ...) | `SUM()` on BIT fails (error 8117) - used as a teaching pitfall in level 2 | use TINYINT/INT 0/1 measures in facts |

## Not checked yet (ideas)

- Statistical outliers (Fallwert, prescription costs) as a rule instead of an exercise
- Trend checks between loads (row counts per source must not drop by > x %)
- Freshness (age of the newest file per source in `meta.load_file`)
