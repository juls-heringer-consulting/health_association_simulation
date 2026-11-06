/* =============================================================================
   300_drop_core_tables.sql
   Start of the CORE layer. Drops all core tables so that 301-309 can rebuild
   them. All core data can be reloaded from staging (EXEC core.usp_load_all).

   IMPORTANT: run the core scripts as a block, 300 -> 309. Running only e.g. 302
   fails, because other core tables reference its tables via foreign keys.
   ============================================================================= */
USE KVSim;
GO

EXEC meta.usp_drop_tables @schema = N'core';
GO
