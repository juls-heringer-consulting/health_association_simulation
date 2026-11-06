# 09 Data quality and security

*Phase 5. Scripts: `sql/70_quality`, `sql/80_security`. Reports: [data_quality_report.md](../data_quality_report.md), [security.md](../security.md).*

## Data quality is measured, not hoped for

A data-quality **rule** is a query that counts rows violating an expectation. A **run**
executes all rules and stores the counts with a timestamp, so quality becomes visible over
time (`meta.dq_run`, `meta.dq_result`).

| Category | Question | Example in this project |
|---|---|---|
| Validity | Is the value well-formed? | LANR check digit (DQ01) |
| Consistency | Do rows contradict each other? | overlapping Teilnahmen (DQ03), appointment before request (DQ16) |
| Completeness | Did anything get lost? | rows in stg but not in core (DQ07) |
| Reconciliation | Do independent sources agree? | Bescheid points vs. billing lines (DQ09) |
| Business rule | Is there something a department must act on? | GOP billed without permit (DQ12) |

Two different reactions:
- **Constraints** (PK, FK, CHECK) *block* bad data at load time - for rules that must never be broken.
- **DQ rules** *report* - for rules that need cross-table logic, or where the data must still
  be loaded (a finding is information, not garbage).

**Reconciliation** is the strongest test: two systems built by different people agree only
if both are right. DQ13 is a nice example: our own check of QS permits (DQ12) and the KV's
correction in the Honorarbescheid arrive at the same points.

## Security in a nutshell

| Concept | Meaning | Here |
|---|---|---|
| Principal | who: login (server), user (database), role | `u_controlling`, `rl_controlling` |
| Securable | what: schema, table, view, column, procedure | `SCHEMA::mart`, `mart.dim_arzt (arzt_name)` |
| Permission | how: SELECT, INSERT, EXECUTE, ... | `GRANT SELECT ON SCHEMA::mart TO rl_controlling` |
| GRANT / DENY / REVOKE | allow / forbid (DENY wins) / remove an entry | `DENY SELECT ON mart.dim_arzt (arzt_name)` |
| Ownership chaining | views/procedures of the same owner skip permission checks on underlying tables | why `v_plausi_tagesprofil` is denied too |
| Impersonation | `EXECUTE AS USER = '...'` ... `REVERT` | test what a role can see |

## Try it

```sql
EXEC meta.usp_run_dq_checks;
SELECT * FROM meta.v_dq_latest WHERE result = 'FAIL';

EXECUTE AS USER = 'u_zulassung';
SELECT * FROM fn_my_permissions('core.versorgungsgrad', 'OBJECT');
SELECT TOP 1 * FROM core.leistung;   -- denied
REVERT;
```
