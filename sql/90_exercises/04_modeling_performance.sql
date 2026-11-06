/* =============================================================================
   EXERCISES - Level 4: Modelling and performance
   -----------------------------------------------------------------------------
   SQL concepts : extending a normalised model, key design, SCD type 2 (classic
                  incremental algorithm), columnstore vs. rowstore, incremental loads,
                  transactions, Row-Level Security
   Main objects : core.praxis, core.leistung, core.arzt, mart.dim_praxis, mart.fact_leistung,
                  mart.fact_abrechnungsfall, mart.dim_region, sql/60_mart_load/602_load_facts.sql
   Solutions    : sql/91_solutions/04_modeling_performance.sql  (try first!)

   These are design tasks: write down your design (tables, keys, relationships, what
   changes in queries) BEFORE you write SQL. When you test DDL, protect the training
   database:
       BEGIN TRANSACTION;  ... your CREATE / ALTER / INSERT ...;  ROLLBACK TRANSACTION;
   or work on #temp tables, or DROP what you created. Worst case: tools/run_all.ps1
   rebuilds everything.

   German terms used in this file:
     Betriebsstaette (BSNR)       practice site; Hauptbetriebsstaette = main site
     Nebenbetriebsstaette (NBSNR) additional site (branch) of the same practice
     LANR-Stamm                   first 7 digits of the LANR (id + check digit), lifelong;
                                  digits 8-9 = Fachgruppe
     Kooperationsform             EP (Einzelpraxis), BAG (joint practice), MVZ
     Bezirksstelle                regional office of a KV
   ============================================================================= */
USE KVSim;
GO

/* -----------------------------------------------------------------------------
   4.1  Nebenbetriebsstaetten
   Scenario : Many practices run a branch in a neighbouring village. The Abrechnung needs
              to know WHERE a service was performed; the Bedarfsplanung keeps counting
              the doctor at the main site.
   Task     : Design the extension: new table(s), keys, constraints, and how core.leistung
              records the site. Write the DDL, insert one test branch, move two services
              there and write a query "services per site of a practice". Roll back.
   Questions: Why is the new foreign key in core.leistung nullable? What changes in the mart?
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   4.2  Doctors with two Fachgruppen
   Scenario : A doctor works as Hausarzt AND as Fachinternist. In reality she has two
              LANRs with the same first 7 digits (01 and 23 at the end). Our model has one
              LANR and one Fachgruppe per person (see ck_arzt_lanr_fachgruppe).
   Task     : Propose a redesign (person vs. LANR), show how today's data would be
              migrated, and test it with one doctor who gets a second LANR. Which tables
              should reference the person, which the LANR?
   Check    : is the 7-digit stem unique in today's data?
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   4.3  Classic SCD type 2 for dim_praxis
   Scenario : mart.dim_praxis is type 1: when an Einzelpraxis becomes a BAG, the old value
              is overwritten and 2025 reports suddenly show the practice as BAG all year.
   Task     : On #temp copies (not on the real dimension!) implement the classic SCD2
              algorithm for the tracked attributes praxis_name and kooperationsform_code:
                load 1: insert all practices as version 1 (valid from 2025-01-01)
                change: one Einzelpraxis becomes a BAG in the source copy
                load 2 (2025-10-01): 1. close the current version of changed members,
                                     2. insert a new current version.
              Show the two versions of the changed practice. Run load 2 again - what happens?
   Hints    : NULL-safe change detection: EXISTS (SELECT new values EXCEPT SELECT old values)
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   4.4  Columnstore vs. rowstore
   Scenario : The real KV has millions of billing lines. Would a columnstore index help
              the fact tables?
   Task     : Copy mart.fact_leistung 10 times into a rowstore table (clustered index) and
              into a clustered columnstore table. Compare size (sp_spaceused) and the
              logical reads of an aggregation per quarter and Fachgruppe. Drop both copies.
   Questions: Which queries are faster on columnstore, which slower? Where in this
              project would you use it?
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   4.5  Incremental fact load for one quarter
   Scenario : A corrected billing delivery for 2025Q2 arrives. Rebuilding all facts is
              fine today, but not with ten years of data.
   Task     : Write a procedure that replaces only one quarter in mart.fact_leistung
              (DELETE + INSERT in one transaction). Base it on mart.usp_load_facts
              (sql/60_mart_load/602_load_facts.sql). Test it inside an outer transaction and
              roll back. Check that the row count of the quarter is unchanged.
   Questions: Why one transaction? What must be true about the dimensions beforehand?
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
   4.6  Row-Level Security for a Bezirksstelle
   Scenario : Staff of the Bezirksstelle St. Wendel may only see billing cases of practices
              in their Kreis - in the same table that the head office uses unfiltered.
   Task     : In a schema "uebung": a mapping table user -> Kreis, an inline predicate
              function WITH SCHEMABINDING, and a SECURITY POLICY with a FILTER PREDICATE on
              mart.fact_abrechnungsfall. Create a test user WITHOUT LOGIN, grant SELECT,
              compare COUNT(*) as dbo and as the test user (EXECUTE AS USER / REVERT).
              Drop everything again.
   Questions: What about the other tables containing the same data?
   Expected : dbo sees 11,994 cases, the Bezirksstelle user several hundred
   ----------------------------------------------------------------------------- */



