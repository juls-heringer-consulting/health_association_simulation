# Zulassungsausschuss (licensing committee)

| | |
|---|---|
| Simulated origin | Case management of the office (Geschäftsstelle) of the Zulassungsausschuss für Ärzte und Psychotherapeuten |
| Owner (in the KV) | Geschäftsstelle Zulassungsausschuss |
| Update frequency | XML: year-end export (as of 2026-01-05); minutes: one file per monthly session |
| Loaded into | `stg.zulassung_verfahren_xml` → `core.zulassungsverfahren`, `core.zulassungsverfahren_status`, `core.dokument` (Bescheide); `stg.zulassung_protokolle` → `core.dokument` (Protokolle) |

## Files

| File | Content |
|---|---|
| `zulassungsverfahren_2025.xml` | All procedures (Neuzulassung, Nachbesetzung, Anstellung, Ruhen, Verzicht) with status history and the text of the Bescheid (formal notice) |
| `protokolle/ZA-Sitzung_<date>.md` | Minutes (Niederschrift) of each session, Markdown with YAML-style front matter |

## Known quirks

- Status history only has **start dates** (`<Status code="..." ab="..."/>`); end dates must be derived (LEAD()).
- Optional elements (`Betriebsstaette`, `Sitzung`, `Bescheid`) are missing when not applicable.
- The Bescheid is **free text inside the XML** - structured and unstructured data in one file.
- Minutes link to procedures only through the **Aktenzeichen mentioned in the text** (e.g. `ZA-2025-0007`).
- Aktenzeichen carry the year of the application, so some procedures decided in 2025 have `ZA-2024-...`.

## Realism note

Sessions on the 3rd Wednesday of each month (assumption). All persons synthetic.
