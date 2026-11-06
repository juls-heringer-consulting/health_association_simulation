# Mitgliederservice (member service CRM)

| | |
|---|---|
| Simulated origin | Ticket export of the CRM used by the member service (questions from doctors and practices) |
| Owner (in the KV) | Mitgliederservice / Beratung |
| Update frequency | daily (here: one yearly export) |
| Loaded into | `stg.mitgliederservice_anfragen_json` → `core.dokument` (type ANFRAGE) + `core.dokument_bezug` |

## File

`anfragen_2025.json` - `{ "exportedAt": ..., "tickets": [ ... ] }`, each ticket with
`ticketId`, `createdAt`, `channel`, `topic`, `requester {lanr, bsnr}`, `subject`, `body`,
`status`, `closedAt`.

## Known quirks

- Free text (`body`) contains line breaks and umlauts; JSON escapes them.
- `closedAt` is `null` for open tickets.
- The link to doctor and practice is **structured** (`requester`) - the easy case of linking text.
