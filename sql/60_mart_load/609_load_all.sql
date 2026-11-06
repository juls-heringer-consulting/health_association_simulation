/* =============================================================================
   609_load_all.sql
   mart.usp_load_all: rebuild the mart from core.
     1. empty the fact tables (they reference dimension versions)
     2. load / update dimensions (surrogate keys of type-1 members stay stable)
     3. reload facts
   Usage in SSMS:   EXEC mart.usp_load_all;
   ============================================================================= */
USE KVSim;
GO

CREATE OR ALTER PROCEDURE mart.usp_load_all
    @batch_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @batch_id = COALESCE(@batch_id, meta.fn_latest_batch_id());

    TRUNCATE TABLE mart.fact_leistung;
    TRUNCATE TABLE mart.fact_abrechnungsfall;
    TRUNCATE TABLE mart.fact_honorar_quartal;
    TRUNCATE TABLE mart.fact_versorgungsgrad;
    TRUNCATE TABLE mart.fact_tss_anfrage;
    TRUNCATE TABLE mart.fact_bereitschaftsdienst;

    EXEC mart.usp_load_dimensions @batch_id = @batch_id;
    EXEC mart.usp_load_facts      @batch_id = @batch_id;

    SELECT step_name, status, rows_affected, DATEDIFF(MILLISECOND, started_at, finished_at) AS duration_ms
    FROM meta.load_step
    WHERE batch_id = @batch_id AND step_name LIKE N'mart.%'
    ORDER BY step_id;
END
GO
