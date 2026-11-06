/* =============================================================================
   002_create_schemas.sql
   One schema per architecture layer. Schemas are namespaces AND security
   boundaries: permissions can be granted per schema (see sql/80_security).
   Re-runnable.
   ============================================================================= */
USE KVSim;
GO

IF SCHEMA_ID(N'meta') IS NULL EXEC (N'CREATE SCHEMA meta AUTHORIZATION dbo;');  -- load log, data quality, data dictionary
IF SCHEMA_ID(N'stg')  IS NULL EXEC (N'CREATE SCHEMA stg  AUTHORIZATION dbo;');  -- staging: 1:1 copies of source files
IF SCHEMA_ID(N'core') IS NULL EXEC (N'CREATE SCHEMA core AUTHORIZATION dbo;');  -- integrated, normalised model (3NF)
IF SCHEMA_ID(N'mart') IS NULL EXEC (N'CREATE SCHEMA mart AUTHORIZATION dbo;');  -- star schemas for reporting
GO
-- Why EXEC(...)? CREATE SCHEMA must be the only statement in its batch; wrapping it in
-- dynamic SQL lets us combine it with IF.

SELECT name AS schema_name FROM sys.schemas WHERE name IN (N'meta', N'stg', N'core', N'mart');
GO
