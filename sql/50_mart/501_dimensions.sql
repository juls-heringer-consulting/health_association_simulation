/* =============================================================================
   501_dimensions.sql
   Dimension tables: the "who / what / where / when" of the star schemas.

   Conventions (see docs/concepts/07_star_schema_and_scd2.md):
     * surrogate key <name>_key (INT). The key -1 is the "unknown" member, so a
       fact row never needs a NULL foreign key.
     * dimensions are DENORMALISED on purpose (e.g. dim_fachgruppe repeats the
       Arztgruppe text): fewer joins, easier for report users. The normalised
       truth stays in core.
     * dim_datum uses a "smart key" yyyymmdd (20250331) - readable and sortable.
     * dim_arzt is a Slowly Changing Dimension type 2 (SCD2): a new version
       (row) whenever the doctor's practice or employment form changes.
   ============================================================================= */
USE KVSim;
GO

CREATE TABLE mart.dim_datum (
    datum_key      INT          NOT NULL CONSTRAINT pk_dim_datum PRIMARY KEY,
    datum          DATE         NULL,
    jahr           SMALLINT     NULL,
    quartal_nr     TINYINT      NULL,
    quartal_code   CHAR(6)      NULL,
    monat_nr       TINYINT      NULL,
    monat_name     NVARCHAR(12) NULL,
    kalenderwoche  TINYINT      NULL,
    wochentag_nr   TINYINT      NULL,    -- 1 = Monday ... 7 = Sunday
    wochentag_name NVARCHAR(12) NULL,
    ist_wochenende BIT          NULL,
    ist_feiertag   BIT          NULL,    -- public holiday in the Saarland
    feiertag_name  NVARCHAR(40) NULL
);
INSERT INTO mart.dim_datum (datum_key) VALUES (-1);   -- unknown member

CREATE TABLE mart.dim_quartal (
    quartal_key   INT          NOT NULL CONSTRAINT pk_dim_quartal PRIMARY KEY,   -- e.g. 20251
    quartal_code  CHAR(6)      NULL,
    quartal_label NVARCHAR(10) NULL,    -- e.g. 1/2025 (as printed on German documents)
    jahr          SMALLINT     NULL,
    quartal_nr    TINYINT      NULL,
    erster_tag    DATE         NULL,
    letzter_tag   DATE         NULL
);
INSERT INTO mart.dim_quartal (quartal_key, quartal_label) VALUES (-1, N'unbekannt');

CREATE TABLE mart.dim_region (
    region_key           INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_region PRIMARY KEY,
    kreis_id             INT           NULL CONSTRAINT uq_dim_region_kreis UNIQUE,
    ags                  CHAR(5)       NULL,
    kreis                NVARCHAR(100) NULL,
    kreisart             NVARCHAR(30)  NULL,
    verwaltungssitz      NVARCHAR(60)  NULL,
    planungsbereich_code VARCHAR(10)   NULL,
    land                 NVARCHAR(30)  NULL,
    geo_breite           DECIMAL(8,5)  NULL,
    geo_laenge           DECIMAL(8,5)  NULL
);

CREATE TABLE mart.dim_arztgruppe (
    arztgruppe_key      INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_arztgruppe PRIMARY KEY,
    arztgruppe_code     VARCHAR(4)    NULL CONSTRAINT uq_dim_arztgruppe_code UNIQUE,
    arztgruppe          NVARCHAR(100) NULL,
    versorgungsebene    NVARCHAR(60)  NULL,
    planungsbereich_typ VARCHAR(5)    NULL,
    verhaeltniszahl     INT           NULL
);

CREATE TABLE mart.dim_fachgruppe (
    fachgruppe_key   INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_fachgruppe PRIMARY KEY,
    fachgruppe_code  CHAR(2)       NULL CONSTRAINT uq_dim_fachgruppe_code UNIQUE,
    fachgruppe       NVARCHAR(100) NULL,
    arztgruppe_code  VARCHAR(4)    NULL,
    arztgruppe       NVARCHAR(100) NULL,
    versorgungsebene NVARCHAR(60)  NULL
);

-- SCD type 2: one row per VERSION of a doctor. arzt_id is the "durable key" that is the
-- same for all versions; arzt_key identifies one version. Facts store arzt_key, so they
-- keep pointing to the version that was valid when the service happened.
CREATE TABLE mart.dim_arzt (
    arzt_key           INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_arzt PRIMARY KEY,
    arzt_id            INT           NULL,
    lanr               CHAR(9)       NULL,
    arzt_name          NVARCHAR(160) NULL,
    geschlecht         CHAR(1)       NULL,
    geburtsjahr        SMALLINT      NULL,
    fachgruppe_code    CHAR(2)       NULL,
    fachgruppe         NVARCHAR(100) NULL,
    -- type-2 attributes: a change creates a new version
    praxis_bsnr        CHAR(9)       NULL,
    praxis_name        NVARCHAR(200) NULL,
    teilnahmeform_code VARCHAR(3)    NULL,
    anrechnungsfaktor  DECIMAL(3,2)  NULL,
    -- version validity [valid_from, valid_to)
    valid_from         DATE          NOT NULL,
    valid_to           DATE          NOT NULL,
    is_current         BIT           NOT NULL,
    CONSTRAINT uq_dim_arzt_version UNIQUE (arzt_id, valid_from)
);

CREATE TABLE mart.dim_praxis (
    praxis_key            INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_praxis PRIMARY KEY,
    praxis_id             INT           NULL CONSTRAINT uq_dim_praxis_praxis_id UNIQUE,
    bsnr                  CHAR(9)       NULL,
    praxis_name           NVARCHAR(200) NULL,
    kooperationsform_code VARCHAR(3)    NULL,
    kooperationsform      NVARCHAR(60)  NULL,
    ort                   NVARCHAR(60)  NULL,
    kreis                 NVARCHAR(100) NULL,
    gruendungsdatum       DATE          NULL
);

CREATE TABLE mart.dim_krankenkasse (
    kasse_key       INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_krankenkasse PRIMARY KEY,
    krankenkasse_id INT           NULL CONSTRAINT uq_dim_krankenkasse_id UNIQUE,
    ik              CHAR(9)       NULL,
    krankenkasse    NVARCHAR(150) NULL,
    kassenart_code  VARCHAR(4)    NULL,
    kassenart       NVARCHAR(60)  NULL
);

CREATE TABLE mart.dim_gop (
    gop_key            INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_gop PRIMARY KEY,
    gop_id             INT           NULL CONSTRAINT uq_dim_gop_id UNIQUE,
    gop_code           CHAR(5)       NULL,
    gop                NVARCHAR(200) NULL,
    kapitel_nr         TINYINT       NULL,
    kapitel            NVARCHAR(100) NULL,
    ebm_bereich        VARCHAR(5)    NULL,
    punktzahl          INT           NULL,
    pruefzeit_min      SMALLINT      NULL,
    ist_extrabudgetaer BIT           NULL,
    qs_bereich         NVARCHAR(60)  NULL
);

CREATE TABLE mart.dim_altersgruppe (
    altersgruppe_key  INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_altersgruppe PRIMARY KEY,
    altersgruppe_code VARCHAR(5)   NULL CONSTRAINT uq_dim_altersgruppe_code UNIQUE,
    altersgruppe      NVARCHAR(40) NULL,
    sortierung        TINYINT      NULL
);

CREATE TABLE mart.dim_planungsbereich (
    planungsbereich_key  INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dim_planungsbereich PRIMARY KEY,
    planungsbereich_id   INT           NULL CONSTRAINT uq_dim_planungsbereich_id UNIQUE,
    planungsbereich_code VARCHAR(10)   NULL,
    planungsbereich      NVARCHAR(100) NULL,
    typ                  VARCHAR(5)    NULL
);
GO

-- Unknown members (-1) for all dimensions with an IDENTITY key.
-- IDENTITY_INSERT allows us to insert an explicit value into an identity column.
SET IDENTITY_INSERT mart.dim_region ON;
INSERT INTO mart.dim_region (region_key, kreis) VALUES (-1, N'unbekannt');
SET IDENTITY_INSERT mart.dim_region OFF;
SET IDENTITY_INSERT mart.dim_arztgruppe ON;
INSERT INTO mart.dim_arztgruppe (arztgruppe_key, arztgruppe) VALUES (-1, N'unbekannt');
SET IDENTITY_INSERT mart.dim_arztgruppe OFF;
SET IDENTITY_INSERT mart.dim_fachgruppe ON;
INSERT INTO mart.dim_fachgruppe (fachgruppe_key, fachgruppe) VALUES (-1, N'unbekannt');
SET IDENTITY_INSERT mart.dim_fachgruppe OFF;
SET IDENTITY_INSERT mart.dim_arzt ON;
INSERT INTO mart.dim_arzt (arzt_key, arzt_name, valid_from, valid_to, is_current) VALUES (-1, N'unbekannt', '1900-01-01', '9999-12-31', 1);
SET IDENTITY_INSERT mart.dim_arzt OFF;
SET IDENTITY_INSERT mart.dim_praxis ON;
INSERT INTO mart.dim_praxis (praxis_key, praxis_name) VALUES (-1, N'unbekannt');
SET IDENTITY_INSERT mart.dim_praxis OFF;
SET IDENTITY_INSERT mart.dim_krankenkasse ON;
INSERT INTO mart.dim_krankenkasse (kasse_key, krankenkasse) VALUES (-1, N'unbekannt');
SET IDENTITY_INSERT mart.dim_krankenkasse OFF;
SET IDENTITY_INSERT mart.dim_gop ON;
INSERT INTO mart.dim_gop (gop_key, gop) VALUES (-1, N'unbekannt');
SET IDENTITY_INSERT mart.dim_gop OFF;
SET IDENTITY_INSERT mart.dim_altersgruppe ON;
INSERT INTO mart.dim_altersgruppe (altersgruppe_key, altersgruppe) VALUES (-1, N'unbekannt');
SET IDENTITY_INSERT mart.dim_altersgruppe OFF;
SET IDENTITY_INSERT mart.dim_planungsbereich ON;
INSERT INTO mart.dim_planungsbereich (planungsbereich_key, planungsbereich) VALUES (-1, N'unbekannt');
SET IDENTITY_INSERT mart.dim_planungsbereich OFF;
GO
