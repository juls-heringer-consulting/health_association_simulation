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
