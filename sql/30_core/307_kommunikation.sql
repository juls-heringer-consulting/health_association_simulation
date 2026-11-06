/* =============================================================================
   307_kommunikation.sql
   Unstructured text: member enquiries, complaints, minutes, notices.

   Pattern: ONE document table holds the text (NVARCHAR(MAX)) plus a few
   searchable metadata columns; links to structured entities live in a separate
   link table with REAL foreign keys. Full-text search: sql/85_fulltext.
   ============================================================================= */
USE KVSim;
GO

CREATE TABLE core.dokumenttyp (
    dokumenttyp_code VARCHAR(10)  NOT NULL CONSTRAINT pk_dokumenttyp PRIMARY KEY,
    bezeichnung      NVARCHAR(60) NOT NULL,
    vertraulichkeit  VARCHAR(12)  NOT NULL CONSTRAINT ck_dokumenttyp_vertraulichkeit CHECK (vertraulichkeit IN ('INTERN', 'VERTRAULICH')),
    load_batch_id    INT          NULL,
    loaded_at        DATETIME2(0) NOT NULL CONSTRAINT df_dokumenttyp_loaded_at DEFAULT (SYSDATETIME())
);
INSERT INTO core.dokumenttyp (dokumenttyp_code, bezeichnung, vertraulichkeit) VALUES
    ('ANFRAGE',    N'Mitgliederanfrage',                 'INTERN'),
    ('BESCHWERDE', N'Patientenbeschwerde',               'VERTRAULICH'),
    ('PROTOKOLL',  N'Sitzungsprotokoll (Niederschrift)', 'VERTRAULICH'),
    ('BESCHEID',   N'Bescheid des Zulassungsausschusses', 'VERTRAULICH');

CREATE TABLE core.dokument (
    dokument_id      INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dokument PRIMARY KEY,
    dokumenttyp_code VARCHAR(10)   NOT NULL CONSTRAINT fk_dokument_dokumenttyp REFERENCES core.dokumenttyp (dokumenttyp_code),
    quelle_referenz  NVARCHAR(200) NOT NULL CONSTRAINT uq_dokument_quelle_referenz UNIQUE,   -- business key: ticket id, file name, ...
    titel            NVARCHAR(300) NOT NULL,
    dokument_datum   DATE          NOT NULL,
    kategorie        NVARCHAR(40)  NULL,
    status           VARCHAR(10)   NULL,
    inhalt           NVARCHAR(MAX) NOT NULL,   -- the full original text (up to 2 GB)
    inhalt_sha256    BINARY(32)    NOT NULL,   -- fingerprint: detects changed or duplicate texts cheaply
    zeichen_anzahl   AS LEN(inhalt),
    load_batch_id    INT           NULL,
    loaded_at        DATETIME2(0)  NOT NULL CONSTRAINT df_dokument_loaded_at DEFAULT (SYSDATETIME())
);
CREATE INDEX ix_dokument_typ_datum ON core.dokument (dokumenttyp_code, dokument_datum);

/* Link table with an "exclusive arc": every row points to exactly ONE target
   (arzt OR praxis OR verfahren). Unlike a generic (entity_type, entity_id) pair,
   each target column has a real foreign key, so links can never dangle. */
CREATE TABLE core.dokument_bezug (
    dokument_bezug_id INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dokument_bezug PRIMARY KEY,
    dokument_id       INT          NOT NULL CONSTRAINT fk_dokument_bezug_dokument REFERENCES core.dokument (dokument_id),
    arzt_id           INT          NULL CONSTRAINT fk_dokument_bezug_arzt REFERENCES core.arzt (arzt_id),
    praxis_id         INT          NULL CONSTRAINT fk_dokument_bezug_praxis REFERENCES core.praxis (praxis_id),
    verfahren_id      INT          NULL CONSTRAINT fk_dokument_bezug_verfahren REFERENCES core.zulassungsverfahren (verfahren_id),
    bezugsart         VARCHAR(12)  NOT NULL CONSTRAINT ck_dokument_bezug_art CHECK (bezugsart IN ('ABSENDER', 'BETROFFEN', 'GEGENSTAND')),
    load_batch_id     INT          NULL,
    loaded_at         DATETIME2(0) NOT NULL CONSTRAINT df_dokument_bezug_loaded_at DEFAULT (SYSDATETIME()),
    CONSTRAINT ck_dokument_bezug_genau_ein_ziel CHECK (
        IIF(arzt_id IS NULL, 0, 1) + IIF(praxis_id IS NULL, 0, 1) + IIF(verfahren_id IS NULL, 0, 1) = 1)
);
CREATE UNIQUE INDEX uq_dokument_bezug_arzt      ON core.dokument_bezug (dokument_id, arzt_id)      WHERE arzt_id IS NOT NULL;
CREATE UNIQUE INDEX uq_dokument_bezug_praxis    ON core.dokument_bezug (dokument_id, praxis_id)    WHERE praxis_id IS NOT NULL;
CREATE UNIQUE INDEX uq_dokument_bezug_verfahren ON core.dokument_bezug (dokument_id, verfahren_id) WHERE verfahren_id IS NOT NULL;
CREATE INDEX ix_dokument_bezug_praxis ON core.dokument_bezug (praxis_id) WHERE praxis_id IS NOT NULL;
GO
