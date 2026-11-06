# Prüfungsstelle (joint audit office)

| | |
|---|---|
| Simulated origin | Case management of the Prüfungsstelle der Ärzte und Krankenkassen (joint body of KV and Kassen, § 106c SGB V) |
| Owner (in the KV) | Prüfwesen (as recipient of the results) |
| Update frequency | monthly export (as of 2026-10-31) |
| Loaded into | `stg.pruefung_verfahren_xml` → `core.pruefverfahren` |

## File

`pruefverfahren_2025.xml` - Wirtschaftlichkeitsprüfungen (efficiency audits) of prescriptions:
Auffälligkeitsprüfung (statistical outlier) or Zufälligkeitsprüfung (random sample).

## Known quirks

- Quarter written as **`1/2025`**.
- `Abgeschlossen` and `Massnahme` only exist for finished procedures; the amount (`betrag`) only for a Nachforderung (recourse).

## Realism note

Procedures are triggered when prescription costs exceed 125 % of the Richtgrößenvolumen
(simplified: real audit rules differ by region and have changed since 2017).
