# Qualitätssicherung (quality assurance)

| | |
|---|---|
| Simulated origin | Permit administration of the QS department (Genehmigungen nach § 135 Abs. 2 SGB V) |
| Owner (in the KV) | Qualitätssicherung |
| Update frequency | daily full export (assumption) |
| Loaded into | `stg.qs_genehmigungen` → `core.qs_genehmigung` |

## File

`qs_genehmigungen.csv` - `LANR;Leistungsbereich;Genehmigt_ab;Genehmigt_bis`

Leistungsbereich codes: `US` Ultraschall, `KOLO` Koloskopie, `AKU` Akupunktur, `HKS` Hautkrebs-Screening.

## Known quirks

- Dates `dd.mm.yyyy`; empty `Genehmigt_bis` = unlimited.
- Full snapshot every time: the core load replaces all permits (but never with an empty file).
