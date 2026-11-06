# Security sketch: who in a KV may see what

Implemented in [`sql/80_security/801_roles_and_permissions.sql`](../sql/80_security/801_roles_and_permissions.sql).
It is a sketch for learning, not a production concept (that would be designed together with
the data protection officer and IT security).

## Principles

1. **Least privilege**: each role gets exactly what its department needs.
2. **Roles, not users**: permissions are granted to database roles; people (Windows/AD
   groups in reality) become members of roles.
3. **Schemas as boundaries**: `GRANT SELECT ON SCHEMA::mart` covers all present and future
   objects of the schema. `stg` is visible only to the ETL role (raw, unvalidated data).
4. **Views as filters**: a role that may only see some rows of a table gets a view
   (`core.v_dokument_zulassung` only shows minutes and notices).
5. **Data minimisation first**: what is not stored (names of patients, birth dates, insurance
   numbers) cannot leak. See [assumptions.md](assumptions.md) A-40.

## Role matrix

| Role | stg | core | mart | meta | Notes |
|---|---|---|---|---|---|
| `rl_etl` | full | full | full | read/write, execute | technical account of the load process |
| `rl_abrechnung` | - | billing, catalogues, register (read) | all | - | sees pseudonyms (needed for case checks) |
| `rl_pruefwesen` | - | billing + prescriptions + audits + QS + CME | all | - | audits need case-level detail |
| `rl_zulassung` | - | register, planning, procedures; documents via `v_dokument_zulassung` | Versorgungsgrad star | - | **no billing data** |
| `rl_versorgung` | - | TSS, out-of-hours, register basics | TSS and out-of-hours stars | - | |
| `rl_mitgliederservice` | - | enquiries/complaints via `v_dokument_mitgliederservice`, arzt, praxis | - | - | |
| `rl_controlling` | - | - | all, **except** `dim_arzt.arzt_name` and `v_plausi_tagesprofil` | - | aggregated reporting only |

## Try it in SSMS

The script creates three users **without login** (`u_abrechnung`, `u_zulassung`,
`u_controlling`). You can impersonate them:

```sql
EXECUTE AS USER = 'u_controlling';
SELECT TOP 5 lanr, fachgruppe FROM mart.dim_arzt;   -- works
SELECT TOP 5 arzt_name FROM mart.dim_arzt;          -- error 230: column permission denied
REVERT;
```

## A trap worth knowing: ownership chaining

When a view and its tables have the same owner (here: `dbo`), SQL Server does **not**
check permissions on the tables again when the view is used. A column DENY on
`mart.dim_arzt.arzt_name` would therefore be bypassed by any view that returns that column.
That is why `rl_controlling` is also denied `mart.v_plausi_tagesprofil`. Rule of thumb:
whenever you restrict a column, check every view that exposes it.

## Next steps (not implemented yet)

- **Row-level security** (`CREATE SECURITY POLICY`): e.g. a Bezirksstelle (regional office)
  sees only practices in its Kreise. Sketched in exercise 04.
- **Dynamic data masking** for names in non-production copies.
- **Auditing** (SQL Server Audit) of who read which sensitive table.
- **Encryption**: TDE for data at rest, Always Encrypted for especially sensitive columns.
- Mapping real AD groups to the roles; separate service account for ETL.
