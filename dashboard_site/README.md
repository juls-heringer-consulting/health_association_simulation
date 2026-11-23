# Static dashboard (GitHub Pages)

Live: **https://juls-heringer-consulting.github.io/health_association_simulation/**

A small static website with the same eight pages as the Power BI report in
[`../powerbi_report`](../powerbi_report/README.md), in the same order:

1. Overview
2. Doctors
3. Billing & Honorar
4. Appointments (TSS)
5. Planning & Out-of-hours
6. Fachgruppe Explorer
7. Fachgruppe Growth
8. Vega Showcase

It runs in any browser without Power BI or SQL Server. All data is synthetic.

## Files

| File | What it is |
|---|---|
| `index.html`, `styles.css` | Page shell, light and dark theme |
| `charts.js` | Small SVG chart kit (bars, 100 % bars, donut, treemap, heat map, scatter, funnel, waterfall, stacked area). It has no dependencies and no CDN |
| `app.js` | The eight pages, slicers, KPI tiles, tooltips and table views, plus the card that runs Deneb visuals (`vegaCard`) |
| `data.js` | **Generated** data (about 360 KB), written by `python/export_dashboard_data.py`. Do not edit by hand |
| `deneb_specs.js` | **Generated** copy of every Deneb visual's spec and config in the Power BI report, written by `python/export_deneb_specs.py`. Do not edit by hand |
| `vendor/vega.min.js`, `vendor/vega-lite.min.js` | Vega 6.4.0 and Vega-Lite 6.4.3, the versions Deneb uses (BSD-3-Clause, see `vendor/LICENSE-*.txt`). They are served from this folder, not from a CDN, and load only when a page with a Deneb visual is opened |

## Pages that mirror the newer Power BI pages

- **Fachgruppe Explorer** is rebuilt with the chart kit. It mirrors the Power BI page:
  - Quarter and Kreis slicers (Kreis of the billing practice).
  - KPIs: billing cases, gross Honorar, EBM points per case.
  - Cases by Fachgruppe. Clicking a bar filters the page; clicking it again clears the filter.
  - Cases per quarter. Clicking a quarter sets the quarter slicer.
  - **Honorar uses the same logic as the measure** *Honorar Brutto (Practices in Fachgruppe)*: it is
    the Honorar of the practices that billed cases in the current filter.
  - Checked against SQL: Psychologische Psychotherapie, 2/2025, Neunkirchen gives 77 cases,
    38,608 € and 4,047 points per case, in both SQL and the site.
- **Fachgruppe Growth** runs the report's two Deneb specs unchanged:
  - The raincloud (Vega) and the heatmap (Vega-Lite).
  - The data are the yearly counts of active doctors per Fachgruppe (2010 to the data year). They
    are exported with the same logic as the measures *Active Doctors (Year End)* and *Doctor Growth YoY*.

## Deneb visuals on the site

- **The specs are the same as in Power BI.** `deneb_specs.js` is a 1:1 copy of the Deneb visuals
  `growth_raincloud`, `growth_heatmap` and `tss_year_clock`.
  - Each visual gets the same field names Deneb passes in Power BI. For example, the showcase gets
    `anfrage_id`, `datum`, `arztgruppe`, `dringlichkeit`, `kanal`, `status`, `wartezeit_tage` and
    `termin_wahrgenommen`.
  - Vega-Lite specs are compiled to Vega in the browser.
  - If a spec changes in Power BI, run `python\export_deneb_specs.py` to update the copy.
- **Tooltips.** Vega tooltips appear in the dashboard's own tooltip box.
- **Debugging.** `window.KVSIM_VIEWS` holds the live Vega views by visual name, for the browser console.

### Vega Showcase page

- **Renderer switch.** *SVG* and *Canvas* compare Vega's two renderers outside Power BI. The line
  *Hover state* below the chart shows the hovered request, which helps with debugging.
- **Tooltip cards stay in the chart.**
  - Vega's SVG renderer does not remove a *group* item from the page when the item's data row
    disappears. A tooltip card built that way stays visible after the mouse has left.
  - So the spec keeps both cards in the chart once they have been shown, and only switches their
    opacity. The hovered dot is found from the pointer position, not from mouseover/mouseout events.
- **Width.** The chart needs at least 1,000 px. On smaller screens the card scrolls sideways.

## Open locally

Double-click `index.html`. The data comes from a `<script>` file, so no web server is needed.

## Refresh the data

After rebuilding the database (`tools\run_all.ps1`), run this from the project root:

```powershell
.venv\Scripts\python.exe python\export_dashboard_data.py
.venv\Scripts\python.exe python\export_deneb_specs.py     # only if a Deneb visual changed in Power BI
```

The script reads the connection from `config/settings.toml`. It aggregates the `mart` star
schemas or exports anonymous rows: no names, LANR or BSNR. It then rewrites `data.js`.
Commit the new `data.js` to update the published site.

## Publish with GitHub Pages

The workflow `.github/workflows/pages.yml` publishes this folder on every push to `main` that
touches `dashboard_site/`. It can also be started by hand under *Actions*. One-time setup:

1. On GitHub, open **Settings → Pages → Build and deployment → Source** and select **GitHub Actions**.
2. Push to `main`, or run the workflow *Deploy dashboard to GitHub Pages* by hand.
3. The site appears at `https://<owner>.github.io/<repository>/`.

> GitHub Pages for a **private** repository needs a paid plan (Pro, Team or Enterprise), and
> the site is then **public** unless the organisation is on Enterprise Cloud with private
> Pages. The data is synthetic, but check this before you publish.

## How it relates to the Power BI report

- **Same figures.** Headless Edge checked the KPIs against the expected SQL values in the report
  README. Examples: 1,789 doctors, 1,452,002 € → 146,552 €, TSS 1,500 → 1,266 → 1,127, and
  areas open/closed/under-supplied of 18/37/0 at 01.01.2026 and 18/36/1 at 01.01.2025.
- **Same colour system.** Blue/orange/aqua are nominal categories in a fixed order. A blue ramp
  shows urgency. Red ↔ grey ↔ blue shows below/at/above target. Red marks the "bad direction"
  and grey marks totals. Dark mode uses separately chosen colour steps, checked with the same
  palette validator.
- **Slicers.**
  - Each page has one slicer (Kreis, quarter, specialty or reference date), as in the report.
  - Charts whose axis *is* the slicer dimension keep all values and highlight the selection
    instead of filtering. Examples are MGV/EGV per quarter, the insurer × quarter heat map and
    the average wait by specialty.
  - Clicking a bar in *Average waiting time by specialty* filters the TSS page.
- **Extras the report does not have.**
  - A one-sentence summary per page, recalculated for the current slicer.
  - A *Table* view on every chart.
  - A light/dark theme switch.

## Limitations

- The data is a snapshot from the last export, not a live connection.
- Doctors without an active practice (16) appear only under "All Kreise".
- Month and weekday labels are English abbreviations. They are derived from the month and weekday
  numbers in `dim_datum`.
- Billing and Honorar are a sample of the simulated data
  ([assumptions.md](../docs/assumptions.md)). Compare shares and patterns, not absolute euros.
