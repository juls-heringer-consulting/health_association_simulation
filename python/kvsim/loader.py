"""Generic staging loader: reads every registered source file and inserts it 1:1 into stg.

Principles:
  * no business transformation here (that is done in T-SQL) - only physical parsing
  * empty fields become NULL
  * the column list of every file is checked against the stg table ("schema drift" check):
    if a source adds, removes or renames a column, the load fails loudly instead of
    silently loading wrong data
  * every file is logged in meta.load_file with row count and SHA-256 fingerprint
"""
from __future__ import annotations

import csv
import hashlib
import re
from datetime import date, datetime
from pathlib import Path

import pyodbc
from openpyxl import load_workbook

from .sources import SOURCES, Source

METADATA_COLUMNS = {"load_batch_id", "source_file", "source_row_nr", "loaded_at"}
_UMLAUTS = str.maketrans({"ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss", "Ä": "ae", "Ö": "oe", "Ü": "ue"})


def sanitize(header: str) -> str:
    """'Kreis_AGS' -> 'kreis_ags', 'Verhältniszahl' -> 'verhaeltniszahl'."""
    name = header.strip().translate(_UMLAUTS).lower()
    return re.sub(r"[^a-z0-9]+", "_", name).strip("_")


def sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ------------------------------------------------------------------ readers
def read_csv(path: Path, src: Source) -> tuple[list[str], list[tuple[int, list[str | None]]]]:
    lines = path.read_text(encoding=src.encoding).splitlines()
    first_line_no = src.skip_lines + 1
    lines = lines[src.skip_lines:]
    if src.stop_at_blank:
        lines = lines[:lines.index("")] if "" in lines else lines
    reader = csv.reader(lines, delimiter=";")
    if src.has_header:
        header = [sanitize(h) for h in next(reader)]
        offset = first_line_no + 1
    else:
        header = list(src.columns)
        offset = first_line_no
    rows = []
    for i, row in enumerate(reader):
        if not any(cell.strip() for cell in row):
            continue
        rows.append((offset + i, [cell if cell != "" else None for cell in row]))
    return header, rows


def _cell_to_text(value) -> str | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date().isoformat() if value.time() == datetime.min.time() else value.isoformat()
    if isinstance(value, date):
        return value.isoformat()
    return str(value)


def read_xlsx(path: Path, src: Source) -> tuple[list[str], list[tuple[int, list[str | None]]]]:
    wb = load_workbook(path, read_only=True, data_only=True)
    try:
        ws = wb[src.sheet]
        header, rows = None, []
        for row_nr, values in enumerate(ws.iter_rows(min_row=src.header_row, values_only=True), start=src.header_row):
            if header is None:
                header = [sanitize(str(v)) for v in values if v is not None]
                continue
            cells = [_cell_to_text(v) for v in values[:len(header)]]
            if any(c is not None for c in cells):
                rows.append((row_nr, cells))
        return header or [], rows
    finally:
        wb.close()


def read_lines(path: Path, src: Source) -> tuple[list[str], list[tuple[int, list[str | None]]]]:
    lines = path.read_text(encoding=src.encoding).splitlines()
    return ["zeile"], [(i, [line]) for i, line in enumerate(lines, 1) if line.strip()]


# ------------------------------------------------------------------ loader
class StagingLoader:
    def __init__(self, conn: pyodbc.Connection, sources_dir: Path):
        self.conn = conn
        self.sources_dir = sources_dir

    def stg_columns(self, table: str) -> list[str]:
        schema, name = table.split(".")
        cur = self.conn.cursor()
        cur.execute(
            "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS "
            "WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION", schema, name)
        return [r[0] for r in cur.fetchall() if r[0] not in METADATA_COLUMNS]

    def start_batch(self, note: str) -> int:
        cur = self.conn.cursor()
        cur.execute("SET NOCOUNT ON; DECLARE @id INT; "
                    "EXEC meta.usp_batch_start @note = ?, @batch_id = @id OUTPUT; SELECT @id;", note)
        batch_id = cur.fetchone()[0]
        self.conn.commit()
        return batch_id

    def end_batch(self, batch_id: int, status: str) -> None:
        self.conn.cursor().execute("EXEC meta.usp_batch_end @batch_id = ?, @status = ?", batch_id, status)
        self.conn.commit()

    def load_source(self, src: Source, batch_id: int) -> int:
        folder = self.sources_dir / src.folder
        files = sorted(folder.glob(src.pattern))
        if not files:
            raise FileNotFoundError(f"{src.name}: no file matches {folder / src.pattern}")
        cur = self.conn.cursor()
        cur.execute(f"TRUNCATE TABLE {src.stg_table};")
        total = 0
        for path in files:
            rel = path.relative_to(self.sources_dir).as_posix()
            if src.kind in ("xml_doc", "text_doc"):
                n = self._load_document(cur, src, path, rel, batch_id)
            else:
                n = self._load_rows(cur, src, path, rel, batch_id)
            cur.execute("EXEC meta.usp_file_log ?, ?, ?, ?, ?, ?, ?",
                        batch_id, src.name, rel, sha256_of(path), path.stat().st_size, src.stg_table, n)
            total += n
        self.conn.commit()
        return total

    def _load_rows(self, cur, src: Source, path: Path, rel: str, batch_id: int) -> int:
        reader = {"csv": read_csv, "xlsx": read_xlsx, "lines": read_lines}[src.kind]
        header, rows = reader(path, src)
        expected = self.stg_columns(src.stg_table)
        if sorted(header) != sorted(expected):
            raise ValueError(
                f"Schema drift in {rel} -> {src.stg_table}\n"
                f"  missing in file : {sorted(set(expected) - set(header))}\n"
                f"  unexpected      : {sorted(set(header) - set(expected))}")
        for line_no, cells in rows:
            if len(cells) != len(header):
                raise ValueError(f"{rel} line {line_no}: {len(cells)} fields, expected {len(header)}")
        columns = header + ["load_batch_id", "source_file", "source_row_nr"]
        sql = f"INSERT INTO {src.stg_table} ({', '.join(columns)}) VALUES ({', '.join('?' * len(columns))})"
        data = [cells + [batch_id, rel, line_no] for line_no, cells in rows]
        if data:
            cur.fast_executemany = True   # sends rows in large packets instead of one round trip per row
            cur.executemany(sql, data)
            cur.fast_executemany = False
        return len(data)

    def _load_document(self, cur, src: Source, path: Path, rel: str, batch_id: int) -> int:
        if src.kind == "xml_doc":
            # Pass the raw bytes: SQL Server then honours the encoding declared in the XML header.
            # (Passing a Python str would fail with "unable to switch the encoding".)
            # pyodbc sends large byte strings as the legacy type IMAGE, which cannot be converted to
            # XML directly - hence the detour via VARBINARY(MAX).
            cur.execute(f"INSERT INTO {src.stg_table} (content, load_batch_id, source_file, source_row_nr) "
                        f"VALUES (CONVERT(XML, CAST(? AS VARBINARY(MAX))), ?, ?, 1)",
                        path.read_bytes(), batch_id, rel)
        else:
            cur.execute(f"INSERT INTO {src.stg_table} (content, load_batch_id, source_file, source_row_nr) "
                        f"VALUES (?, ?, ?, 1)", path.read_text(encoding=src.encoding), batch_id, rel)
        return 1

    def load_all(self, note: str) -> int:
        batch_id = self.start_batch(note)
        try:
            for src in SOURCES:
                n = self.load_source(src, batch_id)
                print(f"  {src.stg_table:<40} {n:>7} rows")
        except Exception:
            self.conn.rollback()
            self.end_batch(batch_id, "FAILED")
            raise
        self.end_batch(batch_id, "OK")
        return batch_id
