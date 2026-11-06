/* =============================================================================
   303_zulassung_bedarfsplanung.sql
   Needs planning (Bedarfsplanung) and licensing procedures (Zulassungsverfahren).
   ============================================================================= */
USE KVSim;
GO

-- Planungsbereich = planning area. In this simulation: each Kreis for Hausaerzte and
-- general specialists, the whole Saarland (Raumordnungsregion Saar) for Fachinternisten.
CREATE TABLE core.planungsbereich (
    planungsbereich_id   INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_planungsbereich PRIMARY KEY,
    planungsbereich_code VARCHAR(10)   NOT NULL CONSTRAINT uq_planungsbereich_code UNIQUE,
    name                 NVARCHAR(100) NOT NULL,
    typ                  VARCHAR(5)    NOT NULL CONSTRAINT ck_planungsbereich_typ CHECK (typ IN ('KREIS', 'ROR')),
    load_batch_id        INT           NULL,
    loaded_at            DATETIME2(0)  NOT NULL CONSTRAINT df_planungsbereich_loaded_at DEFAULT (SYSDATETIME())
);

-- Which Kreise belong to which Planungsbereich (many-to-many: a Kreis is in a
-- KREIS-type area AND in the ROR-type area).
CREATE TABLE core.planungsbereich_kreis (
    planungsbereich_id INT          NOT NULL CONSTRAINT fk_planungsbereich_kreis_pb REFERENCES core.planungsbereich (planungsbereich_id),
    kreis_id           INT          NOT NULL CONSTRAINT fk_planungsbereich_kreis_kreis REFERENCES core.kreis (kreis_id),
    load_batch_id      INT          NULL,
    loaded_at          DATETIME2(0) NOT NULL CONSTRAINT df_planungsbereich_kreis_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT pk_planungsbereich_kreis PRIMARY KEY (planungsbereich_id, kreis_id)
);

/* Official Versorgungsgrad (supply level) as decided by the Landesausschuss.
   soll/versorgungsgrad could be computed from the other columns - we still store them,
   because the DECIDED figure is a legal fact of its own (and can be reconciled against
   a recomputation from core.teilnahme, see sql/70_quality). */
CREATE TABLE core.versorgungsgrad (
    planungsbereich_id  INT          NOT NULL CONSTRAINT fk_versorgungsgrad_planungsbereich REFERENCES core.planungsbereich (planungsbereich_id),
    arztgruppe_code     VARCHAR(4)   NOT NULL CONSTRAINT fk_versorgungsgrad_arztgruppe REFERENCES core.arztgruppe (arztgruppe_code),
    stichtag            DATE         NOT NULL,
    einwohner           INT          NOT NULL,
    verhaeltniszahl     INT          NOT NULL,
    soll_aerzte         DECIMAL(7,2) NOT NULL,
    ist_aerzte          DECIMAL(7,2) NOT NULL,
    versorgungsgrad_pct DECIMAL(6,1) NOT NULL,
    status              VARCHAR(15)  NOT NULL CONSTRAINT ck_versorgungsgrad_status CHECK (status IN ('OFFEN', 'GESPERRT', 'UNTERVERSORGT')),
    load_batch_id       INT          NULL,
    loaded_at           DATETIME2(0) NOT NULL CONSTRAINT df_versorgungsgrad_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT pk_versorgungsgrad PRIMARY KEY (planungsbereich_id, arztgruppe_code, stichtag)
);

-- One licensing procedure before the Zulassungsausschuss.
CREATE TABLE core.zulassungsverfahren (
    verfahren_id       INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_zulassungsverfahren PRIMARY KEY,
    aktenzeichen       VARCHAR(20)  NOT NULL CONSTRAINT uq_zulassungsverfahren_aktenzeichen UNIQUE,
    verfahrensart      VARCHAR(15)  NOT NULL CONSTRAINT ck_zulassungsverfahren_art
                       CHECK (verfahrensart IN ('NEUZULASSUNG', 'NACHBESETZUNG', 'ANSTELLUNG', 'RUHEN', 'VERZICHT')),
    arzt_id            INT          NOT NULL CONSTRAINT fk_zulassungsverfahren_arzt REFERENCES core.arzt (arzt_id),
    praxis_id          INT          NULL CONSTRAINT fk_zulassungsverfahren_praxis REFERENCES core.praxis (praxis_id),
    planungsbereich_id INT          NOT NULL CONSTRAINT fk_zulassungsverfahren_planungsbereich REFERENCES core.planungsbereich (planungsbereich_id),
    antragsdatum       DATE         NOT NULL,
    sitzungsdatum      DATE         NULL,
    ergebnis           VARCHAR(16)  NOT NULL CONSTRAINT ck_zulassungsverfahren_ergebnis
                       CHECK (ergebnis IN ('GENEHMIGT', 'ABGELEHNT', 'ZURUECKGENOMMEN', 'OFFEN')),
    wirksam_ab         DATE         NULL,
    wirksam_bis        DATE         NULL,
    teilnahme_id       INT          NULL CONSTRAINT fk_zulassungsverfahren_teilnahme REFERENCES core.teilnahme (teilnahme_id),  -- Teilnahme created/changed by the decision
    load_batch_id      INT          NULL,
    loaded_at          DATETIME2(0) NOT NULL CONSTRAINT df_zulassungsverfahren_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT ck_zulassungsverfahren_genehmigt CHECK (ergebnis <> 'GENEHMIGT' OR wirksam_ab IS NOT NULL)
);
CREATE INDEX ix_zulassungsverfahren_arzt ON core.zulassungsverfahren (arzt_id);

-- Status history of a procedure. The source only delivers "status X since date D";
-- valid_to is derived with LEAD() during the load.
CREATE TABLE core.zulassungsverfahren_status (
    verfahren_id  INT          NOT NULL CONSTRAINT fk_zulassungsverfahren_status_verfahren REFERENCES core.zulassungsverfahren (verfahren_id),
    valid_from    DATE         NOT NULL,
    valid_to      DATE         NOT NULL,
    status_code   VARCHAR(20)  NOT NULL CONSTRAINT ck_zulassungsverfahren_status_code
                  CHECK (status_code IN ('EINGANG', 'IN_PRUEFUNG', 'TERMINIERT', 'ENTSCHIEDEN', 'BESCHEID_VERSANDT',
                                         'BESTANDSKRAEFTIG', 'WIDERSPRUCH', 'ZURUECKGENOMMEN')),
    load_batch_id INT          NULL,
    loaded_at     DATETIME2(0) NOT NULL CONSTRAINT df_zulassungsverfahren_status_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT pk_zulassungsverfahren_status PRIMARY KEY (verfahren_id, valid_from),
    CONSTRAINT ck_zulassungsverfahren_status_interval CHECK (valid_to > valid_from)
);
GO
