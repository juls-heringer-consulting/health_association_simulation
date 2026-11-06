# Assumptions

Everything here is a **labelled assumption**, made from general knowledge without looking up
current official sources. Use this list as a checklist when you start at a real KV: confirm,
correct, and note the real answer next to each item.

## Region and population

| ID | Assumption | Why it matters | Verify at the KV |
|---|---|---|---|
| A-01 | The simulated KV is the real **KV Saarland** with its 6 real Kreise and 52 Gemeinden. Everything else (doctors, practices, cases) is synthetic. | Real geography, no invented regions. | - |
| A-02 | Population totals per Kreis are **rounded approximations**; the age split is modelled. | Drives Versorgungsgrade. | Statistisches Amt Saarland. |
| A-03 | Kreis seat coordinates are approximate (point per Kreis, no boundaries). | Spatial exercises only. | BKG geodata (VG250). |
| A-04 | Gemeinde-level AGS codes are **not** included because they could not be stated reliably; practices carry the Kreis-AGS and the Ort as text. | Planning at Gemeinde/Mittelbereich level is not possible yet. | Official Gemeindeverzeichnis. |
| A-05 | BSNR prefix **73** identifies the KV Saarland. | DQ02 checks it. | KV Arztregister. |

## Doctors and practices

| ID | Assumption | Why it matters | Verify at the KV |
|---|---|---|---|
| A-10 | About **1,800 persons** (≈1,770 with an active or past Teilnahme) - realistic for the population, more than the originally planned 300-500, because a real region needs this many doctors for realistic Versorgungsgrade. | Volume. | Real number of members. |
| A-11 | Only 10 Arztgruppen / 11 Fachgruppen are simulated (no surgeons, urologists, radiologists, labs, ...). | Coverage. | - |
| A-12 | Fachgruppe codes follow the KBV Arztgruppenschlüssel (01, 03, 05, 10, 15, 19, 21, 23, 34, 51, 68) - **codes to be verified**. | LANR suffix check. | Arztnummern-Richtlinie, Anlage. |
| A-13 | Each doctor has **one Fachgruppe and one LANR** and works at **one practice at a time**. In reality doctors can hold several LANRs (one per Fachgruppe) and work at several sites. | Simplifies keys and SCD2. | Exercise 04 sketches the extension. |
| A-14 | One practice = one Betriebsstätte (no Nebenbetriebsstätten). | Simplification. | - |
| A-15 | Ermächtigungen (authorised hospital doctors) are not modelled. | - | - |

## Bedarfsplanung and Zulassung

| ID | Assumption | Why it matters | Verify at the KV |
|---|---|---|---|
| A-20 | Hausärzte are planned **per Kreis** (real: Mittelbereich); Fachinternisten for the whole Saarland as one Raumordnungsregion "Saar". | Planning areas. | Bedarfsplan of the KV. |
| A-21 | Verhältniszahlen are simplified and refer to the **total population** (real values depend on Kreistyp and, e.g. for paediatricians, on the child population, plus a demography factor). | Soll calculation. | Bedarfsplanungs-Richtlinie (G-BA). |
| A-22 | Status rules: > 110 % = GESPERRT; < 75 % (Hausärzte) / < 50 % (others) = UNTERVERSORGT. "Drohende Unterversorgung" is not modelled. | Status column. | Bedarfsplanungs-Richtlinie. |
| A-23 | Ist = sum of Anrechnungsfaktoren of all Teilnahmen valid on the Stichtag, **including RUHEND**. | Reconciliation DQ11. | Landesausschuss practice. |
| A-24 | The Zulassungsausschuss meets on the 3rd Wednesday of each month; decisions take effect at least 10 days later. | Dates of procedures. | Geschäftsstelle. |
| A-25 | Vertragsarztsitz (seat) is not a separate entity; succession is visible through procedures (NACHBESETZUNG) and Teilnahmen. | Model scope. | - |

## Billing and fees

| ID | Assumption | Why it matters | Verify at the KV |
|---|---|---|---|
| A-30 | Billing data is a **sample** of ~3,000 cases per quarter. Euro amounts are therefore tiny; ratios are meaningful. | All money figures. | - |
| A-31 | GOP codes are real EBM codes, but **points, Prüfzeiten and titles are simplified example values**. | Points, Plausi profiles. | EBM of the KBV. |
| A-32 | Orientierungswert 2025 ≈ 12.3934 cent per point. | Euro valuation. | KBV / Bewertungsausschuss. |
| A-33 | Honorarverteilung simplified to one payout quota per Arztgruppe and quarter for budgeted (MGV) points; extrabudgetary points at full value. No RLV/QZV. | Honorarbescheid. | HVM of the KV Saarland. |
| A-34 | Verwaltungskostensatz 2.5 %. | Honorarbescheid. | Satzung / HVM. |
| A-35 | Three monthly Abschläge per quarter on the 25th, settled in the Bescheid; Bescheide are issued ~3.5 months after quarter end. | Payment data. | Finanzen. |
| A-36 | Krankenkassen names are real; **IK numbers synthetic**; market shares approximate. | - | Kassenverzeichnis. |
| A-37 | Behandlungsfall = patient × practice × quarter (Kasse ignored for the uniqueness rule). | Unique constraint. | Abrechnungsbestimmungen. |
| A-38 | Billing CSVs are an analytics export of the billing system (real input format is KVDT). | Source format. | IT / Abrechnung. |

## Data protection

| ID | Assumption | Why it matters | Verify at the KV |
|---|---|---|---|
| A-40 | KVs receive identifying patient data with the billing (§ 295 SGB V) and may process it for defined tasks (§ 285 SGB V). This project models the **analytics view**: patients only as salted SHA-256 pseudonyms, age group instead of birth date. | Patient columns. | Datenschutzbeauftragte/r. |
| A-41 | Complaints are stored with the complaining person anonymised; documents carry a confidentiality class. | Text data. | Datenschutz / Beschwerdemanagement. |

## Care provision, QS, audits, prescriptions

| ID | Assumption | Why it matters | Verify at the KV |
|---|---|---|---|
| A-50 | One Bereitschaftsdienstpraxis per Kreis; shifts Mon/Tue/Thu 18-08, Wed/Fri 13-20 + 20-08, weekends/holidays 08-20 + 20-08; psychotherapists and paediatricians not included. | Shift data. | Bereitschaftsdienstordnung. |
| A-51 | TSS requests carry Dringlichkeit (AKUT / DRINGEND / ROUTINE); the 4-week rule is measured as wait ≤ 28 days. | TSS KPIs. | TSS team. |
| A-52 | QS areas US, KOLO, AKU, HKS with permits per doctor; ~4 % of QS-GOPs of doctors without permit are billed anyway (findings) and corrected in the Bescheid. | DQ12/DQ13. | QS department. |
| A-53 | CME: all doctors evaluated for 2021-2025, only those participating since before 2021 count. | DQ14. | QS department. |
| A-54 | Wirtschaftlichkeitsprüfung triggered at > 125 % of the Richtgrößenvolumen (Richtgröße × cases of the sample). Real audit procedures differ by region since 2017. | Prüfverfahren. | Prüfvereinbarung. |
| A-55 | Verordnungen arrive aggregated per practice, quarter and type; no ATC or therapy detail. | - | Verordnungsmanagement. |
