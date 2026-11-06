# 05 History and time

*Phase 3 (core). Tables: `core.teilnahme`, `core.teilnahme_status`, `core.qs_genehmigung`, `core.zulassungsverfahren_status`.*

## Facts change - and you must still answer questions about the past

"Who worked at practice X on 30 June?", "Did the doctor have the ultrasound permit on the
day he billed it?", "How many Hausärzte did the Landkreis have on the Stichtag?" - all
need history, not just the current state.

## Valid time with half-open intervals

Every changing fact gets a validity interval **[valid_from, valid_to)**:

```
Teilnahme of Dr. A at practice P
 [2008-01-01 ────────── 2025-07-01)   AKTIV ... then
                       [2025-07-01 ────── 9999-12-31)   BEENDET
```

- `valid_from` inclusive, `valid_to` **exclusive**: consecutive periods share the boundary date
  without overlapping.
- `9999-12-31` = open end ("until further notice"). Easier than NULL: no special cases in
  comparisons.
- The **as-of test** is always the same:

```sql
DECLARE @stichtag DATE = '2025-06-30';
SELECT * FROM core.teilnahme
WHERE @stichtag >= valid_from AND @stichtag < valid_to;
```

`core.fn_teilnahme_am(@stichtag)` packages this test (with the status) as an inline table-valued function.

## Two kinds of history

| | Status history | Event history |
|---|---|---|
| Example | `teilnahme_status`: AKTIV → RUHEND → AKTIV → BEENDET | `zulassungsverfahren_status`: EINGANG, IN_PRUEFUNG, ... |
| Source delivers | from/to | only "since" dates |
| Load | copy | derive `valid_to` with **LEAD()** = the next row's `valid_from` |

```sql
-- LEAD looks at the next row of the same procedure
SELECT verfahren_id, status_code, valid_from,
       LEAD(valid_from) OVER (PARTITION BY verfahren_id ORDER BY valid_from) AS naechster_status_ab
FROM core.zulassungsverfahren_status;
```

## Rules a history must follow (and how they are enforced)

| Rule | Enforced by |
|---|---|
| `valid_to > valid_from` | CHECK `ck_teilnahme_interval` |
| at most one open row | filtered UNIQUE index `uq_teilnahme_status_open` |
| no overlaps between a doctor's Teilnahmen | DQ03 (a CHECK cannot compare rows) |
| no gaps in the status history | DQ04 with `LAG()` |

Overlap test for two intervals (used in DQ03): `a.valid_from < b.valid_to AND b.valid_from < a.valid_to`.

## Valid time vs. system time (temporal tables)

SQL Server's **system-versioned temporal tables** (`PERIOD FOR SYSTEM_TIME`) automatically
keep old row versions with the *time of the database change*. That answers "what did the
database say last Tuesday?" (audit), not "who was licensed on 1 April?" - because a
Zulassung is valid from the date the committee decided, independent of when we loaded it.
This project therefore uses explicit business validity columns (DD-05). Both can be
combined: valid time for the business, a temporal table for the audit trail.

## Try it

```sql
-- doctors with a suspended licence (RUHEND) in 2025 and how long it lasted
SELECT a.lanr, a.nachname, s.valid_from, s.valid_to, DATEDIFF(DAY, s.valid_from, s.valid_to) AS tage
FROM core.teilnahme_status AS s
JOIN core.teilnahme AS t ON t.teilnahme_id = s.teilnahme_id
JOIN core.arzt AS a ON a.arzt_id = t.arzt_id
WHERE s.status_code = 'RUHEND';
```
