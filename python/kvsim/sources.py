"""Registry of all source files: where they are, how to read them, which stg table they go to.

This is the single place that knows the physical properties of each source
(encoding, delimiter, header position, ...). The loader itself is generic.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Source:
    name: str                 # logical source name (also written to meta.load_file)
    folder: str               # folder below data/sources
    pattern: str              # glob pattern inside that folder
    kind: str                 # csv | xlsx | lines | xml_doc | text_doc
    stg_table: str            # target table, e.g. "stg.arztregister_aerzte"
    encoding: str = "utf-8-sig"
    skip_lines: int = 0       # metadata lines before the header (csv)
    stop_at_blank: bool = False   # footer after the first empty line (csv)
    has_header: bool = True
    columns: tuple[str, ...] = ()  # column names for files without a header
    sheet: str | None = None  # xlsx sheet
    header_row: int = 1       # xlsx header row (1-based)


SOURCES: list[Source] = [
    # Statistisches Amt Saarland
    Source("statistik_bevoelkerung", "statistik", "bevoelkerung_kreise_*.csv", "csv", "stg.statistik_bevoelkerung",
           encoding="cp1252", skip_lines=5, stop_at_blank=True),
    Source("statistik_kreise", "statistik", "kreise_saarland.geojson", "text_doc", "stg.statistik_kreise_geojson",
           encoding="utf-8"),
    # KBV / BfArM / Kassen
    Source("kbv_arztgruppenschluessel", "kbv_referenz", "arztgruppenschluessel.csv", "csv", "stg.kbv_arztgruppenschluessel"),
    Source("kbv_ebm", "kbv_referenz", "ebm_*.xml", "xml_doc", "stg.kbv_ebm_xml"),
    Source("bfarm_icd10", "bfarm", "icd10gm*.txt", "csv", "stg.bfarm_icd10", encoding="utf-8",
           has_header=False, columns=("kapitel", "code", "titel")),
    Source("kassenverzeichnis", "kassenverzeichnis", "krankenkassen.csv", "csv", "stg.kassen_krankenkassen"),
    # Arztregister
    Source("arztregister_aerzte", "arztregister", "aerzte.csv", "csv", "stg.arztregister_aerzte"),
    Source("arztregister_betriebsstaetten", "arztregister", "betriebsstaetten.csv", "csv", "stg.arztregister_betriebsstaetten"),
    Source("arztregister_teilnahmen", "arztregister", "teilnahmen.csv", "csv", "stg.arztregister_teilnahmen"),
    Source("arztregister_teilnahme_status", "arztregister", "teilnahme_status.csv", "csv", "stg.arztregister_teilnahme_status"),
    # Zulassungsausschuss
    Source("zulassung_verfahren", "zulassungsausschuss", "zulassungsverfahren_*.xml", "xml_doc", "stg.zulassung_verfahren_xml"),
    Source("zulassung_protokolle", "zulassungsausschuss/protokolle", "ZA-Sitzung_*.md", "text_doc",
           "stg.zulassung_protokolle", encoding="utf-8"),
    # Bedarfsplanung (one workbook, three sheets)
    Source("bedarfsplanung_arztgruppen", "bedarfsplanung", "bedarfsplanung_*.xlsx", "xlsx",
           "stg.bedarfsplanung_arztgruppen", sheet="Arztgruppen"),
    Source("bedarfsplanung_planungsbereiche", "bedarfsplanung", "bedarfsplanung_*.xlsx", "xlsx",
           "stg.bedarfsplanung_planungsbereiche", sheet="Planungsbereiche"),
    Source("bedarfsplanung_versorgungsgrade", "bedarfsplanung", "bedarfsplanung_*.xlsx", "xlsx",
           "stg.bedarfsplanung_versorgungsgrade", sheet="Versorgungsgrade", header_row=3),
    # Abrechnung
    Source("abrechnung_faelle", "abrechnung", "faelle_*.csv", "csv", "stg.abrechnung_faelle", encoding="utf-8"),
    Source("abrechnung_leistungen", "abrechnung", "leistungen_*.csv", "csv", "stg.abrechnung_leistungen", encoding="utf-8"),
    Source("abrechnung_diagnosen", "abrechnung", "diagnosen_*.csv", "csv", "stg.abrechnung_diagnosen", encoding="utf-8"),
    # Honorar
    Source("honorar_bescheide", "honorar", "honorarbescheide_*.xml", "xml_doc", "stg.honorar_bescheide_xml"),
    Source("honorar_abschlaege", "honorar", "abschlagszahlungen_*.csv", "csv", "stg.honorar_abschlaege", encoding="cp1252"),
    # Versorgung
    Source("tss_anfragen", "terminservice", "tss_anfragen_*.json", "text_doc", "stg.tss_anfragen_json", encoding="utf-8"),
    Source("bd_bereitschaftspraxen", "bereitschaftsdienst", "bereitschaftspraxen.csv", "csv", "stg.bd_bereitschaftspraxen"),
    Source("bd_dienstplan", "bereitschaftsdienst", "dienstplan_*.csv", "csv", "stg.bd_dienstplan"),
    # QS, Kammern, Pruefungsstelle
    Source("qs_genehmigungen", "qualitaetssicherung", "qs_genehmigungen.csv", "csv", "stg.qs_genehmigungen"),
    Source("kammer_fortbildung", "kammern", "fortbildungspunkte_*.csv", "csv", "stg.kammer_fortbildungspunkte"),
    Source("pruefung_verfahren", "pruefungsstelle", "pruefverfahren_*.xml", "xml_doc", "stg.pruefung_verfahren_xml"),
    # Verordnungen
    Source("verordnung_zeilen", "verordnungen", "verordnungen_*.txt", "lines", "stg.verordnung_zeilen", encoding="cp1252"),
    Source("verordnung_richtgroessen", "verordnungen", "richtgroessen_*.csv", "csv", "stg.verordnung_richtgroessen"),
    # Kommunikation
    Source("mitgliederservice_anfragen", "mitgliederservice", "anfragen_*.json", "text_doc",
           "stg.mitgliederservice_anfragen_json", encoding="utf-8"),
    Source("beschwerden", "beschwerdemanagement", "beschwerde_*.txt", "text_doc", "stg.beschwerden_txt", encoding="utf-8"),
]
