# Arztregister (physician register)

| | |
|---|---|
| Simulated origin | Arztregister system of the KV Saarland (register of all physicians and psychotherapists, § 95 SGB V / Ärzte-ZV) |
| Owner (in the KV) | Department Arztregister / Zulassung |
| Update frequency | daily full export (assumption) |
| Loaded into | `stg.arztregister_*` → `core.arzt`, `core.praxis`, `core.teilnahme`, `core.teilnahme_status` |

## Files

| File | One row per | Business key |
|---|---|---|
| `aerzte.csv` | person (doctor / psychotherapist), incl. applicants without Teilnahme | LANR |
| `betriebsstaetten.csv` | practice site (Betriebsstätte) | BSNR |
| `teilnahmen.csv` | participation of a person at a practice over time | LANR + BSNR + Gueltig_ab |
| `teilnahme_status.csv` | status period of a participation (AKTIV / RUHEND / BEENDET) | LANR + BSNR + Teilnahme_ab + Status_ab |

## Known quirks

- Dates as `dd.mm.yyyy`; an **empty `Gueltig_bis` / `Status_bis` means open-ended**.
- Decimal comma: `Anrechnungsfaktor` is `1,00`, `0,75`, ...
- The status file references the Teilnahme by its natural key (LANR, BSNR, start date) - there is no technical id.
- `Kreis_AGS` is maintained by the KV for planning purposes; the Gemeinde (`Ort`) is free text.
- The file always contains the full history (full snapshot), not only changes.

## Realism note

All persons and practices are **synthetic** (Faker de_DE). LANR check digits and BSNR
structure are realistic. Ort names are real Saarland Gemeinden; street names are invented.
