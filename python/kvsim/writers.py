"""Exports the in-memory World into heterogeneous source files under data/sources/<system>/.

Each writer imitates the habits of a different (simulated) source system: different
encodings, delimiters, date formats, number formats and file types. The README.md in
every source folder documents these quirks; the generator never touches README files.
"""
from __future__ import annotations

import csv
import json
import xml.etree.ElementTree as ET
from collections import defaultdict
from datetime import date, datetime
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Font

from . import reference as ref
from .generator import OPEN_END, ZULASSUNG_EXPORT_DATE, World

SOURCE_FOLDERS = [
    "statistik", "kbv_referenz", "bfarm", "kassenverzeichnis", "arztregister", "zulassungsausschuss",
    "bedarfsplanung", "abrechnung", "honorar", "terminservice", "bereitschaftsdienst",
    "qualitaetssicherung", "kammern", "pruefungsstelle", "verordnungen", "mitgliederservice",
    "beschwerdemanagement",
]
DATA_SUFFIXES = {".csv", ".txt", ".xml", ".json", ".geojson", ".xlsx", ".md"}


# =========================================================================== helpers
def clean(root: Path) -> None:
    """Delete previously generated data files (never README.md) so no stale files survive."""
    for folder in SOURCE_FOLDERS:
        base = root / folder
        if not base.exists():
            continue
        for f in sorted(base.rglob("*")):
            if f.is_file() and f.name != "README.md" and f.suffix.lower() in DATA_SUFFIXES:
                f.unlink()


def write_csv(path: Path, header: list[str] | None, rows, encoding: str = "utf-8-sig") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding=encoding, newline="") as fh:
        writer = csv.writer(fh, delimiter=";", lineterminator="\r\n")
        if header:
            writer.writerow(header)
        writer.writerows(rows)


def write_xml(path: Path, root: ET.Element) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(root, space="  ")
    ET.ElementTree(root).write(path, encoding="UTF-8", xml_declaration=True)


def write_text(path: Path, text: str, newline: str = "\n", encoding: str = "utf-8") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding=encoding, newline=newline) as fh:
        fh.write(text)


def de_date(d: date | None) -> str:
    return "" if d is None or d == OPEN_END else d.strftime("%d.%m.%Y")


def de_decimal(x: float, decimals: int = 2) -> str:
    s = f"{x:,.{decimals}f}"                                 # 1,234.56
    return s.replace(",", "X").replace(".", ",").replace("X", ".")   # 1.234,56


def berlin_iso(dt: datetime) -> str:
    offset = "+02:00" if date(2025, 3, 30) <= dt.date() < date(2025, 10, 26) else "+01:00"
    return dt.strftime("%Y-%m-%dT%H:%M:%S") + offset


def sub(parent: ET.Element, tag: str, text: str | None = None, **attrs) -> ET.Element:
    el = ET.SubElement(parent, tag, {k: str(v) for k, v in attrs.items() if v is not None})
    if text is not None:
        el.text = text
    return el


# =========================================================================== writers
def write_statistik(w: World, root: Path) -> None:
    folder = root / "statistik"
    folder.mkdir(parents=True, exist_ok=True)
    label = {ag.code: ag.label_statistik for ag in ref.ALTERSGRUPPEN}
    lines = [
        "Statistisches Amt Saarland",
        "Bevölkerung nach Kreisen, Altersgruppen und Geschlecht",
        "Stichtag: 31.12.2024",
        "Gebietsstand: 31.12.2024",
        "",
        "Stichtag;AGS;Kreis;Altersgruppe;Geschlecht;Anzahl",
    ]
    for ags, ag, sex, n in w.einwohner:
        name = ref.KREIS_BY_AGS[ags].name
        lines.append(f"31.12.2024;{ags};{name};{label[ag]};{'weiblich' if sex == 'w' else 'männlich'};{n:,}".replace(",", "."))
    lines += ["", "Hinweis: Werte gerundet. Synthetische Simulation - keine amtlichen Zahlen."]
    write_text(folder / "bevoelkerung_kreise_2024.csv", "\r\n".join(lines) + "\r\n", newline="", encoding="cp1252")

    features = [{
        "type": "Feature",
        "properties": {"AGS": k.ags, "GEN": k.name, "BEZ": k.kreisart, "SITZ": k.sitz},
        "geometry": {"type": "Point", "coordinates": [k.lon, k.lat]},   # GeoJSON order: lon, lat
    } for k in ref.KREISE]
    write_text(folder / "kreise_saarland.geojson",
               json.dumps({"type": "FeatureCollection", "name": "kreise_saarland", "features": features},
                          ensure_ascii=False, indent=2) + "\n")


def write_kbv_referenz(w: World, root: Path) -> None:
    folder = root / "kbv_referenz"
    write_csv(folder / "arztgruppenschluessel.csv", ["Schluessel", "Bezeichnung"],
              [(code, name) for code, name, _ in ref.FACHGRUPPEN])
    ebm = ET.Element("EBM", version="2025", gueltig_ab="2025-01-01")
    sub(ebm, "Orientierungswert", jahr="2025", euro_je_punkt=f"{ref.ORIENTIERUNGSWERT[2025]:.6f}")
    for nr, bereich, titel in ref.EBM_KAPITEL:
        kap = sub(ebm, "Kapitel", nr=nr, bereich=bereich, bezeichnung=titel)
        for g in (g for g in ref.GOPS if g.kapitel == nr):
            gop = sub(kap, "GOP", code=g.code, punkte=g.punkte, pruefzeit_min=g.pruefzeit_min,
                      extrabudgetaer="ja" if g.extrabudgetaer else "nein", qs_bereich=g.qs)
            sub(gop, "Titel", g.titel)
    write_xml(folder / "ebm_2025.xml", ebm)


def write_bfarm(w: World, root: Path) -> None:
    lines = [f"{ref.icd_kapitel(code)};{code};{titel}" for code, titel in sorted(ref.ICD_TITLES.items())]
    write_text(root / "bfarm" / "icd10gm2025_auswahl.txt", "\n".join(lines) + "\n")


def write_kassen(w: World, root: Path) -> None:
    write_csv(root / "kassenverzeichnis" / "krankenkassen.csv", ["IK", "Name", "Kassenart"],
              [(k.ik, k.name, k.kassenart) for k in w.kassen])


def write_arztregister(w: World, root: Path) -> None:
    folder = root / "arztregister"
    write_csv(folder / "aerzte.csv",
              ["LANR", "EFN", "Titel", "Vorname", "Nachname", "Geschlecht", "Geburtsjahr", "Fachgruppe"],
              [(a.lanr, a.efn, a.titel, a.vorname, a.nachname, a.geschlecht, a.geburtsjahr, a.fachgruppe)
               for a in sorted(w.aerzte, key=lambda a: a.lanr)])
    write_csv(folder / "betriebsstaetten.csv",
              ["BSNR", "Name", "Kooperationsform", "Strasse", "Ort", "Kreis_AGS", "Gruendungsdatum"],
              [(p.bsnr, p.name, p.kooperationsform, p.strasse, p.ort, p.kreis_ags, de_date(p.gruendungsdatum))
               for p in sorted(w.praxen, key=lambda p: p.bsnr)])
    teilnahmen = sorted(w.teilnahmen, key=lambda t: (t.arzt.lanr, t.von))
    write_csv(folder / "teilnahmen.csv",
              ["LANR", "BSNR", "Teilnahmeform", "Anrechnungsfaktor", "Gueltig_ab", "Gueltig_bis"],
              [(t.arzt.lanr, t.praxis.bsnr, t.form, de_decimal(t.faktor), de_date(t.von), de_date(t.bis))
               for t in teilnahmen])
    write_csv(folder / "teilnahme_status.csv",
              ["LANR", "BSNR", "Teilnahme_ab", "Status", "Status_ab", "Status_bis"],
              [(t.arzt.lanr, t.praxis.bsnr, de_date(t.von), p.status, de_date(p.von), de_date(p.bis))
               for t in teilnahmen for p in t.status])


def write_zulassung(w: World, root: Path) -> None:
    folder = root / "zulassungsausschuss"
    xml_root = ET.Element("Zulassungsverfahren", exportiert_am=ZULASSUNG_EXPORT_DATE.isoformat(),
                          gremium="Zulassungsausschuss für Ärzte und Psychotherapeuten im Saarland")
    for v in w.verfahren:
        el = sub(xml_root, "Verfahren", aktenzeichen=v.aktenzeichen, art=v.art)
        sub(el, "Antragsteller", lanr=v.arzt.lanr)
        if v.praxis is not None:
            sub(el, "Betriebsstaette", bsnr=v.praxis.bsnr)
        sub(el, "Planungsbereich", v.pb_code)
        sub(el, "Antragsdatum", v.antrag.isoformat())
        if v.sitzung is not None:
            sub(el, "Sitzung", v.sitzung.isoformat())
        sub(el, "Ergebnis", v.ergebnis,
            wirksam_ab=v.wirksam_ab.isoformat() if v.wirksam_ab else None,
            wirksam_bis=v.wirksam_bis.isoformat() if v.wirksam_bis else None)
        verlauf = sub(el, "Statusverlauf")
        for code, ab in v.status:
            sub(verlauf, "Status", code=code, ab=ab.isoformat())
        if v.bescheid_text:
            sub(el, "Bescheid", v.bescheid_text, datum=v.bescheid_datum.isoformat())
    write_xml(folder / "zulassungsverfahren_2025.xml", xml_root)

    from .texts import protokoll_markdown
    by_sitzung: dict[date, list] = defaultdict(list)
    for v in w.verfahren:
        if v.sitzung is not None and any(c == "ENTSCHIEDEN" for c, _ in v.status):
            by_sitzung[v.sitzung].append(v)
    for sitzung in sorted(by_sitzung):
        write_text(folder / "protokolle" / f"ZA-Sitzung_{sitzung.isoformat()}.md",
                   protokoll_markdown(sitzung, by_sitzung[sitzung]))


def write_bedarfsplanung(w: World, root: Path) -> None:
    folder = root / "bedarfsplanung"
    folder.mkdir(parents=True, exist_ok=True)
    wb = Workbook()
    wb.properties.creator = "Bedarfsplanung (Simulation)"
    wb.properties.created = datetime(2026, 1, 12, 9, 0)
    wb.properties.modified = datetime(2026, 1, 12, 9, 0)

    ws = wb.active
    ws.title = "Arztgruppen"
    ws.append(["Code", "Arztgruppe", "Versorgungsebene", "Planungsbereichstyp", "Verhaeltniszahl", "Fachgruppenschluessel"])
    for g in ref.ARZTGRUPPEN:
        ws.append([g.code, g.name, g.versorgungsebene, g.planungsbereich_typ, g.verhaeltniszahl, ", ".join(g.fachgruppen)])

    ws = wb.create_sheet("Planungsbereiche")
    ws.append(["PB_Code", "Planungsbereich", "Typ", "Kreise_AGS"])
    for code, name, typ, ags_list in w.planungsbereiche:
        ws.append([code, name, typ, ", ".join(ags_list)])

    ws = wb.create_sheet("Versorgungsgrade")
    ws["A1"] = "Feststellungen des Landesausschusses zum Versorgungsgrad (Simulation)"
    ws["A1"].font = Font(bold=True, size=12)
    ws.merge_cells("A1:I1")
    ws.append([])
    ws.append(["Stichtag", "PB_Code", "Arztgruppe", "Einwohner", "Verhaeltniszahl", "Soll", "Ist", "Versorgungsgrad", "Status"])
    for r in w.versorgungsgrade:
        ws.append([r["stichtag"], r["pb_code"], r["arztgruppe"], r["einwohner"], r["verhaeltniszahl"],
                   r["soll"], r["ist"], r["versorgungsgrad"] / 100, r["status"]])
        row = ws.max_row
        ws.cell(row=row, column=1).number_format = "DD.MM.YYYY"
        ws.cell(row=row, column=8).number_format = "0.0%"
    wb.save(folder / "bedarfsplanung_2025.xlsx")


def write_abrechnung(w: World, root: Path) -> None:
    folder = root / "abrechnung"
    y = w.settings.year
    for q in range(1, 5):
        faelle = [f for f in w.faelle if f.quartal == q]
        write_csv(folder / f"faelle_{y}Q{q}.csv",
                  ["Fallnummer", "BSNR", "Quartal", "Patientenpseudonym", "Kassen_IK", "Versichertenstatus",
                   "Geschlecht", "Geburtsjahr", "Scheinuntergruppe", "TSS_Vermittlungscode"],
                  [(f.fallnummer, f.praxis.bsnr, f"{q}{y}", f.patient.pseudonym, f.patient.kasse_ik,
                    f.patient.status, f.patient.geschlecht, f.patient.geburtsjahr, f.scheinuntergruppe,
                    f.tss_code or "") for f in faelle], encoding="utf-8")
        write_csv(folder / f"leistungen_{y}Q{q}.csv",
                  ["Fallnummer", "Position", "Datum", "LANR", "GOP", "Anzahl"],
                  [(f.fallnummer, i, l.datum.strftime("%d%m%Y"), l.arzt.lanr, l.gop, l.anzahl)
                   for f in faelle for i, l in enumerate(f.leistungen, 1)], encoding="utf-8")
        write_csv(folder / f"diagnosen_{y}Q{q}.csv", ["Fallnummer", "ICD", "Sicherheit"],
                  [(f.fallnummer, code, sicherheit) for f in faelle for code, sicherheit in f.diagnosen],
                  encoding="utf-8")


def write_honorar(w: World, root: Path) -> None:
    folder = root / "honorar"
    y = w.settings.year
    for q in range(1, 5):
        bescheide = [b for b in w.honorar if b.quartal == q]
        xml_root = ET.Element("Honorarbescheide", kv=ref.KV_CODE, quartal=f"{y}Q{q}",
                              erstellt_am=bescheide[0].datum.isoformat())
        for b in bescheide:
            el = sub(xml_root, "Bescheid", nr=b.nr, bsnr=b.praxis.bsnr, datum=b.datum.isoformat())
            sub(el, "Punkte", angefordert=b.punkte_angefordert, berichtigt=b.punkte_berichtigt,
                mgv=b.punkte_mgv, egv=b.punkte_egv)
            sub(el, "Verguetung", quote_mgv=f"{b.quote_mgv:.4f}" if b.quote_mgv is not None else None,
                mgv=f"{b.betrag_mgv:.2f}", egv=f"{b.betrag_egv:.2f}", brutto=f"{b.brutto:.2f}")
            sub(el, "Abzuege", verwaltungskosten=f"{b.verwaltungskosten:.2f}", abschlaege=f"{b.abschlaege:.2f}")
            sub(el, "Auszahlungsbetrag", f"{b.auszahlung:.2f}")
        write_xml(folder / f"honorarbescheide_{y}Q{q}.xml", xml_root)
    rows = sorted(w.abschlaege, key=lambda a: (a.datum, a.praxis.bsnr))
    write_csv(folder / f"abschlagszahlungen_{y}.csv", ["Buchungsdatum", "BSNR", "Betrag", "Verwendungszweck"],
              [(de_date(a.datum), a.praxis.bsnr, de_decimal(a.betrag), f"Abschlag {a.nr}/3 Quartal {a.quartal}/{y}")
               for a in rows], encoding="cp1252")


def write_tss(w: World, root: Path) -> None:
    folder = root / "terminservice"
    folder.mkdir(parents=True, exist_ok=True)
    fachgebiet = {g.code: g.tss_fachgebiet for g in ref.ARZTGRUPPEN}
    items = []
    for a in w.tss:
        termin = None
        if a.termin is not None:
            termin = {"bsnr": a.praxis.bsnr, "start": berlin_iso(a.termin),
                      "vermittlungscode": a.code, "wahrgenommen": a.wahrgenommen}
        items.append({
            "id": a.uuid, "createdAt": berlin_iso(a.eingang), "channel": a.kanal,
            "fachgebiet": fachgebiet[a.arztgruppe], "dringlichkeit": a.dringlichkeit,
            "patient": {"kreisAgs": a.patient.kreis_ags, "alter": a.alter},
            "status": a.status, "termin": termin,
        })
    page_size = 100
    pages = (len(items) + page_size - 1) // page_size
    for p in range(pages):
        payload = {"page": p + 1, "pageSize": page_size, "totalItems": len(items), "totalPages": pages,
                   "exportedAt": berlin_iso(datetime.combine(w.settings.export_date, datetime.min.time())),
                   "items": items[p * page_size:(p + 1) * page_size]}
        write_text(folder / f"tss_anfragen_{w.settings.year}_p{p + 1:03d}.json",
                   json.dumps(payload, ensure_ascii=False, indent=2) + "\n")


def write_bereitschaftsdienst(w: World, root: Path) -> None:
    folder = root / "bereitschaftsdienst"
    write_csv(folder / "bereitschaftspraxen.csv", ["Kennung", "Name", "Ort", "Kreis_AGS"],
              [(k, f"Bereitschaftsdienstpraxis {ort}", ort, ags) for k, ort, ags in ref.BEREITSCHAFTSPRAXEN])
    write_csv(folder / f"dienstplan_{w.settings.year}.csv",
              ["Dienst_ID", "Kennung", "Datum", "Beginn", "Ende", "LANR", "Getauscht_von_LANR"],
              [(d.dienst_id, d.kennung, de_date(d.beginn.date()), d.beginn.strftime("%H:%M"),
                d.ende.strftime("%H:%M"), d.arzt.lanr, d.getauscht_von.lanr if d.getauscht_von else "")
               for d in w.dienste])


def write_qs(w: World, root: Path) -> None:
    rows = sorted(((a.lanr, area, de_date(von), de_date(bis)) for a, area, von, bis in w.qs_genehmigungen))
    write_csv(root / "qualitaetssicherung" / "qs_genehmigungen.csv",
              ["LANR", "Leistungsbereich", "Genehmigt_ab", "Genehmigt_bis"], rows)


def write_kammern(w: World, root: Path) -> None:
    rows = sorted((a.efn, jahr, punkte) for a, jahr, punkte in w.fortbildung)
    write_csv(root / "kammern" / "fortbildungspunkte_2021_2025.csv", ["EFN", "Jahr", "Punkte"], rows)


def write_pruefungsstelle(w: World, root: Path) -> None:
    xml_root = ET.Element("Pruefverfahren", exportiert_am=w.settings.export_date.isoformat(),
                          stelle="Prüfungsstelle der Ärzte und Krankenkassen im Saarland (Simulation)")
    for p in w.pruefverfahren:
        el = sub(xml_root, "Verfahren", aktenzeichen=p.aktenzeichen)
        sub(el, "BSNR", p.praxis.bsnr)
        sub(el, "Quartal", f"{p.quartal}/{w.settings.year}")
        sub(el, "Gegenstand", p.gegenstand)
        sub(el, "Anlass", p.anlass)
        sub(el, "Eingeleitet", p.eingeleitet.isoformat())
        sub(el, "Status", p.status)
        if p.abgeschlossen is not None:
            sub(el, "Abgeschlossen", p.abgeschlossen.isoformat())
        if p.massnahme is not None:
            sub(el, "Massnahme", p.massnahme, betrag=f"{p.betrag:.2f}" if p.betrag is not None else None)
    write_xml(root / "pruefungsstelle" / f"pruefverfahren_{w.settings.year}.xml", xml_root)


def write_verordnungen(w: World, root: Path) -> None:
    folder = root / "verordnungen"
    y = w.settings.year
    records = sorted(w.verordnungen, key=lambda v: (v.quartal, v.praxis.bsnr, v.art))
    lines = [f"HD{w.settings.export_date:%Y%m%d}KV{ref.KV_CODE}VERORDNUNGEN {y}".ljust(40)]
    total_cent = 0
    for v in records:
        cent = round(v.brutto * 100)
        total_cent += cent
        lines.append(f"VO{v.praxis.bsnr}{y}{v.quartal}{v.art}{v.anzahl:07d}{cent:011d}".ljust(40))
    lines.append(f"TR{len(records):07d}{total_cent:013d}".ljust(40))
    write_text(folder / f"verordnungen_{y}.txt", "\r\n".join(lines) + "\r\n", newline="", encoding="cp1252")
    write_csv(folder / f"richtgroessen_{y}.csv", ["Arztgruppe", "Jahr", "Verordnungsart", "Richtgroesse_EUR_je_Fall"],
              [(g, y, art, de_decimal(v)) for art, values in ref.RICHTGROESSEN.items() for g, v in values.items()])


def write_mitgliederservice(w: World, root: Path) -> None:
    tickets = [{
        "ticketId": a.ticket_id, "createdAt": berlin_iso(a.erstellt), "channel": a.kanal, "topic": a.thema,
        "requester": {"lanr": a.arzt.lanr, "bsnr": a.praxis.bsnr},
        "subject": a.betreff, "body": a.text, "status": a.status,
        "closedAt": berlin_iso(a.erledigt) if a.erledigt else None,
    } for a in w.anfragen]
    payload = {"exportedAt": berlin_iso(datetime.combine(w.settings.export_date, datetime.min.time())),
               "system": "CRM Mitgliederservice (Simulation)", "tickets": tickets}
    write_text(root / "mitgliederservice" / f"anfragen_{w.settings.year}.json",
               json.dumps(payload, ensure_ascii=False, indent=2) + "\n")


def write_beschwerden(w: World, root: Path) -> None:
    folder = root / "beschwerdemanagement"
    for b in w.beschwerden:
        text = (
            f"Eingangsdatum: {de_date(b.eingang)}\r\n"
            f"Eingangskanal: {b.kanal}\r\n"
            f"Kategorie: {b.kategorie}\r\n"
            f"Bezug-BSNR: {b.praxis.bsnr}\r\n"
            f"Betreff: {b.betreff}\r\n"
            f"Beschwerdeführende Person: (anonymisiert)\r\n"
            f"\r\n{b.text}\r\n"
        )
        write_text(folder / f"beschwerde_{w.settings.year}_{b.nr:03d}.txt", text, newline="")


def write_all(w: World, root: Path) -> None:
    clean(root)
    for writer in (write_statistik, write_kbv_referenz, write_bfarm, write_kassen, write_arztregister,
                   write_zulassung, write_bedarfsplanung, write_abrechnung, write_honorar, write_tss,
                   write_bereitschaftsdienst, write_qs, write_kammern, write_pruefungsstelle,
                   write_verordnungen, write_mitgliederservice, write_beschwerden):
        writer(w, root)
