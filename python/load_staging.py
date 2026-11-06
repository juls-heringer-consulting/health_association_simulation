"""Load all source files from data/sources/ into the stg schema of KVSim.

Usage (from the project root):
    .venv\\Scripts\\python.exe python\\load_staging.py

Afterwards run the transformations in SSMS (or let tools/run_all.ps1 do it):
    EXEC core.usp_load_all;   -- stg  -> core
    EXEC mart.usp_load_all;   -- core -> mart
"""
from __future__ import annotations

import sys
import time

import pyodbc

from kvsim.config import SOURCES_DIR, load_settings
from kvsim.loader import StagingLoader


def main() -> int:
    settings = load_settings()
    started = time.perf_counter()
    with pyodbc.connect(settings.connection_string(), autocommit=False) as conn:
        batch_id = StagingLoader(conn, SOURCES_DIR).load_all(note="python/load_staging.py")
    print(f"Staging batch {batch_id} loaded in {time.perf_counter() - started:.1f}s.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
