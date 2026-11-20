# Power BI analysis report (PBIP) - KV Saarland, simulated

A five-page analysis report on the simulated KV data. It is the "second iteration" next to the
quick first look in [`../powerbi_overview`](../powerbi_overview/README.md): more data (17 mart
tables plus 2 helper tables), more chart types, and **one colour system across all pages**.
All data is synthetic.

> **Status:** opened and refreshed in Power BI Desktop 2.159 (Oct 2026) on the reference build;
> all 28 headline measures match SQL exactly. The rendered charts *with data* have not been
> looked at yet - see [What was verified](#what-was-verified).

## Pages at a glance

| Page | Question it answers | Visuals |
|---|---|---|
| **Overview** | How big is the system and where does the volume sit? | 5 KPI cards · cases per quarter (column) · cases by patient age group (column) · practices by form of cooperation (donut) · cases by specialty (**treemap**, coloured by level of care) · cases by Kreis (bar) |
| **Doctors** | Who provides care? | Kreis slicer · 5 KPI cards (doctors, share female, average age, share 60+, share employed) · gender mix by specialty (**100 % stacked bar**) · age structure (column) · licensed vs. employed by practice type (stacked column) |
| **Billing & Honorar** | Where does the money go? | Quarter slicer · 4 KPI cards · Honorar brutto → final payment (**waterfall**) · MGV vs. EGV per quarter (stacked column) · cases by type of insurer × quarter (**heat-map matrix**) · every practice: cases vs. Honorar (**scatter**) · billed amount by EBM chapter split by MGV/EGV (stacked bar) |
| **Appointments (TSS)** | How fast do patients get an appointment? | Specialty slicer · 4 KPI cards · request → arranged → attended (**funnel**) · requests per month by urgency (stacked column, ordinal colours) · waiting-time distribution (histogram, red beyond 4 weeks) · average wait by specialty (bar, red above 28 days) · request channel (donut) |
| **Planning & Out-of-hours** | Where are doctors missing? | Reference-date slicer · 5 KPI cards · **supply-level heat map** (physician group × planning area, diverging colours) with a colour key · out-of-hours hours by weekday (stacked column) · service hours per month (**stacked area**) |

54 visual containers in total (including headers, colour key and slicers).

## The colour system

Colours follow one rule each, so a colour means the same thing on every page.
The palette is the validated reference palette of the data-viz method used to build this
report; every combination below was checked with its validator (colour-blind separation,
lightness band, contrast) before use.

| Job | Colours | Where |
|---|---|---|
| **One measure, one colour** | blue `#2a78d6` | every single-series chart (cases, doctors, requests, funnel) |
| **Nominal categories** (fixed order, never by rank) | blue `#2a78d6` · orange `#eb6834` · aqua `#1baf7a` | form of cooperation (Einzelpraxis · BAG · MVZ, same colours in donut and scatter), level of care, request channel, licensed/employed, weekday/weekend, **MGV/EGV (blue/orange on both MGV/EGV charts)** |
| **Gender** | aqua `#1baf7a` (female) · violet `#6250d6` (male) | deliberately different from the blue/orange pairs |
| **Ordered categories** | blue ramp `#184f95` → `#2a78d6` → `#86b6ef` | urgency AKUT → DRINGEND → ROUTINE (darker = more urgent) |
| **Magnitude** | sequential blue `#cde2fb` → `#5598e7` | heat map cases by insurer type × quarter |
| **Below / above target** | red `#e34948` ↔ grey `#f0efec` ↔ blue `#3987e5` | supply level (red = under target, grey = at target, blue = above, ≥ 110 % = closed) |
| **"Bad direction"** | red `#e34948` | waterfall deductions, waiting times beyond 4 weeks, specialties with average wait > 28 days |
| **Totals / neutral** | grey `#898781` | waterfall total (= final payment) |

Rules followed: no dual-axis charts (MGV/EGV share one euro axis), every multi-colour chart
has a legend or direct labels, aqua (below 3:1 contrast on white) is only used with data labels,
and text stays in ink colours (`#0b0b0b` / `#52514e`) rather than series colours.
The theme (`KVSim_Analysis.Report/StaticResources/RegisteredResources/KVSim_Analysis_Theme.json`)
sets the categorical order, page/card background, hairline borders, gridlines and fonts; colours
that carry meaning are set explicitly per category value in each visual so they never shift
when a filter removes a category.

## How to open

1. Build the database first (`tools\run_all.ps1`, see the [main README](../README.md)).
2. Power BI Desktop → **File > Open report > Browse this device** → `powerbi_report/KVSim_Analysis.pbip`.
3. Click **Refresh** (or "Refresh now" in the yellow bar). Use **Windows** credentials for the
   SQL Server source when asked. If Desktop complains about the certificate / encryption, allow
   an unencrypted connection (local training instance with a self-signed certificate).

## Manual steps

- **Data source:** Power Query parameters `ServerName` (default `localhost`) and `DatabaseName`
  (default `KVSim`), via *Home > Transform data > Edit parameters*. No credentials or personal
  paths are stored in the project.
- Nothing else; the theme and base theme are part of the project (`StaticResources`).

## Semantic model

- Import mode, source = the `mart` star schemas of `KVSim` (not the files in `data/sources`).
- 17 mart tables (11 dimensions, 6 facts) - see `definition/tables/*.tmdl`; only the columns
  used are selected (`Table.SelectColumns`).
- **Unknown members (`-1`) are filtered out** of every dimension in Power Query: no fact row
  references them (checked in SQL), and slicers stay free of "(Blank)".
- `dim_quartal` keeps only quarters that have billing data (inner join against the distinct
  quarter keys of `fact_abrechnungsfall`; the dimension itself spans 2024-2026).
- Auto date/time is switched off (`__PBI_TimeIntelligenceEnabled = 0`); `dim_datum` is the date
  dimension.
- 18 single-direction many-to-one relationships, including `dim_arzt[praxis_bsnr] → dim_praxis[bsnr]`
  so the Kreis slicer also filters doctors. `dim_arzt` is SCD2: doctor measures count the
  **current** version only (`is_current = TRUE`).
- Two helper tables defined in M (`#table`): `Honorar Step` (waterfall axis) and `TSS Stage`
  (funnel axis).
- Calculated columns (DAX), all derived from existing columns: `dim_arzt[Gender]`,
  `[Participation]`, `[Age 2025]`, `[Age Band]`; `dim_gop[Remuneration]` (MGV/EGV from
  `ist_extrabudgetaer`); `fact_tss_anfrage[Wait Class]`; `fact_bereitschaftsdienst[Day Type]`;
  `fact_versorgungsgrad[Stichtag]` (date from `stichtag_key`).
- 33 measures, among them:
  - `Honorar Bridge`: brutto − administrative costs − advance payments; the total equals `Payout`
    (reconciles to the cent for every practice and quarter, checked in SQL).
  - `Supply Level` = Σ actual ÷ Σ target doctors at the **latest reference date in the current
    filter**, so the heat map shows 01.01.2026 by default and any other date via the slicer.
    `Areas Open / Closed / Undersupplied` work the same way.
  - `Color Wait Class`, `Color Avg Wait` (display folder *Formatting*): colour measures used for
    field-value conditional formatting (red beyond the 4-week target).

## Expected values (SQL, reference build)

Use these to check the report after a refresh:

| Measure | Value | Measure | Value |
|---|---|---|---|
| Doctors | 1,789 | TSS requests | 1,500 |
| Practices | 1,022 | Placement rate | 84.4 % |
| Billing cases | 11,994 | Within 4 weeks (of arranged) | 80.8 % |
| Points per case | 989 | Avg waiting time | 19.0 days |
| Honorar brutto | 1,452,002 € | Shifts | 3,480 |
| Final payment (Payout) | 146,552 € | Swap rate | 5.4 % |
| EGV share | 72.9 % | Areas open / closed / under-supplied (01.01.2026) | 18 / 37 / 0 |
| Share female · avg age · 60+ · employed | 57.0 % · 52.8 · 22.2 % · 22.1 % | | |

## Versions pinned

| File | Schema / version |
|---|---|
| `.pbip` | `pbipProperties` 1.0.0 |
| `definition.pbism` | `definitionProperties` 1.0.0, version 4.0 (TMDL), `compatibilityLevel` 1567 |
| `definition.pbir` | `definitionProperties` 2.0.0, version 4.0, `byPath` |
| `report.json` | `report` 3.0.0, base theme `CY24SU10` + custom theme |
| `pages.json` / `page.json` | `pagesMetadata` 1.0.0 / `page` 2.0.0 |
| `visual.json` | `visualContainer` 2.0.0 |
| `version.json` | `versionMetadata` 1.0.0, version 2.0.0 |
| theme | checked against `reportThemeSchema-2.159.json` (Power BI Desktop 2.159) |

Schemas: <https://github.com/microsoft/json-schemas> (`fabric/item/report/definition/...`) and
<https://github.com/microsoft/powerbi-desktop-samples> (report theme schema).

## Known limitations

- **Charts with data not yet seen.** In the Desktop test the data loaded and all measures were
  correct, but the *Load* dialog stayed open in the UI after the load had finished (see below),
  so the pages could only be looked at empty. Labels may overlap, a sort order or a colour may
  need a click in the format pane. Please check each page once and report what looks wrong.
- Light theme only; there is no dark-mode variant of the theme.
- The month and weekday axes use the German names from `dim_datum` (Januar, Montag, …);
  correct because all TSS and out-of-hours data is from 2025.
- Age (`Age 2025`) is computed for the end of the billing year 2025 (constant `DATA_YEAR` in the
  generator, matching `config/settings.toml`). With another simulation year, change it.
- Billing and Honorar are a **sample** ([assumptions.md](../docs/assumptions.md)): compare shares
  and patterns, not absolute euros.
- Supply-level colours: the red pole starts at 75 % (the under-supply threshold for
  Hausärzte; for specialists it is 50 %). The official status comes from the source
  (`fact_versorgungsgrad.status`) and is what the KPI cards count.
- Not covered: diagnoses (ICD), QS permits, audits, prescriptions, text documents, maps
  (Azure Maps needs an online service and tenant setting, so it was left out on purpose).
- The 16 current doctors without an active participation (no practice) are counted in the
  KPI cards but filtered out of the "licensed vs. employed" chart.

## What was verified

| Check | Result |
|---|---|
| Every table/column exists in `KVSim.mart`, data types taken from `INFORMATION_SCHEMA`, relationship keys have identical types | done by the generator script |
| Every `Table[Column]` / `[Measure]` reference in DAX and every field in a visual exists in the model | done by the generator script |
| Every formatting object/property in `visual.json` and in the theme exists for that visual type in `reportThemeSchema-2.159.json` | done by the generator script / strict theme check |
| All 67 JSON files validate against the official Microsoft schemas pinned above | 0 errors |
| TMDL parses with Microsoft's `TmdlSerializer` (from the installed Desktop) | 19 tables, 18 relationships, 33 measures |
| Colour combinations checked with the palette validator (CVD separation, lightness, contrast) | pass; aqua below 3:1 contrast → always shown with data labels |
| Project opens in Power BI Desktop 2.159 without errors; theme, page background, card borders, titles, subtitles, colour key, 5 page tabs and all 19 tables visible | yes (screenshots) |
| Refresh against the local SQL Server (Windows auth, unencrypted) | all 19 partitions *Ready*, no errors, about 14 s; row counts as expected (e.g. 4 quarters, 1,022 practices, 11,994 cases, 25,309 billing lines) |
| 28 KPI measures queried through the Desktop engine (DAX) vs. the same figures in SQL | 28 / 28 identical |
| Waterfall steps (1,452,002 / −36,300 / −1,269,150 → 146,552), funnel (1,500 → 1,266 → 1,127), MGV/EGV per quarter, age bands, colour measures (red only for > 28 days / classes beyond 4 weeks), Stichtag logic (18/36/1 → 18/37/0) | as expected |

**Desktop quirk seen during the test:** after *Refresh now* the *Load* dialog kept showing
"Evaluating…" although Desktop's own trace shows all query evaluations finished and the engine
had committed the data within seconds. Cancel/close did not dismiss it. After that run the only
query with a cross-table step (`dim_quartal`) was rewritten as a plain, SQL-foldable inner join
and auto date/time was switched off; this final version was opened again but not refreshed
through the UI. If the dialog hangs for you, close Desktop, reopen the `.pbip` and refresh once
more - and please tell me, because then it is reproducible.
