# Ärztlicher Bereitschaftsdienst (out-of-hours service)

| | |
|---|---|
| Simulated origin | Rota planning tool of the out-of-hours service |
| Owner (in the KV) | Bereitschaftsdienst-Organisation |
| Update frequency | monthly plan, daily changes (swaps) |
| Loaded into | `stg.bd_bereitschaftspraxen` → `core.notfallpraxis`; `stg.bd_dienstplan` → `core.bereitschaftsdienst` |

## Files

| File | Content |
|---|---|
| `bereitschaftspraxen.csv` | out-of-hours practices (one per Kreis in this simulation) |
| `dienstplan_2025.csv` | every shift of 2025 with the doctor who served it and, if swapped, the original doctor |

## Known quirks

- A shift is stored as **date + start time + end time**; when the end time is not after the start time (`20:00` → `08:00`), the shift **ends on the next day**.
- Times are local time without offset - on DST change nights a 20:00-08:00 shift is really 11 or 13 hours long.
- `Getauscht_von_LANR` is empty unless the shift was swapped.

## Realism note

Shift pattern (Mon/Tue/Thu evenings, Wed/Fri afternoons, weekends and holidays 24 h in two
shifts) and the locations are assumptions. Psychotherapists and paediatricians are not
scheduled in this service.
