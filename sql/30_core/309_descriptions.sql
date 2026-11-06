/* =============================================================================
   309_descriptions.sql
   Table and column descriptions (MS_Description) for the core layer.
   They feed meta.v_data_dictionary and docs/data_dictionary.md.
   ============================================================================= */
USE KVSim;
GO

DECLARE @d TABLE (tbl SYSNAME, col SYSNAME NULL, txt NVARCHAR(3750));

INSERT INTO @d (tbl, col, txt) VALUES
-- region & reference
('kreis', NULL, N'Kreis / kreisfreie Stadt / Regionalverband (district). Source: GeoJSON of the statistics office.'),
('kreis', 'ags', N'Amtlicher Gemeindeschlüssel at Kreis level (5 digits). Business key.'),
('kreis', 'kreisart', N'Type of district (Landkreis, Regionalverband).'),
('kreis', 'verwaltungssitz', N'Seat of the district administration.'),
('kreis', 'geo_breite', N'Latitude of the seat (approximate, WGS84).'),
('kreis', 'geo_laenge', N'Longitude of the seat (approximate, WGS84).'),
('altersgruppe', NULL, N'Age groups used by statistics, billing and TSS (conformed code list).'),
('altersgruppe', 'statistik_bezeichnung', N'Label used by the statistics office - used to map their file.'),
('einwohner', NULL, N'Population per Kreis, reference date, age group and sex (approximate, synthetic).'),
('quartal', NULL, N'Calendar quarters; billing in German statutory health insurance is quarterly.'),
('quartal', 'quartal_code', N'Quarter in the form YYYYQn, e.g. 2025Q1. Sources use other notations (12025, 1/2025).'),
('kassenart', NULL, N'Type of statutory health insurer (AOK, BKK, IKK, Ersatzkasse, Knappschaft, LKK).'),
('krankenkasse', NULL, N'Statutory health insurer (payer). Real names, SYNTHETIC IK numbers.'),
('krankenkasse', 'ik', N'Institutionskennzeichen (9 digits). Business key.'),
('arztgruppe', NULL, N'Physician group of the Bedarfsplanung (needs planning), e.g. Hausärzte.'),
('arztgruppe', 'verhaeltniszahl', N'Target ratio: inhabitants per doctor at 100 % supply (simplified).'),
('arztgruppe', 'planungsbereich_typ', N'Level of planning: KREIS or ROR (Raumordnungsregion).'),
('arztgruppe', 'schwelle_unterversorgung_pct', N'Below this Versorgungsgrad an area counts as undersupplied (75 % Hausärzte, 50 % others).'),
('fachgruppe', NULL, N'Specialty code = digits 8-9 of the LANR (KBV Arztgruppenschlüssel).'),
('fachgruppe', 'arztgruppe_code', N'Bedarfsplanung group this specialty counts towards (NULL = not planned).'),
('kooperationsform', NULL, N'Form of practice: Einzelpraxis, Berufsausübungsgemeinschaft, MVZ.'),
('teilnahmeform', NULL, N'Form of participation in statutory care: Zulassung or Anstellung.'),
('scheinuntergruppe', NULL, N'Type of billing case (KVDT Scheinuntergruppe), e.g. referral, emergency.'),
('qs_bereich', NULL, N'Quality-assurance area that requires a permit (Genehmigung) to bill its GOPs.'),
('ebm_kapitel', NULL, N'Chapter of the EBM fee schedule.'),
('gop', NULL, N'Gebührenordnungsposition (billing code) of the EBM. Points simplified.'),
('gop', 'gop_code', N'5-digit GOP code. Business key.'),
('gop', 'punktzahl', N'Points per unit (example values).'),
('gop', 'pruefzeit_min', N'Standard minutes used for time-plausibility checks; NULL = none.'),
('gop', 'ist_extrabudgetaer', N'1 = paid outside the budget at full price (EGV).'),
('gop', 'qs_bereich_code', N'If set, the doctor needs a valid QS-Genehmigung to bill this GOP.'),
('orientierungswert', NULL, N'Euro value of one EBM point per year.'),
('icd10', NULL, N'Selection of ICD-10-GM diagnosis codes (simplified).'),
-- Arztregister
('arzt', NULL, N'Physician or psychotherapist in the Arztregister (synthetic persons).'),
('arzt', 'lanr', N'Lebenslange Arztnummer: 6-digit id + check digit + 2-digit Fachgruppe. Business key.'),
('arzt', 'efn', N'Einheitliche Fortbildungsnummer - key used by the Kammer for CME points.'),
('arzt', 'geburtsjahr', N'Year of birth (only the year is kept: data minimisation).'),
('praxis', NULL, N'Betriebsstätte (practice site) with its BSNR.'),
('praxis', 'bsnr', N'Betriebsstättennummer (9 digits, starts with the KV code 73). Business key.'),
('praxis', 'kooperationsform_code', N'EP, BAG or MVZ.'),
('teilnahme', NULL, N'Participation of a doctor at a practice over time (resolves arzt-praxis many-to-many).'),
('teilnahme', 'anrechnungsfaktor', N'Share of a planning seat the person counts for (0.25 - 1.0).'),
('teilnahme', 'valid_from', N'Start of validity (inclusive).'),
('teilnahme', 'valid_to', N'End of validity (EXCLUSIVE); 9999-12-31 = open.'),
('teilnahme_status', NULL, N'Status history of a Teilnahme: AKTIV, RUHEND (suspended), BEENDET.'),
-- Bedarfsplanung & Zulassung
('planungsbereich', NULL, N'Planning area of the Bedarfsplanung.'),
('planungsbereich_kreis', NULL, N'Which Kreise make up a planning area.'),
('versorgungsgrad', NULL, N'Officially decided supply level per planning area, physician group and reference date.'),
('versorgungsgrad', 'ist_aerzte', N'Sum of Anrechnungsfaktoren of all doctors counted on the reference date.'),
('versorgungsgrad', 'versorgungsgrad_pct', N'Ist / Soll * 100. >110 % = closed (GESPERRT).'),
('zulassungsverfahren', NULL, N'Procedure before the Zulassungsausschuss (licensing committee).'),
('zulassungsverfahren', 'aktenzeichen', N'File number, e.g. ZA-2025-0007. Business key.'),
('zulassungsverfahren', 'teilnahme_id', N'Teilnahme created or changed by the decision (NULL if none).'),
('zulassungsverfahren_status', NULL, N'Status history of a Zulassungsverfahren (valid_to derived with LEAD).'),
-- Abrechnung
('abrechnungsfall', NULL, N'Behandlungsfall: one pseudonymised patient at one practice in one quarter. SAMPLE of real volume.'),
('abrechnungsfall', 'patient_pseudonym', N'Salted SHA-256 hash of the insurance number; the KVNR itself never enters the DWH.'),
('abrechnungsfall', 'versichertenstatus', N'M = Mitglied (member), F = Familienversicherter (family), R = Rentner (pensioner).'),
('abrechnungsfall', 'tss_vermittlungscode', N'Code of the TSS appointment if the case came via the Terminservicestelle.'),
('leistung', NULL, N'One billed GOP within a case.'),
('leistung', 'punktzahl', N'Points per unit copied from core.gop at load time (historical snapshot).'),
('leistung', 'arzt_id', N'Doctor (LANR) who performed the service.'),
('fall_diagnose', NULL, N'ICD-10 diagnoses of a case with Diagnosesicherheit (G/V/A/Z).'),
('honorarbescheid', NULL, N'Quarterly fee statement per practice as issued by the KV.'),
('honorarbescheid', 'punkte_berichtigt', N'Points removed by sachlich-rechnerische Berichtigung (e.g. GOP without permit).'),
('honorarbescheid', 'quote_mgv', N'Payout quota applied to budgeted points (simplified Honorarverteilung).'),
('honorarbescheid', 'auszahlungsbetrag', N'Remaining payment after administration fee and advance payments (negative = refund).'),
('abschlagszahlung', NULL, N'Monthly advance payment to a practice during a quarter.'),
-- Versorgung
('tss_fachgebiet', NULL, N'Mapping of the specialty labels of the TSS API to Arztgruppen.'),
('tss_anfrage', NULL, N'Request to the Terminservicestelle (116117) and the appointment arranged.'),
('tss_anfrage', 'wartezeit_tage', N'Computed: days between request and appointment.'),
('notfallpraxis', NULL, N'Bereitschaftsdienstpraxis (out-of-hours practice).'),
('bereitschaftsdienst', NULL, N'One out-of-hours shift and the doctor who served it.'),
('bereitschaftsdienst', 'getauscht_von_arzt_id', N'Originally scheduled doctor if the shift was swapped.'),
-- QS / Pruefung / Verordnung
('qs_genehmigung', NULL, N'Permit of a doctor for a QS area, with validity interval.'),
('fortbildungspunkte', NULL, N'CME points per doctor and year (§ 95d SGB V: 250 points in 5 years).'),
('pruefverfahren', NULL, N'Efficiency audit (Wirtschaftlichkeitsprüfung) of prescriptions by the Prüfungsstelle.'),
('verordnung', NULL, N'Aggregated prescription costs per practice, quarter and type (A = Arzneimittel, H = Heilmittel).'),
('richtgroesse', NULL, N'Target prescription volume in EUR per case (simplified).'),
-- Kommunikation
('dokumenttyp', NULL, N'Type of document with its default confidentiality.'),
('dokument', NULL, N'Unstructured document (enquiry, complaint, minutes, notice) with full text.'),
('dokument', 'quelle_referenz', N'Business key: ticket id, source file name or file number.'),
('dokument', 'inhalt', N'Full original text (NVARCHAR(MAX)); full-text index see sql/85_fulltext.'),
('dokument', 'inhalt_sha256', N'SHA-256 of the text to detect changes and duplicates.'),
('dokument_bezug', NULL, N'Links a document to exactly one arzt, praxis or Zulassungsverfahren (exclusive arc).');

-- technical columns: same text for every core table
INSERT INTO @d (tbl, col, txt)
SELECT t.name, c.name,
       CASE c.name WHEN 'load_batch_id' THEN N'Technical: batch (meta.load_batch) that last wrote the row; NULL = seeded by script.'
                   ELSE N'Technical: time the row was last written.' END
FROM sys.tables AS t
JOIN sys.columns AS c ON c.object_id = t.object_id
WHERE SCHEMA_NAME(t.schema_id) = N'core' AND c.name IN (N'load_batch_id', N'loaded_at');

DECLARE @tbl SYSNAME, @col SYSNAME, @txt NVARCHAR(3750);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT tbl, col, txt FROM @d;
OPEN c;
FETCH NEXT FROM c INTO @tbl, @col, @txt;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC meta.usp_describe @schema = N'core', @table = @tbl, @column = @col, @description = @txt;
    FETCH NEXT FROM c INTO @tbl, @col, @txt;
END
CLOSE c;
DEALLOCATE c;
GO
