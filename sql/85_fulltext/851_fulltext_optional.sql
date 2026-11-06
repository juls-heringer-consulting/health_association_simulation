/* =============================================================================
   851_fulltext_optional.sql
   OPTIONAL: full-text search on core.dokument.inhalt.

   Needs the SQL Server feature "Full-Text and Semantic Extractions for Search".
   It is NOT installed on this machine at the moment
   (SELECT FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') returns 0).
   To add it: run the SQL Server 2025 installer -> "Add features to an existing
   installation" -> instance MSSQLSERVER -> tick "Full-Text and Semantic
   Extractions for Search". Then re-run this script.

   Without the feature this script only prints a message and shows the LIKE
   fallback. The statements are wrapped in EXEC(...) so that the script still
   compiles on a server without full-text support.

   Why full-text instead of LIKE?
     LIKE '%Wartezeit%'   scans every character of every document (no index),
                          finds only the exact string, no word forms.
     CONTAINS / FREETEXT  use an inverted word index, understand German word
                          forms (FORMSOF(INFLECTIONAL, ...)), rank results, and
                          stay fast with millions of documents.
   ============================================================================= */
USE KVSim;
GO

IF FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') = 1
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'ft_kvsim')
        EXEC (N'CREATE FULLTEXT CATALOG ft_kvsim AS DEFAULT;');

    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'core.dokument'))
        -- KEY INDEX: a unique, single-column, non-nullable index -> the primary key pk_dokument
        -- LANGUAGE 1031 = German word breaker and stemmer
        EXEC (N'CREATE FULLTEXT INDEX ON core.dokument (inhalt LANGUAGE 1031, titel LANGUAGE 1031)
                KEY INDEX pk_dokument ON ft_kvsim WITH CHANGE_TRACKING AUTO;');

    PRINT 'Full-text index on core.dokument created (population runs in the background).';
END
ELSE
    PRINT 'Full-Text Search is not installed on this instance - skipped. See the comment at the top of this file.';
GO

/* ---------- fallback that works everywhere: LIKE ------------------------------------------ */
SELECT d.dokumenttyp_code, d.titel, d.dokument_datum
FROM core.dokument AS d
WHERE d.inhalt LIKE N'%Wartezeit%'
ORDER BY d.dokument_datum;
GO

/* ---------- full-text queries (run once the index exists) ----------------------------------
-- all word forms of "warten" (wartet, gewartet, Wartezeit is a compound -> try both)
SELECT dokument_id, titel FROM core.dokument
WHERE CONTAINS(inhalt, N'FORMSOF(INFLECTIONAL, warten)');

-- two words near each other
SELECT dokument_id, titel FROM core.dokument
WHERE CONTAINS(inhalt, N'NEAR((Termin, Patienten), 10)');

-- ranked natural-language search, joined to the practice the document is about
SELECT TOP 10 k.RANK, d.titel, p.bsnr, p.name
FROM FREETEXTTABLE(core.dokument, inhalt, N'telefonisch nicht erreichbar Anrufbeantworter') AS k
JOIN core.dokument AS d ON d.dokument_id = k.[KEY]
LEFT JOIN core.dokument_bezug AS b ON b.dokument_id = d.dokument_id AND b.praxis_id IS NOT NULL
LEFT JOIN core.praxis AS p ON p.praxis_id = b.praxis_id
ORDER BY k.RANK DESC;
------------------------------------------------------------------------------------------- */
