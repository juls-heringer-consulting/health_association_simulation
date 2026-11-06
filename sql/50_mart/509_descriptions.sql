/* =============================================================================
   509_descriptions.sql
   Table descriptions (MS_Description) for the mart layer.
   ============================================================================= */
USE KVSim;
GO

EXEC meta.usp_describe 'mart', 'dim_datum',               NULL, N'Calendar day dimension 2024-2026 with Saarland public holidays. Key = yyyymmdd.';
EXEC meta.usp_describe 'mart', 'dim_quartal',             NULL, N'Quarter dimension (rolled-up calendar). Key = yyyyq, e.g. 20251.';
EXEC meta.usp_describe 'mart', 'dim_region',              NULL, N'Region dimension at Kreis level.';
EXEC meta.usp_describe 'mart', 'dim_arztgruppe',          NULL, N'Bedarfsplanung physician groups.';
EXEC meta.usp_describe 'mart', 'dim_fachgruppe',          NULL, N'Specialties with their Arztgruppe (denormalised).';
EXEC meta.usp_describe 'mart', 'dim_arzt',                NULL, N'Doctors as SCD type 2: one row per version (practice / employment form changes).';
EXEC meta.usp_describe 'mart', 'dim_praxis',              NULL, N'Practices (type 1: always the current attributes).';
EXEC meta.usp_describe 'mart', 'dim_krankenkasse',        NULL, N'Health insurers with their type.';
EXEC meta.usp_describe 'mart', 'dim_gop',                 NULL, N'EBM billing codes with chapter and QS area.';
EXEC meta.usp_describe 'mart', 'dim_altersgruppe',        NULL, N'Age groups.';
EXEC meta.usp_describe 'mart', 'dim_planungsbereich',     NULL, N'Planning areas of the Bedarfsplanung.';
EXEC meta.usp_describe 'mart', 'fact_leistung',           NULL, N'Grain: one billed GOP line. Values at Orientierungswert.';
EXEC meta.usp_describe 'mart', 'fact_abrechnungsfall',    NULL, N'Grain: one Behandlungsfall. arzt/fachgruppe = doctor of the first billing line (Hauptbehandler).';
EXEC meta.usp_describe 'mart', 'fact_honorar_quartal',    NULL, N'Grain: one practice per quarter (periodic snapshot of the Honorarbescheid plus payments).';
EXEC meta.usp_describe 'mart', 'fact_versorgungsgrad',    NULL, N'Grain: planning area x Arztgruppe x reference date (official + recomputed Ist).';
EXEC meta.usp_describe 'mart', 'fact_tss_anfrage',        NULL, N'Grain: one TSS request (accumulating snapshot with request and appointment date).';
EXEC meta.usp_describe 'mart', 'fact_bereitschaftsdienst',NULL, N'Grain: one out-of-hours shift.';
GO

-- Column descriptions derived from the catalog: dimension keys and fact foreign keys
DECLARE @d TABLE (tbl SYSNAME, col SYSNAME, txt NVARCHAR(3750));
INSERT INTO @d (tbl, col, txt)
SELECT t.name, c.name, N'Surrogate key of the dimension; -1 = unknown member.'
FROM sys.tables AS t
JOIN sys.columns AS c ON c.object_id = t.object_id
JOIN sys.index_columns AS ic ON ic.object_id = t.object_id AND ic.column_id = c.column_id
JOIN sys.indexes AS i ON i.object_id = ic.object_id AND i.index_id = ic.index_id AND i.is_primary_key = 1
WHERE SCHEMA_NAME(t.schema_id) = N'mart' AND t.name LIKE N'dim[_]%';
INSERT INTO @d (tbl, col, txt)
SELECT OBJECT_NAME(fkc.parent_object_id), COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
       N'Foreign key to mart.' + OBJECT_NAME(fkc.referenced_object_id) + N'.'
FROM sys.foreign_key_columns AS fkc
WHERE OBJECT_SCHEMA_NAME(fkc.parent_object_id) = N'mart';
INSERT INTO @d (tbl, col, txt) VALUES
    ('dim_arzt', 'arzt_id', N'Durable key: core.arzt.arzt_id, the same for all versions of a doctor.'),
    ('dim_arzt', 'valid_from', N'Start of this version (inclusive).'),
    ('dim_arzt', 'valid_to', N'End of this version (exclusive); 9999-12-31 = open.'),
    ('dim_arzt', 'is_current', N'1 = newest version of the doctor.'),
    ('fact_leistung', 'betrag_eur', N'Points x Orientierungswert (value before Honorarverteilung).'),
    ('fact_leistung', 'pruefzeit_min', N'Anzahl x Prüfzeit of the GOP, for time-plausibility profiles.'),
    ('fact_versorgungsgrad', 'ist_aerzte_berechnet', N'Ist recomputed from core.teilnahme (reconciliation against the official ist_aerzte).'),
    ('fact_tss_anfrage', 'ist_innerhalb_4_wochen', N'1 = appointment within 28 days of the request.');

DECLARE @tbl SYSNAME, @col SYSNAME, @txt NVARCHAR(3750);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT tbl, col, txt FROM @d;
OPEN c;
FETCH NEXT FROM c INTO @tbl, @col, @txt;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC meta.usp_describe @schema = N'mart', @table = @tbl, @column = @col, @description = @txt;
    FETCH NEXT FROM c INTO @tbl, @col, @txt;
END
CLOSE c;
DEALLOCATE c;
GO
