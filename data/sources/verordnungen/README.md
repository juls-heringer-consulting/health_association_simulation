# Verordnungen (prescriptions, aggregated)

| | |
|---|---|
| Simulated origin | Aggregated prescription data from the data centre of the Kassen (pharmacy and therapy claims), as a classic mainframe file |
| Owner (in the KV) | Verordnungsmanagement / Prüfwesen |
| Update frequency | quarterly |
| Loaded into | `stg.verordnung_zeilen` → `core.verordnung`; `stg.verordnung_richtgroessen` → `core.richtgroesse` |

## Files

| File | Content |
|---|---|
| `verordnungen_2025.txt` | fixed-width records: header `HD`, data `VO`, trailer `TR` |
| `richtgroessen_2025.csv` | Richtgröße (target EUR per case) per Arztgruppe and type |

## Fixed-width record layout (`VO`)

| Pos. | Length | Field |
|---|---|---|
| 1-2 | 2 | record type `VO` |
| 3-11 | 9 | BSNR |
| 12-16 | 5 | quarter `JJJJQ` (e.g. `20251`) |
| 17 | 1 | `A` = Arzneimittel (drugs), `H` = Heilmittel (therapies) |
| 18-24 | 7 | number of prescriptions, zero-padded |
| 25-35 | 11 | gross amount **in cent**, zero-padded |

Trailer `TR`: positions 3-9 = number of `VO` records, 10-22 = sum of all amounts in cent.

## Known quirks

- No delimiters at all; lines padded to 40 characters; cp1252; CRLF.
- **Control totals**: the core load rejects the whole file if the trailer does not match the data.
- Yet another quarter notation (`JJJJQ`).
- Richtgrößen CSV uses decimal comma.
