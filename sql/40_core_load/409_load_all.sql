/* =============================================================================
   409_load_all.sql
   core.usp_load_all: runs all stg -> core steps in dependency order.
   Each step is its own transaction; if a step fails, the steps before it stay
   committed and the error is re-raised (see meta.load_step for the log).

   Usage in SSMS:   EXEC core.usp_load_all;            -- latest successful batch
                    EXEC core.usp_load_all @batch_id = 2;
   ============================================================================= */
USE KVSim;
GO

CREATE OR ALTER PROCEDURE core.usp_load_all
    @batch_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @batch_id = COALESCE(@batch_id, meta.fn_latest_batch_id());
    IF @batch_id IS NULL
        THROW 50000, N'No successful staging batch found. Run python/load_staging.py first.', 1;

    EXEC core.usp_load_referenz               @batch_id = @batch_id;  -- region, code lists, catalogues
    EXEC core.usp_load_arztregister           @batch_id = @batch_id;  -- needs: kreis, fachgruppe
    EXEC core.usp_load_bedarfsplanung         @batch_id = @batch_id;  -- needs: kreis, arztgruppe
    EXEC core.usp_load_zulassung              @batch_id = @batch_id;  -- needs: arzt, praxis, teilnahme, planungsbereich
    EXEC core.usp_load_abrechnung             @batch_id = @batch_id;  -- needs: praxis, arzt, gop, icd10, krankenkasse
    EXEC core.usp_load_versorgung             @batch_id = @batch_id;  -- needs: praxis, arzt, kreis
    EXEC core.usp_load_qs_pruefung_verordnung @batch_id = @batch_id;  -- needs: arzt, praxis
    EXEC core.usp_load_kommunikation          @batch_id = @batch_id;  -- needs: arzt, praxis, zulassungsverfahren

    SELECT step_name, status, rows_affected, DATEDIFF(MILLISECOND, started_at, finished_at) AS duration_ms
    FROM meta.load_step
    WHERE batch_id = @batch_id
    ORDER BY step_id;
END
GO
