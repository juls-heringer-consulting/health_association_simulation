# KBV reference data (Kassenärztliche Bundesvereinigung)

| | |
|---|---|
| Simulated origin | KBV publications: Arztgruppenschlüssel (specialty codes) and the EBM master file (Einheitlicher Bewertungsmaßstab = fee schedule) |
| Owner (in the KV) | Abrechnung (billing) - catalogue maintenance |
| Update frequency | EBM: quarterly; specialty codes: rarely |
| Loaded into | `stg.kbv_arztgruppenschluessel` → `core.fachgruppe`; `stg.kbv_ebm_xml` → `core.ebm_kapitel`, `core.gop`, `core.orientierungswert` |

## Files

| File | Content |
|---|---|
| `arztgruppenschluessel.csv` | 2-digit Fachgruppe code (= digits 8-9 of the LANR) and its name |
| `ebm_2025.xml` | EBM chapters with their GOPs (points, Prüfzeit, budget flag, QS area) and the Orientierungswert (EUR per point) |

## Known quirks

- XML booleans are German words: `extrabudgetaer="ja"` / `"nein"`.
- Attributes are **omitted** when there is no value (`pruefzeit_min`, `qs_bereich`) - XQuery then returns NULL.
- Chapter titles are attributes of `<Kapitel>`, GOP titles are child elements `<Titel>` - two styles in one file.

## Realism note

EBM chapter structure and GOP codes follow the real EBM. **Points, Prüfzeiten and the
selection of GOPs are simplified example values** - verify against the official EBM before
using them for anything real. Grundpauschalen exist per age band (…210 / …211 / …212).
