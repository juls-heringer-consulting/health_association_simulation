/* =============================================================================
   500_drop_mart_tables.sql
   Start of the MART layer (dimensional model). Everything in mart is derived
   from core and can be rebuilt at any time with EXEC mart.usp_load_all.
   Run 500 -> 503 as a block.
   ============================================================================= */
USE KVSim;
GO

EXEC meta.usp_drop_tables @schema = N'mart';
GO
