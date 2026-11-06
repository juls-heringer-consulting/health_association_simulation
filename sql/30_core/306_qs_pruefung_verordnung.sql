/* =============================================================================
   306_qs_pruefung_verordnung.sql
   Quality assurance (QS-Genehmigungen, Fortbildung), audits (Pruefverfahren)
   and aggregated prescriptions (Verordnungen) with their targets (Richtgroessen).
   ============================================================================= */
USE KVSim;
GO

-- Permit to bill services of a QS area (e.g. ultrasound). Validity [valid_from, valid_to).
CREATE TABLE core.qs_genehmigung (
    arzt_id         INT          NOT NULL CONSTRAINT fk_qs_genehmigung_arzt REFERENCES core.arzt (arzt_id),
    qs_bereich_code VARCHAR(5)   NOT NULL CONSTRAINT fk_qs_genehmigung_qs_bereich REFERENCES core.qs_bereich (qs_bereich_code),
    valid_from      DATE         NOT NULL,
    valid_to        DATE         NOT NULL CONSTRAINT df_qs_genehmigung_valid_to DEFAULT ('9999-12-31'),
    load_batch_id   INT          NULL,
    loaded_at       DATETIME2(0) NOT NULL CONSTRAINT df_qs_genehmigung_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT pk_qs_genehmigung PRIMARY KEY (arzt_id, qs_bereich_code, valid_from),
    CONSTRAINT ck_qs_genehmigung_interval CHECK (valid_to > valid_from)
);

-- Continuing-education points per doctor and year (reported by the Kammer, keyed by EFN).
CREATE TABLE core.fortbildungspunkte (
    arzt_id       INT          NOT NULL CONSTRAINT fk_fortbildungspunkte_arzt REFERENCES core.arzt (arzt_id),
    jahr          SMALLINT     NOT NULL,
    punkte        SMALLINT     NOT NULL CONSTRAINT ck_fortbildungspunkte_punkte CHECK (punkte >= 0),
    load_batch_id INT          NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_fortbildungspunkte_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT pk_fortbildungspunkte PRIMARY KEY (arzt_id, jahr)
);

-- Wirtschaftlichkeitspruefung (efficiency audit) conducted by the Pruefungsstelle.
CREATE TABLE core.pruefverfahren (
    pruefverfahren_id    INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_pruefverfahren PRIMARY KEY,
    aktenzeichen         VARCHAR(20)   NOT NULL CONSTRAINT uq_pruefverfahren_aktenzeichen UNIQUE,
    praxis_id            INT           NOT NULL CONSTRAINT fk_pruefverfahren_praxis REFERENCES core.praxis (praxis_id),
    quartal_code         CHAR(6)       NOT NULL CONSTRAINT fk_pruefverfahren_quartal REFERENCES core.quartal (quartal_code),
    pruefgegenstand      VARCHAR(15)   NOT NULL CONSTRAINT ck_pruefverfahren_gegenstand CHECK (pruefgegenstand IN ('ARZNEIMITTEL', 'HEILMITTEL')),
    anlass               VARCHAR(15)   NOT NULL CONSTRAINT ck_pruefverfahren_anlass CHECK (anlass IN ('AUFFAELLIGKEIT', 'ZUFAELLIGKEIT')),
    eingeleitet_am       DATE          NOT NULL,
    status               VARCHAR(15)   NOT NULL CONSTRAINT ck_pruefverfahren_status CHECK (status IN ('LAUFEND', 'ABGESCHLOSSEN')),
    abgeschlossen_am     DATE          NULL,
    massnahme            VARCHAR(15)   NULL CONSTRAINT ck_pruefverfahren_massnahme CHECK (massnahme IN ('KEINE', 'BERATUNG', 'NACHFORDERUNG')),
    nachforderung_betrag DECIMAL(12,2) NULL,
    load_batch_id        INT           NULL,
    loaded_at            DATETIME2(0)  NOT NULL CONSTRAINT df_pruefverfahren_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT ck_pruefverfahren_abschluss CHECK (
        (status = 'ABGESCHLOSSEN' AND abgeschlossen_am IS NOT NULL AND massnahme IS NOT NULL)
     OR (status = 'LAUFEND'       AND abgeschlossen_am IS NULL     AND massnahme IS NULL)),
    CONSTRAINT ck_pruefverfahren_betrag CHECK (nachforderung_betrag IS NULL OR massnahme = 'NACHFORDERUNG')
);

-- Aggregated prescriptions per practice, quarter and type (A = Arzneimittel, H = Heilmittel).
CREATE TABLE core.verordnung (
    praxis_id           INT           NOT NULL CONSTRAINT fk_verordnung_praxis REFERENCES core.praxis (praxis_id),
    quartal_code        CHAR(6)       NOT NULL CONSTRAINT fk_verordnung_quartal REFERENCES core.quartal (quartal_code),
    verordnungsart      CHAR(1)       NOT NULL CONSTRAINT ck_verordnung_art CHECK (verordnungsart IN ('A', 'H')),
    anzahl_verordnungen INT           NOT NULL CONSTRAINT ck_verordnung_anzahl CHECK (anzahl_verordnungen >= 0),
    brutto_betrag       DECIMAL(12,2) NOT NULL,
    load_batch_id       INT           NULL,
    loaded_at           DATETIME2(0)  NOT NULL CONSTRAINT df_verordnung_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT pk_verordnung PRIMARY KEY (praxis_id, quartal_code, verordnungsart)
);

-- Richtgroesse = target prescription volume in EUR per case.
CREATE TABLE core.richtgroesse (
    arztgruppe_code VARCHAR(4)   NOT NULL CONSTRAINT fk_richtgroesse_arztgruppe REFERENCES core.arztgruppe (arztgruppe_code),
    jahr            SMALLINT     NOT NULL,
    verordnungsart  CHAR(1)      NOT NULL CONSTRAINT ck_richtgroesse_art CHECK (verordnungsart IN ('A', 'H')),
    euro_je_fall    DECIMAL(8,2) NOT NULL CONSTRAINT ck_richtgroesse_euro CHECK (euro_je_fall > 0),
    load_batch_id   INT          NULL,
    loaded_at       DATETIME2(0) NOT NULL CONSTRAINT df_richtgroesse_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT pk_richtgroesse PRIMARY KEY (arztgruppe_code, jahr, verordnungsart)
);
GO
