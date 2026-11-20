"""Export the aggregates behind the static dashboard to dashboard_site/data.js.

The static site (dashboard_site/, published with GitHub Pages) cannot query SQL Server,
so this script reads the `mart` star schemas once and writes the small, already
aggregated (or row-level but anonymous) datasets the charts need as one JavaScript file.
All data is synthetic. Doctor and practice names are not exported.

Usage (from the project root, after tools\\run_all.ps1 has built the database):
    .venv\\Scripts\\python.exe python\\export_dashboard_data.py
"""
from __future__ import annotations

import json
import sys
from datetime import date
from decimal import Decimal

import pyodbc

from kvsim.config import PROJECT_ROOT, load_settings

OUT_FILE = PROJECT_ROOT / "dashboard_site" / "data.js"


def plain(v):
    """JSON-friendly scalar: Decimal -> float/int, bool stays bool, date -> ISO string."""
    if isinstance(v, Decimal):
        return int(v) if v == v.to_integral_value() else round(float(v), 2)
    if isinstance(v, date):
        return v.isoformat()
    return v


def rows(cur, sql: str) -> list[list]:
    return [[plain(v) for v in r] for r in cur.execute(sql).fetchall()]


class Codes:
    """Turns repeated strings into small integer codes so the file stays small."""

    def __init__(self) -> None:
        self.values: list = []
        self._index: dict = {}

    def __call__(self, value) -> int | None:
        if value is None:
            return None
        if value not in self._index:
            self._index[value] = len(self.values)
            self.values.append(value)
        return self._index[value]


def export(cur, year: int) -> dict:
    d: dict = {}

    # ---------- Overview ----------
    d["overview"] = {
        "casesByQuarter": rows(cur, """
            SELECT q.quartal_label, COUNT(*) FROM mart.fact_abrechnungsfall f
            JOIN mart.dim_quartal q ON q.quartal_key = f.quartal_key
            GROUP BY q.quartal_key, q.quartal_label ORDER BY q.quartal_key"""),
        "casesByAgeGroup": rows(cur, """
            SELECT a.altersgruppe, COUNT(*) FROM mart.fact_abrechnungsfall f
            JOIN mart.dim_altersgruppe a ON a.altersgruppe_key = f.altersgruppe_key
            GROUP BY a.altersgruppe, a.sortierung ORDER BY a.sortierung"""),
        "practicesByForm": rows(cur, """
            SELECT kooperationsform, COUNT(*) FROM mart.dim_praxis
            WHERE praxis_key <> -1 GROUP BY kooperationsform ORDER BY COUNT(*) DESC"""),
        "casesBySpecialty": rows(cur, """
            SELECT g.fachgruppe, g.versorgungsebene, COUNT(*) FROM mart.fact_abrechnungsfall f
            JOIN mart.dim_fachgruppe g ON g.fachgruppe_key = f.fachgruppe_key
            GROUP BY g.fachgruppe, g.versorgungsebene ORDER BY COUNT(*) DESC"""),
        "casesByKreis": rows(cur, """
            SELECT r.kreis, COUNT(*) FROM mart.fact_abrechnungsfall f
            JOIN mart.dim_region r ON r.region_key = f.region_key
            GROUP BY r.kreis ORDER BY COUNT(*) DESC"""),
        "practices": cur.execute("SELECT COUNT(DISTINCT bsnr) FROM mart.dim_praxis WHERE praxis_key <> -1").fetchone()[0],
    }

    # ---------- Doctors: one anonymous row per current doctor ----------
    kreis, fach, form = Codes(), Codes(), Codes()
    doctors = []
    for r in cur.execute("""
            SELECT p.kreis, a.fachgruppe, a.geschlecht, a.geburtsjahr, a.teilnahmeform_code, p.kooperationsform
            FROM mart.dim_arzt a
            LEFT JOIN mart.dim_praxis p ON p.bsnr = a.praxis_bsnr AND p.praxis_key <> -1
            WHERE a.is_current = 1 AND a.arzt_id IS NOT NULL
            ORDER BY a.arzt_id""").fetchall():
        doctors.append([kreis(r[0]), fach(r[1]), r[2], year - r[3] if r[3] else None, r[4], form(r[5])])
    d["doctors"] = {"ageReferenceYear": year, "kreis": kreis.values, "specialty": fach.values,
                    "practiceForm": form.values,
                    "columns": ["kreis", "specialty", "gender", "age", "participation", "practiceForm"],
                    "rows": doctors}

    # ---------- Billing & Honorar (per quarter) ----------
    prax, pform = Codes(), Codes()
    scatter = []
    for r in cur.execute("""
            WITH c AS (SELECT praxis_key, quartal_key, COUNT(*) AS faelle
                       FROM mart.fact_abrechnungsfall GROUP BY praxis_key, quartal_key)
            SELECT p.bsnr, p.kooperationsform, q.quartal_label, ISNULL(c.faelle, 0), ISNULL(h.honorar_brutto, 0)
            FROM c FULL JOIN mart.fact_honorar_quartal h ON h.praxis_key = c.praxis_key AND h.quartal_key = c.quartal_key
            JOIN mart.dim_praxis p ON p.praxis_key = COALESCE(c.praxis_key, h.praxis_key)
            JOIN mart.dim_quartal q ON q.quartal_key = COALESCE(c.quartal_key, h.quartal_key)
            ORDER BY q.quartal_key, p.bsnr""").fetchall():
        scatter.append([prax(r[0]), pform(r[1]), r[2], r[3], plain(r[4])])
    d["billing"] = {
        "quarters": [r[0] for r in rows(cur, """
            SELECT q.quartal_label FROM mart.dim_quartal q
            WHERE EXISTS (SELECT 1 FROM mart.fact_abrechnungsfall f WHERE f.quartal_key = q.quartal_key)
            ORDER BY q.quartal_key""")],
        # quarter, cases, points
        "cases": rows(cur, """
            SELECT q.quartal_label, COUNT(*), SUM(CAST(f.punkte AS bigint)) FROM mart.fact_abrechnungsfall f
            JOIN mart.dim_quartal q ON q.quartal_key = f.quartal_key
            GROUP BY q.quartal_key, q.quartal_label ORDER BY q.quartal_key"""),
        # quarter, honorar brutto, admin costs, advance payments made, final payment, MGV, EGV
        "honorar": rows(cur, """
            SELECT q.quartal_label, SUM(h.honorar_brutto), SUM(h.verwaltungskosten), SUM(h.abschlaege_gezahlt),
                   SUM(h.auszahlungsbetrag), SUM(h.betrag_mgv), SUM(h.betrag_egv)
            FROM mart.fact_honorar_quartal h JOIN mart.dim_quartal q ON q.quartal_key = h.quartal_key
            GROUP BY q.quartal_key, q.quartal_label ORDER BY q.quartal_key"""),
        # type of insurer, quarter, cases
        "casesByInsurer": rows(cur, """
            SELECT k.kassenart, q.quartal_label, COUNT(*) FROM mart.fact_abrechnungsfall f
            JOIN mart.dim_krankenkasse k ON k.kasse_key = f.kasse_key
            JOIN mart.dim_quartal q ON q.quartal_key = f.quartal_key
            GROUP BY k.kassenart, q.quartal_key, q.quartal_label ORDER BY k.kassenart, q.quartal_key"""),
        # EBM chapter, extra-budgetary (EGV), quarter, billed amount
        "ebm": rows(cur, """
            SELECT g.kapitel, CAST(g.ist_extrabudgetaer AS int), q.quartal_label, SUM(f.betrag_eur)
            FROM mart.fact_leistung f
            JOIN mart.dim_gop g ON g.gop_key = f.gop_key
            JOIN mart.dim_quartal q ON q.quartal_key = f.quartal_key
            GROUP BY g.kapitel_nr, g.kapitel, g.ist_extrabudgetaer, q.quartal_key, q.quartal_label
            ORDER BY g.kapitel_nr, q.quartal_key"""),
        "practiceForm": pform.values,
        "practiceCount": len(prax.values),
        # practice code, practice form code, quarter, cases, honorar brutto
        "practices": scatter,
    }

    # ---------- Appointments (TSS): one row per request ----------
    grp = Codes()
    tss = []
    for r in cur.execute("""
            SELECT g.arztgruppe, d.monat_nr, f.dringlichkeit, f.kanal, CAST(f.ist_vermittelt AS int),
                   f.wartezeit_tage, CAST(f.ist_innerhalb_4_wochen AS int), CAST(f.termin_wahrgenommen AS int)
            FROM mart.fact_tss_anfrage f
            JOIN mart.dim_arztgruppe g ON g.arztgruppe_key = f.arztgruppe_key
            JOIN mart.dim_datum d ON d.datum_key = f.eingang_datum_key
            ORDER BY f.anfrage_id""").fetchall():
        tss.append([grp(r[0]), r[1], r[2], r[3], r[4], r[5], r[6] or 0, r[7] or 0])
    d["tss"] = {"specialty": grp.values,
                "columns": ["specialty", "month", "urgency", "channel", "arranged", "waitDays", "within4Weeks", "attended"],
                "rows": tss}

    # ---------- Planning & out-of-hours ----------
    d["planning"] = {
        # reference date, physician group, level of care, planning area, area type, target, actual, supply %, status
        "supply": rows(cur, """
            SELECT dd.datum, g.arztgruppe, g.versorgungsebene, p.planungsbereich, p.typ,
                   f.soll_aerzte, f.ist_aerzte, f.versorgungsgrad_pct, f.status
            FROM mart.fact_versorgungsgrad f
            JOIN mart.dim_datum dd ON dd.datum_key = f.stichtag_key
            JOIN mart.dim_arztgruppe g ON g.arztgruppe_key = f.arztgruppe_key
            JOIN mart.dim_planungsbereich p ON p.planungsbereich_key = f.planungsbereich_key
            ORDER BY dd.datum, g.arztgruppe, p.planungsbereich"""),
        # month, weekday (1 = Monday), weekend/holiday, shifts, hours, swapped shifts
        "shifts": rows(cur, """
            SELECT d.monat_nr, d.wochentag_nr, CAST(f.ist_wochenende_feiertag AS int),
                   COUNT(*), SUM(f.dauer_stunden), SUM(CAST(f.ist_getauscht AS int))
            FROM mart.fact_bereitschaftsdienst f JOIN mart.dim_datum d ON d.datum_key = f.datum_key
            GROUP BY d.monat_nr, d.wochentag_nr, f.ist_wochenende_feiertag
            ORDER BY d.monat_nr, d.wochentag_nr, f.ist_wochenende_feiertag"""),
        "shiftYear": year,
    }
    return d


def main() -> int:
    settings = load_settings()
    with pyodbc.connect(settings.connection_string()) as conn:
        data = export(conn.cursor(), settings.year)
    data["meta"] = {"exported": date.today().isoformat(), "database": settings.database,
                    "dataYear": settings.year, "synthetic": True}
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    OUT_FILE.write_text(
        "// Generated by python/export_dashboard_data.py from the KVSim mart schemas. Do not edit by hand.\n"
        "// All data is synthetic (simulated KV Saarland).\n"
        f"window.KVSIM = {payload};\n", encoding="utf-8")
    print(f"wrote {OUT_FILE.relative_to(PROJECT_ROOT)} ({OUT_FILE.stat().st_size / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
