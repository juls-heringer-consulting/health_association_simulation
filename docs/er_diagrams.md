# Entity-relationship diagrams

Mermaid diagrams (rendered by GitHub, VS Code with a Mermaid extension, or
<https://mermaid.live>). Only key columns are shown; see [data_dictionary.md](data_dictionary.md)
for all columns. Notation: `||--o{` = one to zero-or-many, `||--|{` = one to one-or-many,
`|o--o{` = zero-or-one to zero-or-many (optional foreign key).

## 1. Region, Arztregister, Bedarfsplanung, Zulassung

```mermaid
erDiagram
    kreis ||--o{ einwohner : "population"
    altersgruppe ||--o{ einwohner : "age group"
    kreis ||--o{ praxis : "located in"
    kooperationsform ||--o{ praxis : "form"
    arztgruppe ||--o{ fachgruppe : "planned as"
    fachgruppe ||--o{ arzt : "LANR digits 8-9"
    arzt ||--o{ teilnahme : "works as"
    praxis ||--o{ teilnahme : "has"
    teilnahmeform ||--o{ teilnahme : "form"
    teilnahme ||--|{ teilnahme_status : "status history"
    planungsbereich ||--|{ planungsbereich_kreis : "consists of"
    kreis ||--o{ planungsbereich_kreis : "belongs to"
    planungsbereich ||--o{ versorgungsgrad : "measured"
    arztgruppe ||--o{ versorgungsgrad : "per group"
    arzt ||--o{ zulassungsverfahren : "applicant"
    praxis |o--o{ zulassungsverfahren : "practice"
    planungsbereich ||--o{ zulassungsverfahren : "area"
    teilnahme |o--o{ zulassungsverfahren : "result"
    zulassungsverfahren ||--|{ zulassungsverfahren_status : "status history"

    kreis {
        int kreis_id PK
        char ags UK
        nvarchar name
    }
    arzt {
        int arzt_id PK
        char lanr UK
        char efn UK
        char fachgruppe_code FK
    }
    praxis {
        int praxis_id PK
        char bsnr UK
        int kreis_id FK
    }
    teilnahme {
        int teilnahme_id PK
        int arzt_id FK
        int praxis_id FK
        decimal anrechnungsfaktor
        date valid_from
        date valid_to
    }
    teilnahme_status {
        int teilnahme_id PK
        date valid_from PK
        date valid_to
        varchar status_code
    }
    versorgungsgrad {
        int planungsbereich_id PK
        varchar arztgruppe_code PK
        date stichtag PK
        decimal versorgungsgrad_pct
    }
    zulassungsverfahren {
        int verfahren_id PK
        varchar aktenzeichen UK
        varchar ergebnis
    }
```

## 2. Abrechnung and Honorar

```mermaid
erDiagram
    praxis ||--o{ abrechnungsfall : "bills"
    quartal ||--o{ abrechnungsfall : "in"
    krankenkasse ||--o{ abrechnungsfall : "payer"
    kassenart ||--o{ krankenkasse : "type"
    altersgruppe ||--o{ abrechnungsfall : "patient age"
    scheinuntergruppe ||--o{ abrechnungsfall : "case type"
    abrechnungsfall ||--|{ leistung : "billing lines"
    arzt ||--o{ leistung : "performed by"
    gop ||--o{ leistung : "code"
    ebm_kapitel ||--o{ gop : "chapter"
    qs_bereich |o--o{ gop : "requires permit"
    abrechnungsfall ||--o{ fall_diagnose : "diagnoses"
    icd10 ||--o{ fall_diagnose : "code"
    praxis ||--o{ honorarbescheid : "receives"
    quartal ||--o{ honorarbescheid : "for"
    praxis ||--o{ abschlagszahlung : "receives"
    quartal ||--o{ abschlagszahlung : "for"

    abrechnungsfall {
        int fall_id PK
        varchar fallnummer UK
        char patient_pseudonym "unique with praxis and quartal"
        char tss_vermittlungscode
    }
    leistung {
        bigint leistung_id PK
        int fall_id FK
        date leistungsdatum
        int punktzahl "snapshot"
    }
    gop {
        int gop_id PK
        char gop_code UK
        int punktzahl
        smallint pruefzeit_min
    }
    honorarbescheid {
        int bescheid_id PK
        int praxis_id FK "unique with quartal"
        int punkte_angefordert
        decimal auszahlungsbetrag
    }
```

## 3. Versorgung, Qualitätssicherung, Prüfung, Verordnung

```mermaid
erDiagram
    arztgruppe ||--o{ tss_fachgebiet : "mapping"
    arztgruppe ||--o{ tss_anfrage : "requested specialty"
    kreis ||--o{ tss_anfrage : "patient region"
    praxis |o--o{ tss_anfrage : "appointment at"
    kreis ||--o{ notfallpraxis : "located in"
    notfallpraxis ||--o{ bereitschaftsdienst : "shifts"
    arzt ||--o{ bereitschaftsdienst : "serves"
    arzt ||--o{ qs_genehmigung : "holds"
    qs_bereich ||--o{ qs_genehmigung : "area"
    arzt ||--o{ fortbildungspunkte : "earns"
    praxis ||--o{ pruefverfahren : "audited"
    praxis ||--o{ verordnung : "prescribes"
    arztgruppe ||--o{ richtgroesse : "target"

    tss_anfrage {
        int anfrage_id PK
        uniqueidentifier tss_anfrage_uuid UK
        char vermittlungscode UK
        int wartezeit_tage "computed"
    }
    bereitschaftsdienst {
        int dienst_id PK
        datetime2 beginn
        datetime2 ende
        int getauscht_von_arzt_id FK
    }
    qs_genehmigung {
        int arzt_id PK
        varchar qs_bereich_code PK
        date valid_from PK
        date valid_to
    }
    verordnung {
        int praxis_id PK
        char quartal_code PK
        char verordnungsart PK
        decimal brutto_betrag
    }
```

The TSS request and the billing case are connected through the `vermittlungscode`
(a business key, not a foreign key: the two sources are independent systems).

## 4. Kommunikation (text)

```mermaid
erDiagram
    dokumenttyp ||--o{ dokument : "type"
    dokument ||--o{ dokument_bezug : "links"
    arzt |o--o{ dokument_bezug : "about doctor"
    praxis |o--o{ dokument_bezug : "about practice"
    zulassungsverfahren |o--o{ dokument_bezug : "about procedure"

    dokument {
        int dokument_id PK
        nvarchar quelle_referenz UK
        nvarchar inhalt "NVARCHAR(MAX)"
        binary inhalt_sha256
    }
    dokument_bezug {
        int dokument_bezug_id PK
        int arzt_id FK "exactly one of"
        int praxis_id FK "these three"
        int verfahren_id FK "is set"
    }
```

## 5. Mart: star schema for billing

```mermaid
erDiagram
    dim_datum ||--o{ fact_leistung : "day"
    dim_quartal ||--o{ fact_leistung : "quarter"
    dim_arzt ||--o{ fact_leistung : "SCD2 version"
    dim_praxis ||--o{ fact_leistung : "practice"
    dim_region ||--o{ fact_leistung : "Kreis"
    dim_fachgruppe ||--o{ fact_leistung : "specialty"
    dim_krankenkasse ||--o{ fact_leistung : "payer"
    dim_gop ||--o{ fact_leistung : "GOP"
    dim_altersgruppe ||--o{ fact_leistung : "age group"

    fact_leistung {
        bigint leistung_id PK
        varchar fallnummer "degenerate dimension"
        int anzahl
        int punkte
        decimal betrag_eur
        int pruefzeit_min
    }
    dim_arzt {
        int arzt_key PK
        int arzt_id "durable key"
        date valid_from
        date valid_to
        bit is_current
    }
```

The other stars follow the same pattern:

| Fact | Dimensions |
|---|---|
| `fact_abrechnungsfall` | quartal, praxis, region, arzt, fachgruppe, krankenkasse, altersgruppe |
| `fact_honorar_quartal` | quartal, praxis, region |
| `fact_versorgungsgrad` | datum (Stichtag), planungsbereich, arztgruppe |
| `fact_tss_anfrage` | datum **twice** (request and appointment: a role-playing dimension), arztgruppe, region, altersgruppe, praxis |
| `fact_bereitschaftsdienst` | datum, arzt, region |
