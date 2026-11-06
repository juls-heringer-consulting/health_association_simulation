# Bedarfsplanung (needs planning)

| | |
|---|---|
| Simulated origin | Working file of the Bedarfsplanung department with the decisions of the Landesausschuss der Ärzte und Krankenkassen |
| Owner (in the KV) | Bedarfsplanung |
| Update frequency | twice a year (Stichtage 1 January / 1 July), plus ad-hoc decisions |
| Loaded into | `stg.bedarfsplanung_*` → `core.arztgruppe`, `core.planungsbereich`, `core.planungsbereich_kreis`, `core.versorgungsgrad` |

## File: `bedarfsplanung_2025.xlsx`

| Sheet | Content | Header row |
|---|---|---|
| `Arztgruppen` | physician groups with level, planning-area type and Verhältniszahl (inhabitants per doctor) | 1 |
| `Planungsbereiche` | planning areas and the Kreise they consist of | 1 |
| `Versorgungsgrade` | supply level per planning area, group and Stichtag (2025-01-01, 2025-07-01, 2026-01-01) | **3** |

## Known quirks

- Sheet `Versorgungsgrade` has a **merged title cell in row 1 and an empty row 2**; the header is in row 3.
- `Versorgungsgrad` is stored as a **fraction formatted as percent** (cell shows 108.3 %, value is 1.083).
- **Lists inside one cell**: `Fachgruppenschluessel` = `01, 03`, `Kreise_AGS` = `10041, 10042, ...` (violates 1NF; split with STRING_SPLIT in core).
- Excel dates are real date cells; the loader writes them as ISO text into staging.

## Realism note

Simplified: Hausärzte are planned per Kreis (real: Mittelbereich), Fachinternisten for the
whole Saarland (Raumordnungsregion). Verhältniszahlen are simplified, total-population based.
Rules used: Versorgungsgrad > 110 % → GESPERRT (closed); < 75 % (Hausärzte) / < 50 % (others) → UNTERVERSORGT.
