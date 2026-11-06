/* =============================================================================
   001_create_database.sql
   Creates the training database KVSim if it does not exist yet.
   Re-runnable: never drops anything.
   ============================================================================= */
USE master;
GO

IF DB_ID(N'KVSim') IS NULL
BEGIN
    CREATE DATABASE KVSim;
    PRINT 'Database KVSim created.';
END
ELSE
    PRINT 'Database KVSim already exists - nothing to do.';
GO

-- SIMPLE recovery model: this database can be rebuilt completely from the source files,
-- so point-in-time restore is not needed. A production DWH at a KV would decide this
-- together with the database operations team.
ALTER DATABASE KVSim SET RECOVERY SIMPLE;
GO
