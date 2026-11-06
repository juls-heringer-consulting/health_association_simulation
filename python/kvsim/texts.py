"""German text templates for the unstructured sources (enquiries, complaints, minutes, notices).

All persons and practices are synthetic. Patients are never named.
"""
from __future__ import annotations

import random
from datetime import date, timedelta

GREMIUM = "Zulassungsausschuss für Ärzte und Psychotherapeuten im Saarland"

VERFAHRENSART_LABEL = {
    "NEUZULASSUNG": "Antrag auf Zulassung (Neuzulassung)",
    "NACHBESETZUNG": "Nachbesetzung eines Vertragsarztsitzes",
    "ANSTELLUNG": "Genehmigung einer Anstellung",
    "RUHEN": "Ruhen der Zulassung",
    "VERZICHT": "Verzicht auf die Zulassung",
}


def de(d: date) -> str:
    return d.strftime("%d.%m.%Y")


def faktor_de(f: float) -> str:
    return f"{f:.2f}".replace(".", ",")


# ------------------------------------------------------------------ Zulassungsausschuss
def beschluss_satz(v) -> str:
    """One-sentence decision used in notices and minutes. `v` is a generator.Verfahren."""
    if v.ergebnis == "ABGELEHNT":
        return (f"Der Antrag wird abgelehnt. Im Planungsbereich {v.pb_code} sind für die Arztgruppe "
                f"der {v.arztgruppe_name} Zulassungsbeschränkungen angeordnet (Versorgungsgrad über 110 %).")
    if v.art == "VERZICHT":
        return (f"Der Ausschuss stellt fest, dass die Zulassung durch Verzicht mit Ablauf des "
                f"{de(v.wirksam_ab - timedelta(days=1))} endet.")
    if v.art == "RUHEN":
        return (f"Das Ruhen der Zulassung wird für den Zeitraum vom {de(v.wirksam_ab)} bis zum "
                f"{de(v.wirksam_bis - timedelta(days=1))} angeordnet.")
    if v.art == "ANSTELLUNG":
        return (f"Die Genehmigung zur Anstellung in der Betriebsstätte {v.praxis.name} (BSNR {v.praxis.bsnr}) "
                f"mit einem Anrechnungsfaktor von {faktor_de(v.teilnahme.faktor)} wird mit Wirkung zum "
                f"{de(v.wirksam_ab)} erteilt.")
    return (f"Dem Antrag wird stattgegeben. Die Zulassung im Planungsbereich {v.pb_code} wird mit Wirkung "
            f"zum {de(v.wirksam_ab)} erteilt (Versorgungsauftrag {faktor_de(v.teilnahme.faktor)}).")


def bescheid_text(v, bescheid_datum: date) -> str:
    anrede = "Sehr geehrte Frau" if v.arzt.geschlecht == "w" else "Sehr geehrter Herr"
    return (
        f"{GREMIUM}\n"
        f"Bescheid\n"
        f"Aktenzeichen: {v.aktenzeichen}\n"
        f"Saarbrücken, den {de(bescheid_datum)}\n\n"
        f"{anrede} {v.arzt.titel + ' ' if v.arzt.titel else ''}{v.arzt.nachname},\n\n"
        f"der Zulassungsausschuss hat in seiner Sitzung vom {de(v.sitzung)} über Ihren Antrag vom "
        f"{de(v.antrag)} ({VERFAHRENSART_LABEL[v.art]}) wie folgt beschlossen:\n\n"
        f"{beschluss_satz(v)}\n\n"
        f"Rechtsbehelfsbelehrung: Gegen diesen Beschluss kann innerhalb eines Monats nach Zustellung "
        f"Widerspruch beim Berufungsausschuss eingelegt werden.\n"
    )


def protokoll_markdown(sitzung: date, verfahren: list) -> str:
    lines = [
        "---",
        f"gremium: {GREMIUM}",
        f"sitzung: {sitzung.isoformat()}",
        "ort: Saarbrücken",
        f"anzahl_tagesordnungspunkte: {len(verfahren)}",
        "---",
        "",
        f"# Niederschrift über die Sitzung des Zulassungsausschusses am {de(sitzung)}",
        "",
        "Anwesend: 3 Vertreter der Ärzte und Psychotherapeuten, 3 Vertreter der Krankenkassen "
        "(Namen werden in dieser Simulation nicht aufgeführt).",
        "",
    ]
    for i, v in enumerate(verfahren, 1):
        lines += [f"## TOP {i}: {v.aktenzeichen} – {VERFAHRENSART_LABEL[v.art]}", ""]
        lines.append(f"- Antragsteller/in: {v.arzt.display_name} (LANR {v.arzt.lanr})")
        if v.praxis is not None:
            lines.append(f"- Betriebsstätte: {v.praxis.name} (BSNR {v.praxis.bsnr}), {v.praxis.ort}")
        lines.append(f"- Planungsbereich: {v.pb_code}")
        lines.append(f"- Beschluss: {beschluss_satz(v)}")
        lines.append("")
    lines.append("Die Sitzung endet um 16:30 Uhr.")
    return "\n".join(lines) + "\n"


# ------------------------------------------------------------------ Mitgliederanfragen
def anfrage_text(rng: random.Random, topic: str, arzt, praxis, ctx: dict) -> tuple[str, str]:
    gruss = f"\n\nMit freundlichen Grüßen\n{arzt.display_name}\n{praxis.name}, {praxis.ort}"
    q, gop = ctx["quartal"], ctx["gop"]
    variants: dict[str, list[tuple[str, str]]] = {
        "ABRECHNUNG": [
            (f"Frage zur Abrechnung der GOP {gop.code}",
             f"Sehr geehrte Damen und Herren,\n\nin unserer Praxis (BSNR {praxis.bsnr}) ist unklar, ob die GOP "
             f"{gop.code} ({gop.titel}) im Quartal {q} neben der Grundpauschale berechnungsfähig ist. "
             f"Gibt es hierzu einen Abrechnungsausschluss?"),
            (f"Korrektur der Abrechnung {q}",
             f"Sehr geehrte Damen und Herren,\n\nbei unserer Quartalsabrechnung {q} wurde die GOP {gop.code} "
             f"versehentlich mit falschem Leistungsdatum übermittelt. Wie können wir die Abrechnung korrigieren?"),
        ],
        "HONORAR": [
            (f"Rückfrage zum Honorarbescheid {q}",
             f"Sehr geehrte Damen und Herren,\n\ndie im Honorarbescheid {q} ausgewiesene Quote für die "
             f"morbiditätsbedingte Gesamtvergütung ist für uns nicht nachvollziehbar. Bitte erläutern Sie die "
             f"Berechnung für unsere Betriebsstätte (BSNR {praxis.bsnr})."),
            ("Anpassung der Abschlagszahlungen",
             "Sehr geehrte Damen und Herren,\n\nunsere Fallzahlen sind seit dem letzten Quartal deutlich "
             "gestiegen. Wir bitten um Anpassung der monatlichen Abschlagszahlungen."),
        ],
        "ZULASSUNG": [
            ("Anstellung einer Kollegin in Teilzeit",
             f"Sehr geehrte Damen und Herren,\n\nwir möchten zum {ctx['datum']} eine Kollegin mit einem "
             f"Anrechnungsfaktor von 0,5 anstellen. Welche Unterlagen benötigt der Zulassungsausschuss?"),
            ("Praxisabgabe und Nachbesetzung",
             "Sehr geehrte Damen und Herren,\n\nich plane, meine vertragsärztliche Tätigkeit zum Ende des "
             "kommenden Jahres zu beenden. Wie läuft das Nachbesetzungsverfahren für meinen Sitz ab?"),
            (f"Freie Sitze im Planungsbereich {ctx['pb_code']}",
             f"Sehr geehrte Damen und Herren,\n\ngibt es im Planungsbereich {ctx['pb_code']} derzeit "
             f"Zulassungsmöglichkeiten für {ctx['arztgruppe']}?"),
        ],
        "QS": [
            (f"Genehmigung {ctx['qs']}",
             f"Sehr geehrte Damen und Herren,\n\nich möchte eine Genehmigung für den Leistungsbereich "
             f"{ctx['qs']} beantragen. Welche fachlichen Nachweise sind einzureichen?"),
            ("Nachweis der Fortbildungspunkte",
             "Sehr geehrte Damen und Herren,\n\nbis wann muss ich den Nachweis der Fortbildungspunkte nach "
             "§ 95d SGB V erbringen, und werden die Punkte direkt von der Kammer übermittelt?"),
        ],
        "BEREITSCHAFTSDIENST": [
            (f"Diensttausch am {ctx['datum']}",
             f"Sehr geehrte Damen und Herren,\n\nich möchte meinen Bereitschaftsdienst am {ctx['datum']} in der "
             f"Bereitschaftsdienstpraxis {ctx['bdp']} mit einer Kollegin tauschen. Bitte bestätigen Sie den Tausch."),
            ("Befreiung vom Bereitschaftsdienst",
             "Sehr geehrte Damen und Herren,\n\naus gesundheitlichen Gründen beantrage ich eine befristete "
             "Befreiung vom ärztlichen Bereitschaftsdienst. Ein Attest liegt bei."),
        ],
        "VERORDNUNG": [
            ("Frage zur Richtgröße Arzneimittel",
             f"Sehr geehrte Damen und Herren,\n\nunsere Arzneimittelverordnungen lagen im Quartal {q} über dem "
             f"Durchschnitt der Fachgruppe. Droht uns eine Wirtschaftlichkeitsprüfung, und welche "
             f"Praxisbesonderheiten können wir geltend machen?"),
            ("Langfristiger Heilmittelbedarf",
             "Sehr geehrte Damen und Herren,\n\nwie sind Heilmittelverordnungen bei langfristigem "
             "Heilmittelbedarf in der Wirtschaftlichkeitsprüfung zu berücksichtigen?"),
        ],
        "IT": [
            ("Zugang zum Mitgliederportal",
             "Sehr geehrte Damen und Herren,\n\nseit dem letzten Update kann ich mich nicht mehr im "
             "Mitgliederportal anmelden. Bitte setzen Sie meinen Zugang zurück."),
            ("Abrechnungsübermittlung über KIM",
             f"Sehr geehrte Damen und Herren,\n\ndie Übermittlung unserer Abrechnung {q} über KIM ist mit "
             f"einer Fehlermeldung abgebrochen. Ist die Abrechnung bei Ihnen eingegangen?"),
        ],
    }
    subject, body = rng.choice(variants[topic])
    return subject, body + gruss


# ------------------------------------------------------------------ Beschwerden
BESCHWERDE_KATEGORIEN = ["WARTEZEIT", "TERMINVERGABE", "ERREICHBARKEIT", "KOMMUNIKATION", "PRIVATLEISTUNG", "HYGIENE"]
BESCHWERDE_KANAELE = ["Online-Formular", "E-Mail", "Brief (eingescannt)", "Telefon (Gesprächsnotiz)"]


def beschwerde_text(rng: random.Random, kategorie: str, praxis, arzt, vorfall: date) -> tuple[str, str]:
    wer = arzt.display_name if arzt is not None else "die behandelnde Ärztin bzw. der behandelnde Arzt"
    texte = {
        "WARTEZEIT": ("Lange Wartezeit trotz Termin",
                      f"Ich hatte am {de(vorfall)} einen Termin in der Praxis {praxis.name} in {praxis.ort}. "
                      f"Trotz Termin musste ich über {rng.randint(2, 4)} Stunden warten, ohne dass mir jemand "
                      f"den Grund erklärt hat. Ich bitte die KV, sich die Terminorganisation anzusehen."),
        "TERMINVERGABE": ("Keine Termine für neue Patienten",
                          f"Die Praxis {praxis.name} in {praxis.ort} nimmt nach Auskunft am Telefon keine neuen "
                          f"Patienten auf. Ich wohne seit kurzem in {praxis.ort} und finde keine Praxis. "
                          f"Ist das zulässig?"),
        "ERREICHBARKEIT": ("Praxis telefonisch nicht erreichbar",
                           f"Seit dem {de(vorfall)} versuche ich, die Praxis {praxis.name} telefonisch zu "
                           f"erreichen. Es meldet sich nur der Anrufbeantworter, Rückrufe erfolgen nicht."),
        "KOMMUNIKATION": ("Unfreundliche Behandlung",
                          f"Bei meinem Besuch am {de(vorfall)} hat sich {wer} kaum Zeit genommen und meine "
                          f"Fragen nicht beantwortet. Ich habe mich nicht ernst genommen gefühlt."),
        "PRIVATLEISTUNG": ("Druck zu einer Privatleistung",
                           f"In der Praxis {praxis.name} wurde mir am {de(vorfall)} nahegelegt, eine Untersuchung "
                           f"privat zu bezahlen, da sie sonst erst in einigen Monaten möglich sei."),
        "HYGIENE": ("Hygienemängel",
                    f"Bei meinem Besuch in der Praxis {praxis.name} am {de(vorfall)} sind mir deutliche "
                    f"Hygienemängel im Wartebereich aufgefallen."),
    }
    return texte[kategorie]
