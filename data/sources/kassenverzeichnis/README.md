# Kassenverzeichnis (directory of statutory health insurers)

| | |
|---|---|
| Simulated origin | Directory of Krankenkassen with their IK (Institutionskennzeichen) |
| Owner (in the KV) | Abrechnung / Finanzen |
| Update frequency | monthly (mergers of Kassen happen regularly) |
| Loaded into | `stg.kassen_krankenkassen` → `core.krankenkasse` |

## File

`krankenkassen.csv` - `IK;Name;Kassenart` (UTF-8 with BOM, `;`)

## Realism note

The **names** are real Krankenkassen active in the Saarland. The **IK numbers are synthetic**
(9 digits, correct format, but NOT the real IKs of these Kassen). Market shares are approximate.
