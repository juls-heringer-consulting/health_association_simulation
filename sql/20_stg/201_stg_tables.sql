/* =============================================================================
   201_stg_tables.sql
   STAGING layer = 1:1 landing zone for the source files.

   Rules of this layer (see docs/concepts/03_staging_and_lineage.md):
     * one table per source file type, named <source system>_<content>
     * column names = source header names (lower case, umlauts transliterated)
     * ALL business columns are text (NVARCHAR) - no conversion, no constraints.
       A file with a broken date must still land, so we can see and report it.
     * XML files land as one row per file in an XML column, JSON/text files in
       NVARCHAR(MAX). They are shredded later in T-SQL (OPENJSON, XQuery).
     * every row carries lineage: load_batch_id, source_file, source_row_nr
     * staging only keeps the latest load (the loader truncates before loading)
   Re-runnable: drops and recreates all stg tables (staging data is disposable).
   ============================================================================= */
USE KVSim;
GO

EXEC meta.usp_drop_tables @schema = N'stg';
GO

/* ---------- Statistisches Amt Saarland --------------------------------------- */
CREATE TABLE stg.statistik_bevoelkerung (
    stichtag      NVARCHAR(20)  NULL,
    ags           NVARCHAR(20)  NULL,
    kreis         NVARCHAR(200) NULL,
    altersgruppe  NVARCHAR(100) NULL,
    geschlecht    NVARCHAR(20)  NULL,
    anzahl        NVARCHAR(20)  NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_statistik_bevoelkerung_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.statistik_kreise_geojson (
    content       NVARCHAR(MAX) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_statistik_kreise_geojson_loaded_at DEFAULT (SYSDATETIME())
);

/* ---------- KBV / BfArM reference data -------------------------------------- */
CREATE TABLE stg.kbv_arztgruppenschluessel (
    schluessel    NVARCHAR(20)  NULL,
    bezeichnung   NVARCHAR(200) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_kbv_arztgruppenschluessel_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.kbv_ebm_xml (
    content       XML NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_kbv_ebm_xml_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.bfarm_icd10 (
    kapitel       NVARCHAR(20)  NULL,
    code          NVARCHAR(20)  NULL,
    titel         NVARCHAR(400) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_bfarm_icd10_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.kassen_krankenkassen (
    ik            NVARCHAR(20)  NULL,
    name          NVARCHAR(200) NULL,
    kassenart     NVARCHAR(20)  NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_kassen_krankenkassen_loaded_at DEFAULT (SYSDATETIME())
);

/* ---------- Arztregister ---------------------------------------------------- */
CREATE TABLE stg.arztregister_aerzte (
    lanr          NVARCHAR(20)  NULL,
    efn           NVARCHAR(20)  NULL,
    titel         NVARCHAR(100) NULL,
    vorname       NVARCHAR(100) NULL,
    nachname      NVARCHAR(100) NULL,
    geschlecht    NVARCHAR(10)  NULL,
    geburtsjahr   NVARCHAR(10)  NULL,
    fachgruppe    NVARCHAR(10)  NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_arztregister_aerzte_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.arztregister_betriebsstaetten (
    bsnr             NVARCHAR(20)  NULL,
    name             NVARCHAR(300) NULL,
    kooperationsform NVARCHAR(20)  NULL,
    strasse          NVARCHAR(200) NULL,
    ort              NVARCHAR(100) NULL,
    kreis_ags        NVARCHAR(20)  NULL,
    gruendungsdatum  NVARCHAR(20)  NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_arztregister_betriebsstaetten_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.arztregister_teilnahmen (
    lanr              NVARCHAR(20) NULL,
    bsnr              NVARCHAR(20) NULL,
    teilnahmeform     NVARCHAR(10) NULL,
    anrechnungsfaktor NVARCHAR(10) NULL,
    gueltig_ab        NVARCHAR(20) NULL,
    gueltig_bis       NVARCHAR(20) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_arztregister_teilnahmen_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.arztregister_teilnahme_status (
    lanr          NVARCHAR(20) NULL,
    bsnr          NVARCHAR(20) NULL,
    teilnahme_ab  NVARCHAR(20) NULL,
    status        NVARCHAR(20) NULL,
    status_ab     NVARCHAR(20) NULL,
    status_bis    NVARCHAR(20) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_arztregister_teilnahme_status_loaded_at DEFAULT (SYSDATETIME())
);

/* ---------- Zulassungsausschuss ------------------------------------------------ */
CREATE TABLE stg.zulassung_verfahren_xml (
    content       XML NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_zulassung_verfahren_xml_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.zulassung_protokolle (
    content       NVARCHAR(MAX) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_zulassung_protokolle_loaded_at DEFAULT (SYSDATETIME())
);

/* ---------- Bedarfsplanung (Excel workbook, one table per sheet) --------------- */
CREATE TABLE stg.bedarfsplanung_arztgruppen (
    code                  NVARCHAR(20)  NULL,
    arztgruppe            NVARCHAR(200) NULL,
    versorgungsebene      NVARCHAR(200) NULL,
    planungsbereichstyp   NVARCHAR(20)  NULL,
    verhaeltniszahl       NVARCHAR(20)  NULL,
    fachgruppenschluessel NVARCHAR(100) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_bedarfsplanung_arztgruppen_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.bedarfsplanung_planungsbereiche (
    pb_code         NVARCHAR(20)  NULL,
    planungsbereich NVARCHAR(200) NULL,
    typ             NVARCHAR(20)  NULL,
    kreise_ags      NVARCHAR(200) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_bedarfsplanung_planungsbereiche_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.bedarfsplanung_versorgungsgrade (
    stichtag        NVARCHAR(30) NULL,
    pb_code         NVARCHAR(20) NULL,
    arztgruppe      NVARCHAR(20) NULL,
    einwohner       NVARCHAR(20) NULL,
    verhaeltniszahl NVARCHAR(20) NULL,
    soll            NVARCHAR(30) NULL,
    ist             NVARCHAR(30) NULL,
    versorgungsgrad NVARCHAR(30) NULL,
    status          NVARCHAR(20) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_bedarfsplanung_versorgungsgrade_loaded_at DEFAULT (SYSDATETIME())
);

/* ---------- Abrechnung (quarterly CSV export of the billing system) ------------ */
CREATE TABLE stg.abrechnung_faelle (
    fallnummer           NVARCHAR(30)  NULL,
    bsnr                 NVARCHAR(20)  NULL,
    quartal              NVARCHAR(10)  NULL,
    patientenpseudonym   NVARCHAR(100) NULL,
    kassen_ik            NVARCHAR(20)  NULL,
    versichertenstatus   NVARCHAR(10)  NULL,
    geschlecht           NVARCHAR(10)  NULL,
    geburtsjahr          NVARCHAR(10)  NULL,
    scheinuntergruppe    NVARCHAR(10)  NULL,
    tss_vermittlungscode NVARCHAR(30)  NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_abrechnung_faelle_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.abrechnung_leistungen (
    fallnummer    NVARCHAR(30) NULL,
    position      NVARCHAR(10) NULL,
    datum         NVARCHAR(20) NULL,
    lanr          NVARCHAR(20) NULL,
    gop           NVARCHAR(20) NULL,
    anzahl        NVARCHAR(10) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_abrechnung_leistungen_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.abrechnung_diagnosen (
    fallnummer    NVARCHAR(30) NULL,
    icd           NVARCHAR(20) NULL,
    sicherheit    NVARCHAR(10) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_abrechnung_diagnosen_loaded_at DEFAULT (SYSDATETIME())
);

/* ---------- Honorar --------------------------------------------------------- */
CREATE TABLE stg.honorar_bescheide_xml (
    content       XML NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_honorar_bescheide_xml_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.honorar_abschlaege (
    buchungsdatum    NVARCHAR(20)  NULL,
    bsnr             NVARCHAR(20)  NULL,
    betrag           NVARCHAR(30)  NULL,
    verwendungszweck NVARCHAR(200) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_honorar_abschlaege_loaded_at DEFAULT (SYSDATETIME())
);

/* ---------- Versorgung: Terminservicestelle and Bereitschaftsdienst ------------ */
CREATE TABLE stg.tss_anfragen_json (
    content       NVARCHAR(MAX) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_tss_anfragen_json_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.bd_bereitschaftspraxen (
    kennung       NVARCHAR(20)  NULL,
    name          NVARCHAR(200) NULL,
    ort           NVARCHAR(100) NULL,
    kreis_ags     NVARCHAR(20)  NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_bd_bereitschaftspraxen_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.bd_dienstplan (
    dienst_id          NVARCHAR(40) NULL,
    kennung            NVARCHAR(20) NULL,
    datum              NVARCHAR(20) NULL,
    beginn             NVARCHAR(10) NULL,
    ende               NVARCHAR(10) NULL,
    lanr               NVARCHAR(20) NULL,
    getauscht_von_lanr NVARCHAR(20) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_bd_dienstplan_loaded_at DEFAULT (SYSDATETIME())
);

/* ---------- Qualitaetssicherung, Kammern, Pruefungsstelle ---------------------- */
CREATE TABLE stg.qs_genehmigungen (
    lanr             NVARCHAR(20) NULL,
    leistungsbereich NVARCHAR(20) NULL,
    genehmigt_ab     NVARCHAR(20) NULL,
    genehmigt_bis    NVARCHAR(20) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_qs_genehmigungen_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.kammer_fortbildungspunkte (
    efn           NVARCHAR(20) NULL,
    jahr          NVARCHAR(10) NULL,
    punkte        NVARCHAR(10) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_kammer_fortbildungspunkte_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.pruefung_verfahren_xml (
    content       XML NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_pruefung_verfahren_xml_loaded_at DEFAULT (SYSDATETIME())
);

/* ---------- Verordnungen (fixed-width file: one raw line per row) -------------- */
CREATE TABLE stg.verordnung_zeilen (
    zeile         NVARCHAR(200) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_verordnung_zeilen_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.verordnung_richtgroessen (
    arztgruppe               NVARCHAR(20) NULL,
    jahr                     NVARCHAR(10) NULL,
    verordnungsart           NVARCHAR(10) NULL,
    richtgroesse_eur_je_fall NVARCHAR(20) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_verordnung_richtgroessen_loaded_at DEFAULT (SYSDATETIME())
);

/* ---------- Kommunikation (documents) ------------------------------------------ */
CREATE TABLE stg.mitgliederservice_anfragen_json (
    content       NVARCHAR(MAX) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_mitgliederservice_anfragen_json_loaded_at DEFAULT (SYSDATETIME())
);
CREATE TABLE stg.beschwerden_txt (
    content       NVARCHAR(MAX) NULL,
    load_batch_id INT NOT NULL, source_file NVARCHAR(260) NOT NULL, source_row_nr INT NOT NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_stg_beschwerden_txt_loaded_at DEFAULT (SYSDATETIME())
);
GO

/* ---------- Descriptions for the data dictionary --------------------------------- */
EXEC meta.usp_describe 'stg', 'statistik_bevoelkerung',          NULL, N'Source: statistik/bevoelkerung_kreise_2024.csv (Statistisches Amt, cp1252, metadata header lines).';
EXEC meta.usp_describe 'stg', 'statistik_kreise_geojson',        NULL, N'Source: statistik/kreise_saarland.geojson - one row per file, shredded with OPENJSON.';
EXEC meta.usp_describe 'stg', 'kbv_arztgruppenschluessel',       NULL, N'Source: kbv_referenz/arztgruppenschluessel.csv - Fachgruppe codes (LANR digits 8-9).';
EXEC meta.usp_describe 'stg', 'kbv_ebm_xml',                     NULL, N'Source: kbv_referenz/ebm_2025.xml - EBM catalogue, one row per file (XML).';
EXEC meta.usp_describe 'stg', 'bfarm_icd10',                     NULL, N'Source: bfarm/icd10gm2025_auswahl.txt - ICD-10-GM selection, file has no header row.';
EXEC meta.usp_describe 'stg', 'kassen_krankenkassen',            NULL, N'Source: kassenverzeichnis/krankenkassen.csv.';
EXEC meta.usp_describe 'stg', 'arztregister_aerzte',             NULL, N'Source: arztregister/aerzte.csv - persons in the Arztregister.';
EXEC meta.usp_describe 'stg', 'arztregister_betriebsstaetten',   NULL, N'Source: arztregister/betriebsstaetten.csv - practices (BSNR).';
EXEC meta.usp_describe 'stg', 'arztregister_teilnahmen',         NULL, N'Source: arztregister/teilnahmen.csv - who works where (Zulassung/Anstellung).';
EXEC meta.usp_describe 'stg', 'arztregister_teilnahme_status',   NULL, N'Source: arztregister/teilnahme_status.csv - status history per Teilnahme.';
EXEC meta.usp_describe 'stg', 'zulassung_verfahren_xml',         NULL, N'Source: zulassungsausschuss/zulassungsverfahren_2025.xml - one row per file (XML).';
EXEC meta.usp_describe 'stg', 'zulassung_protokolle',            NULL, N'Source: zulassungsausschuss/protokolle/*.md - one row per Markdown file.';
EXEC meta.usp_describe 'stg', 'bedarfsplanung_arztgruppen',      NULL, N'Source: bedarfsplanung_2025.xlsx, sheet Arztgruppen.';
EXEC meta.usp_describe 'stg', 'bedarfsplanung_planungsbereiche', NULL, N'Source: bedarfsplanung_2025.xlsx, sheet Planungsbereiche.';
EXEC meta.usp_describe 'stg', 'bedarfsplanung_versorgungsgrade', NULL, N'Source: bedarfsplanung_2025.xlsx, sheet Versorgungsgrade (header in row 3).';
EXEC meta.usp_describe 'stg', 'abrechnung_faelle',               NULL, N'Source: abrechnung/faelle_<year>Q<n>.csv - one row per Behandlungsfall.';
EXEC meta.usp_describe 'stg', 'abrechnung_leistungen',           NULL, N'Source: abrechnung/leistungen_<year>Q<n>.csv - one row per billed GOP.';
EXEC meta.usp_describe 'stg', 'abrechnung_diagnosen',            NULL, N'Source: abrechnung/diagnosen_<year>Q<n>.csv - one row per ICD per case.';
EXEC meta.usp_describe 'stg', 'honorar_bescheide_xml',           NULL, N'Source: honorar/honorarbescheide_<year>Q<n>.xml - one row per file (XML).';
EXEC meta.usp_describe 'stg', 'honorar_abschlaege',              NULL, N'Source: honorar/abschlagszahlungen_<year>.csv (finance system, cp1252, German number format).';
EXEC meta.usp_describe 'stg', 'tss_anfragen_json',               NULL, N'Source: terminservice/tss_anfragen_<year>_pNNN.json - one row per API page.';
EXEC meta.usp_describe 'stg', 'bd_bereitschaftspraxen',          NULL, N'Source: bereitschaftsdienst/bereitschaftspraxen.csv.';
EXEC meta.usp_describe 'stg', 'bd_dienstplan',                   NULL, N'Source: bereitschaftsdienst/dienstplan_<year>.csv - shifts; end time may be on the next day.';
EXEC meta.usp_describe 'stg', 'qs_genehmigungen',                NULL, N'Source: qualitaetssicherung/qs_genehmigungen.csv.';
EXEC meta.usp_describe 'stg', 'kammer_fortbildungspunkte',       NULL, N'Source: kammern/fortbildungspunkte_2021_2025.csv - keyed by EFN, not LANR.';
EXEC meta.usp_describe 'stg', 'pruefung_verfahren_xml',          NULL, N'Source: pruefungsstelle/pruefverfahren_<year>.xml - one row per file (XML).';
EXEC meta.usp_describe 'stg', 'verordnung_zeilen',               NULL, N'Source: verordnungen/verordnungen_<year>.txt - fixed-width records (HD/VO/TR), one raw line per row.';
EXEC meta.usp_describe 'stg', 'verordnung_richtgroessen',        NULL, N'Source: verordnungen/richtgroessen_<year>.csv.';
EXEC meta.usp_describe 'stg', 'mitgliederservice_anfragen_json', NULL, N'Source: mitgliederservice/anfragen_<year>.json (CRM export) - one row per file.';
EXEC meta.usp_describe 'stg', 'beschwerden_txt',                 NULL, N'Source: beschwerdemanagement/beschwerde_*.txt - one row per complaint file.';
GO
