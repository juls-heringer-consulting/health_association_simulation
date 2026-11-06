# Honorar (fees) and Abschlagszahlungen (advance payments)

| | |
|---|---|
| Simulated origin | Honorarbescheide from the KV fee system (Honorarverteilung); advance payments from the finance system (FiBu) |
| Owner (in the KV) | Honorar / Finanzen |
| Update frequency | Bescheide: once per quarter (about 3-4 months after quarter end); payments: monthly |
| Loaded into | `stg.honorar_bescheide_xml` → `core.honorarbescheid`; `stg.honorar_abschlaege` → `core.abschlagszahlung` |

## Files

| File | Content |
|---|---|
| `honorarbescheide_2025Q1.xml` … `Q4` | one `<Bescheid>` per practice: points (requested, corrected, MGV, EGV), payout quota, amounts, deductions, remaining payment |
| `abschlagszahlungen_2025.csv` | 3 monthly advance payments per practice and quarter |

## Known quirks

- CSV is **cp1252** with **German number format** `1.234,56`.
- The quarter and the payment number exist **only inside the free text** `Verwendungszweck`: `Abschlag 2/3 Quartal 1/2025`.
- Payment dates move to the previous Friday when the 25th is a weekend.
- XML amounts use a decimal point; `quote_mgv` is omitted when a practice has no budgeted points.

## Business logic (simplified)

`Brutto = MGV points × Orientierungswert × Quote + EGV points × Orientierungswert`,
`Auszahlung = Brutto − Verwaltungskosten (2.5 %) − Abschläge` (negative = refund).
GOPs billed without a QS permit are removed (`punkte_berichtigt`).
