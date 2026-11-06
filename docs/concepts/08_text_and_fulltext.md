# 08 Unstructured text: storing, linking, searching

*Tables: `core.dokument`, `core.dokument_bezug`, `core.dokumenttyp`. Scripts: `307_kommunikation.sql`, `407_load_kommunikation.sql`, `sql/85_fulltext`.*

## Storing

| Column | Purpose |
|---|---|
| `inhalt NVARCHAR(MAX)` | the full original text (up to 2 GB, Unicode) |
| `titel`, `dokument_datum`, `kategorie`, `status` | metadata extracted from the text or its source - what people filter on |
| `inhalt_sha256 BINARY(32)` | fingerprint: detects changed or duplicate documents without comparing megabytes of text |
| `zeichen_anzahl AS LEN(inhalt)` | computed column |
| `dokumenttyp.vertraulichkeit` | confidentiality class - basis for access rules |

One table for all text types (enquiries, complaints, minutes, notices) keeps search in one
place. Type-specific structured attributes could go into 1:1 subtype tables later
(e.g. `beschwerde` with `kategorie`, `ergebnis`).

Binary originals (PDF scans) would be stored as `VARBINARY(MAX)` or with FILESTREAM /
FileTable, or in a document management system with only the reference in the database.

## Linking text to structured data

| Source | How the link is found | Quality |
|---|---|---|
| CRM tickets (JSON) | structured fields `requester.lanr`, `requester.bsnr` | exact |
| complaints (TXT) | header line `Bezug-BSNR:` added at intake | exact, depends on intake discipline |
| minutes (Markdown) | file numbers found **inside the text** (`LIKE '%' + aktenzeichen + '%'`) | good for strict patterns |
| notices (XML) | parent element of the text | exact |

The links go into `core.dokument_bezug` with real foreign keys and an **exclusive arc**:
each row points to exactly one of arzt / praxis / verfahren (DD-08).

```sql
-- all documents about one practice, newest first
SELECT d.dokumenttyp_code, d.dokument_datum, d.titel
FROM core.dokument_bezug AS b
JOIN core.dokument AS d ON d.dokument_id = b.dokument_id
JOIN core.praxis AS p ON p.praxis_id = b.praxis_id
WHERE p.bsnr = (SELECT TOP 1 bsnr FROM core.praxis ORDER BY bsnr)
ORDER BY d.dokument_datum DESC;
```

Parsing helper: `core.fn_text_field(text, 'Key')` returns the value of a `Key: value` line
(mail headers, Markdown front matter).

## Searching: LIKE vs. full-text

| | `LIKE '%Wartezeit%'` | Full-text (`CONTAINS`, `FREETEXT`) |
|---|---|---|
| index | none possible with a leading `%` → reads all text | inverted index of words |
| word forms | exact string only | `FORMSOF(INFLECTIONAL, warten)` finds wartet, gewartet |
| ranking | no | `CONTAINSTABLE` / `FREETEXTTABLE` return a RANK |
| language | none | German word breaker and stemmer (LANGUAGE 1031) |
| works now on this PC | ✔ | needs the full-text feature (not installed yet) |

`sql/85_fulltext/851_fulltext_optional.sql` creates the catalog and index when the feature
is present, and shows example queries. To install it, run the SQL Server 2025 installer →
"Add features to an existing installation" → "Full-Text and Semantic Extractions for Search".

## Outlook

SQL Server 2025 also has a `VECTOR` data type for semantic search with embeddings, and
regular-expression functions (`REGEXP_LIKE`, ...) that make pattern extraction like
Aktenzeichen easier. Not used here to stay compatible with older versions (DD-20).
