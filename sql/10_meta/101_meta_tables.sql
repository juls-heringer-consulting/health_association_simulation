/* =============================================================================
   101_meta_tables.sql
   Technical metadata: load log (batches, files, steps) and data-quality results.
   Re-runnable WITHOUT data loss: tables are only created if missing, so the load
   history survives rebuilds of stg/core/mart.
   Naming: meta is a technical schema, so table and column names are English.
   ============================================================================= */
USE KVSim;
GO

-- One row per load run ("batch"). Every staging and core row points to the batch that loaded it.
IF OBJECT_ID(N'meta.load_batch', N'U') IS NULL
BEGIN
    CREATE TABLE meta.load_batch (
        batch_id     INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_load_batch PRIMARY KEY,
        started_at   DATETIME2(0)  NOT NULL CONSTRAINT df_load_batch_started_at DEFAULT (SYSDATETIME()),
        finished_at  DATETIME2(0)  NULL,
        status       VARCHAR(10)   NOT NULL CONSTRAINT df_load_batch_status DEFAULT ('RUNNING')
                     CONSTRAINT ck_load_batch_status CHECK (status IN ('RUNNING', 'OK', 'FAILED')),
        started_by   NVARCHAR(128) NOT NULL CONSTRAINT df_load_batch_started_by DEFAULT (SUSER_SNAME()),
        note         NVARCHAR(400) NULL
    );
END
GO

-- One row per source file loaded into staging: lineage + a fingerprint (SHA-256) of the file.
IF OBJECT_ID(N'meta.load_file', N'U') IS NULL
BEGIN
    CREATE TABLE meta.load_file (
        load_file_id    INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_load_file PRIMARY KEY,
        batch_id        INT            NOT NULL CONSTRAINT fk_load_file_load_batch REFERENCES meta.load_batch (batch_id),
        source_name     VARCHAR(60)    NOT NULL,
        file_name       NVARCHAR(260)  NOT NULL,
        file_sha256     CHAR(64)       NOT NULL,
        file_size_bytes BIGINT         NOT NULL,
        target_table    NVARCHAR(128)  NOT NULL,
        rows_loaded     INT            NOT NULL,
        loaded_at       DATETIME2(0)   NOT NULL CONSTRAINT df_load_file_loaded_at DEFAULT (SYSDATETIME())
    );
    CREATE INDEX ix_load_file_batch_id ON meta.load_file (batch_id);
END
GO

-- One row per load procedure call (stg -> core, core -> mart).
IF OBJECT_ID(N'meta.load_step', N'U') IS NULL
BEGIN
    CREATE TABLE meta.load_step (
        step_id        INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_load_step PRIMARY KEY,
        batch_id       INT            NOT NULL CONSTRAINT fk_load_step_load_batch REFERENCES meta.load_batch (batch_id),
        step_name      NVARCHAR(128)  NOT NULL,
        started_at     DATETIME2(0)   NOT NULL CONSTRAINT df_load_step_started_at DEFAULT (SYSDATETIME()),
        finished_at    DATETIME2(0)   NULL,
        status         VARCHAR(10)    NOT NULL CONSTRAINT df_load_step_status DEFAULT ('RUNNING')
                       CONSTRAINT ck_load_step_status CHECK (status IN ('RUNNING', 'OK', 'FAILED')),
        rows_affected  INT            NULL,
        message        NVARCHAR(4000) NULL
    );
    CREATE INDEX ix_load_step_batch_id ON meta.load_step (batch_id);
END
GO

-- Catalogue of data-quality rules (filled by sql/70_quality).
IF OBJECT_ID(N'meta.dq_rule', N'U') IS NULL
BEGIN
    CREATE TABLE meta.dq_rule (
        rule_code    VARCHAR(10)    NOT NULL CONSTRAINT pk_dq_rule PRIMARY KEY,
        rule_name    NVARCHAR(200)  NOT NULL,
        category     VARCHAR(20)    NOT NULL
                     CONSTRAINT ck_dq_rule_category CHECK (category IN ('VALIDITY', 'CONSISTENCY', 'COMPLETENESS', 'RECONCILIATION', 'BUSINESS_RULE')),
        severity     VARCHAR(10)    NOT NULL
                     CONSTRAINT ck_dq_rule_severity CHECK (severity IN ('ERROR', 'WARNING', 'INFO')),
        checked_object NVARCHAR(256) NOT NULL,
        description  NVARCHAR(1000) NOT NULL
    );
END
GO

IF OBJECT_ID(N'meta.dq_run', N'U') IS NULL
BEGIN
    CREATE TABLE meta.dq_run (
        run_id       INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_dq_run PRIMARY KEY,
        batch_id     INT          NULL,
        started_at   DATETIME2(0) NOT NULL CONSTRAINT df_dq_run_started_at DEFAULT (SYSDATETIME()),
        finished_at  DATETIME2(0) NULL
    );
END
GO

IF OBJECT_ID(N'meta.dq_result', N'U') IS NULL
BEGIN
    CREATE TABLE meta.dq_result (
        run_id       INT          NOT NULL CONSTRAINT fk_dq_result_dq_run REFERENCES meta.dq_run (run_id),
        rule_code    VARCHAR(10)  NOT NULL CONSTRAINT fk_dq_result_dq_rule REFERENCES meta.dq_rule (rule_code),
        failed_rows  INT          NOT NULL,
        result       VARCHAR(10)  NOT NULL CONSTRAINT ck_dq_result_result CHECK (result IN ('PASS', 'FAIL')),
        checked_at   DATETIME2(0) NOT NULL CONSTRAINT df_dq_result_checked_at DEFAULT (SYSDATETIME()),
        CONSTRAINT pk_dq_result PRIMARY KEY (run_id, rule_code)
    );
END
GO
