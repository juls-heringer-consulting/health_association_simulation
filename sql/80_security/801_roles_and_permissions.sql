/* =============================================================================
   801_roles_and_permissions.sql
   Role-based security sketch: "who in a KV may see what" (see docs/security.md).

   Principles
     * least privilege: a role gets exactly the objects its department needs
     * permissions go to ROLES, never to individual users
     * schemas are security boundaries: GRANT ... ON SCHEMA::mart covers all
       current AND future objects in that schema
     * nobody but the ETL role sees stg (raw data, possibly not yet validated)

   Test users are created WITHOUT LOGIN: they cannot connect, but you can
   impersonate them in SSMS to see the effect (block at the end of this file).
   Re-runnable.
   ============================================================================= */
USE KVSim;
GO

/* ---------- roles -------------------------------------------------------------- */
IF DATABASE_PRINCIPAL_ID(N'rl_etl')               IS NULL CREATE ROLE rl_etl;               -- technical load process
IF DATABASE_PRINCIPAL_ID(N'rl_abrechnung')        IS NULL CREATE ROLE rl_abrechnung;        -- billing department
IF DATABASE_PRINCIPAL_ID(N'rl_pruefwesen')        IS NULL CREATE ROLE rl_pruefwesen;        -- audits / plausibility
IF DATABASE_PRINCIPAL_ID(N'rl_zulassung')         IS NULL CREATE ROLE rl_zulassung;         -- licensing & needs planning
IF DATABASE_PRINCIPAL_ID(N'rl_versorgung')        IS NULL CREATE ROLE rl_versorgung;        -- TSS & out-of-hours service
IF DATABASE_PRINCIPAL_ID(N'rl_mitgliederservice') IS NULL CREATE ROLE rl_mitgliederservice; -- member service, complaints
IF DATABASE_PRINCIPAL_ID(N'rl_controlling')       IS NULL CREATE ROLE rl_controlling;       -- management reporting
GO

/* ---------- ETL: full access to the layers it maintains ------------------------------ */
GRANT SELECT, INSERT, UPDATE, DELETE, ALTER, EXECUTE ON SCHEMA::stg  TO rl_etl;   -- ALTER is needed for TRUNCATE
GRANT SELECT, INSERT, UPDATE, DELETE, ALTER, EXECUTE ON SCHEMA::core TO rl_etl;
GRANT SELECT, INSERT, UPDATE, DELETE, ALTER, EXECUTE ON SCHEMA::mart TO rl_etl;
GRANT SELECT, INSERT, UPDATE, EXECUTE ON SCHEMA::meta TO rl_etl;

/* ---------- Abrechnung: billing data incl. patient pseudonym, plus mart ---------------- */
GRANT SELECT ON core.abrechnungsfall   TO rl_abrechnung;
GRANT SELECT ON core.leistung          TO rl_abrechnung;
GRANT SELECT ON core.fall_diagnose     TO rl_abrechnung;
GRANT SELECT ON core.honorarbescheid   TO rl_abrechnung;
GRANT SELECT ON core.abschlagszahlung  TO rl_abrechnung;
GRANT SELECT ON core.gop               TO rl_abrechnung;
GRANT SELECT ON core.ebm_kapitel       TO rl_abrechnung;
GRANT SELECT ON core.orientierungswert TO rl_abrechnung;
GRANT SELECT ON core.icd10             TO rl_abrechnung;
GRANT SELECT ON core.krankenkasse      TO rl_abrechnung;
GRANT SELECT ON core.kassenart         TO rl_abrechnung;
GRANT SELECT ON core.quartal           TO rl_abrechnung;
GRANT SELECT ON core.arzt              TO rl_abrechnung;
GRANT SELECT ON core.praxis            TO rl_abrechnung;
GRANT SELECT ON core.teilnahme         TO rl_abrechnung;
GRANT SELECT ON core.qs_genehmigung    TO rl_abrechnung;
GRANT SELECT ON SCHEMA::mart           TO rl_abrechnung;

/* ---------- Pruefwesen: billing + prescriptions + audits + QS ------------------------- */
GRANT SELECT ON core.abrechnungsfall    TO rl_pruefwesen;
GRANT SELECT ON core.leistung           TO rl_pruefwesen;
GRANT SELECT ON core.fall_diagnose      TO rl_pruefwesen;
GRANT SELECT ON core.gop                TO rl_pruefwesen;
GRANT SELECT ON core.icd10              TO rl_pruefwesen;
GRANT SELECT ON core.quartal            TO rl_pruefwesen;
GRANT SELECT ON core.arzt               TO rl_pruefwesen;
GRANT SELECT ON core.praxis             TO rl_pruefwesen;
GRANT SELECT ON core.teilnahme          TO rl_pruefwesen;
GRANT SELECT ON core.verordnung         TO rl_pruefwesen;
GRANT SELECT ON core.richtgroesse       TO rl_pruefwesen;
GRANT SELECT ON core.pruefverfahren     TO rl_pruefwesen;
GRANT SELECT ON core.qs_genehmigung     TO rl_pruefwesen;
GRANT SELECT ON core.fortbildungspunkte TO rl_pruefwesen;
GRANT SELECT ON SCHEMA::mart            TO rl_pruefwesen;

/* ---------- Zulassung / Bedarfsplanung: register and planning, NO billing data ------------ */
GRANT SELECT ON core.arzt                       TO rl_zulassung;
GRANT SELECT ON core.praxis                     TO rl_zulassung;
GRANT SELECT ON core.teilnahme                  TO rl_zulassung;
GRANT SELECT ON core.teilnahme_status           TO rl_zulassung;
GRANT SELECT ON core.zulassungsverfahren        TO rl_zulassung;
GRANT SELECT ON core.zulassungsverfahren_status TO rl_zulassung;
GRANT SELECT ON core.planungsbereich            TO rl_zulassung;
GRANT SELECT ON core.planungsbereich_kreis      TO rl_zulassung;
GRANT SELECT ON core.versorgungsgrad            TO rl_zulassung;
GRANT SELECT ON core.arztgruppe                 TO rl_zulassung;
GRANT SELECT ON core.fachgruppe                 TO rl_zulassung;
GRANT SELECT ON core.kreis                      TO rl_zulassung;
GRANT SELECT ON core.einwohner                  TO rl_zulassung;
GRANT SELECT ON core.v_dokument_zulassung       TO rl_zulassung;   -- minutes and notices only (view filters the rows)
GRANT SELECT ON mart.fact_versorgungsgrad       TO rl_zulassung;
GRANT SELECT ON mart.dim_planungsbereich        TO rl_zulassung;
GRANT SELECT ON mart.dim_arztgruppe             TO rl_zulassung;
GRANT SELECT ON mart.dim_datum                  TO rl_zulassung;
GRANT SELECT ON mart.v_versorgung_aktuell       TO rl_zulassung;

/* ---------- Versorgung: TSS and Bereitschaftsdienst ------------------------------------ */
GRANT SELECT ON core.tss_anfrage              TO rl_versorgung;
GRANT SELECT ON core.tss_fachgebiet           TO rl_versorgung;
GRANT SELECT ON core.notfallpraxis            TO rl_versorgung;
GRANT SELECT ON core.bereitschaftsdienst      TO rl_versorgung;
GRANT SELECT ON core.arzt                     TO rl_versorgung;
GRANT SELECT ON core.praxis                   TO rl_versorgung;
GRANT SELECT ON core.kreis                    TO rl_versorgung;
GRANT SELECT ON mart.fact_tss_anfrage         TO rl_versorgung;
GRANT SELECT ON mart.fact_bereitschaftsdienst TO rl_versorgung;
GRANT SELECT ON mart.dim_datum                TO rl_versorgung;
GRANT SELECT ON mart.dim_arzt                 TO rl_versorgung;
GRANT SELECT ON mart.dim_praxis               TO rl_versorgung;
GRANT SELECT ON mart.dim_region               TO rl_versorgung;
GRANT SELECT ON mart.dim_arztgruppe           TO rl_versorgung;
GRANT SELECT ON mart.dim_altersgruppe         TO rl_versorgung;

/* ---------- Mitgliederservice: enquiries and complaints, master data -------------------- */
GRANT SELECT ON core.v_dokument_mitgliederservice TO rl_mitgliederservice;
GRANT SELECT ON core.arzt                         TO rl_mitgliederservice;
GRANT SELECT ON core.praxis                       TO rl_mitgliederservice;

/* ---------- Controlling: aggregated mart only, no doctor names ---------------------------- */
GRANT SELECT ON SCHEMA::mart TO rl_controlling;
-- Column-level DENY: everything in dim_arzt except the name is visible.
DENY SELECT ON mart.dim_arzt (arzt_name) TO rl_controlling;
-- Careful: a VIEW owned by the same owner as its tables does NOT re-check the table
-- permissions ("ownership chaining"). The view below exposes arzt_name, so it must be
-- denied separately - otherwise the column DENY above could be bypassed through it.
DENY SELECT ON mart.v_plausi_tagesprofil TO rl_controlling;
GO

/* ---------- test users (no login) ----------------------------------------------------------- */
IF DATABASE_PRINCIPAL_ID(N'u_abrechnung')  IS NULL CREATE USER u_abrechnung  WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID(N'u_zulassung')   IS NULL CREATE USER u_zulassung   WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID(N'u_controlling') IS NULL CREATE USER u_controlling WITHOUT LOGIN;
ALTER ROLE rl_abrechnung  ADD MEMBER u_abrechnung;
ALTER ROLE rl_zulassung   ADD MEMBER u_zulassung;
ALTER ROLE rl_controlling ADD MEMBER u_controlling;
GO

/* ---------- try it in SSMS (select the lines and press F5) ---------------------------------
EXECUTE AS USER = 'u_zulassung';
    SELECT TOP 5 * FROM mart.v_versorgung_aktuell;          -- works
    SELECT TOP 5 * FROM core.leistung;                      -- error 229: permission denied
    SELECT dokumenttyp_code, COUNT(*) FROM core.v_dokument_zulassung GROUP BY dokumenttyp_code;  -- only PROTOKOLL/BESCHEID
REVERT;

EXECUTE AS USER = 'u_controlling';
    SELECT TOP 5 lanr, fachgruppe, praxis_name FROM mart.dim_arzt;   -- works
    SELECT TOP 5 arzt_name FROM mart.dim_arzt;                       -- error 230: column denied
REVERT;

-- Who has which permission? (catalog views)
SELECT pr.name AS principal, pe.permission_name, pe.state_desc, pe.class_desc,
       COALESCE(OBJECT_SCHEMA_NAME(pe.major_id) + '.' + OBJECT_NAME(pe.major_id), SCHEMA_NAME(pe.major_id)) AS securable
FROM sys.database_permissions AS pe
JOIN sys.database_principals AS pr ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name LIKE 'rl[_]%'
ORDER BY principal, securable;
------------------------------------------------------------------------------------------- */
