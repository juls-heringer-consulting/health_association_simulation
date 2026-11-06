/* =============================================================================
   308_functions_views.sql
   Reusable functions and views on the core layer.
   ============================================================================= */
USE KVSim;
GO

/* Check digit of a LANR (digit 7), computed from digits 1-6.
   Weights 4,9,4,9,4,9 -> sum -> mod 10 -> 10 minus that (10 becomes 0).
   Usage: SELECT lanr FROM core.arzt WHERE core.fn_lanr_pruefziffer(lanr) <> CAST(SUBSTRING(lanr, 7, 1) AS TINYINT); */
CREATE OR ALTER FUNCTION core.fn_lanr_pruefziffer (@lanr CHAR(9))
RETURNS TINYINT
AS
BEGIN
    IF @lanr IS NULL OR @lanr NOT LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
        RETURN NULL;
    DECLARE @summe INT =
          CAST(SUBSTRING(@lanr, 1, 1) AS INT) * 4 + CAST(SUBSTRING(@lanr, 2, 1) AS INT) * 9
        + CAST(SUBSTRING(@lanr, 3, 1) AS INT) * 4 + CAST(SUBSTRING(@lanr, 4, 1) AS INT) * 9
        + CAST(SUBSTRING(@lanr, 5, 1) AS INT) * 4 + CAST(SUBSTRING(@lanr, 6, 1) AS INT) * 9;
    RETURN (10 - @summe % 10) % 10;
END
GO

/* Reads "Key: value" lines from a text (mail headers, Markdown front matter).
   Example: core.fn_text_field(content, N'Bezug-BSNR') -> '731234567' */
CREATE OR ALTER FUNCTION core.fn_text_field (@text NVARCHAR(MAX), @key NVARCHAR(100))
RETURNS NVARCHAR(400)
AS
BEGIN
    DECLARE @t NVARCHAR(MAX) = NCHAR(10) + REPLACE(@text, NCHAR(13), N'');  -- normalise CRLF -> LF
    DECLARE @pos INT = CHARINDEX(NCHAR(10) + @key + N':', @t);
    IF @pos = 0 RETURN NULL;
    DECLARE @start INT = @pos + LEN(@key) + 2;                             -- first char after "<LF>key:"
    DECLARE @end INT = CHARINDEX(NCHAR(10), @t, @start);
    IF @end = 0 SET @end = LEN(@t) + 1;
    RETURN LTRIM(RTRIM(SUBSTRING(@t, @start, @end - @start)));
END
GO

/* "Parameterised view": all Teilnahmen valid on a given date with their status then.
   An inline table-valued function is expanded into the calling query like a view,
   so the optimizer can use indexes - unlike a multi-statement function. */
CREATE OR ALTER FUNCTION core.fn_teilnahme_am (@stichtag DATE)
RETURNS TABLE
AS
RETURN
    SELECT t.teilnahme_id, t.arzt_id, t.praxis_id, t.teilnahmeform_code, t.anrechnungsfaktor, s.status_code
    FROM core.teilnahme AS t
    JOIN core.teilnahme_status AS s
      ON s.teilnahme_id = t.teilnahme_id
     AND @stichtag >= s.valid_from AND @stichtag < s.valid_to    -- half-open interval test
    WHERE @stichtag >= t.valid_from AND @stichtag < t.valid_to;
GO

-- Who works where today? (readable starting point for beginners)
CREATE OR ALTER VIEW core.v_teilnahme_aktuell
AS
SELECT a.lanr, a.titel, a.vorname, a.nachname, f.bezeichnung AS fachgruppe,
       p.bsnr, p.name AS praxis, k.name AS kreis,
       t.teilnahmeform_code, t.anrechnungsfaktor, t.status_code
FROM core.fn_teilnahme_am(CAST(SYSDATETIME() AS DATE)) AS t
JOIN core.arzt       AS a ON a.arzt_id = t.arzt_id
JOIN core.fachgruppe AS f ON f.fachgruppe_code = a.fachgruppe_code
JOIN core.praxis     AS p ON p.praxis_id = t.praxis_id
JOIN core.kreis      AS k ON k.kreis_id = p.kreis_id;
GO

/* Role-specific document views (see sql/80_security): a role gets SELECT on a
   view that only shows "its" document types instead of the whole table. */
CREATE OR ALTER VIEW core.v_dokument_zulassung
AS
SELECT dokument_id, dokumenttyp_code, quelle_referenz, titel, dokument_datum, kategorie, inhalt
FROM core.dokument
WHERE dokumenttyp_code IN ('PROTOKOLL', 'BESCHEID');
GO

CREATE OR ALTER VIEW core.v_dokument_mitgliederservice
AS
SELECT dokument_id, dokumenttyp_code, quelle_referenz, titel, dokument_datum, kategorie, status, inhalt
FROM core.dokument
WHERE dokumenttyp_code IN ('ANFRAGE', 'BESCHWERDE');
GO
