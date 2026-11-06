"""Builds one consistent synthetic 'world' of the KV Saarland in memory.

Design idea: there is ONE truth (this module). writers.py then exports that truth into
many heterogeneous source formats - exactly like real source systems that each hold a
slice of the same reality. Because everything comes from one truth, the data warehouse
can later reconcile the sources against each other (e.g. Honorarbescheid vs. billing lines).

Reproducibility: every random decision uses self.rng (random.Random(seed)) and Faker is
seeded with the same seed. Same seed + same code = same data.
"""
from __future__ import annotations

import math
import random
import uuid
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta

from faker import Faker

from . import ids
from . import reference as ref
from . import texts
from .config import Settings

OPEN_END = ref.OPEN_END
ZULASSUNG_EXPORT_DATE = date(2026, 1, 5)   # the Zulassung XML is a year-end export


# =========================================================================== helpers
def quarter_start(year: int, q: int) -> date:
    return date(year, 3 * (q - 1) + 1, 1)


def quarter_end_excl(year: int, q: int) -> date:
    return date(year + 1, 1, 1) if q == 4 else date(year, 3 * q + 1, 1)


def quarter_of(d: date) -> int:
    return (d.month - 1) // 3 + 1


def first_of_quarter(d: date) -> date:
    return date(d.year, 3 * (quarter_of(d) - 1) + 1, 1)


def add_months(d: date, n: int) -> date:
    m = d.month - 1 + n
    return date(d.year + m // 12, m % 12 + 1, 1)


def is_holiday(d: date) -> bool:
    return d in ref.FEIERTAGE_2025 or (d.month == 1 and d.day == 1)


def is_workday(d: date) -> bool:
    return d.weekday() < 5 and not is_holiday(d)


def third_wednesday(year: int, month: int) -> date:
    d = date(year, month, 1)
    return d + timedelta(days=(2 - d.weekday()) % 7 + 14)


def poisson(rng: random.Random, lam: float) -> int:
    if lam <= 0:
        return 0
    limit, k, p = math.exp(-lam), 0, 1.0
    while True:
        k += 1
        p *= rng.random()
        if p <= limit:
            return k - 1


def kreis_display_name(k: ref.Kreis) -> str:
    if k.kreisart == "Landkreis" and not k.name.endswith("Kreis"):
        return f"Landkreis {k.name}"
    return k.name


# =========================================================================== model
@dataclass
class Arzt:
    idx: int
    lanr: str
    efn: str
    titel: str
    vorname: str
    nachname: str
    geschlecht: str
    geburtsjahr: int
    fachgruppe: str
    arztgruppe: str
    kreis_ags: str
    teilnahmen: list["Teilnahme"] = field(default_factory=list)

    @property
    def display_name(self) -> str:
        return " ".join(p for p in (self.titel, self.vorname, self.nachname) if p)


@dataclass
class Praxis:
    bsnr: str
    name: str
    kooperationsform: str
    strasse: str
    ort: str
    kreis_ags: str
    gruendungsdatum: date
    main_group: str
    hochabrechner: bool = False
    hochverordner: bool = False
    teilnahmen: list["Teilnahme"] = field(default_factory=list)


@dataclass
class Periode:
    status: str
    von: date
    bis: date


@dataclass
class Teilnahme:
    arzt: Arzt
    praxis: Praxis
    form: str
    faktor: float
    von: date
    bis: date = OPEN_END
    ruhend: list[tuple[date, date]] = field(default_factory=list)
    status: list[Periode] = field(default_factory=list)

    def finalize_status(self) -> None:
        periods, cursor = [], self.von
        for rs, re_ in sorted(self.ruhend):
            if cursor < rs:
                periods.append(Periode("AKTIV", cursor, rs))
            periods.append(Periode("RUHEND", rs, re_))
            cursor = re_
        if cursor < self.bis:
            periods.append(Periode("AKTIV", cursor, self.bis))
        if self.bis != OPEN_END:
            periods.append(Periode("BEENDET", self.bis, OPEN_END))
        self.status = periods

    def active_on(self, d: date) -> bool:
        return any(p.status == "AKTIV" and p.von <= d < p.bis for p in self.status)


@dataclass
class Verfahren:
    art: str
    arzt: Arzt
    praxis: Praxis | None
    pb_code: str
    antrag: date
    sitzung: date | None
    ergebnis: str
    wirksam_ab: date | None
    wirksam_bis: date | None
    teilnahme: Teilnahme | None
    status: list[tuple[str, date]]
    aktenzeichen: str = ""
    bescheid_datum: date | None = None
    bescheid_text: str | None = None

    @property
    def arztgruppe_name(self) -> str:
        return ref.ARZTGRUPPE_BY_CODE[self.arzt.arztgruppe].name


@dataclass(frozen=True)
class Kasse:
    ik: str
    name: str
    kassenart: str


@dataclass
class Patient:
    pseudonym: str
    kreis_ags: str
    geburtsjahr: int
    geschlecht: str
    kasse_ik: str
    status: str


@dataclass
class Leistung:
    datum: date
    arzt: Arzt
    gop: str
    anzahl: int
    berichtigt: bool


@dataclass
class Fall:
    praxis: Praxis
    quartal: int
    patient: Patient
    scheinuntergruppe: str
    tss_code: str | None
    hauptarzt: Arzt
    leistungen: list[Leistung]
    diagnosen: list[tuple[str, str]]
    fallnummer: str = ""


@dataclass
class Honorarbescheid:
    nr: str
    praxis: Praxis
    quartal: int
    datum: date
    punkte_angefordert: int
    punkte_berichtigt: int
    punkte_mgv: int
    punkte_egv: int
    quote_mgv: float | None
    betrag_mgv: float
    betrag_egv: float
    brutto: float
    verwaltungskosten: float
    abschlaege: float
    auszahlung: float


@dataclass
class Abschlag:
    praxis: Praxis
    quartal: int
    nr: int
    datum: date
    betrag: float


@dataclass
class Verordnung:
    praxis: Praxis
    quartal: int
    art: str
    anzahl: int
    brutto: float
    rgv: float     # Richtgroessenvolumen (only used to derive Pruefverfahren; not exported)


@dataclass
class Pruefverfahren:
    aktenzeichen: str
    praxis: Praxis
    quartal: int
    gegenstand: str
    anlass: str
    eingeleitet: date
    status: str
    abgeschlossen: date | None
    massnahme: str | None
    betrag: float | None


@dataclass
class TssAnfrage:
    uuid: str
    eingang: datetime
    kanal: str
    arztgruppe: str
    dringlichkeit: str
    patient: Patient
    alter: int
    status: str
    praxis: Praxis | None = None
    termin: datetime | None = None
    code: str | None = None
    wahrgenommen: bool | None = None


@dataclass
class Dienst:
    dienst_id: str
    kennung: str
    beginn: datetime
    ende: datetime
    arzt: Arzt
    getauscht_von: Arzt | None


@dataclass
class Anfrage:
    ticket_id: str
    erstellt: datetime
    kanal: str
    thema: str
    arzt: Arzt
    praxis: Praxis
    betreff: str
    text: str
    status: str
    erledigt: datetime | None


@dataclass
class Beschwerde:
    nr: int
    eingang: date
    kanal: str
    kategorie: str
    praxis: Praxis
    betreff: str
    text: str


@dataclass
class World:
    settings: Settings
    planungsbereiche: list[tuple[str, str, str, list[str]]]
    einwohner: list[tuple[str, str, str, int]]
    kassen: list[Kasse]
    aerzte: list[Arzt]
    praxen: list[Praxis]
    teilnahmen: list[Teilnahme]
    verfahren: list[Verfahren]
    versorgungsgrade: list[dict]
    qs_genehmigungen: list[tuple[Arzt, str, date, date]]
    faelle: list[Fall]
    honorar: list[Honorarbescheid]
    abschlaege: list[Abschlag]
    verordnungen: list[Verordnung]
    pruefverfahren: list[Pruefverfahren]
    tss: list[TssAnfrage]
    dienste: list[Dienst]
    fortbildung: list[tuple[Arzt, int, int]]
    anfragen: list[Anfrage]
    beschwerden: list[Beschwerde]
    sitzungen: list[date]


# Patient age-group weights per Arztgruppe (who visits which specialty)
AGE_WEIGHTS = {
    "KI": {"00-05": .45, "06-17": .55},
    "PT": {"18-39": .45, "40-64": .45, "65-74": .07, "75+": .03},
    "FR": {"18-39": .45, "40-64": .40, "65-74": .10, "75+": .05},
    "AU": {"00-05": .02, "06-17": .06, "18-39": .12, "40-64": .30, "65-74": .22, "75+": .28},
    "HA": {"06-17": .03, "18-39": .20, "40-64": .34, "65-74": .19, "75+": .24},
    "default": {"06-17": .08, "18-39": .25, "40-64": .37, "65-74": .15, "75+": .15},
}
MIN_AGE = {"01732": 35, "01741": 50, "01745": 35, "03321": 18, "03220": 18}
PRAXIS_PREFIX = {
    "HA": "Hausarztpraxis", "KI": "Kinder- und Jugendarztpraxis", "AU": "Augenarztpraxis",
    "FR": "Frauenarztpraxis", "HN": "HNO-Praxis", "HT": "Hautarztpraxis", "OR": "Orthopädische Praxis",
    "NE": "Nervenärztliche Praxis", "PT": "Psychotherapeutische Praxis", "FI": "Internistische Praxis",
}


# =========================================================================== builder
class WorldBuilder:
    def __init__(self, settings: Settings):
        self.s = settings
        self.year = settings.year
        self.rng = random.Random(settings.seed)
        self.fake = Faker("de_DE")
        self.fake.seed_instance(settings.seed)
        self._doc_ids = iter(self.rng.sample(range(100_000, 1_000_000), 5000))
        self._bsnr_serials = iter(self.rng.sample(range(1_000_000, 10_000_000), 4000))
        self._efns: set[str] = set()
        self._mvz_names: dict[str, int] = {}
        self.mvz_by_kreis: dict[str, list[Praxis]] = {k.ags: [] for k in ref.KREISE}
        self.aerzte: list[Arzt] = []
        self.praxen: list[Praxis] = []
        self.teilnahmen: list[Teilnahme] = []
        self.verfahren: list[Verfahren] = []
        self._active_days_cache: dict[tuple[int, int], list[date]] = {}
        self.planungsbereiche = (
            [(f"PB{k.ags}", kreis_display_name(k), "KREIS", [k.ags]) for k in ref.KREISE]
            + [("PB10", "Raumordnungsregion Saar", "ROR", [k.ags for k in ref.KREISE])]
        )

    # ------------------------------------------------------------------ entry point
    def build(self) -> World:
        y = self.year
        self.build_population()
        self.build_kassen()
        self.build_doctors_and_practices()
        for t in self.teilnahmen:
            t.finalize_status()
        self.initial_vg = {(r["pb_code"], r["arztgruppe"]): r for r in self.compute_versorgungsgrade(date(y, 1, 1))}
        self.sitzungen = [third_wednesday(y, m) for m in range(1, 13)] + [third_wednesday(y + 1, 1)]
        self.apply_events()
        for t in self.teilnahmen:
            t.finalize_status()
        self.number_verfahren()
        versorgungsgrade = [row for st in (date(y, 1, 1), date(y, 7, 1), date(y + 1, 1, 1))
                            for row in self.compute_versorgungsgrade(st)]
        self.build_qs_genehmigungen()
        self.build_patients()
        self.build_billing()
        self.build_tss()
        faelle = self.number_cases()
        honorar, abschlaege = self.build_honorar(faelle)
        verordnungen, pruefverfahren = self.build_verordnungen_and_pruefungen(faelle)
        dienste = self.build_bereitschaftsdienst()
        fortbildung = self.build_fortbildung()
        anfragen, beschwerden = self.build_communication(faelle, dienste)
        return World(
            settings=self.s, planungsbereiche=self.planungsbereiche, einwohner=self.einwohner,
            kassen=self.kassen, aerzte=self.aerzte, praxen=self.praxen, teilnahmen=self.teilnahmen,
            verfahren=self.verfahren, versorgungsgrade=versorgungsgrade,
            qs_genehmigungen=self.qs_genehmigungen, faelle=faelle, honorar=honorar,
            abschlaege=abschlaege, verordnungen=verordnungen, pruefverfahren=pruefverfahren,
            tss=self.tss, dienste=dienste, fortbildung=fortbildung, anfragen=anfragen,
            beschwerden=beschwerden, sitzungen=self.sitzungen,
        )

    # ------------------------------------------------------------------ region
    def build_population(self) -> None:
        rng = self.rng
        self.einwohner = []
        self.kreis_einwohner: dict[str, int] = {}
        self.einwohner_by_kreis_ag: dict[tuple[str, str], int] = {}
        for k in ref.KREISE:
            shares = []
            for ag in ref.ALTERSGRUPPEN:
                s = ag.share * rng.uniform(0.94, 1.06)
                if k.ags in ("10042", "10046") and ag.von >= 65:   # rural Kreise are a bit older
                    s *= 1.06
                shares.append(s)
            total_share = sum(shares)
            kreis_total = 0
            for ag, s in zip(ref.ALTERSGRUPPEN, shares):
                n = round(k.einwohner * s / total_share)
                w = round(n * ag.share_female * rng.uniform(0.98, 1.02))
                self.einwohner.append((k.ags, ag.code, "w", w))
                self.einwohner.append((k.ags, ag.code, "m", n - w))
                self.einwohner_by_kreis_ag[(k.ags, ag.code)] = n
                kreis_total += n
            self.kreis_einwohner[k.ags] = kreis_total

    def pick_kreis_by_population(self) -> str:
        kreise = list(self.kreis_einwohner)
        return self.rng.choices(kreise, weights=[self.kreis_einwohner[k] for k in kreise])[0]

    def pb_code_for(self, arztgruppe: str, kreis_ags: str) -> str:
        return "PB10" if ref.ARZTGRUPPE_BY_CODE[arztgruppe].planungsbereich_typ == "ROR" else f"PB{kreis_ags}"

    # ------------------------------------------------------------------ insurers
    def build_kassen(self) -> None:
        iks: list[str] = []
        while len(iks) < len(ref.KRANKENKASSEN):
            ik = ids.make_ik(self.rng)
            if ik not in iks:
                iks.append(ik)
        self.kassen = [Kasse(ik, name, art) for ik, (name, art, _) in zip(iks, ref.KRANKENKASSEN)]
        self.kassen_weights = [w for _, _, w in ref.KRANKENKASSEN]

    # ------------------------------------------------------------------ doctors & practices
    def pick_titel(self, group: str) -> str:
        r = self.rng.random()
        if group == "PT":
            return "Dipl.-Psych." if r < .45 else ("M. Sc. Psych." if r < .75 else ("Dr. phil." if r < .87 else ""))
        return "Dr. med." if r < .62 else ("Prof. Dr. med." if r < .63 else "")

    def new_arzt(self, group: str, kreis: str, age: int | None = None, fachgruppe: str | None = None) -> Arzt:
        rng = self.rng
        g = ref.ARZTGRUPPE_BY_CODE[group]
        female = rng.random() < g.share_female
        if age is None:
            age = min(72, max(33, round(rng.gauss(53, 9))))
        if fachgruppe is None:
            fachgruppe = g.fachgruppen[0] if len(g.fachgruppen) == 1 else ("01" if rng.random() < .75 else "03")
        vorname = self.fake.first_name_female() if female else self.fake.first_name_male()
        nachname = self.fake.last_name()
        efn = ids.make_efn(rng)
        while efn in self._efns:
            efn = ids.make_efn(rng)
        self._efns.add(efn)
        arzt = Arzt(
            idx=len(self.aerzte), lanr=ids.make_lanr(next(self._doc_ids), fachgruppe), efn=efn,
            titel=self.pick_titel(group), vorname=vorname, nachname=nachname,
            geschlecht="w" if female else "m", geburtsjahr=self.year - age,
            fachgruppe=fachgruppe, arztgruppe=group, kreis_ags=kreis,
        )
        self.aerzte.append(arzt)
        return arzt

    def career_start(self, arzt: Arzt) -> date:
        age = self.year - arzt.geburtsjahr
        max_years = max(0.6, min(age - 32, 30))
        years_back = self.rng.uniform(0.3, max_years)
        return first_of_quarter(date(self.year, 1, 1) - timedelta(days=int(years_back * 365.25)))

    def praxis_name(self, form: str, group: str, members: list[Arzt], ort: str) -> str:
        if form == "MVZ":
            n = self._mvz_names[ort] = self._mvz_names.get(ort, 0) + 1
            return f"MVZ {ort}" + ("" if n == 1 else f" {n}")
        if form == "BAG":
            return f"Gemeinschaftspraxis {' & '.join(a.nachname for a in members)} ({ref.ARZTGRUPPE_BY_CODE[group].name})"
        a = members[0]
        person = f"{a.titel} {a.nachname}" if a.titel else f"{a.vorname} {a.nachname}"
        return f"{PRAXIS_PREFIX[group]} {person}"

    def new_praxis(self, form: str, kreis: str, group: str, members: list[Arzt], gruendung: date) -> Praxis:
        rng = self.rng
        k = ref.KREIS_BY_AGS[kreis]
        exponent = 1.0 if group in ("HA", "KI") else (1.8 if form == "MVZ" else 1.6)
        orte = [g for g, _ in k.gemeinden]
        ort = rng.choices(orte, weights=[w ** exponent for _, w in k.gemeinden])[0]
        praxis = Praxis(
            bsnr=ids.make_bsnr(ref.KV_CODE, next(self._bsnr_serials)),
            name=self.praxis_name(form, group, members, ort), kooperationsform=form,
            strasse=f"{self.fake.street_name()} {rng.randint(1, 120)}", ort=ort, kreis_ags=kreis,
            gruendungsdatum=gruendung, main_group=group,
        )
        praxis.hochabrechner = rng.random() < 0.02
        praxis.hochverordner = rng.random() < 0.012
        self.praxen.append(praxis)
        if form == "MVZ":
            self.mvz_by_kreis[kreis].append(praxis)
        return praxis

    def new_teilnahme(self, arzt: Arzt, praxis: Praxis, form: str, faktor: float, von: date) -> Teilnahme:
        t = Teilnahme(arzt=arzt, praxis=praxis, form=form, faktor=faktor, von=von)
        self.teilnahmen.append(t)
        arzt.teilnahmen.append(t)
        praxis.teilnahmen.append(t)
        return t

    def build_doctors_and_practices(self) -> None:
        rng = self.rng
        mvz_pool: dict[str, list[tuple[Arzt, float]]] = {k.ags: [] for k in ref.KREISE}
        for g in ref.ARZTGRUPPEN:
            for pb_code, _, typ, ags_list in self.planungsbereiche:
                if typ != g.planungsbereich_typ:
                    continue
                soll = sum(self.kreis_einwohner[a] for a in ags_list) / g.verhaeltniszahl
                if g.code == "HA":
                    vg = ref.HA_TARGET_VG[ags_list[0]]
                elif typ == "ROR":
                    vg = ref.FI_TARGET_VG
                elif ags_list[0] == "10041":
                    vg = rng.uniform(*ref.FA_TARGET_VG_CITY)
                else:
                    vg = rng.uniform(*ref.FA_TARGET_VG_OTHER)
                target, fte = soll * vg, 0.0
                per_kreis: dict[str, dict[str, list[tuple[Arzt, float]]]] = {}
                while fte < target - 0.25:
                    kreis = ags_list[0] if typ == "KREIS" else self.pick_kreis_by_population()
                    arzt = self.new_arzt(g.code, kreis)
                    r = rng.random()
                    role = "MVZ" if (g.code != "PT" and r < 0.12) else ("ANG" if r < 0.22 else "ZUL")
                    if role == "ZUL":
                        faktor = 0.5 if rng.random() < (0.35 if g.code == "PT" else 0.08) else 1.0
                    else:
                        faktor = rng.choices([0.25, 0.5, 0.75, 1.0], weights=[.10, .35, .25, .30])[0]
                    fte += faktor
                    if role == "MVZ":
                        mvz_pool[kreis].append((arzt, faktor))
                    else:
                        per_kreis.setdefault(kreis, {"ZUL": [], "ANG": []})[role].append((arzt, faktor))
                for kreis, roles in per_kreis.items():
                    self._form_practices(g.code, kreis, roles["ZUL"], roles["ANG"])
        for k in ref.KREISE:
            self._form_mvz(k.ags, mvz_pool[k.ags])

    def _form_practices(self, group: str, kreis: str, zul: list, ang: list) -> None:
        rng = self.rng
        created: list[Praxis] = []
        i = 0
        while i < len(zul):
            r = rng.random()
            size = (1 if r < .92 else 2) if group == "PT" else (1 if r < .62 else (2 if r < .90 else 3))
            members = zul[i:i + size]
            i += size
            starts = [self.career_start(a) for a, _ in members]
            form = "EP" if len(members) == 1 else "BAG"
            praxis = self.new_praxis(form, kreis, group, [a for a, _ in members], gruendung=min(starts))
            for (a, f), st in zip(members, starts):
                self.new_teilnahme(a, praxis, "ZUL", f, st)
            created.append(praxis)
        for a, f in ang:
            if created:
                praxis = rng.choice(created)
                self.new_teilnahme(a, praxis, "ANG", f, max(self.career_start(a), praxis.gruendungsdatum))
            else:  # no practice to join: the doctor runs an own practice instead
                st = self.career_start(a)
                praxis = self.new_praxis("EP", kreis, group, [a], gruendung=st)
                self.new_teilnahme(a, praxis, "ZUL", 1.0 if f >= 0.75 else 0.5, st)

    def _form_mvz(self, kreis: str, pool: list[tuple[Arzt, float]]) -> None:
        rng = self.rng
        i = 0
        while i < len(pool):
            members = pool[i:i + rng.randint(4, 8)]
            i += len(members)
            if len(members) < 3 and self.mvz_by_kreis[kreis]:
                praxis = self.mvz_by_kreis[kreis][-1]
            else:
                gruendung = first_of_quarter(date(rng.randint(2006, 2020), rng.randint(1, 12), 1))
                praxis = self.new_praxis("MVZ", kreis, "MVZ", [a for a, _ in members], gruendung)
            for a, f in members:
                self.new_teilnahme(a, praxis, "ANG", f, max(self.career_start(a), praxis.gruendungsdatum))

    # ------------------------------------------------------------------ Bedarfsplanung
    def compute_versorgungsgrade(self, stichtag: date) -> list[dict]:
        """Ist = sum of Anrechnungsfaktoren of all Teilnahmen valid on the Stichtag (AKTIV or RUHEND)."""
        ist: dict[tuple[str, str], float] = defaultdict(float)
        for t in self.teilnahmen:
            if t.von <= stichtag < t.bis:
                g = t.arzt.arztgruppe
                ist[(self.pb_code_for(g, t.praxis.kreis_ags), g)] += t.faktor
        rows = []
        for g in ref.ARZTGRUPPEN:
            for pb_code, _, typ, ags_list in self.planungsbereiche:
                if typ != g.planungsbereich_typ:
                    continue
                einwohner = sum(self.kreis_einwohner[a] for a in ags_list)
                soll = round(einwohner / g.verhaeltniszahl, 2)
                ist_val = round(ist[(pb_code, g.code)], 2)
                vg = round(ist_val / soll * 100, 1)
                schwelle = ref.UNTERVERSORGUNG_PCT.get(g.code, ref.UNTERVERSORGUNG_DEFAULT_PCT)
                status = "GESPERRT" if vg > ref.UEBERVERSORGUNG_PCT else ("UNTERVERSORGT" if vg < schwelle else "OFFEN")
                rows.append({"stichtag": stichtag, "pb_code": pb_code, "arztgruppe": g.code,
                             "einwohner": einwohner, "verhaeltniszahl": g.verhaeltniszahl,
                             "soll": soll, "ist": ist_val, "versorgungsgrad": vg, "status": status})
        return rows

    # ------------------------------------------------------------------ Zulassung events 2025
    def _add_verfahren(self, art: str, arzt: Arzt, praxis: Praxis | None, ergebnis: str,
                       wirksam_ab: date | None = None, wirksam_bis: date | None = None,
                       teilnahme: Teilnahme | None = None, pb_code: str | None = None,
                       antrag: date | None = None) -> Verfahren:
        rng = self.rng
        pb_code = pb_code or self.pb_code_for(arzt.arztgruppe, praxis.kreis_ags if praxis else arzt.kreis_ags)
        sitzung = None
        if ergebnis == "GENEHMIGT":
            sitzung = [s for s in self.sitzungen if s <= wirksam_ab - timedelta(days=10)][-1]
            antrag = sitzung - timedelta(days=rng.randint(30, 80))
        elif ergebnis == "ABGELEHNT":
            later = [s for s in self.sitzungen if s >= antrag + timedelta(days=30)]
            sitzung = later[0] if later else self.sitzungen[-1]
        status = [("EINGANG", antrag), ("IN_PRUEFUNG", antrag + timedelta(days=rng.randint(2, 10)))]
        bescheid_datum = None
        if sitzung is not None:
            status.append(("TERMINIERT", max(status[-1][1] + timedelta(days=1), sitzung - timedelta(days=21))))
            status.append(("ENTSCHIEDEN", sitzung))
            bescheid_datum = sitzung + timedelta(days=rng.randint(7, 14))
            status.append(("BESCHEID_VERSANDT", bescheid_datum))
            if ergebnis == "ABGELEHNT" and rng.random() < 0.35:
                status.append(("WIDERSPRUCH", bescheid_datum + timedelta(days=rng.randint(10, 28))))
            else:
                status.append(("BESTANDSKRAEFTIG", bescheid_datum + timedelta(days=31)))
        elif ergebnis == "ZURUECKGENOMMEN":
            status.append(("ZURUECKGENOMMEN", status[-1][1] + timedelta(days=rng.randint(20, 60))))
        status = [(c, d) for c, d in status if d <= ZULASSUNG_EXPORT_DATE]
        v = Verfahren(art=art, arzt=arzt, praxis=praxis, pb_code=pb_code, antrag=antrag, sitzung=sitzung,
                      ergebnis=ergebnis, wirksam_ab=wirksam_ab, wirksam_bis=wirksam_bis,
                      teilnahme=teilnahme, status=status, bescheid_datum=bescheid_datum)
        self.verfahren.append(v)
        return v

    def apply_events(self) -> None:
        rng, y = self.rng, self.year
        affected: set[int] = set()        # membership test only (never iterated)
        q_starts = [date(y, 4, 1), date(y, 7, 1), date(y, 10, 1)]
        initial = list(self.teilnahmen)

        # 1) Verzicht (retirement) at a quarter end, mostly with a successor (Nachbesetzung)
        for t in initial:
            if t.form != "ZUL" or t.arzt.idx in affected or y - t.arzt.geburtsjahr < 63 or rng.random() >= 0.22:
                continue
            end = rng.choice(q_starts + [date(y + 1, 1, 1)])
            t.bis = end
            affected.add(t.arzt.idx)
            self._add_verfahren("VERZICHT", t.arzt, t.praxis, "GENEHMIGT", wirksam_ab=end, teilnahme=t)
            if rng.random() < 0.8:
                nf = self.new_arzt(t.arzt.arztgruppe, t.praxis.kreis_ags, age=rng.randint(34, 48),
                                   fachgruppe=t.arzt.fachgruppe)
                affected.add(nf.idx)
                nt = self.new_teilnahme(nf, t.praxis, "ZUL", t.faktor, end)
                self._add_verfahren("NACHBESETZUNG", nf, t.praxis, "GENEHMIGT", wirksam_ab=end, teilnahme=nt)

        # 2) Neuzulassungen where the planning area is open (Versorgungsgrad <= 110 %)
        for (pb_code, g), row in self.initial_vg.items():
            if row["status"] == "GESPERRT":
                continue
            n = 2 if (g == "HA" and row["versorgungsgrad"] < 85) else (1 if rng.random() < 0.5 else 0)
            for _ in range(n):
                start = rng.choice(q_starts)
                kreis = pb_code[2:] if len(pb_code) == 7 else self.pick_kreis_by_population()
                nd = self.new_arzt(g, kreis, age=rng.randint(33, 50))
                affected.add(nd.idx)
                bags = [p for p in self.praxen if p.kreis_ags == kreis and p.kooperationsform == "BAG"
                        and p.main_group == g]
                if bags and rng.random() < 0.3:
                    praxis = rng.choice(bags)
                else:
                    praxis = self.new_praxis("EP", kreis, g, [nd], gruendung=start)
                faktor = 0.5 if (g == "PT" and rng.random() < 0.4) else 1.0
                nt = self.new_teilnahme(nd, praxis, "ZUL", faktor, start)
                self._add_verfahren("NEUZULASSUNG", nd, praxis, "GENEHMIGT", wirksam_ab=start,
                                    teilnahme=nt, pb_code=pb_code)

        # 3) applications without a resulting Teilnahme (area closed, withdrawn, still pending)
        closed = [k for k, r in self.initial_vg.items() if r["status"] == "GESPERRT"]
        for i in range(16):
            pb_code, g = rng.choice(closed)
            kreis = pb_code[2:] if len(pb_code) == 7 else self.pick_kreis_by_population()
            nd = self.new_arzt(g, kreis, age=rng.randint(33, 50))
            if i < 8:
                ergebnis, antrag = "ABGELEHNT", date(y, 1, 10) + timedelta(days=rng.randint(0, 260))
            elif i < 11:
                ergebnis, antrag = "ZURUECKGENOMMEN", date(y, 1, 10) + timedelta(days=rng.randint(0, 260))
            else:
                ergebnis, antrag = "OFFEN", date(y, 11, 20) + timedelta(days=rng.randint(0, 30))
            self._add_verfahren("NEUZULASSUNG", nd, None, ergebnis, pb_code=pb_code, antrag=antrag)

        # 4) employed doctors moving to another practice (creates SCD2 history in the mart)
        for t in initial:
            if t.form != "ANG" or t.arzt.idx in affected or t.bis != OPEN_END or rng.random() >= 0.05:
                continue
            move = date(y, rng.randint(3, 11), 1)
            targets = [p for p in self.praxen if p.kreis_ags == t.praxis.kreis_ags and p is not t.praxis
                       and p.gruendungsdatum <= move and (p.kooperationsform == "MVZ" or p.main_group == t.arzt.arztgruppe)]
            if not targets:
                continue
            target = rng.choice(targets)
            t.bis = move
            affected.add(t.arzt.idx)
            nt = self.new_teilnahme(t.arzt, target, "ANG", rng.choice([0.5, 0.75, 1.0]), move)
            self._add_verfahren("ANSTELLUNG", t.arzt, target, "GENEHMIGT", wirksam_ab=move, teilnahme=nt)

        # 5) Ruhen der Zulassung for a few months (e.g. parental leave, illness)
        for t in initial:
            if t.form != "ZUL" or t.arzt.idx in affected or t.bis != OPEN_END or rng.random() >= 0.02:
                continue
            start = date(y, rng.randint(2, 9), 1)
            end = add_months(start, rng.randint(2, 5))
            t.ruhend.append((start, end))
            affected.add(t.arzt.idx)
            self._add_verfahren("RUHEN", t.arzt, t.praxis, "GENEHMIGT", wirksam_ab=start, wirksam_bis=end, teilnahme=t)

    def number_verfahren(self) -> None:
        seq: dict[int, int] = defaultdict(int)
        for v in sorted(self.verfahren, key=lambda v: (v.antrag, v.arzt.lanr)):
            seq[v.antrag.year] += 1
            v.aktenzeichen = f"ZA-{v.antrag.year}-{seq[v.antrag.year]:04d}"
        self.verfahren.sort(key=lambda v: v.aktenzeichen)
        for v in self.verfahren:
            if v.bescheid_datum is not None:
                v.bescheid_text = texts.bescheid_text(v, v.bescheid_datum)

    # ------------------------------------------------------------------ QS
    def build_qs_genehmigungen(self) -> None:
        rng, y = self.rng, self.year
        self.qs_genehmigungen = []
        self._genehmigung: dict[tuple[int, str], list[tuple[date, date]]] = defaultdict(list)
        for a in self.aerzte:
            quoten = ref.QS_GENEHMIGUNG_QUOTE.get(a.arztgruppe)
            if not quoten or not a.teilnahmen:
                continue
            base = max(min(t.von for t in a.teilnahmen), date(2008, 1, 1))
            for area, quote in quoten.items():
                if rng.random() >= quote:
                    continue
                if rng.random() < 0.85 and base < date(y, 1, 1):
                    von = base + timedelta(days=rng.randint(0, (date(y, 1, 1) - base).days - 1))
                else:
                    von = date(y, 1, 1) + timedelta(days=rng.randint(0, 272))
                bis = OPEN_END
                if rng.random() < 0.05 and von < date(y, 6, 1):
                    bis = date(y, rng.randint(6, 12), 1)
                self.qs_genehmigungen.append((a, area, von, bis))
                self._genehmigung[(a.idx, area)].append((von, bis))

    def has_genehmigung(self, arzt: Arzt, area: str, d: date) -> bool:
        return any(von <= d < bis for von, bis in self._genehmigung.get((arzt.idx, area), []))

    # ------------------------------------------------------------------ patients
    def build_patients(self) -> None:
        rng, s = self.rng, self.s
        total = sum(self.kreis_einwohner.values())
        self.patient_pool: dict[tuple[str, str, str], list[Patient]] = defaultdict(list)
        for k in ref.KREISE:
            n = round(s.patient_pool_size * self.kreis_einwohner[k.ags] / total)
            weights = [self.einwohner_by_kreis_ag[(k.ags, ag.code)] for ag in ref.ALTERSGRUPPEN]
            for _ in range(n):
                ag = rng.choices(ref.ALTERSGRUPPEN, weights=weights)[0]
                age = rng.randint(ag.von, ag.bis if ag.bis is not None else 95)
                sex = "w" if rng.random() < ag.share_female else "m"
                kasse = rng.choices(self.kassen, weights=self.kassen_weights)[0]
                if age < 18:
                    status = "F"
                elif age >= 65:
                    status = "R" if rng.random() < .9 else "M"
                else:
                    status = "M" if rng.random() < .85 else "F"
                pseudonym = ids.pseudonymize(ids.make_kvnr(rng), s.pseudonym_salt)
                self.patient_pool[(k.ags, ag.code, sex)].append(
                    Patient(pseudonym, k.ags, self.year - age, sex, kasse.ik, status))

    def pick_patient(self, group: str, kreis: str) -> Patient:
        rng = self.rng
        weights = AGE_WEIGHTS.get(group, AGE_WEIGHTS["default"])
        if rng.random() > 0.85:
            kreis = self.pick_kreis_by_population()
        ag = rng.choices(list(weights), weights=list(weights.values()))[0]
        if group == "FR":
            sex = "w"
        else:
            nw, nm = len(self.patient_pool[(kreis, ag, "w")]), len(self.patient_pool[(kreis, ag, "m")])
            sex = "w" if rng.random() < nw / (nw + nm) else "m"
        return rng.choice(self.patient_pool[(kreis, ag, sex)])

    # ------------------------------------------------------------------ billing
    def active_days(self, t: Teilnahme, q: int) -> list[date]:
        key = (id(t), q)
        if key not in self._active_days_cache:
            start, end = quarter_start(self.year, q), quarter_end_excl(self.year, q)
            d, days = max(start, t.von), []
            stop = min(end, t.bis)
            while d < stop:
                if is_workday(d) and t.active_on(d):
                    days.append(d)
                d += timedelta(days=1)
            self._active_days_cache[key] = days
        return self._active_days_cache[key]

    def build_billing(self) -> None:
        rng = self.rng
        self.faelle_by_q: dict[int, list[Fall]] = {q: [] for q in range(1, 5)}
        self.fall_by_key: dict[tuple[str, int, str], Fall] = {}
        for q in range(1, 5):
            start, end = quarter_start(self.year, q), quarter_end_excl(self.year, q)
            n_workdays = sum(1 for i in range((end - start).days) if is_workday(start + timedelta(days=i)))
            for p in self.praxen:
                active = [(t, self.active_days(t, q)) for t in p.teilnahmen]
                active = [(t, days) for t, days in active if days]
                if not active:
                    continue
                fte = sum(t.faktor * len(days) / n_workdays for t, days in active)
                for _ in range(poisson(rng, self.s.cases_per_fte_quarter * fte)):
                    t, days = rng.choices(active, weights=[t.faktor * len(d) for t, d in active])[0]
                    self.create_case(p, q, t, rng.choice(days))

    def create_case(self, praxis: Praxis, q: int, t: Teilnahme, first: date,
                    tss_code: str | None = None, patient: Patient | None = None) -> Fall | None:
        rng = self.rng
        group = t.arzt.arztgruppe
        pat = None
        for _ in range(25):
            candidate = patient or self.pick_patient(group, praxis.kreis_ags)
            if (praxis.bsnr, q, candidate.pseudonym) not in self.fall_by_key:
                pat = candidate
                break
            if patient is not None:
                break
        if pat is None:
            return None
        age = self.year - pat.geburtsjahr
        if tss_code:
            sug = "00" if group in ("HA", "KI", "PT") else "24"
        elif group in ("HA", "KI", "PT"):
            sug = "43" if rng.random() < .04 else "00"
        else:
            r = rng.random()
            sug = "24" if r < .60 else ("43" if r < .63 else "00")
        days = [d for d in self.active_days(t, q) if d >= first] or [first]
        basis = ref.BASIS.get(group) or [ref.grundpauschale_code(group, age)]
        leistungen = [Leistung(first, t.arzt, code, 1, False) for code in basis]
        billed = list(basis)
        boost = 2.2 if praxis.hochabrechner else 1.0
        for code, prob, lo, hi, req in ref.OPTIONAL.get(group, []):
            if (req and req not in billed) or age < MIN_AGE.get(code, 0):
                continue
            if rng.random() >= min(0.95, prob * boost):
                continue
            d = rng.choice(days)
            gop = ref.GOP_BY_CODE[code]
            berichtigt = False
            if gop.qs and not self.has_genehmigung(t.arzt, gop.qs, d):
                if rng.random() < 0.04:
                    berichtigt = True    # billed without permit -> will be corrected in the Honorarbescheid
                else:
                    continue
            anzahl = rng.randint(lo, hi) + (2 if praxis.hochabrechner and hi > 1 else 0)
            leistungen.append(Leistung(d, t.arzt, code, anzahl, berichtigt))
            billed.append(code)
        pool = ref.DIAGNOSEN[group]
        k = rng.choices([1, 2, 3], weights=[.5, .35, .15])[0]
        diagnosen = [(c, rng.choices("GVZA", weights=[.90, .05, .04, .01])[0]) for c in rng.sample(pool, k)]
        fall = Fall(praxis=praxis, quartal=q, patient=pat, scheinuntergruppe=sug, tss_code=tss_code,
                    hauptarzt=t.arzt, leistungen=leistungen, diagnosen=diagnosen)
        self.fall_by_key[(praxis.bsnr, q, pat.pseudonym)] = fall
        self.faelle_by_q[q].append(fall)
        return fall

    def number_cases(self) -> list[Fall]:
        faelle: list[Fall] = []
        for q in range(1, 5):
            cases = sorted(self.faelle_by_q[q], key=lambda f: f.praxis.bsnr)
            for i, f in enumerate(cases, 1):
                f.fallnummer = f"F{self.year}Q{q}-{i:06d}"
                f.leistungen.sort(key=lambda l: l.datum)
            faelle.extend(cases)
        return faelle

    # ------------------------------------------------------------------ Terminservicestelle
    def build_tss(self) -> None:
        rng, y = self.rng, self.year
        groups = list(ref.TSS_GRUPPEN_GEWICHT)
        index: dict[tuple[str, str], list[Teilnahme]] = defaultdict(list)
        for t in self.teilnahmen:
            index[(t.arzt.arztgruppe, t.praxis.kreis_ags)].append(t)
        self.tss: list[TssAnfrage] = []
        for _ in range(self.s.tss_requests):
            g = rng.choices(groups, weights=list(ref.TSS_GRUPPEN_GEWICHT.values()))[0]
            kanal = rng.choices(["TELEFON", "ONLINE", "APP"], weights=[.55, .35, .10])[0]
            day = date(y, 1, 1) + timedelta(days=rng.randint(0, 364))
            if kanal == "TELEFON":
                while not is_workday(day):
                    day += timedelta(days=1)
                hour = rng.randint(8, 17)
            else:
                hour = rng.randint(6, 22)
            eingang = datetime.combine(day, time(hour, rng.randint(0, 59)))
            patient = self.pick_patient(g, self.pick_kreis_by_population())
            alter = y - patient.geburtsjahr
            if g == "PT":
                dringlichkeit = "ROUTINE" if rng.random() < .6 else "DRINGEND"
            elif g == "HA":
                dringlichkeit = "AKUT" if rng.random() < .3 else "DRINGEND"
            else:
                dringlichkeit = "DRINGEND" if rng.random() < .85 else "ROUTINE"
            vg = self.initial_vg[(self.pb_code_for(g, patient.kreis_ags), g)]["versorgungsgrad"]
            r = rng.random()
            status = "STORNIERT" if r < .07 else ("NICHT_VERMITTELT" if r < .07 + (.20 if vg < 100 else .06) else "VERMITTELT")
            a = TssAnfrage(uuid=str(uuid.UUID(int=rng.getrandbits(128), version=4)), eingang=eingang,
                           kanal=kanal, arztgruppe=g, dringlichkeit=dringlichkeit, patient=patient,
                           alter=alter, status=status)
            if status == "VERMITTELT":
                base = ref.TSS_WARTEZEIT_BASIS_TAGE[g] * (1.4 if vg < 100 else 1.0)
                if dringlichkeit == "AKUT":
                    wait = rng.randint(0, 2)
                else:
                    wait = min(60, round(base * rng.uniform(0.4, 1.6) * (1.5 if dringlichkeit == "ROUTINE" else 1.0)))
                tday = day + timedelta(days=wait)
                while not is_workday(tday):
                    tday += timedelta(days=1)
                cands = [t for t in index[(g, patient.kreis_ags)] if t.active_on(tday)] if rng.random() < .8 else []
                if not cands:
                    cands = [t for k in ref.KREISE for t in index[(g, k.ags)] if t.active_on(tday)]
                if not cands:
                    a.status = "NICHT_VERMITTELT"
                else:
                    t = rng.choice(cands)
                    a.praxis = t.praxis
                    a.termin = datetime.combine(tday, time(8, 0)) + timedelta(minutes=15 * rng.randint(0, 38))
                    a.code = ids.make_vermittlungscode(rng)
                    a.wahrgenommen = rng.random() < 0.9
                    if a.wahrgenommen and tday.year == y:
                        q = quarter_of(tday)
                        existing = self.fall_by_key.get((t.praxis.bsnr, q, patient.pseudonym))
                        if existing is not None:
                            if existing.tss_code is None:
                                existing.tss_code = a.code
                        else:
                            self.create_case(t.praxis, q, t, tday, tss_code=a.code, patient=patient)
            self.tss.append(a)
        self.tss.sort(key=lambda a: a.eingang)

    # ------------------------------------------------------------------ Honorar
    def build_honorar(self, faelle: list[Fall]) -> tuple[list[Honorarbescheid], list[Abschlag]]:
        rng, y = self.rng, self.year
        ow = ref.ORIENTIERUNGSWERT[y]
        quotes = {(g.code, q): (rng.uniform(.95, 1.0) if g.code == "HA" else rng.uniform(.90, .99))
                  for g in ref.ARZTGRUPPEN for q in range(1, 5)}
        bescheid_datum = {1: date(y, 7, 15), 2: date(y, 10, 15), 3: date(y + 1, 1, 15), 4: date(y + 1, 4, 15)}
        by_pq: dict[tuple[str, int], list[Fall]] = defaultdict(list)
        for f in faelle:
            by_pq[(f.praxis.bsnr, f.quartal)].append(f)
        bescheide, abschlaege, seq = [], [], defaultdict(int)
        for (bsnr, q), fs in by_pq.items():
            ang = ber = mgv_p = egv_p = 0
            betrag_mgv = 0.0
            for f in fs:
                for l in f.leistungen:
                    gop = ref.GOP_BY_CODE[l.gop]
                    pts = gop.punkte * l.anzahl
                    ang += pts
                    if l.berichtigt:
                        ber += pts
                    elif gop.extrabudgetaer:
                        egv_p += pts
                    else:
                        mgv_p += pts
                        betrag_mgv += pts * ow * quotes[(l.arzt.arztgruppe, q)]
            betrag_mgv = round(betrag_mgv, 2)
            betrag_egv = round(egv_p * ow, 2)
            brutto = round(betrag_mgv + betrag_egv, 2)
            vwk = round(brutto * ref.VERWALTUNGSKOSTENSATZ, 2)
            payment = max(1.0, float(round(brutto * rng.uniform(.70, 1.05) / 3)))
            for m in range(3):
                d = date(y, 3 * (q - 1) + m + 1, 25)
                if d.weekday() == 5:
                    d -= timedelta(days=1)
                elif d.weekday() == 6:
                    d -= timedelta(days=2)
                abschlaege.append(Abschlag(fs[0].praxis, q, m + 1, d, payment))
            seq[q] += 1
            abschlag_summe = round(3 * payment, 2)
            bescheide.append(Honorarbescheid(
                nr=f"HB-{y}Q{q}-{seq[q]:05d}", praxis=fs[0].praxis, quartal=q, datum=bescheid_datum[q],
                punkte_angefordert=ang, punkte_berichtigt=ber, punkte_mgv=mgv_p, punkte_egv=egv_p,
                quote_mgv=round(betrag_mgv / (mgv_p * ow), 4) if mgv_p else None,
                betrag_mgv=betrag_mgv, betrag_egv=betrag_egv, brutto=brutto, verwaltungskosten=vwk,
                abschlaege=abschlag_summe, auszahlung=round(brutto - vwk - abschlag_summe, 2)))
        return bescheide, abschlaege

    # ------------------------------------------------------------------ Verordnungen & Pruefungen
    def build_verordnungen_and_pruefungen(self, faelle: list[Fall]) -> tuple[list[Verordnung], list[Pruefverfahren]]:
        rng, y = self.rng, self.year
        by_pq: dict[tuple[str, int], list[Fall]] = defaultdict(list)
        for f in faelle:
            by_pq[(f.praxis.bsnr, f.quartal)].append(f)
        verordnungen: list[Verordnung] = []
        for (_, q), fs in by_pq.items():
            praxis = fs[0].praxis
            for art in ("A", "H"):
                rg = ref.RICHTGROESSEN[art]
                relevant = [f for f in fs if f.hauptarzt.arztgruppe in rg]
                if not relevant:
                    continue
                rgv = sum(rg[f.hauptarzt.arztgruppe] for f in relevant)
                factor = rng.uniform(1.3, 1.8) if praxis.hochverordner else math.exp(rng.gauss(0, .10))
                rate = 1.6 if art == "A" else 0.3
                anzahl = max(1, round(len(relevant) * rate * rng.uniform(.8, 1.2)))
                verordnungen.append(Verordnung(praxis, q, art, anzahl, round(rgv * factor, 2), rgv))
        flagged = [v for v in verordnungen if v.brutto > 1.25 * v.rgv]
        unflagged = [v for v in verordnungen if v.art == "A" and v.brutto <= 1.25 * v.rgv]
        candidates = [(v, "AUFFAELLIGKEIT") for v in flagged] + [(v, "ZUFAELLIGKEIT") for v in rng.sample(unflagged, 5)]
        candidates.sort(key=lambda c: (c[0].quartal, c[0].praxis.bsnr, c[0].art))
        verfahren = []
        for i, (v, anlass) in enumerate(candidates, 1):
            eingeleitet = quarter_end_excl(y, v.quartal) + timedelta(days=rng.randint(120, 200))
            done = v.quartal <= 2 or (v.quartal == 3 and rng.random() < .4)
            massnahme = betrag = abgeschlossen = None
            if done:
                r = rng.random()
                if anlass == "ZUFAELLIGKEIT":
                    massnahme = "KEINE" if r < .7 else "BERATUNG"
                elif v.brutto / v.rgv < 1.35 and r < .4:
                    massnahme = "KEINE"
                elif r < .85:
                    massnahme = "BERATUNG"
                else:
                    massnahme = "NACHFORDERUNG"
                    betrag = round((v.brutto - 1.25 * v.rgv) * rng.uniform(.5, 1.0), 2)
                abgeschlossen = min(eingeleitet + timedelta(days=rng.randint(60, 150)), self.s.export_date)
            verfahren.append(Pruefverfahren(
                aktenzeichen=f"PS-{y}-{i:04d}", praxis=v.praxis, quartal=v.quartal,
                gegenstand="ARZNEIMITTEL" if v.art == "A" else "HEILMITTEL", anlass=anlass,
                eingeleitet=eingeleitet, status="ABGESCHLOSSEN" if done else "LAUFEND",
                abgeschlossen=abgeschlossen, massnahme=massnahme, betrag=betrag))
        return verordnungen, verfahren

    # ------------------------------------------------------------------ Bereitschaftsdienst
    @staticmethod
    def shift_times(d: date) -> list[tuple[time, time]]:
        if d in ref.FEIERTAGE_2025 or d.weekday() >= 5:
            return [(time(8), time(20)), (time(20), time(8))]
        if d.weekday() in (2, 4):          # Wednesday, Friday afternoon
            return [(time(13), time(20)), (time(20), time(8))]
        return [(time(18), time(8))]       # Monday, Tuesday, Thursday evening/night

    def build_bereitschaftsdienst(self) -> list[Dienst]:
        rng, y = self.rng, self.year
        eligible: dict[str, list[Teilnahme]] = defaultdict(list)
        for t in self.teilnahmen:
            if t.arzt.arztgruppe not in ("PT", "KI"):   # psychotherapists / paediatricians: not in this service
                eligible[t.praxis.kreis_ags].append(t)
        counts: dict[int, int] = defaultdict(int)
        dienste: list[Dienst] = []
        d = date(y, 1, 1)
        while d.year == y:
            for kennung, _, ags in ref.BEREITSCHAFTSPRAXEN:
                cands = [t for t in eligible[ags] if t.active_on(d)]
                for n, (b, e) in enumerate(self.shift_times(d), 1):
                    ranked = sorted(cands, key=lambda t: (counts[t.arzt.idx] + 1) / t.faktor + rng.random() * 0.3)
                    chosen, getauscht = ranked[0], None
                    if len(ranked) > 1 and rng.random() < 0.05:
                        getauscht, chosen = ranked[0], ranked[1]
                    counts[chosen.arzt.idx] += 1
                    beginn = datetime.combine(d, b)
                    ende = datetime.combine(d if e > b else d + timedelta(days=1), e)
                    dienste.append(Dienst(f"BD-{kennung[4:]}-{d:%Y%m%d}-{n}", kennung, beginn, ende,
                                          chosen.arzt, getauscht.arzt if getauscht else None))
            d += timedelta(days=1)
        return dienste

    # ------------------------------------------------------------------ Fortbildung
    def build_fortbildung(self) -> list[tuple[Arzt, int, int]]:
        rng, rows = self.rng, []
        for a in self.aerzte:
            if not a.teilnahmen:
                continue
            first_year = min(t.von for t in a.teilnahmen).year
            low = rng.random() < .06
            for jahr in range(max(2021, first_year), self.year + 1):
                pts = rng.gauss(30, 10) if low else rng.gauss(60, 14)
                rows.append((a, jahr, int(min(140, max(0, round(pts))))))
        return rows

    # ------------------------------------------------------------------ communication
    def build_communication(self, faelle: list[Fall], dienste: list[Dienst]) -> tuple[list[Anfrage], list[Beschwerde]]:
        rng, y = self.rng, self.year
        topics = ["ABRECHNUNG", "HONORAR", "ZULASSUNG", "QS", "BEREITSCHAFTSDIENST", "VERORDNUNG", "IT"]
        topic_w = [.30, .15, .14, .12, .12, .10, .07]
        anfragen: list[Anfrage] = []
        for i in range(1, self.s.member_enquiries + 1):
            day = date(y, 1, 2) + timedelta(days=rng.randint(0, 360))
            while not is_workday(day):
                day += timedelta(days=1)
            active = [t for t in self.teilnahmen if t.active_on(day)]
            t = rng.choice(active)
            topic = rng.choices(topics, weights=topic_w)[0]
            ctx = {
                "quartal": f"{quarter_of(day)}/{y}",
                "gop": ref.GOP_BY_CODE[rng.choice([g.code for g in ref.GOPS])],
                "datum": (day + timedelta(days=rng.randint(14, 60))).strftime("%d.%m.%Y"),
                "pb_code": self.pb_code_for(t.arzt.arztgruppe, t.praxis.kreis_ags),
                "arztgruppe": ref.ARZTGRUPPE_BY_CODE[t.arzt.arztgruppe].name,
                "qs": rng.choice([q[1] for q in ref.QS_BEREICHE]),
                "bdp": rng.choice([b[1] for b in ref.BEREITSCHAFTSPRAXEN]),
            }
            betreff, text = texts.anfrage_text(rng, topic, t.arzt, t.praxis, ctx)
            erstellt = datetime.combine(day, time(rng.randint(7, 18), rng.randint(0, 59)))
            done = rng.random() < .88
            erledigt = erstellt + timedelta(days=rng.randint(1, 21), hours=rng.randint(0, 6)) if done else None
            anfragen.append(Anfrage(f"T-{y}-{i:05d}", erstellt, rng.choices(["EMAIL", "TELEFON", "PORTAL"], weights=[.5, .3, .2])[0],
                                    topic, t.arzt, t.praxis, betreff, text, "ERLEDIGT" if done else "OFFEN", erledigt))
        anfragen.sort(key=lambda a: a.erstellt)

        beschwerden: list[Beschwerde] = []
        for i in range(1, self.s.complaints + 1):
            f = rng.choice(faelle)
            kategorie = rng.choice(texts.BESCHWERDE_KATEGORIEN)
            vorfall = f.leistungen[0].datum
            arzt = f.hauptarzt if rng.random() < .6 else None
            betreff, text = texts.beschwerde_text(rng, kategorie, f.praxis, arzt, vorfall)
            beschwerden.append(Beschwerde(i, vorfall + timedelta(days=rng.randint(1, 20)),
                                          rng.choice(texts.BESCHWERDE_KANAELE), kategorie, f.praxis, betreff, text))
        return anfragen, beschwerden


def build_world(settings: Settings) -> World:
    return WorldBuilder(settings).build()
