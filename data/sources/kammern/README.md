# Kammern (Ärztekammer / Psychotherapeutenkammer)

| | |
|---|---|
| Simulated origin | Continuing-education (CME) points reported electronically by the chambers |
| Owner (in the KV) | Qualitätssicherung (monitoring of § 95d SGB V) |
| Update frequency | monthly |
| Loaded into | `stg.kammer_fortbildungspunkte` → `core.fortbildungspunkte` |

## File

`fortbildungspunkte_2021_2025.csv` - `EFN;Jahr;Punkte`

## Known quirks

- The chambers identify doctors by the **EFN** (Einheitliche Fortbildungsnummer, 15 digits),
  **not by the LANR**. The core load maps EFN → doctor via `core.arzt.efn`: a classic
  "different source, different key" situation.

## Rule

§ 95d SGB V: 250 CME points within 5 years. Doctors below are a finding for the KV
(rule DQ14 in `sql/70_quality`).
