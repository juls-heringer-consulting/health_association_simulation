"""Generate all synthetic source files into data/sources/.

Usage (from the project root):
    .venv\\Scripts\\python.exe python\\generate_sources.py
"""
from __future__ import annotations

import sys
import time
from collections import Counter

from kvsim.config import SOURCES_DIR, load_settings
from kvsim.generator import build_world
from kvsim.writers import write_all


def main() -> int:
    settings = load_settings()
    if settings.inject_dq_issues:
        print("inject_dq_issues = true is not implemented yet (optional phase). Set it to false.")
        return 1
    started = time.perf_counter()
    world = build_world(settings)
    write_all(world, SOURCES_DIR)
    forms = Counter(p.kooperationsform for p in world.praxen)
    print(f"Generated in {time.perf_counter() - started:.1f}s (seed {settings.seed}) -> {SOURCES_DIR}")
    print(f"  Aerzte/Psychotherapeuten : {len(world.aerzte)}  (with Teilnahme: {sum(1 for a in world.aerzte if a.teilnahmen)})")
    print(f"  Betriebsstaetten         : {len(world.praxen)}  {dict(forms)}")
    print(f"  Teilnahmen               : {len(world.teilnahmen)}")
    print(f"  Zulassungsverfahren      : {len(world.verfahren)}")
    print(f"  Behandlungsfaelle        : {len(world.faelle)}  Leistungen: {sum(len(f.leistungen) for f in world.faelle)}")
    print(f"  Honorarbescheide         : {len(world.honorar)}  Abschlaege: {len(world.abschlaege)}")
    print(f"  TSS-Anfragen             : {len(world.tss)}  Dienste: {len(world.dienste)}")
    print(f"  Verordnungssaetze        : {len(world.verordnungen)}  Pruefverfahren: {len(world.pruefverfahren)}")
    print(f"  Anfragen/Beschwerden     : {len(world.anfragen)} / {len(world.beschwerden)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
