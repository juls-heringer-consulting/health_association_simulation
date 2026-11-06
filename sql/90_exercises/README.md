# SQL exercise path

Realistic analysis tasks from a Kassenärztliche Vereinigung (KV), from your first `SELECT` to modelling and performance work. Each task describes which department asks, what it needs, hints and the expected result shape.

## How to work through it

1. Make sure the database is built: `tools/run_all.ps1` (or the manual steps in the root README).
2. Open an exercise file in SSMS and write your query in the empty space below a task.
3. Compare your result with the "Expected" line: row count, columns, a key number.
4. Only then open the same file in `sql/91_solutions/`. The solutions explain *why*, show pitfalls and often an alternative approach. Your query does not have to look the same. If it returns the same result for the right reasons, it is correct.
5. Stuck for more than 20 minutes? Read the hints again, look at the tables with `SELECT TOP (20) * FROM ...`, check the data dictionary (`docs/data_dictionary.md`), and only then peek at the solution.

| Level | File | Concepts | Tasks |
|---|---|---|---|
| 1 Basics | `01_basics.sql` | SELECT, WHERE, ORDER BY, INNER/LEFT JOIN, GROUP BY, HAVING, percentages | 8 |
| 2 Intermediate | `02_intermediate.sql` | CTEs, subqueries, CASE, window functions (LAG, SUM/AVG OVER, DENSE_RANK, PERCENTILE_CONT), running totals | 8 |
| 3 Advanced | `03_advanced.sql` | as-of queries with validity intervals, NOT EXISTS, reconciliation, gaps & islands, SARGability, indexes, execution plans, recursive CTEs, spatial data | 8 |
| 4 Modelling & performance | `04_modeling_performance.sql` | model extensions, key design, SCD2, columnstore, incremental loads, transactions, Row-Level Security | 6 |

Level 1 mostly uses the normalised `core` schema, so you learn the joins. Level 2 mostly uses the `mart` star schemas, so you can compare how much simpler analytical queries become there.

## Rules that save you a lot of debugging

- **Validity intervals are half-open:** `valid_from` is inclusive, `valid_to` is exclusive, and `9999-12-31` means "open". "Valid on day D" is `D >= valid_from AND D < valid_to`. Do not use `BETWEEN`.
- **Integer division:** `7 / 2` is `3` in SQL Server. Write `100.0 * a / b`.
- **NULL:** `NULL = NULL` is not true. Use `IS NULL`, `COALESCE`, and `EXISTS (... EXCEPT ...)` for NULL-safe comparisons.
- **LEFT JOIN:** a condition on the right table belongs in `ON`. In `WHERE` it turns the LEFT JOIN into an INNER JOIN.
- **The billing data is a sample:** about 3 cases per doctor and quarter. Ratios (Fallwert, shares, ranks) are meaningful; absolute EUR amounts and hours are not.
- **Leave the database as you found it:** wrap experiments in `BEGIN TRANSACTION ... ROLLBACK`, use `#temp` tables, or drop what you created.

## SSMS tips

| Shortcut | What it does |
|---|---|
| F5 / Ctrl+E | Execute. If text is selected, **only the selection** runs. |
| Ctrl+M | Include the **actual execution plan** (toggle, then execute) |
| Ctrl+L | Show the estimated plan without running the query |
| Ctrl+K, Ctrl+C / Ctrl+K, Ctrl+U | Comment / uncomment the selected lines |
| Ctrl+R | Show / hide the results pane |
| Ctrl+Shift+R | Refresh IntelliSense after you created new objects |
| Alt+F1 on a selected table name | `sp_help`: columns, keys, indexes of that table |

- **Read I/O cost:** run `SET STATISTICS IO, TIME ON;` before a query. The "Messages" tab then shows logical reads, the main number to compare.
- **Use the views:** `core.v_teilnahme_aktuell`, `mart.v_fallwert_praxis_quartal`, `mart.v_versorgung_aktuell` and `mart.v_plausi_tagesprofil` are good starting points.
