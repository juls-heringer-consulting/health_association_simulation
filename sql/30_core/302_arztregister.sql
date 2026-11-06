/* =============================================================================
   302_arztregister.sql
   Physician register: persons, practices and who works where (Teilnahme).

   Model:
       arzt 1 ──< teilnahme >── 1 praxis        (many-to-many over time)
                     │
                     └──< teilnahme_status        (status history)

   A doctor can work at several practices over time (e.g. changes employer),
   and a practice has several doctors (BAG, MVZ). The associative entity
   "teilnahme" resolves this many-to-many relationship and carries the
   attributes of the relationship itself (form, Anrechnungsfaktor, validity).
   ============================================================================= */
USE KVSim;
GO

CREATE TABLE core.arzt (
    arzt_id         INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_arzt PRIMARY KEY,
    lanr            CHAR(9)       NOT NULL CONSTRAINT uq_arzt_lanr UNIQUE,
    efn             CHAR(15)      NULL,     -- Einheitliche Fortbildungsnummer (key used by the Aerztekammer)
    titel           NVARCHAR(40)  NULL,
    vorname         NVARCHAR(60)  NOT NULL,
    nachname        NVARCHAR(60)  NOT NULL,
    geschlecht      CHAR(1)       NOT NULL CONSTRAINT ck_arzt_geschlecht CHECK (geschlecht IN ('w', 'm', 'd')),
    geburtsjahr     SMALLINT      NOT NULL CONSTRAINT ck_arzt_geburtsjahr CHECK (geburtsjahr BETWEEN 1930 AND 2005),
    fachgruppe_code CHAR(2)       NOT NULL CONSTRAINT fk_arzt_fachgruppe REFERENCES core.fachgruppe (fachgruppe_code),
    load_batch_id   INT           NULL,
    loaded_at       DATETIME2(0)  NOT NULL CONSTRAINT df_arzt_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT ck_arzt_lanr_format CHECK (lanr LIKE REPLICATE('[0-9]', 9)),
    -- Table-level CHECK across two columns: the last two LANR digits ARE the Fachgruppe.
    CONSTRAINT ck_arzt_lanr_fachgruppe CHECK (RIGHT(lanr, 2) = fachgruppe_code)
);
-- EFN is optional but must be unique when present -> filtered unique index
CREATE UNIQUE INDEX uq_arzt_efn ON core.arzt (efn) WHERE efn IS NOT NULL;

-- One row per Betriebsstaette (practice site with its own BSNR).
CREATE TABLE core.praxis (
    praxis_id             INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_praxis PRIMARY KEY,
    bsnr                  CHAR(9)       NOT NULL CONSTRAINT uq_praxis_bsnr UNIQUE,
    name                  NVARCHAR(200) NOT NULL,
    kooperationsform_code VARCHAR(3)    NOT NULL CONSTRAINT fk_praxis_kooperationsform REFERENCES core.kooperationsform (kooperationsform_code),
    strasse               NVARCHAR(120) NULL,
    ort                   NVARCHAR(60)  NOT NULL,
    kreis_id              INT           NOT NULL CONSTRAINT fk_praxis_kreis REFERENCES core.kreis (kreis_id),
    gruendungsdatum       DATE          NULL,
    load_batch_id         INT           NULL,
    loaded_at             DATETIME2(0)  NOT NULL CONSTRAINT df_praxis_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT ck_praxis_bsnr_format CHECK (bsnr LIKE REPLICATE('[0-9]', 9))
);
CREATE INDEX ix_praxis_kreis_id ON core.praxis (kreis_id);

/* Teilnahme = participation of a doctor in statutory care AT a practice:
   as Vertragsarzt (Zulassung, ZUL) or as employed doctor (Anstellung, ANG).
   Validity interval convention (used everywhere in this project):
       [valid_from, valid_to)  - from inclusive, to EXCLUSIVE
       valid_to = '9999-12-31' - open end ("until further notice")
   With exclusive ends, consecutive periods touch without overlapping:
   [2020-01-01, 2025-07-01) and [2025-07-01, 9999-12-31). */
CREATE TABLE core.teilnahme (
    teilnahme_id       INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_teilnahme PRIMARY KEY,
    arzt_id            INT          NOT NULL CONSTRAINT fk_teilnahme_arzt REFERENCES core.arzt (arzt_id),
    praxis_id          INT          NOT NULL CONSTRAINT fk_teilnahme_praxis REFERENCES core.praxis (praxis_id),
    teilnahmeform_code VARCHAR(3)   NOT NULL CONSTRAINT fk_teilnahme_teilnahmeform REFERENCES core.teilnahmeform (teilnahmeform_code),
    anrechnungsfaktor  DECIMAL(3,2) NOT NULL,   -- how much of a planning seat this person counts (1.0 = full)
    valid_from         DATE         NOT NULL,
    valid_to           DATE         NOT NULL CONSTRAINT df_teilnahme_valid_to DEFAULT ('9999-12-31'),
    load_batch_id      INT          NULL,
    loaded_at          DATETIME2(0) NOT NULL CONSTRAINT df_teilnahme_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT uq_teilnahme_arzt_praxis_from UNIQUE (arzt_id, praxis_id, valid_from),
    CONSTRAINT ck_teilnahme_interval CHECK (valid_to > valid_from),
    CONSTRAINT ck_teilnahme_faktor CHECK (anrechnungsfaktor IN (0.25, 0.50, 0.75, 1.00))
);
-- "Which doctors work at practice X?" is a very frequent question -> index on praxis_id.
-- INCLUDE adds columns to the index leaf level so the query needs no lookup into the table.
CREATE INDEX ix_teilnahme_praxis ON core.teilnahme (praxis_id, valid_from) INCLUDE (arzt_id, valid_to, anrechnungsfaktor);

-- Status history of a Teilnahme (AKTIV / RUHEND / BEENDET), gapless over time.
CREATE TABLE core.teilnahme_status (
    teilnahme_id  INT          NOT NULL CONSTRAINT fk_teilnahme_status_teilnahme REFERENCES core.teilnahme (teilnahme_id),
    valid_from    DATE         NOT NULL,
    valid_to      DATE         NOT NULL CONSTRAINT df_teilnahme_status_valid_to DEFAULT ('9999-12-31'),
    status_code   VARCHAR(10)  NOT NULL CONSTRAINT ck_teilnahme_status_code CHECK (status_code IN ('AKTIV', 'RUHEND', 'BEENDET')),
    load_batch_id INT          NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_teilnahme_status_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT pk_teilnahme_status PRIMARY KEY (teilnahme_id, valid_from),
    CONSTRAINT ck_teilnahme_status_interval CHECK (valid_to > valid_from)
);
-- At most ONE open (current) status row per Teilnahme. A CHECK constraint cannot look at
-- other rows, but a filtered UNIQUE index can enforce this rule.
CREATE UNIQUE INDEX uq_teilnahme_status_open ON core.teilnahme_status (teilnahme_id) WHERE valid_to = '9999-12-31';
GO
