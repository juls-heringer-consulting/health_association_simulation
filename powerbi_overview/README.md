# Power BI overview (PBIP) - a first look at the KV simulation

A deliberately small Power BI report (2 pages, 12 visuals) for a quick first look at the
simulated KV Saarland data. All data is synthetic.

> **Status: not opened in Power BI Desktop.** The project was generated as text files and
> checked as far as possible without the Desktop UI (see [What was verified](#what-was-verified)).
> Expect to fix small things when you open it for the first time.

## Data source

The report reads the **`mart` star schemas of the SQL Server database `KVSim`**
(see the [main README](../README.md) and [er_diagrams.md](../docs/er_diagrams.md), section 5).
It does **not** read the CSV/XML/JSON files in `data/sources/`: those are raw inputs that the
loader turns into `stg` → `core` → `mart`. So the database must be built first
(`tools\run_all.ps1`). Import mode, 11 tables (all columns used are listed in `definition/tables/*.tmdl`).

## What the report shows

**Page "Overview"** - who is billing what?

| Visual | Why |
|---|---|
| Cards: Doctors, Practices, Billing cases | Size of the dataset in three numbers |
| Cases per quarter (column) | Time trend 2025 Q1-Q4 |
| Honorar brutto per quarter (column) | Money side; amounts are a tiny simulated sample, only ratios are realistic |
| Cases by Fachgruppe (bar, sorted) | Top specialties |
| Cases by Kreis (bar, sorted) | Regional distribution over the 6 Kreise |

**Page "Versorgung"** - access to care

| Visual | Why |
|---|---|
| Cards: TSS requests, share of arranged appointments within 4 weeks | Terminservicestelle headline numbers |
| TSS requests per month (line) | Trend over 2025 |
| TSS requests by Arztgruppe (bar) | Which specialties are requested |
| Out-of-hours shifts by Kreis (bar) | Bereitschaftsdienst workload by region |

Measures (DAX, on the fact/dimension table they belong to): `Doctors`, `Practices`, `Cases`,
`Honorar Brutto EUR`, `TSS Requests`, `Share Within 4 Weeks`, `Shifts`.

### Expected values (computed with SQL on the reference build)

Use these to check the report after the first refresh:
Doctors 1,789 · Practices 1,022 · Cases 11,994 (Q1 2,974 / Q2 3,005 / Q3 2,967 / Q4 3,048) ·
Honorar brutto 1,452,001.83 EUR · TSS requests 1,500 · Share within 4 weeks 80.8 % (1,023 of 1,266 arranged appointments).

## How to open

1. Make sure the `KVSim` database exists on your SQL Server (default instance on `localhost`).
2. Power BI Desktop → **File > Open report > Browse this device** → `powerbi_overview/KVSim_Overview.pbip`.
   (If Desktop refuses to open a PBIP: *File > Options > Preview features > "Power BI Project (.pbip) save option"* and for TMDL, "Store semantic model using TMDL format"; newer builds have these on by default.)
3. If the data source differs from the default, change the parameters (below).
4. **Home > Refresh.** Windows (current user) credentials are used; Desktop asks once.

## Manual steps

- **Data source location:** Power Query parameters `ServerName` (default `localhost`) and
  `DatabaseName` (default `KVSim`). Change them via *Home > Transform data > Edit parameters*.
  No credentials or personal paths are stored in the files.
- **Credentials:** choose "Windows" (current credentials) for the SQL Server source when asked.
- **Encryption prompt:** the local instance uses a self-signed certificate. If Desktop reports
  a certificate / encryption error, accept "connect without encryption" (local training DB only).
  The `Sql.Database` connector has no `TrustServerCertificate` option, so this cannot be set in the M code.

## Versions pinned

| File | Schema / version |
|---|---|
| `.pbip` | `fabric/pbip/pbipProperties` 1.0.0 |
| `SemanticModel/definition.pbism` | `definitionProperties` 1.0.0, `"version": "4.0"` (TMDL) |
| `SemanticModel/definition/database.tmdl` | `compatibilityLevel: 1567` |
| `Report/definition.pbir` | `definitionProperties` 2.0.0, `"version": "4.0"` (PBIR, `byPath`) |
| `Report/definition/report.json` | `report` 3.0.0 |
| `.../pages/pages.json`, `page.json` | `pagesMetadata` 1.0.0, `page` 2.0.0 |
| `.../visual.json` | `visualContainer` 2.0.0 |
| `.../version.json` | `versionMetadata` 1.0.0, `"version": "2.0.0"` |

Schema base: `https://developer.microsoft.com/json-schemas/fabric/item/report/definition/...`
(sources: <https://github.com/microsoft/json-schemas>). Older schema versions were chosen
on purpose so that a not-quite-current Desktop can still read them.

## Model in short

Star schemas as in `mart`: facts `fact_abrechnungsfall`, `fact_honorar_quartal`,
`fact_tss_anfrage`, `fact_bereitschaftsdienst`; dimensions `dim_quartal`, `dim_praxis`,
`dim_region`, `dim_fachgruppe`, `dim_arztgruppe`, `dim_datum`, `dim_arzt`.
12 many-to-one relationships (single direction, keys are the `*_key` columns, key columns hidden).
`fact_tss_anfrage` → `dim_datum` has two relationships: receipt date (active) and appointment
date (inactive, for later use with `USERELATIONSHIP`). Quarter and month labels are sorted by
`quartal_key` / `monat_nr`.

## Known limitations

- **Untested in Power BI Desktop** (see above). Visual layout/formatting is minimal and has never been looked at.
- `dim_arzt` is not related to any fact: it is only used to count doctors (`DISTINCTCOUNT(arzt_id)`,
  because the table is SCD2 and has several rows per doctor). Doctor-level analysis would need `arzt_key` relationships.
- `dim_quartal` contains 2024-2026, but data exists for 2025 only; empty quarters do not appear in charts.
  The monthly TSS chart uses month names without year, which is correct only because all TSS data is from 2025.
- Not shown on purpose: patients, diagnoses, GOP lines, Versorgungsgrad, Honorar details, QS, Prüfungen, Verordnungen,
  text documents. All of them are in `mart` / `core` for a second iteration.
- Billing and Honorar are a **sample** (see [assumptions.md](../docs/assumptions.md)): compare shares, not absolute euros.
- The `mart` unknown member (`-1`, "unbekannt") is kept in the dimensions, so a chart may show an "unbekannt" bar if a fact row has no match.

## What was verified

- Every table/column used exists in the live `KVSim.mart` schema (checked with `INFORMATION_SCHEMA`); data types
  of the TMDL columns were derived from it; relationship key columns have identical types on both sides.
- All 20 JSON files validate against the official Microsoft JSON schemas (versions above).
- The TMDL folder parses with Microsoft's `TmdlSerializer` (from the installed Power BI Desktop 2.159):
  11 tables, 12 relationships, 2 parameters.
- Expected values above were computed with SQL, not with DAX.

**Not verified:** that the M queries refresh, that DAX measures evaluate, that visuals render and bind
(field references were checked against the model by script, not by Desktop), and the visual appearance.
