# Statistisches Amt Saarland (statistics office)

| | |
|---|---|
| Simulated origin | Official statistics office of the Land (GENESIS-style table export) and administrative boundaries (simplified to point features) |
| Owner (in the KV) | Bedarfsplanung / Versorgungsanalyse, who download the files |
| Update frequency | yearly (population on 31.12., published months later) |
| Loaded into | `stg.statistik_bevoelkerung` → `core.einwohner`; `stg.statistik_kreise_geojson` → `core.kreis` |

## Files

| File | Content |
|---|---|
| `bevoelkerung_kreise_2024.csv` | Population per Kreis, age group and sex on 31.12.2024 |
| `kreise_saarland.geojson` | The 6 Kreise of the Saarland with AGS, name, type, seat and an approximate point coordinate |

## Known quirks

- **cp1252 encoding** (Windows "ANSI"), not UTF-8 - umlauts break if read with the wrong encoding.
- **4 metadata lines + 1 empty line before the header** and a **footer note** after an empty line.
- Thousands separator is a dot: `7.920` means 7920.
- Age groups are text labels (`6 bis unter 18 Jahre`) that must be mapped to our codes (`core.altersgruppe.statistik_bezeichnung`).
- GeoJSON coordinates are in the order **[longitude, latitude]**.
- Property names follow official geodata conventions: `GEN` = name, `BEZ` = type of district.

## Realism note

Kreise, AGS codes and seats are real. Population totals are **rounded approximations from
general knowledge**, the age split is modelled. Do not use these numbers as facts.
