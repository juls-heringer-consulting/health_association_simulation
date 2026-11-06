# Terminservicestelle (appointment service, 116117)

| | |
|---|---|
| Simulated origin | REST API of the appointment service (eTerminservice / 116117), exported page by page |
| Owner (in the KV) | Versorgungsmanagement / TSS |
| Update frequency | daily incremental pull in reality; here one yearly export (as of 2026-10-31) |
| Loaded into | `stg.tss_anfragen_json` → `core.tss_anfrage` |

## Files

`tss_anfragen_2025_p001.json` … `p015.json` - one API page each (100 requests per page),
with paging metadata (`page`, `pageSize`, `totalItems`, `totalPages`) and an `items` array.

## Known quirks

- Timestamps are **ISO 8601 with UTC offset** (`+01:00` in winter, `+02:00` in summer) → `DATETIMEOFFSET`.
- **`termin` is `null`** when no appointment was arranged.
- The API uses its **own specialty labels** (`fachgebiet: "Augenheilkunde"`), mapped via `core.tss_fachgebiet`.
- The patient is described only by Kreis and age (data minimisation), no identity.
- The `vermittlungscode` (appointment code) also appears in the billing data of the treating practice - the link between the two sources.
