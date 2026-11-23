# Static dashboard (GitHub Pages)

Live: **https://juls-heringer-consulting.github.io/health_association_simulation/**

A small static website with the core pages of the Power BI report in
[`../powerbi_report`](../powerbi_report/README.md): Overview, Doctors, Billing & Honorar,
Appointments (TSS) and Planning & Out-of-hours. A sixth page, **Vega Showcase**, has the radial year
clock of the Power BI page with the same name. It runs in any browser without Power BI or SQL Server.
All data is synthetic.

## Files

| File | What it is |
|---|---|
| `index.html`, `styles.css` | Page shell, light and dark theme |
| `charts.js` | Small SVG chart kit (bars, 100 % bars, donut, treemap, heat map, scatter, funnel, waterfall, stacked area). It has no dependencies and no CDN |
| `app.js` | The six pages, slicers, KPI tiles, tooltips and table views |
| `data.js` | **Generated** data (about 250 KB), written by `python/export_dashboard_data.py`. Do not edit by hand |
| `showcase_spec.js` | **Generated** copy of the Deneb visual's Vega spec and config, written by `python/export_showcase_spec.py`. Do not edit by hand |
| `vendor/vega.min.js` | Vega 6.4.0, the same version Deneb uses (BSD-3-Clause, see `vendor/LICENSE-vega.txt`). It is served from this folder, not from a CDN, and is loaded only when the Vega Showcase page is opened |

## Vega Showcase page

- **The spec is the same as in Power BI.** `showcase_spec.js` is a 1:1 copy of the Deneb visual
  `tss_year_clock` (Power BI page *Vega Showcase*).
  - It is fed with the same field names Deneb passes: `anfrage_id`, `datum`, `arztgruppe`, `dringlichkeit`,
    `kanal`, `status`, `wartezeit_tage` and `termin_wahrgenommen`.
  - If the spec changes in Power BI, run `python\export_showcase_spec.py` to update the copy.
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
.venv\Scripts\python.exe python\export_showcase_spec.py   # only if the Deneb spec changed
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
