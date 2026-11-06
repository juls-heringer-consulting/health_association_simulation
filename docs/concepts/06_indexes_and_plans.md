# 06 Indexes and execution plans

*Phase 3/4. Every `CREATE INDEX` in `sql/30_core` and `sql/50_mart` has a comment with its reason.*

## The book analogy

- A **clustered index** is the order of the pages in the book: the table rows themselves are
  stored sorted by its key. One per table. Here: the primary key (e.g. `leistung_id`).
- A **nonclustered index** is the index at the back of the book: a sorted list of a column
  plus a pointer to the row. Many per table.
- **INCLUDE** columns are copied into the index leaf so the query can be answered from the
  index alone ("covering index") without jumping to the table ("key lookup").
- A **filtered index** only contains rows that match a WHERE condition
  (`ix_abrechnungsfall_tss ... WHERE tss_vermittlungscode IS NOT NULL`) - small and precise.

## How the indexes in this project were chosen

| Index | Query it supports |
|---|---|
| PK / UNIQUE constraints | every key lookup and join (they create indexes automatically) |
| `ix_teilnahme_praxis (praxis_id, valid_from) INCLUDE (arzt_id, valid_to, anrechnungsfaktor)` | "which doctors work at practice X" - the UNIQUE (arzt_id, praxis_id, valid_from) only helps searches by doctor |
| `ix_leistung_arzt_datum (arzt_id, leistungsdatum) INCLUDE (gop_id, anzahl)` | time profiles per doctor and day (Plausibilitätsprüfung) |
| `ix_abrechnungsfall_quartal (quartal_code) INCLUDE (...)` | everything per quarter |
| `ix_fact_leistung_quartal_praxis` | Fallwert/Fallzahl per practice and quarter |
| foreign keys | SQL Server does **not** index foreign keys automatically; index those you join or delete by |

Indexes are not free: each one costs space and slows down INSERT/UPDATE. Index for the
queries you actually run.

## SARGable predicates

An index can only be used for seeking if the column is left alone in the WHERE clause
("Search ARGument able"):

```sql
-- NOT sargable: the function must be computed for every row -> scan
SELECT COUNT(*) FROM core.leistung WHERE YEAR(leistungsdatum) = 2025;

-- sargable: a range on the bare column -> index seek possible
SELECT COUNT(*) FROM core.leistung WHERE leistungsdatum >= '2025-01-01' AND leistungsdatum < '2026-01-01';
```

Same with `LEFT(bsnr, 2) = '73'` (scan) vs. `bsnr LIKE '73%'` (seek on `uq_praxis_bsnr`), and
with implicit type conversions (comparing a `CHAR` column with an `NVARCHAR` parameter).

## Reading an execution plan in SSMS

1. Press **Ctrl+M** ("Include Actual Execution Plan"), then run the query.
2. Read the plan **right to left**: data flows from the operators on the right to the result.
3. Look for: *Index Seek* (good, targeted) vs. *Table/Clustered Index Scan* (reads everything);
   *Key Lookup* (missing INCLUDE column); thick arrows (many rows); a green
   "Missing Index" hint (a suggestion, not an order).
4. `SET STATISTICS IO ON;` shows *logical reads* per table - the most honest measure of work.

At 25,000 rows everything is fast; the habits matter for the 100+ million rows of a real KV.
Exercise level 3 walks through this with real queries.

## Columnstore (outlook)

Fact tables at a real KV are huge and mostly read by aggregations. A **clustered columnstore
index** stores data column by column, compressed, and processes it in batches - often 10×
less IO for `SUM ... GROUP BY`. Available in all editions since SQL Server 2016 SP1.
Exercise 04 compares rowstore and columnstore on a copy of `mart.fact_leistung`.
