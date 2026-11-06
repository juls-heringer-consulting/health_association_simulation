# SQL scripts

All scripts are T-SQL for SQL Server (2019 or later), runnable in SSMS (open → F5) or with
`sqlcmd`. They are numbered: run folders and files **in ascending order**.

| Folder | Content | Re-run behaviour |
|---|---|---|
| `00_setup` | database `KVSim`, schemas | safe, never drops |
| `10_meta` | load log, DQ tables, helper procedures, data-dictionary view | tables kept (history survives), code replaced |
| `20_stg` | staging tables | **drops and recreates** all `stg` tables |
| `30_core` | core tables, constraints, indexes, functions, views, descriptions | `300` **drops all core tables** → run 300-309 as a block |
| `40_core_load` | stg → core load procedures | code only (`CREATE OR ALTER`) |
| `50_mart` | dimensions, facts, views, descriptions | `500` **drops all mart tables** → run 500-509 as a block |
| `60_mart_load` | core → mart load procedures | code only |
| `70_quality` | DQ rule catalogue + `meta.usp_run_dq_checks` | safe |
| `80_security` | roles, permissions, test users | safe; run again after 50_mart (object grants are lost when tables are dropped) |
| `85_fulltext` | optional full-text index | skips itself if the feature is missing |
| `90_exercises` | exercise path (try first!) | read-only |
| `91_solutions` | solutions | read-only or clean up after themselves |

## Order of a complete build

```text
00 → 10 → 20 → 30 → 40 → 50 → 60 → 70 → 80 → 85      (create objects)
python\load_staging.py                                (fill stg)
EXEC core.usp_load_all;                               (stg → core)
EXEC mart.usp_load_all;                               (core → mart)
EXEC meta.usp_run_dq_checks;                          (data quality)
```

`tools\run_all.ps1` does exactly this (plus generating the source files).

All `.sql` files are saved as **UTF-8 with BOM** (byte order mark), so SSMS reads German
umlauts in literals such as `N'männlich'` correctly. Keep it that way when you save files.

## sqlcmd flags used

`sqlcmd -S localhost -E -C -b -I -f 65001 -i <file>`: Windows authentication (`-E`), trust the
local self-signed certificate (`-C`), stop on error (`-b`), QUOTED_IDENTIFIER on (`-I`, needed
for filtered indexes and XML methods), read files as UTF-8 (`-f 65001`).
