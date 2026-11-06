# Naming conventions

Consistency matters more than any single rule. These rules are applied everywhere.

## General

- **lower_snake_case** for all objects and columns; no spaces, no quoted identifiers.
- **Umlauts transliterated**: ä → ae, ö → oe, ü → ue, ß → ss (`betriebsstaette`, `pruefzeit_min`).
- **Singular** table names: `core.arzt`, not `core.aerzte`.
- **German** for business terms (`teilnahme`, `versorgungsgrad`), **English** for technical
  terms and framework columns (`valid_from`, `load_batch_id`, `is_current`, `meta.load_step`).
- The `meta` schema is purely technical and therefore English throughout.

## Schemas

| Schema | Content |
|---|---|
| `stg` | `<source system>_<content>`, e.g. `stg.arztregister_aerzte`, `stg.honorar_bescheide_xml` |
| `core` | entity names, e.g. `core.praxis`; histories `<entity>_status`; link tables `<a>_<b>` |
| `mart` | `dim_<name>`, `fact_<name>`, views `v_<name>` |
| `meta` | technical: `load_batch`, `dq_rule`, ... |

## Columns

| Pattern | Meaning | Example |
|---|---|---|
| `<table>_id` | surrogate key in core (INT IDENTITY) | `arzt_id` |
| `<name>_code` | code of a lookup table (natural key) | `kassenart_code` |
| `<name>_key` | surrogate key of a mart dimension | `arzt_key` |
| `valid_from` / `valid_to` | validity interval, `[from, to)`, open end `9999-12-31` | `teilnahme.valid_to` |
| `ist_<adjective>` / `is_current` | BIT flags (German business flag / English technical flag) | `ist_extrabudgetaer` |
| `anzahl_<x>`, `<x>_betrag`, `<x>_pct` | counts, amounts (DECIMAL), percentages | `anzahl_verordnungen` |
| `<x>_datum`, `<x>_zeitpunkt` | DATE / DATETIME(OFFSET) | `leistungsdatum`, `eingang_zeitpunkt` |
| `load_batch_id`, `loaded_at` | technical lineage columns (every core table) | |
| `source_file`, `source_row_nr` | staging lineage | |

## Constraints and indexes

| Prefix | Object | Example |
|---|---|---|
| `pk_` | primary key | `pk_arzt` |
| `fk_<child>_<parent>[_role]` | foreign key | `fk_teilnahme_arzt`, `fk_bereitschaftsdienst_arzt_getauscht` |
| `uq_<table>_<columns>` | unique constraint / unique index | `uq_arzt_lanr` |
| `ck_<table>_<rule>` | check constraint | `ck_arzt_lanr_fachgruppe` |
| `df_<table>_<column>` | default constraint | `df_arzt_loaded_at` |
| `ix_<table>_<columns>` | non-unique index | `ix_leistung_arzt_datum` |

Always name constraints explicitly: system-generated names (`PK__arzt__3213E83F...`) differ
on every server and make scripts impossible to compare.

## Procedures, functions, views

| Pattern | Example |
|---|---|
| `usp_<verb>_<object>` stored procedure | `core.usp_load_arztregister`, `meta.usp_run_dq_checks` |
| `fn_<name>` function | `core.fn_lanr_pruefziffer`, `core.fn_teilnahme_am` |
| `v_<name>` view | `mart.v_fallwert_praxis_quartal` |
| roles `rl_<department>`, test users `u_<department>` | `rl_zulassung`, `u_controlling` |

## SQL style (in all scripts)

- Schema-qualify every object (`core.arzt`, never just `arzt`).
- Table aliases with `AS`, short and meaningful (`a` for arzt, `p` for praxis).
- Keywords in UPPER CASE, one clause per line for longer queries.
- Comments explain *why*, not *what*.
- Every script is re-runnable (`CREATE OR ALTER`, `IF ... IS NULL`, `DROP ... IF EXISTS`).
