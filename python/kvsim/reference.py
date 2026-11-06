"""Static reference data for the simulation of the KV Saarland.

What is REAL here (from general knowledge, not looked up):
  * the 6 Kreise of the Saarland with their 5-digit AGS and seats, the 52 Gemeinden
  * the structure of LANR/BSNR, the EBM chapter structure, ICD-10-GM chapter ranges
  * the Kassenarten and the names of Krankenkassen active in the Saarland
  * the Saarland public holidays 2025

What is APPROXIMATE or SIMPLIFIED (see docs/assumptions.md):
  * population numbers (rounded, from memory) and the age split
  * Verhaeltniszahlen, EBM points, Pruefzeiten, Richtgroessen (example values)
  * the selection of ICD codes and GOPs (verify against the official catalogues)
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date

KV_NAME = "Kassenärztliche Vereinigung Saarland"
KV_CODE = "73"            # KV-Bereich code = first two digits of a BSNR (assumption, verify)
LAND_NAME = "Saarland"
POPULATION_STICHTAG = date(2024, 12, 31)
ORIENTIERUNGSWERT = {2025: 0.123934}   # EUR per EBM point (approx. 12.3934 Cent)
VERWALTUNGSKOSTENSATZ = 0.025          # KV administration fee on fees (assumption)
OPEN_END = date(9999, 12, 31)          # convention for "valid until further notice"


# --------------------------------------------------------------------------- region
@dataclass(frozen=True)
class Kreis:
    ags: str
    name: str            # "GEN" in official geodata
    kreisart: str        # "BEZ" in official geodata
    sitz: str            # seat of the administration
    lat: float           # approximate coordinates of the seat
    lon: float
    einwohner: int       # approximate, rounded
    gemeinden: tuple[tuple[str, int], ...] = field(default=())  # (name, weight ~ population in 1000)


KREISE: list[Kreis] = [
    Kreis("10041", "Regionalverband Saarbrücken", "Regionalverband", "Saarbrücken", 49.2354, 6.9965, 329_000,
          (("Saarbrücken", 180), ("Völklingen", 39), ("Püttlingen", 19), ("Heusweiler", 18),
           ("Sulzbach/Saar", 16), ("Riegelsberg", 14), ("Quierschied", 13), ("Kleinblittersdorf", 11),
           ("Friedrichsthal", 10), ("Großrosseln", 8))),
    Kreis("10042", "Merzig-Wadern", "Landkreis", "Merzig", 49.4433, 6.6378, 103_000,
          (("Merzig", 30), ("Wadern", 16), ("Losheim am See", 16), ("Beckingen", 15),
           ("Mettlach", 12), ("Perl", 9), ("Weiskirchen", 6))),
    Kreis("10043", "Neunkirchen", "Landkreis", "Ottweiler", 49.4010, 7.1630, 131_000,
          (("Neunkirchen", 46), ("Eppelborn", 17), ("Illingen", 16), ("Schiffweiler", 15),
           ("Ottweiler", 14), ("Spiesen-Elversberg", 13), ("Merchweiler", 10))),
    Kreis("10044", "Saarlouis", "Landkreis", "Saarlouis", 49.3135, 6.7524, 196_000,
          (("Saarlouis", 35), ("Dillingen/Saar", 20), ("Lebach", 19), ("Schwalbach", 17),
           ("Wadgassen", 17), ("Schmelz", 15), ("Rehlingen-Siersburg", 14), ("Saarwellingen", 13),
           ("Überherrn", 11), ("Nalbach", 9), ("Wallerfangen", 9), ("Bous", 7), ("Ensdorf", 6))),
    Kreis("10045", "Saarpfalz-Kreis", "Landkreis", "Homburg", 49.3266, 7.3386, 142_000,
          (("Homburg", 42), ("St. Ingbert", 35), ("Blieskastel", 20), ("Bexbach", 18),
           ("Mandelbachtal", 11), ("Kirkel", 10), ("Gersheim", 6))),
    Kreis("10046", "St. Wendel", "Landkreis", "St. Wendel", 49.4669, 7.1686, 87_000,
          (("St. Wendel", 26), ("Tholey", 12), ("Marpingen", 10), ("Nohfelden", 10),
           ("Nonnweiler", 8), ("Freisen", 8), ("Namborn", 7), ("Oberthal", 6))),
]
KREIS_BY_AGS = {k.ags: k for k in KREISE}


@dataclass(frozen=True)
class Altersgruppe:
    code: str
    label_statistik: str   # label used by the statistics office
    von: int
    bis: int | None
    share: float           # share of population (approx.)
    share_female: float


ALTERSGRUPPEN: list[Altersgruppe] = [
    Altersgruppe("00-05", "unter 6 Jahre", 0, 5, 0.050, 0.49),
    Altersgruppe("06-17", "6 bis unter 18 Jahre", 6, 17, 0.105, 0.49),
    Altersgruppe("18-39", "18 bis unter 40 Jahre", 18, 39, 0.245, 0.49),
    Altersgruppe("40-64", "40 bis unter 65 Jahre", 40, 64, 0.345, 0.50),
    Altersgruppe("65-74", "65 bis unter 75 Jahre", 65, 74, 0.125, 0.52),
    Altersgruppe("75+", "75 Jahre und mehr", 75, None, 0.130, 0.58),
]


def altersgruppe_for_age(age: int) -> Altersgruppe:
    for ag in ALTERSGRUPPEN:
        if ag.bis is None or age <= ag.bis:
            if age >= ag.von:
                return ag
    raise ValueError(age)


# ------------------------------------------------------------ physicians & planning
@dataclass(frozen=True)
class Arztgruppe:
    code: str
    name: str
    versorgungsebene: str
    planungsbereich_typ: str      # KREIS or ROR (Raumordnungsregion)
    verhaeltniszahl: int          # inhabitants per doctor (simplified, total population)
    fachgruppen: tuple[str, ...]
    tss_fachgebiet: str           # label used by the Terminservice API
    share_female: float


ARZTGRUPPEN: list[Arztgruppe] = [
    Arztgruppe("HA", "Hausärzte", "hausärztliche Versorgung", "KREIS", 1609, ("01", "03"), "Hausarzt", 0.52),
    Arztgruppe("KI", "Kinder- und Jugendärzte", "allgemeine fachärztliche Versorgung", "KREIS", 14000, ("34",), "Kinder- und Jugendmedizin", 0.65),
    Arztgruppe("AU", "Augenärzte", "allgemeine fachärztliche Versorgung", "KREIS", 19000, ("05",), "Augenheilkunde", 0.50),
    Arztgruppe("FR", "Frauenärzte", "allgemeine fachärztliche Versorgung", "KREIS", 7500, ("15",), "Frauenheilkunde", 0.75),
    Arztgruppe("HN", "HNO-Ärzte", "allgemeine fachärztliche Versorgung", "KREIS", 23000, ("19",), "Hals-Nasen-Ohren-Heilkunde", 0.35),
    Arztgruppe("HT", "Hautärzte", "allgemeine fachärztliche Versorgung", "KREIS", 28000, ("21",), "Dermatologie", 0.62),
    Arztgruppe("OR", "Orthopäden", "allgemeine fachärztliche Versorgung", "KREIS", 19000, ("10",), "Orthopädie", 0.18),
    Arztgruppe("NE", "Nervenärzte", "allgemeine fachärztliche Versorgung", "KREIS", 21000, ("51",), "Neurologie/Nervenheilkunde", 0.45),
    Arztgruppe("PT", "Psychotherapeuten", "allgemeine fachärztliche Versorgung", "KREIS", 4000, ("68",), "Psychotherapie", 0.76),
    Arztgruppe("FI", "Fachinternisten", "spezialisierte fachärztliche Versorgung", "ROR", 12000, ("23",), "Innere Medizin", 0.35),
]
ARZTGRUPPE_BY_CODE = {g.code: g for g in ARZTGRUPPEN}

# Fachgruppe code (= digits 8-9 of the LANR), modelled on the KBV Arztgruppenschluessel.
FACHGRUPPEN: list[tuple[str, str, str]] = [
    ("01", "Allgemeinmedizin", "HA"),
    ("03", "Innere Medizin (hausärztlich)", "HA"),
    ("05", "Augenheilkunde", "AU"),
    ("10", "Orthopädie", "OR"),
    ("15", "Frauenheilkunde und Geburtshilfe", "FR"),
    ("19", "Hals-Nasen-Ohrenheilkunde", "HN"),
    ("21", "Haut- und Geschlechtskrankheiten", "HT"),
    ("23", "Innere Medizin (fachärztlich)", "FI"),
    ("34", "Kinder- und Jugendmedizin", "KI"),
    ("51", "Nervenheilkunde", "NE"),
    ("68", "Psychologische Psychotherapie", "PT"),
]

# Target supply level (Versorgungsgrad) on 2025-01-01 used to size the doctor population.
# Hausaerzte: explicit values (rural Kreise lower); other groups: drawn from ranges.
HA_TARGET_VG = {"10041": 1.08, "10042": 0.84, "10043": 0.97, "10044": 1.03, "10045": 1.01, "10046": 0.73}
FA_TARGET_VG_CITY = (1.15, 1.55)   # Regionalverband Saarbruecken
FA_TARGET_VG_OTHER = (0.92, 1.30)
FI_TARGET_VG = 1.18

UEBERVERSORGUNG_PCT = 110.0
UNTERVERSORGUNG_PCT = {"HA": 75.0}   # all other groups: 50 %
UNTERVERSORGUNG_DEFAULT_PCT = 50.0

KOOPERATIONSFORMEN = [
    ("EP", "Einzelpraxis"),
    ("BAG", "Berufsausübungsgemeinschaft"),
    ("MVZ", "Medizinisches Versorgungszentrum"),
]
TEILNAHMEFORMEN = [
    ("ZUL", "Zulassung (Vertragsarzt / Vertragspsychotherapeut)"),
    ("ANG", "Anstellung (angestellte Ärztin / angestellter Arzt)"),
]

# ------------------------------------------------------------------------- billing
KASSENARTEN = [
    ("AOK", "Allgemeine Ortskrankenkasse"),
    ("BKK", "Betriebskrankenkasse"),
    ("IKK", "Innungskrankenkasse"),
    ("EK", "Ersatzkasse"),
    ("KN", "Knappschaft"),
    ("LKK", "Landwirtschaftliche Krankenkasse"),
]
# (name, Kassenart, approximate market share in the simulation)
KRANKENKASSEN = [
    ("AOK Rheinland-Pfalz/Saarland", "AOK", 0.30),
    ("IKK Südwest", "IKK", 0.12),
    ("Techniker Krankenkasse", "EK", 0.14),
    ("BARMER", "EK", 0.11),
    ("DAK-Gesundheit", "EK", 0.08),
    ("KKH Kaufmännische Krankenkasse", "EK", 0.03),
    ("hkk Krankenkasse", "EK", 0.02),
    ("Knappschaft", "KN", 0.09),
    ("Mobil Krankenkasse", "BKK", 0.04),
    ("SBK Siemens-Betriebskrankenkasse", "BKK", 0.03),
    ("SVLFG Landwirtschaftliche Krankenkasse", "LKK", 0.01),
]

SCHEINUNTERGRUPPEN = [
    ("00", "Ambulante Behandlung"),
    ("24", "Mit-/Weiterbehandlung (Überweisung)"),
    ("43", "Notfall"),
]

QS_BEREICHE = [
    ("US", "Ultraschalldiagnostik", "Ultraschall-Vereinbarung nach § 135 Abs. 2 SGB V"),
    ("KOLO", "Koloskopie", "Qualitätssicherungsvereinbarung zur Koloskopie nach § 135 Abs. 2 SGB V"),
    ("AKU", "Akupunktur", "Qualitätssicherungsvereinbarung Akupunktur bei chronisch schmerzkranken Patienten"),
    ("HKS", "Hautkrebs-Screening", "Krebsfrüherkennungs-Richtlinie des G-BA (Genehmigung durch die KV)"),
]

# EBM chapters: (number, Bereich, shortened title)
EBM_KAPITEL = [
    (1, "II", "Allgemeine Gebührenordnungspositionen"),
    (3, "III.a", "Hausärztlicher Versorgungsbereich"),
    (4, "III.a", "Versorgungsbereich Kinder- und Jugendmedizin"),
    (6, "III.b", "Augenheilkunde"),
    (8, "III.b", "Frauenheilkunde und Geburtshilfe"),
    (9, "III.b", "Hals-Nasen-Ohrenheilkunde"),
    (10, "III.b", "Dermatologie"),
    (13, "III.b", "Innere Medizin (fachärztlich)"),
    (16, "III.b", "Neurologie und Nervenheilkunde"),
    (18, "III.b", "Orthopädie"),
    (23, "III.b", "Psychotherapie (Psychotherapeuten)"),
    (30, "IV", "Spezielle Versorgungsbereiche"),
    (33, "IV", "Ultraschalldiagnostik"),
    (35, "IV", "Leistungen gemäß Psychotherapie-Richtlinie"),
]


@dataclass(frozen=True)
class Gop:
    code: str
    titel: str
    kapitel: int
    punkte: int
    pruefzeit_min: int | None   # None = no Pruefzeit ("keine Angabe")
    extrabudgetaer: bool
    qs: str | None


GOPS: list[Gop] = [
    Gop("01100", "Unvorhergesehene Inanspruchnahme I", 1, 196, None, False, None),
    Gop("01410", "Besuch eines Kranken", 1, 213, 20, False, None),
    Gop("01732", "Gesundheitsuntersuchung bei Erwachsenen", 1, 300, 20, True, None),
    Gop("01741", "Früherkennungskoloskopie", 1, 1700, 30, True, "KOLO"),
    Gop("01745", "Früherkennungsuntersuchung auf Hautkrebs", 1, 270, 10, True, "HKS"),
    Gop("01760", "Krebsfrüherkennung bei der Frau", 1, 230, 12, True, None),
    Gop("03000", "Versichertenpauschale (hausärztlich)", 3, 150, 12, False, None),
    Gop("03040", "Zuschlag zur Versichertenpauschale (Vorhaltepauschale)", 3, 138, None, False, None),
    Gop("03220", "Zuschlag Behandlung chronisch Kranker (Chronikerpauschale I)", 3, 130, 4, False, None),
    Gop("03221", "Zuschlag Chronikerpauschale II", 3, 40, 1, False, None),
    Gop("03230", "Problemorientiertes ärztliches Gespräch", 3, 128, 10, False, None),
    Gop("03321", "Belastungs-Elektrokardiographie", 3, 196, 10, False, None),
    Gop("04000", "Versichertenpauschale (Kinder- und Jugendmedizin)", 4, 250, 12, False, None),
    Gop("04230", "Problemorientiertes ärztliches Gespräch (Kinder- und Jugendmedizin)", 4, 128, 10, False, None),
    Gop("13250", "Zusatzpauschale fachinternistische Behandlung", 13, 150, 7, False, None),
    Gop("30790", "Eingangsdiagnostik und Abschlussuntersuchung Körperakupunktur", 30, 450, 20, False, "AKU"),
    Gop("30791", "Durchführung einer Körperakupunktur", 30, 200, 20, False, "AKU"),
    Gop("33042", "Sonographie des Abdomens", 33, 145, 10, False, "US"),
    Gop("35150", "Probatorische Sitzung", 35, 860, 70, True, None),
    Gop("35151", "Psychotherapeutische Sprechstunde", 35, 860, 70, True, None),
    Gop("35401", "Verhaltenstherapie Kurzzeittherapie, Einzelbehandlung", 35, 945, 70, True, None),
]

# Grundpauschalen exist in three age bands per chapter: xx210 (to 5), xx211 (6-59), xx212 (from 60).
GRUNDPAUSCHALE_KAPITEL = {
    "AU": (6, "Augenheilkunde", 112, 6),
    "FR": (8, "Frauenheilkunde", 135, 7),
    "HN": (9, "Hals-Nasen-Ohrenheilkunde", 118, 7),
    "HT": (10, "Dermatologie", 102, 6),
    "FI": (13, "Innere Medizin (fachärztlich)", 180, 9),
    "NE": (16, "Nervenheilkunde", 160, 9),
    "OR": (18, "Orthopädie", 130, 7),
    "PT": (23, "Psychotherapie", 140, 8),
}
_AGE_BANDS = (("0", "bis 5. Lebensjahr", 1.10), ("1", "6. bis 59. Lebensjahr", 1.00), ("2", "ab 60. Lebensjahr", 1.08))
for _grp, (_kap, _fach, _pkt, _pz) in GRUNDPAUSCHALE_KAPITEL.items():
    for _digit, _label, _factor in _AGE_BANDS:
        GOPS.append(Gop(f"{_kap:02d}21{_digit}", f"Grundpauschale {_fach}, {_label}", _kap,
                        round(_pkt * _factor), _pz, False, None))
GOPS.sort(key=lambda g: g.code)
GOP_BY_CODE = {g.code: g for g in GOPS}


def grundpauschale_code(arztgruppe: str, age: int) -> str:
    kap = GRUNDPAUSCHALE_KAPITEL[arztgruppe][0]
    digit = "0" if age <= 5 else ("1" if age <= 59 else "2")
    return f"{kap:02d}21{digit}"


# Billing profile per Arztgruppe: base GOPs (always) + optional GOPs
# optional entry: (gop, probability, min count, max count, required other gop or None)
BASIS = {
    "HA": ["03000", "03040"],
    "KI": ["04000"],
}
OPTIONAL: dict[str, list[tuple[str, float, int, int, str | None]]] = {
    "HA": [("03220", .40, 1, 1, None), ("03221", .80, 1, 1, "03220"), ("03230", .25, 1, 3, None),
           ("03321", .03, 1, 1, None), ("01732", .08, 1, 1, None), ("01745", .05, 1, 1, None),
           ("33042", .07, 1, 1, None), ("30791", .02, 3, 8, None), ("01410", .06, 1, 3, None),
           ("01100", .03, 1, 1, None)],
    "KI": [("04230", .20, 1, 2, None), ("01100", .04, 1, 1, None)],
    "AU": [("01100", .02, 1, 1, None)],
    "FR": [("01760", .30, 1, 1, None)],
    "HN": [("01100", .02, 1, 1, None)],
    "HT": [("01745", .18, 1, 1, None)],
    "OR": [("30790", .03, 1, 1, None), ("30791", .05, 3, 8, None), ("33042", .02, 1, 1, None)],
    "NE": [("01100", .02, 1, 1, None)],
    "PT": [("35151", .30, 1, 2, None), ("35150", .30, 1, 4, None), ("35401", .40, 3, 10, None)],
    "FI": [("13250", .40, 1, 1, None), ("33042", .30, 1, 1, None), ("01741", .04, 1, 1, None)],
}

# Share of doctors per group holding a QS-Genehmigung (permit) per area
QS_GENEHMIGUNG_QUOTE = {
    "HA": {"US": .35, "HKS": .45, "AKU": .05},
    "FI": {"US": .85, "KOLO": .25},
    "OR": {"AKU": .20, "US": .30},
    "HT": {"HKS": .95},
}

# ICD-10-GM selection (simplified, verify against the official catalogue)
ICD_TITLES = {
    "A09.9": "Sonstige und nicht näher bezeichnete Gastroenteritis und Kolitis nicht näher bezeichneten Ursprungs",
    "B35.1": "Tinea unguium",
    "D22.9": "Melanozytennävus, nicht näher bezeichnet",
    "E11.90": "Diabetes mellitus, Typ 2: Ohne Komplikationen: Nicht als entgleist bezeichnet",
    "E78.0": "Reine Hypercholesterinämie",
    "F32.1": "Mittelgradige depressive Episode",
    "F32.9": "Depressive Episode, nicht näher bezeichnet",
    "F33.1": "Rezidivierende depressive Störung, gegenwärtig mittelgradige Episode",
    "F40.1": "Soziale Phobien",
    "F41.1": "Generalisierte Angststörung",
    "F43.1": "Posttraumatische Belastungsstörung",
    "F43.2": "Anpassungsstörungen",
    "G40.9": "Epilepsie, nicht näher bezeichnet",
    "G43.9": "Migräne, nicht näher bezeichnet",
    "G62.9": "Polyneuropathie, nicht näher bezeichnet",
    "H10.9": "Konjunktivitis, nicht näher bezeichnet",
    "H25.9": "Senile Katarakt, nicht näher bezeichnet",
    "H35.3": "Degeneration der Makula und des hinteren Poles",
    "H40.1": "Primäres Weitwinkelglaukom",
    "H52.4": "Presbyopie",
    "H61.2": "Zeruminalpfropf",
    "H66.9": "Otitis media, nicht näher bezeichnet",
    "H90.3": "Hörverlust durch Schallempfindungsstörung, beidseitig",
    "H93.1": "Tinnitus aurium",
    "I10.90": "Essentielle Hypertonie, nicht näher bezeichnet: Ohne Angabe einer hypertensiven Krise",
    "I25.9": "Chronische ischämische Herzkrankheit, nicht näher bezeichnet",
    "I48.9": "Vorhofflimmern und Vorhofflattern, nicht näher bezeichnet",
    "J02.9": "Akute Pharyngitis, nicht näher bezeichnet",
    "J06.9": "Akute Infektion der oberen Atemwege, nicht näher bezeichnet",
    "J20.9": "Akute Bronchitis, nicht näher bezeichnet",
    "J32.9": "Chronische Sinusitis, nicht näher bezeichnet",
    "K21.9": "Gastroösophageale Refluxkrankheit ohne Ösophagitis",
    "K29.7": "Gastritis, nicht näher bezeichnet",
    "L20.9": "Atopisches [endogenes] Ekzem, nicht näher bezeichnet",
    "L40.0": "Psoriasis vulgaris",
    "L70.0": "Acne vulgaris",
    "M16.9": "Koxarthrose, nicht näher bezeichnet",
    "M17.9": "Gonarthrose, nicht näher bezeichnet",
    "M51.2": "Sonstige näher bezeichnete Bandscheibenverlagerung",
    "M54.4": "Lumboischialgie",
    "M75.1": "Läsionen der Rotatorenmanschette",
    "N39.0": "Harnwegsinfektion, Lokalisation nicht näher bezeichnet",
    "N76.0": "Akute Kolpitis",
    "N95.1": "Zustände im Zusammenhang mit der Menopause und dem Klimakterium",
    "R10.4": "Sonstige und nicht näher bezeichnete Bauchschmerzen",
    "R51": "Kopfschmerz",
    "Z00.0": "Ärztliche Allgemeinuntersuchung",
    "Z00.1": "Gesundheitsvorsorgeuntersuchung eines Kindes",
    "Z12.1": "Spezielle Verfahren zur Untersuchung auf Neubildung des Darmtraktes",
    "Z12.4": "Spezielle Verfahren zur Untersuchung auf Neubildung der Cervix uteri",
    "Z30.9": "Kontrazeptive Maßnahme, nicht näher bezeichnet",
    "Z34": "Überwachung einer normalen Schwangerschaft",
}
DIAGNOSEN: dict[str, list[str]] = {
    "HA": ["I10.90", "E11.90", "E78.0", "J06.9", "M54.4", "K21.9", "F32.9", "Z00.0", "R51", "N39.0", "I25.9"],
    "KI": ["J06.9", "J20.9", "H66.9", "Z00.1", "A09.9", "L20.9"],
    "AU": ["H52.4", "H40.1", "H25.9", "H10.9", "H35.3"],
    "FR": ["Z12.4", "N95.1", "Z30.9", "N76.0", "Z34"],
    "HN": ["J32.9", "H61.2", "J02.9", "H93.1", "H90.3"],
    "HT": ["L40.0", "L20.9", "L70.0", "D22.9", "B35.1"],
    "OR": ["M17.9", "M16.9", "M75.1", "M51.2", "M54.4"],
    "NE": ["G43.9", "G40.9", "F32.9", "G62.9", "R51"],
    "PT": ["F32.1", "F33.1", "F41.1", "F43.1", "F43.2", "F40.1"],
    "FI": ["K21.9", "K29.7", "Z12.1", "I48.9", "E11.90", "R10.4"],
}

# ICD-10-GM chapters (real ranges)
ICD_KAPITEL = [
    ("I", "A00", "B99"), ("II", "C00", "D48"), ("III", "D50", "D90"), ("IV", "E00", "E90"),
    ("V", "F00", "F99"), ("VI", "G00", "G99"), ("VII", "H00", "H59"), ("VIII", "H60", "H95"),
    ("IX", "I00", "I99"), ("X", "J00", "J99"), ("XI", "K00", "K93"), ("XII", "L00", "L99"),
    ("XIII", "M00", "M99"), ("XIV", "N00", "N99"), ("XV", "O00", "O99"), ("XVI", "P00", "P96"),
    ("XVII", "Q00", "Q99"), ("XVIII", "R00", "R99"), ("XIX", "S00", "T98"), ("XX", "V01", "Y84"),
    ("XXI", "Z00", "Z99"), ("XXII", "U00", "U99"),
]


def icd_kapitel(code: str) -> str:
    key = code[:3]
    for kap, lo, hi in ICD_KAPITEL:
        if lo <= key <= hi:
            return kap
    raise ValueError(code)


# ---------------------------------------------------------------- prescriptions
# Richtgroesse in EUR per case (simplified example values)
RICHTGROESSEN = {
    "A": {"HA": 62, "KI": 24, "AU": 28, "FR": 18, "HN": 14, "HT": 26, "OR": 22, "NE": 115, "FI": 125},
    "H": {"HA": 9, "OR": 38, "NE": 16, "KI": 12, "HN": 7},
}

# ------------------------------------------------------------------ care provision
# One Bereitschaftsdienstpraxis per Kreis (simplification, real locations not verified)
BEREITSCHAFTSPRAXEN = [
    ("BDP-SB", "Saarbrücken", "10041"),
    ("BDP-MZG", "Merzig", "10042"),
    ("BDP-NK", "Neunkirchen", "10043"),
    ("BDP-SLS", "Saarlouis", "10044"),
    ("BDP-HOM", "Homburg", "10045"),
    ("BDP-WND", "St. Wendel", "10046"),
]

# Saarland public holidays 2025 (Easter Sunday 2025 = 20 April)
FEIERTAGE_2025 = {
    date(2025, 1, 1): "Neujahr",
    date(2025, 4, 18): "Karfreitag",
    date(2025, 4, 21): "Ostermontag",
    date(2025, 5, 1): "Tag der Arbeit",
    date(2025, 5, 29): "Christi Himmelfahrt",
    date(2025, 6, 9): "Pfingstmontag",
    date(2025, 6, 19): "Fronleichnam",
    date(2025, 8, 15): "Mariä Himmelfahrt",
    date(2025, 10, 3): "Tag der Deutschen Einheit",
    date(2025, 11, 1): "Allerheiligen",
    date(2025, 12, 25): "1. Weihnachtsfeiertag",
    date(2025, 12, 26): "2. Weihnachtsfeiertag",
}

TSS_WARTEZEIT_BASIS_TAGE = {"HA": 2, "KI": 5, "AU": 16, "FR": 12, "HN": 9, "HT": 15, "OR": 12, "NE": 18, "PT": 24, "FI": 20}
TSS_GRUPPEN_GEWICHT = {"PT": .25, "AU": .12, "HT": .10, "OR": .10, "NE": .10, "HA": .10, "FR": .08, "HN": .08, "FI": .05, "KI": .02}
