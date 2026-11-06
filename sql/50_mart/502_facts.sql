/* =============================================================================
   502_facts.sql
   Fact tables: the measurable events. Each fact table has a declared GRAIN
   ("what does one row mean?") - the most important design decision of a star.

   fact type (Kimball)        table                      grain
   -------------------------  -------------------------  -----------------------------------
   transaction                fact_leistung              one billed GOP line
   transaction                fact_abrechnungsfall       one Behandlungsfall
   periodic snapshot          fact_honorar_quartal       one practice per quarter
   periodic snapshot          fact_versorgungsgrad       planning area x Arztgruppe x Stichtag
   accumulating snapshot      fact_tss_anfrage           one TSS request (several dates)
   transaction                fact_bereitschaftsdienst   one out-of-hours shift
   ============================================================================= */
USE KVSim;
GO

CREATE TABLE mart.fact_leistung (
    leistung_id      BIGINT        NOT NULL CONSTRAINT pk_fact_leistung PRIMARY KEY,
    fallnummer       VARCHAR(20)   NOT NULL,   -- degenerate dimension (an id without its own dimension table)
    datum_key        INT           NOT NULL CONSTRAINT fk_fact_leistung_datum REFERENCES mart.dim_datum (datum_key),
    quartal_key      INT           NOT NULL CONSTRAINT fk_fact_leistung_quartal REFERENCES mart.dim_quartal (quartal_key),
    arzt_key         INT           NOT NULL CONSTRAINT fk_fact_leistung_arzt REFERENCES mart.dim_arzt (arzt_key),
    praxis_key       INT           NOT NULL CONSTRAINT fk_fact_leistung_praxis REFERENCES mart.dim_praxis (praxis_key),
    region_key       INT           NOT NULL CONSTRAINT fk_fact_leistung_region REFERENCES mart.dim_region (region_key),
    fachgruppe_key   INT           NOT NULL CONSTRAINT fk_fact_leistung_fachgruppe REFERENCES mart.dim_fachgruppe (fachgruppe_key),
    kasse_key        INT           NOT NULL CONSTRAINT fk_fact_leistung_kasse REFERENCES mart.dim_krankenkasse (kasse_key),
    gop_key          INT           NOT NULL CONSTRAINT fk_fact_leistung_gop REFERENCES mart.dim_gop (gop_key),
    altersgruppe_key INT           NOT NULL CONSTRAINT fk_fact_leistung_altersgruppe REFERENCES mart.dim_altersgruppe (altersgruppe_key),
    anzahl           SMALLINT      NOT NULL,
    punkte           INT           NOT NULL,   -- anzahl * points
    betrag_eur       DECIMAL(12,2) NOT NULL,   -- valued at the Orientierungswert (before Honorarverteilung)
    pruefzeit_min    INT           NULL        -- anzahl * Pruefzeit (for time-plausibility profiles)
);
CREATE INDEX ix_fact_leistung_quartal_praxis ON mart.fact_leistung (quartal_key, praxis_key) INCLUDE (punkte, betrag_eur);
CREATE INDEX ix_fact_leistung_arzt_datum ON mart.fact_leistung (arzt_key, datum_key) INCLUDE (pruefzeit_min);

CREATE TABLE mart.fact_abrechnungsfall (
    fall_id            INT           NOT NULL CONSTRAINT pk_fact_abrechnungsfall PRIMARY KEY,
    fallnummer         VARCHAR(20)   NOT NULL,
    quartal_key        INT           NOT NULL CONSTRAINT fk_fact_abrechnungsfall_quartal REFERENCES mart.dim_quartal (quartal_key),
    praxis_key         INT           NOT NULL CONSTRAINT fk_fact_abrechnungsfall_praxis REFERENCES mart.dim_praxis (praxis_key),
    region_key         INT           NOT NULL CONSTRAINT fk_fact_abrechnungsfall_region REFERENCES mart.dim_region (region_key),
    arzt_key           INT           NOT NULL CONSTRAINT fk_fact_abrechnungsfall_arzt REFERENCES mart.dim_arzt (arzt_key),
    fachgruppe_key     INT           NOT NULL CONSTRAINT fk_fact_abrechnungsfall_fachgruppe REFERENCES mart.dim_fachgruppe (fachgruppe_key),
    kasse_key          INT           NOT NULL CONSTRAINT fk_fact_abrechnungsfall_kasse REFERENCES mart.dim_krankenkasse (kasse_key),
    altersgruppe_key   INT           NOT NULL CONSTRAINT fk_fact_abrechnungsfall_altersgruppe REFERENCES mart.dim_altersgruppe (altersgruppe_key),
    versichertenstatus CHAR(1)       NOT NULL,
    scheinuntergruppe  CHAR(2)       NOT NULL,
    ist_tss_fall       BIT           NOT NULL,
    anzahl_leistungen  INT           NOT NULL,
    anzahl_diagnosen   INT           NOT NULL,
    punkte             INT           NOT NULL,
    betrag_eur         DECIMAL(12,2) NOT NULL
);
CREATE INDEX ix_fact_abrechnungsfall_quartal_praxis ON mart.fact_abrechnungsfall (quartal_key, praxis_key) INCLUDE (fachgruppe_key, punkte, betrag_eur);

CREATE TABLE mart.fact_honorar_quartal (
    quartal_key              INT           NOT NULL CONSTRAINT fk_fact_honorar_quartal REFERENCES mart.dim_quartal (quartal_key),
    praxis_key               INT           NOT NULL CONSTRAINT fk_fact_honorar_praxis REFERENCES mart.dim_praxis (praxis_key),
    region_key               INT           NOT NULL CONSTRAINT fk_fact_honorar_region REFERENCES mart.dim_region (region_key),
    anzahl_faelle            INT           NOT NULL,
    punkte_angefordert       INT           NOT NULL,
    punkte_berichtigt        INT           NOT NULL,
    punkte_mgv               INT           NOT NULL,
    punkte_egv               INT           NOT NULL,
    betrag_mgv               DECIMAL(12,2) NOT NULL,
    betrag_egv               DECIMAL(12,2) NOT NULL,
    honorar_brutto           DECIMAL(12,2) NOT NULL,
    verwaltungskosten        DECIMAL(12,2) NOT NULL,
    abschlaege_laut_bescheid DECIMAL(12,2) NOT NULL,
    abschlaege_gezahlt       DECIMAL(12,2) NOT NULL,   -- from the finance system (should equal the Bescheid)
    auszahlungsbetrag        DECIMAL(12,2) NOT NULL,
    CONSTRAINT pk_fact_honorar_quartal PRIMARY KEY (quartal_key, praxis_key)
);

CREATE TABLE mart.fact_versorgungsgrad (
    stichtag_key         INT          NOT NULL CONSTRAINT fk_fact_versorgungsgrad_datum REFERENCES mart.dim_datum (datum_key),
    planungsbereich_key  INT          NOT NULL CONSTRAINT fk_fact_versorgungsgrad_pb REFERENCES mart.dim_planungsbereich (planungsbereich_key),
    arztgruppe_key       INT          NOT NULL CONSTRAINT fk_fact_versorgungsgrad_arztgruppe REFERENCES mart.dim_arztgruppe (arztgruppe_key),
    einwohner            INT          NOT NULL,
    soll_aerzte          DECIMAL(7,2) NOT NULL,
    ist_aerzte           DECIMAL(7,2) NOT NULL,   -- as decided (official)
    ist_aerzte_berechnet DECIMAL(7,2) NOT NULL,   -- recomputed from core.teilnahme (reconciliation)
    versorgungsgrad_pct  DECIMAL(6,1) NOT NULL,
    status               VARCHAR(15)  NOT NULL,
    CONSTRAINT pk_fact_versorgungsgrad PRIMARY KEY (stichtag_key, planungsbereich_key, arztgruppe_key)
);

CREATE TABLE mart.fact_tss_anfrage (
    anfrage_id             INT         NOT NULL CONSTRAINT pk_fact_tss_anfrage PRIMARY KEY,
    eingang_datum_key      INT         NOT NULL CONSTRAINT fk_fact_tss_eingang_datum REFERENCES mart.dim_datum (datum_key),
    termin_datum_key       INT         NOT NULL CONSTRAINT fk_fact_tss_termin_datum REFERENCES mart.dim_datum (datum_key),  -- role-playing dimension
    arztgruppe_key         INT         NOT NULL CONSTRAINT fk_fact_tss_arztgruppe REFERENCES mart.dim_arztgruppe (arztgruppe_key),
    patient_region_key     INT         NOT NULL CONSTRAINT fk_fact_tss_region REFERENCES mart.dim_region (region_key),
    altersgruppe_key       INT         NOT NULL CONSTRAINT fk_fact_tss_altersgruppe REFERENCES mart.dim_altersgruppe (altersgruppe_key),
    praxis_key             INT         NOT NULL CONSTRAINT fk_fact_tss_praxis REFERENCES mart.dim_praxis (praxis_key),
    kanal                  VARCHAR(10) NOT NULL,
    dringlichkeit          VARCHAR(10) NOT NULL,
    status                 VARCHAR(20) NOT NULL,
    ist_vermittelt         BIT         NOT NULL,
    wartezeit_tage         INT         NULL,
    ist_innerhalb_4_wochen BIT         NULL,
    termin_wahrgenommen    BIT         NULL,
    anzahl_anfragen        INT         NOT NULL   -- always 1: makes SUM() read naturally in reports
);

CREATE TABLE mart.fact_bereitschaftsdienst (
    dienst_id               INT          NOT NULL CONSTRAINT pk_fact_bereitschaftsdienst PRIMARY KEY,
    datum_key               INT          NOT NULL CONSTRAINT fk_fact_bd_datum REFERENCES mart.dim_datum (datum_key),
    arzt_key                INT          NOT NULL CONSTRAINT fk_fact_bd_arzt REFERENCES mart.dim_arzt (arzt_key),
    region_key              INT          NOT NULL CONSTRAINT fk_fact_bd_region REFERENCES mart.dim_region (region_key),
    notfallpraxis_kennung   VARCHAR(10)  NOT NULL,
    dauer_stunden           DECIMAL(5,2) NOT NULL,
    ist_wochenende_feiertag BIT          NOT NULL,
    ist_getauscht           BIT          NOT NULL
);
GO
