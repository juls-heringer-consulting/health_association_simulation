# Design decisions

A short log in the style of "architecture decision records": what was decided, why, and
what the alternatives were. Numbers (DD-xx) are referenced from SQL comments.

---

### DD-01 Layered architecture: `stg` → `core` → `mart`, plus `meta`

**Decision:** one database, one schema per layer.
**Why:** each layer has one job: land the data unchanged, integrate it, present it. Problems
can be located by layer (wrong in stg = source problem; wrong in core = load logic).
Schemas are also security boundaries (DD-17).
**Alternatives:** one database per layer (more isolation, more cross-database joins);
everything in `dbo` (the "data swamp" this project wants to avoid).

### DD-02 ELT: Python only lands files, T-SQL transforms

**Decision:** Python parses files physically and inserts them 1:1 into `stg`; all business
rules are T-SQL stored procedures.
**Why:** one language for business logic, visible and testable in SSMS. `BULK INSERT` /
`OPENROWSET` would need the SQL Server service account to read the user's folder and do
not read Excel or nested JSON pages comfortably.
**Alternative:** SSIS or Azure Data Factory - common at KVs, more tooling than needed here.

### DD-03 Key policy

**Decision:**
- *Entities with a lifecycle* (arzt, praxis, teilnahme, krankenkasse, gop, icd10, verfahren, fall, dokument):
  surrogate key `<table>_id INT IDENTITY` as primary key **plus** a `UNIQUE` constraint on
  the business key (LANR, BSNR, IK, GOP code, Aktenzeichen, ...).
- *Small code lists we control* (kassenart, altersgruppe, quartal, kooperationsform, ...):
  the code itself is the primary key.
- *Association / measurement tables* (teilnahme_status, einwohner, versorgungsgrad,
  verordnung, ...): composite primary key of their parts.
- *Mart:* `<dim>_key` surrogate keys, `-1` = unknown member, `datum_key` = yyyymmdd.

**Why:** business keys change or get reused (Kassen merge and get new IKs; catalogues are
versioned; a LANR suffix changes with the Fachgruppe). Joins on a small integer are cheap
and stable. The UNIQUE constraint still prevents duplicates of the business key - a
surrogate key alone would not.

### DD-04 Identifiers are CHAR, not numbers

LANR, BSNR, IK, AGS, GOP codes are stored as `CHAR(n)` with a `LIKE '[0-9]...'` CHECK.
They have leading zeros and check digits, and nobody calculates with them.

### DD-05 History as valid time with half-open intervals

**Decision:** changing facts get `valid_from` (inclusive) and `valid_to` (exclusive);
`9999-12-31` = open. "At most one open row" is enforced by a filtered unique index;
gaps/overlaps are checked by DQ03/DQ04.
**Why:** half-open intervals let consecutive periods touch (`valid_to` of one =
`valid_from` of the next) without overlap, and the as-of test is always
`@d >= valid_from AND @d < valid_to`.
**Why not SQL Server temporal tables?** System-versioned temporal tables record *when the
database row changed* (system time). A Zulassung is valid from the date the committee
decided (business/valid time), which may be weeks before or after the data arrived. SQL
Server has no built-in application-time; explicit columns are the standard solution.

### DD-06 Deliberate denormalisation: points snapshot in `core.leistung`

`leistung.punktzahl` copies `gop.punktzahl` at load time. It is a historical fact ("valued
with 150 points when billed"), not a duplicate of the current catalogue value.

### DD-07 3NF in core, denormalised dimensions in mart

Core avoids redundancy (e.g. the EBM chapter title lives only in `ebm_kapitel`, list cells
like `"01, 03"` are split into rows). Mart dimensions repeat descriptive text on purpose
(`dim_fachgruppe` contains the Arztgruppe name) to make queries simple and fast.

### DD-08 Unstructured text: one document table + link table with an exclusive arc

**Decision:** `core.dokument` stores the full text (`NVARCHAR(MAX)`) and searchable metadata;
`core.dokument_bezug` links each document to exactly one of arzt / praxis / verfahren per
row (CHECK constraint "exactly one is set"), each with a real foreign key.
**Alternatives:** a generic `(entity_type, entity_id)` pair - flexible, but no foreign key
is possible, so links can dangle; separate link tables per target - also good, more tables.
Files themselves could be stored as `VARBINARY(MAX)` / FILESTREAM; here the text suffices.

### DD-09 Staging is all text, with lineage and a schema-drift check

A file with an invalid date must still land so that it can be inspected and reported.
Every row knows its batch, file and line. The loader compares the file header with the
staging columns and fails loudly on added, missing or renamed columns.

### DD-10 Load strategies per kind of data

| Data | Strategy | Reason |
|---|---|---|
| master data (arzt, praxis, ...) | upsert by business key, never delete | a register never forgets; endings are expressed by validity |
| histories delivered complete (status) | replace the history of the delivered parents | simple, consistent |
| transaction data (billing per quarter) | delete + reload the delivered quarters | quarters are delivered complete; idempotent |
| full snapshots (QS permits, CME points) | replace all - but only if the delivery is not empty | protection against wiping data with an empty file |
| mart facts | full rebuild | seconds at this volume; simplest correct choice |

### DD-11 `UPDATE` + `INSERT` instead of `MERGE`

MERGE has a long history of edge-case bugs and concurrency pitfalls; two plain statements
are easier to read and debug. Change detection uses
`EXISTS (SELECT new... EXCEPT SELECT old...)`, which handles NULLs correctly.

### DD-12 Descriptions live in the database

Table/column descriptions are `MS_Description` extended properties
(`meta.usp_describe`), exposed by `meta.v_data_dictionary` and exported to Markdown.
The dictionary cannot drift away from the schema, and SSMS shows the descriptions.

### DD-13 Naming: German business terms, English technical terms

See [naming_conventions.md](naming_conventions.md). German domain nouns have no exact English
equivalent (Betriebsstätte ≠ practice) and are what colleagues at a KV say.

### DD-14 Store the officially decided Versorgungsgrad

`soll_aerzte` and `versorgungsgrad_pct` could be computed. They are stored because the
*decided* figure is a legal fact of its own; a recomputation is used as reconciliation (DQ11).

### DD-15 Pseudonymisation and data minimisation

Patients only appear as salted SHA-256 pseudonyms; the year of birth is used once to
derive the age group and then dropped; complaints are anonymised. See concept note 02.

### DD-16 SCD2 built from valid-time history

`mart.dim_arzt` gets one version per Teilnahme. Because core already keeps the history
with business dates, the dimension can be rebuilt with correct past versions at any time.
The classic snapshot-comparison SCD2 (close the current row, insert a new one when an
attribute changes) is an exercise for `dim_praxis`.

### DD-17 Security by roles and schemas

Permissions go to roles, not users; `stg` is only visible to the ETL role; departments get
exactly their tables or role-specific views. See [security.md](security.md).

### DD-18 Lookup table or CHECK constraint?

Lookup table when the code has descriptive attributes or is reused (kassenart, qs_bereich).
CHECK constraint for small, fixed status sets that only one table uses (status codes,
geschlecht).

### DD-19 Reject files on failed control totals

The fixed-width prescription file has a trailer with record count and amount sum. If they
do not match, the whole file is rejected (THROW): partial data is worse than no data.

### DD-20 Portability

Scripts use features available in SQL Server 2019 and later (no 2025-only syntax), because
a KV may run an older version. Database files use the instance defaults.
