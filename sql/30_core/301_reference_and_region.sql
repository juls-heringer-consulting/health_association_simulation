/* =============================================================================
   301_reference_and_region.sql
   Reference (lookup) tables and the region model.

   KEY POLICY (see docs/design_decisions.md, DD-03):
     * small code lists we control      -> the code itself is the primary key
       (kassenart_code, altersgruppe_code, quartal_code, ...). Readable in every
       fact row and stable.
     * entities with a lifecycle         -> surrogate key <table>_id INT IDENTITY,
       plus a UNIQUE constraint on the business key (AGS, IK, GOP code, ...).
       Business keys can change (Kassen merge, catalogues get new versions);
       surrogate keys never do.
     * association / measurement tables -> composite primary key of their parts.

   Every core table has two technical columns:
     load_batch_id  batch that last wrote the row (NULL = seeded by this script)
     loaded_at      when the row was last written
   ============================================================================= */
USE KVSim;
GO

/* ---------- Region -------------------------------------------------------- */
-- One row per Kreis (district). The AGS (Amtlicher Gemeindeschluessel) is the
-- official key: 2 digits Land (10 = Saarland) + 1 Regierungsbezirk + 2 Kreis.
CREATE TABLE core.kreis (
    kreis_id        INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_kreis PRIMARY KEY,
    ags             CHAR(5)       NOT NULL CONSTRAINT uq_kreis_ags UNIQUE,
    name            NVARCHAR(100) NOT NULL,
    kreisart        NVARCHAR(30)  NOT NULL,
    verwaltungssitz NVARCHAR(60)  NOT NULL,
    geo_breite      DECIMAL(8,5)  NULL,   -- latitude of the seat (approximate)
    geo_laenge      DECIMAL(8,5)  NULL,   -- longitude of the seat (approximate)
    load_batch_id   INT           NULL,
    loaded_at       DATETIME2(0)  NOT NULL CONSTRAINT df_kreis_loaded_at DEFAULT (SYSDATETIME()),
    -- CHAR(5) + LIKE pattern: an AGS is a code, not a number (leading zeros, no arithmetic)
    CONSTRAINT ck_kreis_ags CHECK (ags LIKE '[0-9][0-9][0-9][0-9][0-9]'),
    CONSTRAINT ck_kreis_geo CHECK (geo_breite BETWEEN 47 AND 56 AND geo_laenge BETWEEN 5 AND 16)
);

CREATE TABLE core.altersgruppe (
    altersgruppe_code     VARCHAR(5)    NOT NULL CONSTRAINT pk_altersgruppe PRIMARY KEY,
    bezeichnung           NVARCHAR(40)  NOT NULL,
    alter_von             TINYINT       NOT NULL,
    alter_bis             TINYINT       NULL,      -- NULL = open-ended (75+)
    statistik_bezeichnung NVARCHAR(60)  NOT NULL CONSTRAINT uq_altersgruppe_statistik UNIQUE,  -- label used by the statistics office
    sortierung            TINYINT       NOT NULL,
    load_batch_id         INT           NULL,
    loaded_at             DATETIME2(0)  NOT NULL CONSTRAINT df_altersgruppe_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT ck_altersgruppe_range CHECK (alter_bis IS NULL OR alter_bis >= alter_von)
);
INSERT INTO core.altersgruppe (altersgruppe_code, bezeichnung, alter_von, alter_bis, statistik_bezeichnung, sortierung) VALUES
    ('00-05', N'0 bis 5 Jahre',   0,  5,    N'unter 6 Jahre',          1),
    ('06-17', N'6 bis 17 Jahre',  6,  17,   N'6 bis unter 18 Jahre',   2),
    ('18-39', N'18 bis 39 Jahre', 18, 39,   N'18 bis unter 40 Jahre',  3),
    ('40-64', N'40 bis 64 Jahre', 40, 64,   N'40 bis unter 65 Jahre',  4),
    ('65-74', N'65 bis 74 Jahre', 65, 74,   N'65 bis unter 75 Jahre',  5),
    ('75+',   N'75 Jahre und älter', 75, NULL, N'75 Jahre und mehr',   6);

-- Population per Kreis, reference date, age group and sex (measurement table -> composite PK)
CREATE TABLE core.einwohner (
    kreis_id          INT          NOT NULL CONSTRAINT fk_einwohner_kreis REFERENCES core.kreis (kreis_id),
    stichtag          DATE         NOT NULL,
    altersgruppe_code VARCHAR(5)   NOT NULL CONSTRAINT fk_einwohner_altersgruppe REFERENCES core.altersgruppe (altersgruppe_code),
    geschlecht        CHAR(1)      NOT NULL CONSTRAINT ck_einwohner_geschlecht CHECK (geschlecht IN ('w', 'm', 'd')),
    anzahl            INT          NOT NULL CONSTRAINT ck_einwohner_anzahl CHECK (anzahl >= 0),
    load_batch_id     INT          NULL,
    loaded_at         DATETIME2(0) NOT NULL CONSTRAINT df_einwohner_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT pk_einwohner PRIMARY KEY (kreis_id, stichtag, altersgruppe_code, geschlecht)
);

/* ---------- Calendar ------------------------------------------------------ */
CREATE TABLE core.quartal (
    quartal_code  CHAR(6)      NOT NULL CONSTRAINT pk_quartal PRIMARY KEY,   -- e.g. 2025Q1
    jahr          SMALLINT     NOT NULL,
    quartal_nr    TINYINT      NOT NULL CONSTRAINT ck_quartal_nr CHECK (quartal_nr BETWEEN 1 AND 4),
    erster_tag    DATE         NOT NULL,
    letzter_tag   DATE         NOT NULL,
    load_batch_id INT          NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_quartal_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT uq_quartal_jahr_nr UNIQUE (jahr, quartal_nr),
    CONSTRAINT ck_quartal_code CHECK (quartal_code = CONCAT(jahr, 'Q', quartal_nr))
);
-- Seed 2024Q1 .. 2026Q4 with a recursive CTE (a CTE that references itself).
WITH q AS (
    SELECT CAST('2024-01-01' AS DATE) AS erster_tag
    UNION ALL
    SELECT DATEADD(QUARTER, 1, erster_tag) FROM q WHERE erster_tag < '2026-10-01'
)
INSERT INTO core.quartal (quartal_code, jahr, quartal_nr, erster_tag, letzter_tag)
SELECT CONCAT(YEAR(erster_tag), 'Q', DATEPART(QUARTER, erster_tag)),
       YEAR(erster_tag), DATEPART(QUARTER, erster_tag), erster_tag,
       DATEADD(DAY, -1, DATEADD(QUARTER, 1, erster_tag))
FROM q;

/* ---------- Insurers ------------------------------------------------------- */
CREATE TABLE core.kassenart (
    kassenart_code VARCHAR(4)    NOT NULL CONSTRAINT pk_kassenart PRIMARY KEY,
    bezeichnung    NVARCHAR(60)  NOT NULL,
    load_batch_id  INT           NULL,
    loaded_at      DATETIME2(0)  NOT NULL CONSTRAINT df_kassenart_loaded_at DEFAULT (SYSDATETIME())
);
INSERT INTO core.kassenart (kassenart_code, bezeichnung) VALUES
    ('AOK', N'Allgemeine Ortskrankenkasse'), ('BKK', N'Betriebskrankenkasse'),
    ('IKK', N'Innungskrankenkasse'), ('EK', N'Ersatzkasse'),
    ('KN', N'Knappschaft'), ('LKK', N'Landwirtschaftliche Krankenkasse');

CREATE TABLE core.krankenkasse (
    krankenkasse_id INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_krankenkasse PRIMARY KEY,
    ik              CHAR(9)       NOT NULL CONSTRAINT uq_krankenkasse_ik UNIQUE,   -- Institutionskennzeichen
    name            NVARCHAR(150) NOT NULL,
    kassenart_code  VARCHAR(4)    NOT NULL CONSTRAINT fk_krankenkasse_kassenart REFERENCES core.kassenart (kassenart_code),
    load_batch_id   INT           NULL,
    loaded_at       DATETIME2(0)  NOT NULL CONSTRAINT df_krankenkasse_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT ck_krankenkasse_ik CHECK (ik LIKE REPLICATE('[0-9]', 9))
);

/* ---------- Physician groups ---------------------------------------------- */
-- Arztgruppe = group used by the Bedarfsplanung (needs planning), e.g. "Hausaerzte".
CREATE TABLE core.arztgruppe (
    arztgruppe_code               VARCHAR(4)    NOT NULL CONSTRAINT pk_arztgruppe PRIMARY KEY,
    bezeichnung                   NVARCHAR(100) NOT NULL,
    versorgungsebene              NVARCHAR(60)  NOT NULL,
    planungsbereich_typ           VARCHAR(5)    NOT NULL CONSTRAINT ck_arztgruppe_pb_typ CHECK (planungsbereich_typ IN ('KREIS', 'ROR')),
    verhaeltniszahl               INT           NOT NULL CONSTRAINT ck_arztgruppe_vz CHECK (verhaeltniszahl > 0),
    schwelle_unterversorgung_pct  DECIMAL(5,1)  NOT NULL,
    load_batch_id                 INT           NULL,
    loaded_at                     DATETIME2(0)  NOT NULL CONSTRAINT df_arztgruppe_loaded_at DEFAULT (SYSDATETIME())
);

-- Fachgruppe = specialty code, digits 8-9 of the LANR (KBV Arztgruppenschluessel).
CREATE TABLE core.fachgruppe (
    fachgruppe_code CHAR(2)       NOT NULL CONSTRAINT pk_fachgruppe PRIMARY KEY,
    bezeichnung     NVARCHAR(100) NOT NULL,
    arztgruppe_code VARCHAR(4)    NULL CONSTRAINT fk_fachgruppe_arztgruppe REFERENCES core.arztgruppe (arztgruppe_code),
    load_batch_id   INT           NULL,
    loaded_at       DATETIME2(0)  NOT NULL CONSTRAINT df_fachgruppe_loaded_at DEFAULT (SYSDATETIME())
);

/* ---------- Small code lists we own (seeded here) --------------------------- */
CREATE TABLE core.kooperationsform (
    kooperationsform_code VARCHAR(3)   NOT NULL CONSTRAINT pk_kooperationsform PRIMARY KEY,
    bezeichnung           NVARCHAR(60) NOT NULL,
    load_batch_id         INT          NULL,
    loaded_at             DATETIME2(0) NOT NULL CONSTRAINT df_kooperationsform_loaded_at DEFAULT (SYSDATETIME())
);
INSERT INTO core.kooperationsform (kooperationsform_code, bezeichnung) VALUES
    ('EP', N'Einzelpraxis'), ('BAG', N'Berufsausübungsgemeinschaft'), ('MVZ', N'Medizinisches Versorgungszentrum');

CREATE TABLE core.teilnahmeform (
    teilnahmeform_code VARCHAR(3)    NOT NULL CONSTRAINT pk_teilnahmeform PRIMARY KEY,
    bezeichnung        NVARCHAR(80)  NOT NULL,
    load_batch_id      INT           NULL,
    loaded_at          DATETIME2(0)  NOT NULL CONSTRAINT df_teilnahmeform_loaded_at DEFAULT (SYSDATETIME())
);
INSERT INTO core.teilnahmeform (teilnahmeform_code, bezeichnung) VALUES
    ('ZUL', N'Zulassung (Vertragsarzt / Vertragspsychotherapeut)'),
    ('ANG', N'Anstellung (angestellte Ärztin / angestellter Arzt)');

CREATE TABLE core.scheinuntergruppe (
    scheinuntergruppe_code CHAR(2)      NOT NULL CONSTRAINT pk_scheinuntergruppe PRIMARY KEY,
    bezeichnung            NVARCHAR(60) NOT NULL,
    load_batch_id          INT          NULL,
    loaded_at              DATETIME2(0) NOT NULL CONSTRAINT df_scheinuntergruppe_loaded_at DEFAULT (SYSDATETIME())
);
INSERT INTO core.scheinuntergruppe (scheinuntergruppe_code, bezeichnung) VALUES
    ('00', N'Ambulante Behandlung'), ('24', N'Mit-/Weiterbehandlung (Überweisung)'), ('43', N'Notfall');

CREATE TABLE core.qs_bereich (
    qs_bereich_code VARCHAR(5)    NOT NULL CONSTRAINT pk_qs_bereich PRIMARY KEY,
    bezeichnung     NVARCHAR(60)  NOT NULL,
    rechtsgrundlage NVARCHAR(200) NOT NULL,
    load_batch_id   INT           NULL,
    loaded_at       DATETIME2(0)  NOT NULL CONSTRAINT df_qs_bereich_loaded_at DEFAULT (SYSDATETIME())
);
INSERT INTO core.qs_bereich (qs_bereich_code, bezeichnung, rechtsgrundlage) VALUES
    ('US',   N'Ultraschalldiagnostik', N'Ultraschall-Vereinbarung nach § 135 Abs. 2 SGB V'),
    ('KOLO', N'Koloskopie',            N'Qualitätssicherungsvereinbarung zur Koloskopie nach § 135 Abs. 2 SGB V'),
    ('AKU',  N'Akupunktur',            N'Qualitätssicherungsvereinbarung Akupunktur bei chronisch schmerzkranken Patienten'),
    ('HKS',  N'Hautkrebs-Screening',   N'Krebsfrüherkennungs-Richtlinie des G-BA (Genehmigung durch die KV)');

/* ---------- EBM catalogue (fee schedule) and ICD-10-GM --------------------------- */
CREATE TABLE core.ebm_kapitel (
    kapitel_nr    TINYINT       NOT NULL CONSTRAINT pk_ebm_kapitel PRIMARY KEY,
    bereich       VARCHAR(5)    NOT NULL,
    bezeichnung   NVARCHAR(100) NOT NULL,
    load_batch_id INT           NULL,
    loaded_at     DATETIME2(0)  NOT NULL CONSTRAINT df_ebm_kapitel_loaded_at DEFAULT (SYSDATETIME())
);

-- GOP = Gebuehrenordnungsposition (billing code). Chapter title lives in ebm_kapitel,
-- NOT repeated here: it depends on kapitel_nr, not on the GOP (3rd normal form).
CREATE TABLE core.gop (
    gop_id             INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_gop PRIMARY KEY,
    gop_code           CHAR(5)       NOT NULL CONSTRAINT uq_gop_code UNIQUE,
    bezeichnung        NVARCHAR(200) NOT NULL,
    kapitel_nr         TINYINT       NOT NULL CONSTRAINT fk_gop_ebm_kapitel REFERENCES core.ebm_kapitel (kapitel_nr),
    punktzahl          INT           NOT NULL CONSTRAINT ck_gop_punktzahl CHECK (punktzahl > 0),
    pruefzeit_min      SMALLINT      NULL,      -- minutes used by the Plausibilitaetspruefung; NULL = none
    ist_extrabudgetaer BIT           NOT NULL,  -- 1 = paid outside the budget (full price)
    qs_bereich_code    VARCHAR(5)    NULL CONSTRAINT fk_gop_qs_bereich REFERENCES core.qs_bereich (qs_bereich_code),
    load_batch_id      INT           NULL,
    loaded_at          DATETIME2(0)  NOT NULL CONSTRAINT df_gop_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT ck_gop_code CHECK (gop_code LIKE '[0-9][0-9][0-9][0-9][0-9]')
);

CREATE TABLE core.orientierungswert (
    jahr          SMALLINT     NOT NULL CONSTRAINT pk_orientierungswert PRIMARY KEY,
    euro_je_punkt DECIMAL(9,6) NOT NULL CONSTRAINT ck_orientierungswert_positiv CHECK (euro_je_punkt > 0),
    load_batch_id INT          NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_orientierungswert_loaded_at DEFAULT (SYSDATETIME())
);

CREATE TABLE core.icd10 (
    icd_id        INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_icd10 PRIMARY KEY,
    icd_code      VARCHAR(7)    NOT NULL CONSTRAINT uq_icd10_code UNIQUE,
    bezeichnung   NVARCHAR(300) NOT NULL,
    kapitel       VARCHAR(5)    NOT NULL,   -- roman numeral, e.g. IX = diseases of the circulatory system
    load_batch_id INT           NULL,
    loaded_at     DATETIME2(0)  NOT NULL CONSTRAINT df_icd10_loaded_at DEFAULT (SYSDATETIME())
);
GO
