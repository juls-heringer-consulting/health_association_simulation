"""Export the data dictionary (meta.v_data_dictionary) to docs/data_dictionary.md.

The database is the single source of truth: descriptions live as MS_Description
extended properties on tables and columns (see sql/30_core/309_descriptions.sql).

Usage (from the project root):
    .venv\\Scripts\\python.exe python\\export_data_dictionary.py
"""
from __future__ import annotations

import sys
from itertools import groupby

import pyodbc

from kvsim.config import DOCS_DIR, load_settings

SCHEMA_ORDER = {"core": 1, "mart": 2, "meta": 3, "stg": 4}
SCHEMA_TITLE = {
    "core": "core - integrated, normalised model",
    "mart": "mart - star schemas for reporting",
    "meta": "meta - load log, data quality",
    "stg": "stg - staging (1:1 copies of the source files)",
}


def md(text: str | None) -> str:
    return (text or "").replace("|", "\\|").replace("\n", " ")


def main() -> int:
    settings = load_settings()
    with pyodbc.connect(settings.connection_string()) as conn:
        rows = conn.cursor().execute(
            "SELECT schema_name, table_name, table_description, column_id, column_name, data_type, "
            "is_nullable, is_identity, is_primary_key, references_table, column_description "
            "FROM meta.v_data_dictionary").fetchall()
    rows.sort(key=lambda r: (SCHEMA_ORDER.get(r.schema_name, 9), r.table_name, r.column_id))

    out = [
        "# Data dictionary",
        "",
        "> Generated from the database by `python/export_data_dictionary.py` (view `meta.v_data_dictionary`).",
        "> Do not edit by hand: change the descriptions in the SQL scripts (`meta.usp_describe`) and re-export.",
        "",
    ]
    for schema, schema_rows in groupby(rows, key=lambda r: r.schema_name):
        schema_rows = list(schema_rows)
        out += [f"## {SCHEMA_TITLE.get(schema, schema)}", ""]
        tables = [(t, list(cols)) for t, cols in groupby(schema_rows, key=lambda r: r.table_name)]
        if schema == "stg":
            out += ["| Table | Source |", "|---|---|"]
            out += [f"| `stg.{t}` | {md(cols[0].table_description)} |" for t, cols in tables]
            out.append("")
            continue
        for table, cols in tables:
            out += [f"### `{schema}.{table}`", "", md(cols[0].table_description) or "_(no description)_", "",
                    "| Column | Type | Null | Key | Description |", "|---|---|---|---|---|"]
            for c in cols:
                key = []
                if c.is_primary_key:
                    key.append("PK")
                if c.is_identity:
                    key.append("identity")
                if c.references_table:
                    key.append(f"FK -> `{c.references_table}`")
                out.append(f"| `{c.column_name}` | {c.data_type} | {'yes' if c.is_nullable else 'no'} | "
                           f"{', '.join(key)} | {md(c.column_description)} |")
            out.append("")
    target = DOCS_DIR / "data_dictionary.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"Written {target} ({len(rows)} columns).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
