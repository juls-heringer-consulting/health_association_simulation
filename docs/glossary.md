# Glossary (German term → English explanation)

Terms are explained as used in this project. Where the real world is more complex,
see [assumptions.md](assumptions.md). "Model" names the table where the term lives.

| German term | English explanation | Model |
|---|---|---|
| **Abrechnung** | Billing. Practices bill their services to the KV once per quarter; the KV checks them and pays the practices. | `core.abrechnungsfall`, `core.leistung` |
| **Abschlagszahlung** | Monthly advance payment from the KV to a practice during a quarter, settled later in the Honorarbescheid. | `core.abschlagszahlung` |
| **AGS (Amtlicher Gemeindeschlüssel)** | Official municipality key. 8 digits for a Gemeinde; the first 5 identify the Kreis (e.g. 10041). | `core.kreis.ags` |
| **Altersgruppe** | Age group. Used instead of the exact age (data minimisation). | `core.altersgruppe` |
| **Angestellter Arzt / Anstellung** | Employed doctor working in a practice or MVZ; needs approval by the Zulassungsausschuss. | `core.teilnahme` (form ANG) |
| **Anrechnungsfaktor** | How much of a planning seat a doctor counts for: 1.0 full-time, 0.5 half, 0.25 ... | `core.teilnahme.anrechnungsfaktor` |
| **Arztgruppe (Bedarfsplanung)** | Physician group of the needs planning, e.g. Hausärzte, Augenärzte. | `core.arztgruppe` |
| **Arztregister** | Register of all physicians and psychotherapists who may take part in statutory care, kept by the KV. | `core.arzt` |
| **Ärztekammer / Kammer** | Medical chamber (professional body), responsible for licensing and continuing education; separate from the KV. | source `kammern` |
| **BAG (Berufsausübungsgemeinschaft)** | Joint practice: several doctors share one practice and bill together (formerly "Gemeinschaftspraxis"). | `core.kooperationsform` |
| **Bedarfsplanung** | Needs planning: how many doctors of a group a planning area needs, based on population. | `core.versorgungsgrad` |
| **Behandlungsfall** | Billing case: all treatment of one patient in one practice in one quarter. | `core.abrechnungsfall` |
| **Bereitschaftsdienst (ärztlicher, ÄBD)** | Out-of-hours medical service (phone 116117) for evenings, weekends and holidays. | `core.bereitschaftsdienst` |
| **Bereitschaftsdienstpraxis** | Practice (often at a hospital) where the out-of-hours service is provided. | `core.notfallpraxis` |
| **Bescheid** | Formal administrative notice (e.g. a licensing decision, a fee statement). | `core.dokument`, `core.honorarbescheid` |
| **Beschwerde** | Complaint, here from patients about practices. | `core.dokument` (type BESCHWERDE) |
| **Betriebsstätte / BSNR** | Practice site / its 9-digit number (Betriebsstättennummer). First two digits = KV region. | `core.praxis.bsnr` |
| **BfArM** | Federal Institute for Drugs and Medical Devices; publishes the ICD-10-GM. | source `bfarm` |
| **Diagnosesicherheit** | Certainty of a diagnosis: G confirmed, V suspected, A excluded, Z history of. | `core.fall_diagnose` |
| **DSGVO** | German name of the GDPR (EU General Data Protection Regulation). | - |
| **EBM (Einheitlicher Bewertungsmaßstab)** | Uniform fee schedule for statutory care; lists all billable services (GOPs) with points. | `core.gop`, `core.ebm_kapitel` |
| **EFN (Einheitliche Fortbildungsnummer)** | 15-digit number used by the chambers for continuing-education points. | `core.arzt.efn` |
| **EGV / extrabudgetär** | Services paid outside the budget at the full price (e.g. screening). | `core.gop.ist_extrabudgetaer` |
| **Einzelpraxis (EP)** | Single-handed practice. | `core.kooperationsform` |
| **Ermächtigung** | Special authorisation (e.g. for hospital doctors) to take part in statutory care. Not modelled yet. | - |
| **Fachgruppe** | Medical specialty; its 2-digit code forms digits 8-9 of the LANR. | `core.fachgruppe` |
| **Fallwert** | Average amount per case (EUR or points per Behandlungsfall). | `mart.v_fallwert_praxis_quartal` |
| **Fallzahl** | Number of cases (Behandlungsfälle). | `mart.fact_abrechnungsfall` |
| **Fortbildungspunkte (CME)** | Continuing-education points; § 95d SGB V requires 250 points in 5 years. | `core.fortbildungspunkte` |
| **GOP (Gebührenordnungsposition)** | A billing code of the EBM, e.g. 03000. | `core.gop` |
| **Grundpauschale / Versichertenpauschale** | Basic flat fee per case for specialists / for family doctors. | `core.gop` |
| **Hausarzt** | Family doctor (general practitioner, also internists working as GPs and paediatricians in some contexts). | `core.arztgruppe` HA |
| **Heilmittel** | Prescribed therapies such as physiotherapy, speech therapy. | `core.verordnung` (H) |
| **Honorar / Honorarbescheid** | Fee / quarterly fee statement of the KV to a practice. | `core.honorarbescheid` |
| **Honorarverteilung (HVM)** | Rules by which the KV distributes the total payment from the Kassen to the practices. Simplified to one quota per group. | `core.honorarbescheid.quote_mgv` |
| **ICD-10-GM** | German version of the international classification of diagnoses. | `core.icd10` |
| **IK (Institutionskennzeichen)** | 9-digit identifier of institutions such as Krankenkassen. | `core.krankenkasse.ik` |
| **Kassenart** | Type of insurer: AOK, BKK, IKK, Ersatzkasse, Knappschaft, LKK. | `core.kassenart` |
| **KBV** | Kassenärztliche Bundesvereinigung: federal umbrella of the 17 KVs; publishes the EBM. | source `kbv_referenz` |
| **Kooperationsform** | Organisational form of a practice: EP, BAG, MVZ. | `core.kooperationsform` |
| **Krankenkasse** | Statutory health insurer; pays the KV for all outpatient care. | `core.krankenkasse` |
| **Kreis / Landkreis / Regionalverband** | District. The Saarland has 5 Landkreise and the Regionalverband Saarbrücken. | `core.kreis` |
| **KV (Kassenärztliche Vereinigung)** | Regional association of statutory-health-insurance physicians and psychotherapists; organises outpatient care, billing and on-call service. | - |
| **KVDT** | Data exchange format (xDT family) in which practices submit their billing. | source `abrechnung` |
| **KVNR** | Health insurance number of the patient. Never stored in this project (only a pseudonym). | - |
| **Landesausschuss** | State committee of doctors and Kassen that decides on over- or under-supply. | `core.versorgungsgrad` |
| **LANR (Lebenslange Arztnummer)** | Lifelong physician number: 6 digits + check digit + 2-digit Fachgruppe. | `core.arzt.lanr` |
| **MGV (morbiditätsbedingte Gesamtvergütung)** | The budgeted total payment of the Kassen for most services. | `core.honorarbescheid.betrag_mgv` |
| **Mitgliederanfrage** | Question from a member (doctor/practice) to the KV. | `core.dokument` (ANFRAGE) |
| **MVZ (Medizinisches Versorgungszentrum)** | Medical care centre: an institution employing several doctors. | `core.kooperationsform` |
| **Nachbesetzung** | Succession: a retiring doctor's licence is taken over by a successor. | `core.zulassungsverfahren` |
| **Nachforderung (Regress)** | Recourse: the doctor has to pay back for uneconomic prescribing. | `core.pruefverfahren` |
| **Niederschrift / Sitzungsprotokoll** | Minutes of a committee session. | `core.dokument` (PROTOKOLL) |
| **Orientierungswert** | Euro value of one EBM point in a year (about 12.39 cent in 2025). | `core.orientierungswert` |
| **Planungsbereich** | Planning area of the Bedarfsplanung. | `core.planungsbereich` |
| **Plausibilitätsprüfung** | Plausibility check of billing by time: each GOP has a Prüfzeit; more than 12 h/day (on 3+ days) or 780 h/quarter is suspicious. | `mart.v_plausi_tagesprofil` |
| **Prüfungsstelle** | Joint audit office of KV and Kassen for efficiency audits. | `core.pruefverfahren` |
| **Prüfzeit** | Standard minutes assigned to a GOP for plausibility checks. | `core.gop.pruefzeit_min` |
| **Psychotherapeut** | Psychological psychotherapist; also a KV member with a LANR. | Fachgruppe 68 |
| **QS (Qualitätssicherung) / QS-Genehmigung** | Quality assurance / permit a doctor needs to bill certain services (ultrasound, colonoscopy, ...). | `core.qs_genehmigung` |
| **Quartal** | Quarter; the billing period. | `core.quartal` |
| **Raumordnungsregion** | Larger spatial planning region; used for specialised specialists. | `core.planungsbereich` (ROR) |
| **Richtgröße** | Target prescription volume in EUR per case for a physician group. | `core.richtgroesse` |
| **Ruhen der Zulassung** | Temporary suspension of a licence (e.g. illness, parental leave). | `core.teilnahme_status` RUHEND |
| **Sachlich-rechnerische Berichtigung** | Correction of a billing for formal reasons (e.g. GOP without permit). | `core.honorarbescheid.punkte_berichtigt` |
| **Scheinuntergruppe** | Type of billing case: regular, referral, emergency. | `core.scheinuntergruppe` |
| **SGB V** | Book V of the German Social Code: law of statutory health insurance. | - |
| **Stichtag** | Reference date. | various |
| **Teilnahme** | Participation of a doctor in statutory care at a practice (as licensed or employed doctor). | `core.teilnahme` |
| **Terminservicestelle (TSS)** | Appointment service of the KV (phone 116117, online) that arranges specialist appointments. | `core.tss_anfrage` |
| **Überweisung** | Referral from one doctor to another. | Scheinuntergruppe 24 |
| **Unterversorgung / Überversorgung** | Under-supply / over-supply of a planning area. | `core.versorgungsgrad.status` |
| **Verhältniszahl** | Target ratio: inhabitants per doctor at 100 % supply. | `core.arztgruppe.verhaeltniszahl` |
| **Vermittlungscode** | Code of an appointment arranged by the TSS; also reported in the billing. | `core.tss_anfrage.vermittlungscode` |
| **Verordnung (Arzneimittel / Heilmittel)** | Prescription (drugs / therapies). | `core.verordnung` |
| **Versichertenstatus** | Insurance status: M member, F family member, R pensioner. | `core.abrechnungsfall` |
| **Versorgungsebene** | Planning level: hausärztlich, allgemein fachärztlich, spezialisiert fachärztlich. | `core.arztgruppe` |
| **Versorgungsgrad** | Supply level in %: actual doctors / target doctors × 100. | `core.versorgungsgrad` |
| **Vertragsarzt** | Doctor licensed to treat statutory-insured patients (has a Zulassung). | `core.teilnahme` (ZUL) |
| **Verwaltungskosten** | Administration fee the KV deducts from the fees. | `core.honorarbescheid` |
| **Verzicht** | Renunciation of the licence (e.g. retirement). | `core.zulassungsverfahren` |
| **Wirtschaftlichkeitsprüfung** | Efficiency audit (e.g. of prescription costs). | `core.pruefverfahren` |
| **Zulassung** | Licence to take part in statutory care as Vertragsarzt. | `core.teilnahme` (ZUL) |
| **Zulassungsausschuss** | Licensing committee (doctors and Kassen) that decides on licences. | `core.zulassungsverfahren` |
| **Zulassungsbeschränkung (gesperrt)** | Planning area closed for new licences because it is over-supplied (> 110 %). | `core.versorgungsgrad.status` |
