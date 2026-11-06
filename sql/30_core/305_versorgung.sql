/* =============================================================================
   305_versorgung.sql
   Care provision: Terminservicestelle (appointment service, 116117) and the
   aerztlicher Bereitschaftsdienst (out-of-hours service).
   ============================================================================= */
USE KVSim;
GO

-- Mapping table: the TSS API uses its own specialty labels. Instead of hard-coding
-- CASE expressions in the load, the mapping is data (owned by the DWH team).
CREATE TABLE core.tss_fachgebiet (
    tss_fachgebiet  NVARCHAR(60) NOT NULL CONSTRAINT pk_tss_fachgebiet PRIMARY KEY,
    arztgruppe_code VARCHAR(4)   NOT NULL CONSTRAINT fk_tss_fachgebiet_arztgruppe REFERENCES core.arztgruppe (arztgruppe_code),
    load_batch_id   INT          NULL,
    loaded_at       DATETIME2(0) NOT NULL CONSTRAINT df_tss_fachgebiet_loaded_at DEFAULT (SYSDATETIME())
);
-- (seeded in core.usp_load_referenz, after core.arztgruppe is filled)

CREATE TABLE core.tss_anfrage (
    anfrage_id                INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_tss_anfrage PRIMARY KEY,
    tss_anfrage_uuid          UNIQUEIDENTIFIER   NOT NULL CONSTRAINT uq_tss_anfrage_uuid UNIQUE,
    eingang_zeitpunkt         DATETIMEOFFSET(0)  NOT NULL,   -- keeps the UTC offset of the source (+01:00 / +02:00)
    kanal                     VARCHAR(10)        NOT NULL CONSTRAINT ck_tss_anfrage_kanal CHECK (kanal IN ('TELEFON', 'ONLINE', 'APP')),
    arztgruppe_code           VARCHAR(4)         NOT NULL CONSTRAINT fk_tss_anfrage_arztgruppe REFERENCES core.arztgruppe (arztgruppe_code),
    dringlichkeit             VARCHAR(10)        NOT NULL CONSTRAINT ck_tss_anfrage_dringlichkeit CHECK (dringlichkeit IN ('AKUT', 'DRINGEND', 'ROUTINE')),
    patient_kreis_id          INT                NOT NULL CONSTRAINT fk_tss_anfrage_kreis REFERENCES core.kreis (kreis_id),
    patient_altersgruppe_code VARCHAR(5)         NOT NULL CONSTRAINT fk_tss_anfrage_altersgruppe REFERENCES core.altersgruppe (altersgruppe_code),
    status                    VARCHAR(20)        NOT NULL CONSTRAINT ck_tss_anfrage_status CHECK (status IN ('VERMITTELT', 'NICHT_VERMITTELT', 'STORNIERT')),
    praxis_id                 INT                NULL CONSTRAINT fk_tss_anfrage_praxis REFERENCES core.praxis (praxis_id),
    termin_zeitpunkt          DATETIMEOFFSET(0)  NULL,
    vermittlungscode          CHAR(14)           NULL,
    termin_wahrgenommen       BIT                NULL,
    -- computed column: not stored, calculated when read
    wartezeit_tage            AS DATEDIFF(DAY, CAST(eingang_zeitpunkt AS DATE), CAST(termin_zeitpunkt AS DATE)),
    load_batch_id             INT                NULL,
    loaded_at                 DATETIME2(0)       NOT NULL CONSTRAINT df_tss_anfrage_loaded_at DEFAULT (SYSDATETIME()),
    -- a request has an appointment exactly when it was successfully arranged
    CONSTRAINT ck_tss_anfrage_termin CHECK (
        (status = 'VERMITTELT'  AND praxis_id IS NOT NULL AND termin_zeitpunkt IS NOT NULL AND vermittlungscode IS NOT NULL)
     OR (status <> 'VERMITTELT' AND praxis_id IS NULL     AND termin_zeitpunkt IS NULL     AND vermittlungscode IS NULL))
);
CREATE UNIQUE INDEX uq_tss_anfrage_vermittlungscode ON core.tss_anfrage (vermittlungscode) WHERE vermittlungscode IS NOT NULL;

-- Bereitschaftsdienstpraxis (out-of-hours practice, often located at a hospital)
CREATE TABLE core.notfallpraxis (
    notfallpraxis_id INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_notfallpraxis PRIMARY KEY,
    kennung          VARCHAR(10)   NOT NULL CONSTRAINT uq_notfallpraxis_kennung UNIQUE,
    name             NVARCHAR(100) NOT NULL,
    ort              NVARCHAR(60)  NOT NULL,
    kreis_id         INT           NOT NULL CONSTRAINT fk_notfallpraxis_kreis REFERENCES core.kreis (kreis_id),
    load_batch_id    INT           NULL,
    loaded_at        DATETIME2(0)  NOT NULL CONSTRAINT df_notfallpraxis_loaded_at DEFAULT (SYSDATETIME())
);

-- One shift in a Bereitschaftsdienstpraxis with the doctor who actually served it.
CREATE TABLE core.bereitschaftsdienst (
    dienst_id             INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_bereitschaftsdienst PRIMARY KEY,
    dienst_nr             VARCHAR(30)  NOT NULL CONSTRAINT uq_bereitschaftsdienst_nr UNIQUE,
    notfallpraxis_id      INT          NOT NULL CONSTRAINT fk_bereitschaftsdienst_notfallpraxis REFERENCES core.notfallpraxis (notfallpraxis_id),
    beginn                DATETIME2(0) NOT NULL,   -- local time (Europe/Berlin)
    ende                  DATETIME2(0) NOT NULL,
    arzt_id               INT          NOT NULL CONSTRAINT fk_bereitschaftsdienst_arzt REFERENCES core.arzt (arzt_id),
    getauscht_von_arzt_id INT          NULL CONSTRAINT fk_bereitschaftsdienst_arzt_getauscht REFERENCES core.arzt (arzt_id),
    dauer_stunden         AS CAST(DATEDIFF(MINUTE, beginn, ende) / 60.0 AS DECIMAL(5,2)),
    load_batch_id         INT          NULL,
    loaded_at             DATETIME2(0) NOT NULL CONSTRAINT df_bereitschaftsdienst_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT ck_bereitschaftsdienst_interval CHECK (ende > beginn),
    CONSTRAINT ck_bereitschaftsdienst_tausch CHECK (getauscht_von_arzt_id IS NULL OR getauscht_von_arzt_id <> arzt_id)
);
CREATE INDEX ix_bereitschaftsdienst_arzt ON core.bereitschaftsdienst (arzt_id, beginn);
GO
