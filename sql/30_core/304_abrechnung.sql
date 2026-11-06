/* =============================================================================
   304_abrechnung.sql
   Billing: Behandlungsfaelle (cases), Leistungen (billed GOPs), diagnoses,
   Honorarbescheide (fee statements) and Abschlagszahlungen (advance payments).

   DATA PROTECTION: a KV is not a doctor - it holds no medical records. The
   analytics model only knows a salted SHA-256 PSEUDONYM per patient, the age
   group (not the birth date) and sex. See docs/concepts/02_sources_and_privacy.md.
   ============================================================================= */
USE KVSim;
GO

-- Behandlungsfall = all treatment of ONE patient at ONE practice in ONE quarter.
CREATE TABLE core.abrechnungsfall (
    fall_id                INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_abrechnungsfall PRIMARY KEY,
    fallnummer             VARCHAR(20)  NOT NULL CONSTRAINT uq_abrechnungsfall_fallnummer UNIQUE,
    praxis_id              INT          NOT NULL CONSTRAINT fk_abrechnungsfall_praxis REFERENCES core.praxis (praxis_id),
    quartal_code           CHAR(6)      NOT NULL CONSTRAINT fk_abrechnungsfall_quartal REFERENCES core.quartal (quartal_code),
    patient_pseudonym      CHAR(64)     NOT NULL,
    krankenkasse_id        INT          NOT NULL CONSTRAINT fk_abrechnungsfall_krankenkasse REFERENCES core.krankenkasse (krankenkasse_id),
    versichertenstatus     CHAR(1)      NOT NULL CONSTRAINT ck_abrechnungsfall_versichertenstatus CHECK (versichertenstatus IN ('M', 'F', 'R')),
    geschlecht             CHAR(1)      NOT NULL CONSTRAINT ck_abrechnungsfall_geschlecht CHECK (geschlecht IN ('w', 'm', 'd')),
    altersgruppe_code      VARCHAR(5)   NOT NULL CONSTRAINT fk_abrechnungsfall_altersgruppe REFERENCES core.altersgruppe (altersgruppe_code),
    scheinuntergruppe_code CHAR(2)      NOT NULL CONSTRAINT fk_abrechnungsfall_scheinuntergruppe REFERENCES core.scheinuntergruppe (scheinuntergruppe_code),
    tss_vermittlungscode   CHAR(14)     NULL,   -- set when the appointment was arranged by the Terminservicestelle
    load_batch_id          INT          NULL,
    loaded_at              DATETIME2(0) NOT NULL CONSTRAINT df_abrechnungsfall_loaded_at DEFAULT (SYSDATETIME()),
    -- the definition of a Behandlungsfall, enforced by the database:
    CONSTRAINT uq_abrechnungsfall_patient UNIQUE (praxis_id, quartal_code, patient_pseudonym)
);
CREATE INDEX ix_abrechnungsfall_quartal ON core.abrechnungsfall (quartal_code) INCLUDE (praxis_id, krankenkasse_id, altersgruppe_code);
CREATE INDEX ix_abrechnungsfall_tss ON core.abrechnungsfall (tss_vermittlungscode) WHERE tss_vermittlungscode IS NOT NULL;

-- One billed GOP line. punktzahl is copied from core.gop at load time on purpose:
-- it documents the points valid WHEN the service was billed (a historical fact),
-- even if the catalogue changes later. This is a deliberate, documented exception
-- to "store each fact only once" (see docs/design_decisions.md, DD-06).
CREATE TABLE core.leistung (
    leistung_id    BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_leistung PRIMARY KEY,
    fall_id        INT          NOT NULL CONSTRAINT fk_leistung_abrechnungsfall REFERENCES core.abrechnungsfall (fall_id),
    positions_nr   SMALLINT     NOT NULL,
    leistungsdatum DATE         NOT NULL,
    arzt_id        INT          NOT NULL CONSTRAINT fk_leistung_arzt REFERENCES core.arzt (arzt_id),
    gop_id         INT          NOT NULL CONSTRAINT fk_leistung_gop REFERENCES core.gop (gop_id),
    anzahl         SMALLINT     NOT NULL CONSTRAINT ck_leistung_anzahl CHECK (anzahl > 0),
    punktzahl      INT          NOT NULL CONSTRAINT ck_leistung_punktzahl CHECK (punktzahl >= 0),   -- points per unit
    load_batch_id  INT          NULL,
    loaded_at      DATETIME2(0) NOT NULL CONSTRAINT df_leistung_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT uq_leistung_fall_position UNIQUE (fall_id, positions_nr)
);
-- Supports time-profile checks (Plausibilitaetspruefung): all services of a doctor per day.
CREATE INDEX ix_leistung_arzt_datum ON core.leistung (arzt_id, leistungsdatum) INCLUDE (gop_id, anzahl);
CREATE INDEX ix_leistung_gop ON core.leistung (gop_id) INCLUDE (fall_id, anzahl, punktzahl);

CREATE TABLE core.fall_diagnose (
    fall_id            INT          NOT NULL CONSTRAINT fk_fall_diagnose_abrechnungsfall REFERENCES core.abrechnungsfall (fall_id),
    icd_id             INT          NOT NULL CONSTRAINT fk_fall_diagnose_icd10 REFERENCES core.icd10 (icd_id),
    -- G = gesichert (confirmed), V = Verdacht (suspected), A = Ausschluss (excluded), Z = Zustand nach (history of)
    diagnosesicherheit CHAR(1)      NOT NULL CONSTRAINT ck_fall_diagnose_sicherheit CHECK (diagnosesicherheit IN ('G', 'V', 'A', 'Z')),
    load_batch_id      INT          NULL,
    loaded_at          DATETIME2(0) NOT NULL CONSTRAINT df_fall_diagnose_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT pk_fall_diagnose PRIMARY KEY (fall_id, icd_id)
);
CREATE INDEX ix_fall_diagnose_icd ON core.fall_diagnose (icd_id);

-- Honorarbescheid = quarterly fee statement per practice, as issued by the KV.
CREATE TABLE core.honorarbescheid (
    bescheid_id        INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_honorarbescheid PRIMARY KEY,
    bescheid_nr        VARCHAR(20)   NOT NULL CONSTRAINT uq_honorarbescheid_nr UNIQUE,
    praxis_id          INT           NOT NULL CONSTRAINT fk_honorarbescheid_praxis REFERENCES core.praxis (praxis_id),
    quartal_code       CHAR(6)       NOT NULL CONSTRAINT fk_honorarbescheid_quartal REFERENCES core.quartal (quartal_code),
    bescheiddatum      DATE          NOT NULL,
    punkte_angefordert INT           NOT NULL,   -- points requested by the practice
    punkte_berichtigt  INT           NOT NULL,   -- points removed (sachlich-rechnerische Berichtigung)
    punkte_mgv         INT           NOT NULL,   -- accepted points inside the budget (MGV)
    punkte_egv         INT           NOT NULL,   -- accepted points outside the budget (extrabudgetaer)
    quote_mgv          DECIMAL(6,4)  NULL,       -- payout quota applied to budget points
    betrag_mgv         DECIMAL(12,2) NOT NULL,
    betrag_egv         DECIMAL(12,2) NOT NULL,
    honorar_brutto     DECIMAL(12,2) NOT NULL,
    verwaltungskosten  DECIMAL(12,2) NOT NULL,   -- KV administration fee
    abschlaege         DECIMAL(12,2) NOT NULL,   -- advance payments already made for the quarter
    auszahlungsbetrag  DECIMAL(12,2) NOT NULL,   -- remaining payment (negative = refund to the KV)
    load_batch_id      INT           NULL,
    loaded_at          DATETIME2(0)  NOT NULL CONSTRAINT df_honorarbescheid_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT uq_honorarbescheid_praxis_quartal UNIQUE (praxis_id, quartal_code),
    -- internal arithmetic of a Bescheid must add up - otherwise the file is rejected
    CONSTRAINT ck_honorarbescheid_punkte CHECK (punkte_angefordert = punkte_berichtigt + punkte_mgv + punkte_egv),
    CONSTRAINT ck_honorarbescheid_betraege CHECK (honorar_brutto = betrag_mgv + betrag_egv
                                              AND auszahlungsbetrag = honorar_brutto - verwaltungskosten - abschlaege)
);

CREATE TABLE core.abschlagszahlung (
    abschlag_id    INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_abschlagszahlung PRIMARY KEY,
    praxis_id      INT           NOT NULL CONSTRAINT fk_abschlagszahlung_praxis REFERENCES core.praxis (praxis_id),
    quartal_code   CHAR(6)       NOT NULL CONSTRAINT fk_abschlagszahlung_quartal REFERENCES core.quartal (quartal_code),
    abschlag_nr    TINYINT       NOT NULL CONSTRAINT ck_abschlagszahlung_nr CHECK (abschlag_nr BETWEEN 1 AND 3),
    zahlungsdatum  DATE          NOT NULL,
    betrag         DECIMAL(12,2) NOT NULL,
    load_batch_id  INT           NULL,
    loaded_at      DATETIME2(0)  NOT NULL CONSTRAINT df_abschlagszahlung_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT uq_abschlagszahlung UNIQUE (praxis_id, quartal_code, abschlag_nr)
);
GO
