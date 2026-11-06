# BfArM - ICD-10-GM (diagnosis codes)

| | |
|---|---|
| Simulated origin | Code list of the ICD-10-GM published by the BfArM (federal institute for drugs and medical devices) |
| Owner (in the KV) | Abrechnung - catalogue maintenance |
| Update frequency | yearly (new version every 1 January) |
| Loaded into | `stg.bfarm_icd10` → `core.icd10` |

## File

`icd10gm2025_auswahl.txt` - one code per line: `kapitel;code;titel`

## Known quirks

- **No header row** - the column names are defined in the loader (`python/kvsim/sources.py`).
- UTF-8 without BOM, LF line endings.
- Chapters are roman numerals (`IX`).

## Realism note

Real chapter structure; only a **small selection** of ~50 codes, titles simplified.
