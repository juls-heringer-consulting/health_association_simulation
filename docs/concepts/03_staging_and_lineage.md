# 03 Staging and lineage

*Phase 2 (staging). Scripts: `sql/20_stg`, `python/kvsim/loader.py`, `python/kvsim/sources.py`.*

## What staging is for

Staging is the **landing zone**: an exact copy of what the source delivered, before any
interpretation. Rules in this project:

1. One table per source file type (`stg.abrechnung_leistungen` ← `leistungen_*.csv`).
2. Column names = header names of the file.
3. All business columns are `NVARCHAR`: no conversion, no constraints.
4. XML lands as one row per file in an `XML` column, JSON/text in `NVARCHAR(MAX)`.
5. Every row carries lineage: `load_batch_id`, `source_file`, `source_row_nr`, `loaded_at`.

Why "everything is text"? If a date column were `DATE`, a single wrong value (`31.02.2025`)
would make the whole file fail to load, and you could not even look at the problem. In
staging the file *always* lands; conversion happens in core with `TRY_CONVERT`, and bad
values become visible (NULL → caught by NOT NULL constraints or DQ rules).

## Lineage: where does this value come from?

```sql
-- which file and line did billing line X come from?
SELECT s.source_file, s.source_row_nr, s.*
FROM stg.abrechnung_leistungen AS s
WHERE s.fallnummer = 'F2025Q1-000001';

-- which files were part of batch 3, and were they ever changed? (compare SHA-256 between batches)
SELECT file_name, rows_loaded, file_sha256 FROM meta.load_file WHERE batch_id = 3 ORDER BY file_name;
```

Every core table also has `load_batch_id`: the batch that last wrote the row.

## Schema drift

Sources change without asking. The loader compares the header of every file with the
columns of its staging table and stops with a clear message if they differ:

```
Schema drift in arztregister/aerzte.csv -> stg.arztregister_aerzte
  missing in file : ['efn']
  unexpected      : ['einheitliche_fortbildungsnummer']
```

Failing loudly is better than silently loading `NULL` into a column.

## Control totals

The prescription file ends with a trailer `TR` containing the number of data records and
the sum of all amounts. `core.usp_load_qs_pruefung_verordnung` recomputes both and rejects
the **whole file** if they differ - an incomplete file transfer must not produce half the
data. Mainframe interfaces at KVs and Kassen use this pattern a lot.

## Batches and idempotency

`meta.load_batch` gives every run an id. The loader truncates each staging table before
loading it, so staging always holds exactly one delivery. Core procedures default to the
newest successful batch (`meta.fn_latest_batch_id()`).

## Try it

1. Open `data/sources/statistik/bevoelkerung_kreise_2024.csv` in a text editor: find the
   header lines the loader skips.
2. `SELECT TOP 20 zeile FROM stg.verordnung_zeilen ORDER BY source_row_nr;` - and decode
   one `VO` record by hand using the layout in `data/sources/verordnungen/README.md`.
3. `SELECT content FROM stg.kbv_ebm_xml;` - click the XML link in SSMS to open it.
