# 01 Layers, schemas and ELT

*Phase 0 (setup). Scripts: `sql/00_setup`, `sql/10_meta`.*

## Database, schema, table

- A **database** (`KVSim`) is the unit of backup, restore and recovery model.
- A **schema** (`stg`, `core`, `mart`, `meta`) is a namespace inside the database *and* a
  security boundary. `core.arzt` and `mart.dim_arzt` live in the same database but in
  different schemas with different permissions.
- A **table** belongs to exactly one schema. Always write the schema: `core.arzt`, never
  `arzt` - otherwise SQL Server guesses from the user's default schema.

## Why layers?

Imagine a KV analyst asks: *"Why does the Honorar of practice 73... look wrong?"*

| If it is wrong in ... | ... the cause is |
|---|---|
| `stg` | the source delivered it like that → talk to the source owner |
| `core` but not in `stg` | our load logic → fix `sql/40_core_load` |
| `mart` but not in `core` | the dimensional transformation → fix `sql/60_mart_load` |

Each layer has one responsibility, so errors can be located. Without layers, raw values,
corrected values and report figures end up mixed in one table: the "data swamp".

## ETL vs. ELT

| | ETL (Extract, Transform, Load) | ELT (Extract, Load, Transform) |
|---|---|---|
| Where is data transformed? | in a tool *before* it reaches the database (SSIS, Python, ...) | *inside* the database, after landing it raw |
| This project | - | ✔ Python lands files 1:1 into `stg`; T-SQL procedures transform |
| Pro | heavy work outside the DB | logic in SQL, visible and testable; raw data kept for audits |
| Con | logic hidden in another tool | the database does the work |

Many KVs use SSIS (SQL Server Integration Services) - conceptually the same steps.

## Re-runnable scripts

Every script can be run again without errors and without duplicating data:

| Technique | Used for | Example |
|---|---|---|
| `IF DB_ID(...) IS NULL CREATE DATABASE` | objects that must keep their data | `001_create_database.sql`, `meta` tables |
| `CREATE OR ALTER PROCEDURE/VIEW/FUNCTION` | code | all procedures |
| drop + create | tables whose data can be rebuilt | `meta.usp_drop_tables N'core'` in `300_drop_core_tables.sql` |
| idempotent load logic | data | upsert, delete-and-reload per quarter |

## The load log (`meta`)

```sql
SELECT * FROM meta.load_batch ORDER BY batch_id DESC;            -- one row per load run
SELECT * FROM meta.load_file WHERE batch_id = 3;                  -- which file, how many rows, SHA-256
SELECT * FROM meta.load_step WHERE batch_id = 3 ORDER BY step_id; -- every procedure with duration and status
```

A failed run stays visible (`status = 'FAILED'` and an error message): the log is how a
data warehouse team proves what happened.

## Try it

1. In SSMS, Object Explorer → KVSim → Security → Schemas: find the four schemas.
2. Run `SELECT SCHEMA_NAME(schema_id) AS s, COUNT(*) AS tables FROM sys.tables GROUP BY schema_id;`
3. Run `EXEC core.usp_load_all;` twice and compare row counts - nothing doubles.
