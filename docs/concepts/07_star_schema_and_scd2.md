# 07 Star schema and SCD type 2

*Phase 4 (mart). Scripts: `sql/50_mart`, `sql/60_mart_load`.*

## Why another model after a perfect 3NF core?

Core is optimised for **correctness** (no redundancy, constraints). Reporting needs
**simplicity and speed**: "Fallwert per Fachgruppe and quarter" should be one join per
question, not ten. The dimensional model (Ralph Kimball) delivers that.

## Facts and dimensions

- **Fact table**: measurable events with numbers (`anzahl`, `punkte`, `betrag_eur`) and
  foreign keys to dimensions. Long and narrow.
- **Dimension table**: the context - who, what, where, when - with descriptive text.
  Short and wide, deliberately denormalised.

```
                 dim_datum   dim_quartal
                        \     /
   dim_gop -------- fact_leistung -------- dim_arzt (SCD2)
                   /     |      \
          dim_praxis  dim_region  dim_krankenkasse ...
```

The shape gives the name: a **star**.

## Grain: the most important decision

The grain says what ONE fact row means. Mixing grains breaks sums.

| Fact | Grain | Fact type |
|---|---|---|
| `fact_leistung` | one billed GOP line | transaction |
| `fact_abrechnungsfall` | one Behandlungsfall | transaction |
| `fact_honorar_quartal` | one practice in one quarter | periodic snapshot |
| `fact_versorgungsgrad` | area × Arztgruppe × Stichtag | periodic snapshot |
| `fact_tss_anfrage` | one request, with request date AND appointment date | accumulating snapshot |
| `fact_bereitschaftsdienst` | one shift | transaction |

Example of the trap: counting cases from `fact_leistung` with `COUNT(*)` counts *lines*,
not cases. Use `fact_abrechnungsfall` or `COUNT(DISTINCT fallnummer)`.

## Useful patterns used here

| Pattern | Where | Meaning |
|---|---|---|
| **Surrogate keys** | `arzt_key`, `praxis_key` | independent from source keys; allow versions |
| **Unknown member** | key `-1` in every dimension | a fact never needs a NULL foreign key |
| **Smart date key** | `datum_key = 20250331` | readable, sortable, partition-friendly |
| **Conformed dimension** | `dim_altersgruppe` used by billing and TSS | the same meaning in every star → stars can be compared |
| **Role-playing dimension** | `dim_datum` twice in `fact_tss_anfrage` | request date and appointment date |
| **Degenerate dimension** | `fallnummer` in `fact_leistung` | an id without its own dimension table |
| **Rolled-up dimension** | `dim_quartal` | coarser grain of the calendar for quarterly facts |

## Slowly Changing Dimensions (SCD)

What happens to `dim_arzt` when a doctor moves from practice A to practice B in July?

| Type | Behaviour | Consequence |
|---|---|---|
| SCD 0 | never change | wrong for movers |
| SCD 1 | overwrite | all of 2025 suddenly looks like practice B - history rewritten |
| **SCD 2** | **new row (version)** with `valid_from`/`valid_to`/`is_current` | facts until June point to version A, from July to version B |
| SCD 3 | extra column "previous practice" | only one step of history |

```sql
-- doctors with more than one version (they changed practice or employment form)
SELECT arzt_id, lanr, praxis_name, teilnahmeform_code, valid_from, valid_to, is_current
FROM mart.dim_arzt
WHERE arzt_id IN (SELECT arzt_id FROM mart.dim_arzt GROUP BY arzt_id HAVING COUNT(*) > 1)
ORDER BY arzt_id, valid_from;
```

The fact load finds the right version with a **range lookup**:
`l.leistungsdatum >= da.valid_from AND l.leistungsdatum < da.valid_to`.

**How the versions are built here (DD-16)**: core already holds the business history
(`core.teilnahme`), so each Teilnahme becomes one version. The classic approach - compare
today's source with the current dimension row, close it and insert a new one when
something changed - is the right tool when the source has *no* history. It is an exercise
for `dim_praxis` in level 04.

## Try it

```sql
SELECT * FROM mart.v_fallwert_praxis_quartal WHERE arztgruppe = N'Augenärzte' ORDER BY fallwert_eur DESC;
SELECT * FROM mart.v_versorgung_aktuell ORDER BY status, versorgungsgrad_pct;
```
