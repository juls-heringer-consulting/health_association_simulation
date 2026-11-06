# Abrechnung (quarterly billing)

| | |
|---|---|
| Simulated origin | Analytics export of the KV billing system. Practices submit their billing in the KVDT format (xDT family) once per quarter; the billing system flattens it into three CSV files per quarter. |
| Owner (in the KV) | Abrechnung |
| Update frequency | once per quarter, a few weeks after quarter end |
| Loaded into | `stg.abrechnung_*` → `core.abrechnungsfall`, `core.leistung`, `core.fall_diagnose` |

## Files (per quarter, e.g. `2025Q1`)

| File | One row per | Key |
|---|---|---|
| `faelle_2025Q1.csv` | Behandlungsfall (one patient at one practice in one quarter) | Fallnummer |
| `leistungen_2025Q1.csv` | billed GOP | Fallnummer + Position |
| `diagnosen_2025Q1.csv` | diagnosis of a case | Fallnummer + ICD |

## Known quirks

- Quarter in **KVDT notation `QJJJJ`**: `12025` = 1st quarter 2025.
- Service date in **KVDT notation `TTMMJJJJ`** without separators: `28012025`.
- Points are **not** in the file - the KV adds them from the EBM (`core.gop`).
- UTF-8 without BOM, CRLF.
- Patients appear only as a 64-character **pseudonym** (salted SHA-256 of the insurance number). The year of birth is used once to derive the age group and then dropped.

## Realism note - this is a SAMPLE

A real KV processes millions of cases per quarter. This simulation generates about
3,000 cases per quarter (about 2 per doctor), so **euro amounts are tiny**, while ratios
(Fallwert per case, shares, rankings) remain meaningful. Realistic business anomalies are
included on purpose: a few "high-billing" practices and GOPs billed without QS permit.
