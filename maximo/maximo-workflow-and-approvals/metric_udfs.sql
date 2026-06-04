-- ─────────────────────────────────────────────────────────────────────────────
-- Trusted Asset functions for Genie.
-- These are UC SQL functions: register them once (CREATE FUNCTION) so Genie
-- Spaces can call them as certified, governed metrics rather than regenerating
-- ad-hoc SQL. Substitute your catalog.schema before running.
-- See: https://docs.databricks.com/aws/en/genie/trusted-assets
-- ─────────────────────────────────────────────────────────────────────────────

-- =============================================================================
-- Maximo Workflow & Approvals — UC SQL Function (Metric UDF) DDL
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} and {{catalog}}.{{metrics_schema}}.
-- Once registered with EXECUTE granted, Genie treats these as Trusted assets.
-- =============================================================================


-- Ensure the metrics schema exists
CREATE SCHEMA IF NOT EXISTS {{catalog}}.{{metrics_schema}}
COMMENT 'Trusted-asset SQL functions for Maximo workflow & approval metrics';


-- -----------------------------------------------------------------------------
-- current_approval_age — hours a specific business record has been in workflow
-- -----------------------------------------------------------------------------
-- Use to answer "how long has WO-12345 been waiting for approval?"
-- Returns NULL if the record is not currently in workflow.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.current_approval_age(
    owner_table STRING COMMENT 'Business-object table name, e.g. WORKORDER, PO, INVOICE',
    owner_id BIGINT COMMENT 'Surrogate primary key of the business record (e.g. WORKORDER.WORKORDERID)'
)
RETURNS DOUBLE
COMMENT 'Trusted metric: hours since the active workflow on a business record started. NULL if no active workflow.'
RETURN (
    SELECT datediff(SECOND, MIN(wi.startdate), current_timestamp()) / 3600.0
    FROM {{catalog}}.{{silver_schema}}.wfinstance wi
    WHERE wi.ownertable = owner_table
      AND wi.ownerid = owner_id
      AND wi.active = 1
);


-- -----------------------------------------------------------------------------
-- mean_cycle_time — average end-to-end workflow cycle time for a process
-- -----------------------------------------------------------------------------
-- Average hours from workflow START to last transaction, for closed workflows
-- of the named process in the given window.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.mean_cycle_time(
    process_name STRING COMMENT 'WFINSTANCE.PROCESSNAME, e.g. WOAPPR, POAPPR, INVCAPPR. NULL for all.',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: mean cycle hours for closed workflows of the given process in the window (uses WFINSTANCE.STARTDATE to last WFTRANSACTION).'
RETURN (
    WITH closed AS (
        SELECT
            wi.wfid,
            wi.startdate,
            MAX(wt.transdate) AS endtime
        FROM {{catalog}}.{{silver_schema}}.wfinstance wi
        JOIN {{catalog}}.{{silver_schema}}.wftransaction wt ON wt.wfid = wi.wfid
        WHERE wi.active = 0
          AND (process_name IS NULL OR wi.processname = process_name)
          AND wi.startdate BETWEEN window_start AND window_end
        GROUP BY wi.wfid, wi.startdate
    )
    SELECT AVG(datediff(SECOND, startdate, endtime) / 3600.0)
    FROM closed
);


-- -----------------------------------------------------------------------------
-- open_approvals_count — count of currently-stuck approvals for a process
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.open_approvals_count(
    process_name STRING COMMENT 'WFINSTANCE.PROCESSNAME. NULL for all.',
    older_than_hours INT COMMENT 'Only count assignments older than this. 0 for all.'
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of ACTIVE assignments for a workflow process, optionally filtered to those older than N hours.'
RETURN (
    SELECT COUNT(DISTINCT wa.wfid)
    FROM {{catalog}}.{{silver_schema}}.wfassignment wa
    JOIN {{catalog}}.{{silver_schema}}.wfinstance wi ON wi.wfid = wa.wfid
    WHERE wa.assignstatus = 'ACTIVE'
      AND wi.active = 1
      AND (process_name IS NULL OR wi.processname = process_name)
      AND datediff(HOUR, wa.assigndate, current_timestamp()) >= older_than_hours
);


-- -----------------------------------------------------------------------------
-- approval_pass_rate — % of completed assignments with positive outcome
-- -----------------------------------------------------------------------------
-- Useful for "are our approvers rubber-stamping or actually reviewing?"
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.approval_pass_rate(
    process_name STRING COMMENT 'WFINSTANCE.PROCESSNAME. NULL for all.',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: % of completed approval assignments with RESULT=POSITIVE in the window.'
RETURN (
    WITH completed AS (
        SELECT wa.result
        FROM {{catalog}}.{{silver_schema}}.wfassignment wa
        JOIN {{catalog}}.{{silver_schema}}.wfinstance wi ON wi.wfid = wa.wfid
        WHERE wa.assignstatus = 'COMPLETE'
          AND wa.completedate BETWEEN window_start AND window_end
          AND (process_name IS NULL OR wi.processname = process_name)
    )
    SELECT
        CASE WHEN COUNT(*) > 0
             THEN 100.0 * SUM(CASE WHEN result = 'POSITIVE' THEN 1 ELSE 0 END) / COUNT(*)
             ELSE NULL
        END
    FROM completed
);


-- =============================================================================
-- Grants (uncomment + substitute principal)
-- =============================================================================
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.current_approval_age TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.mean_cycle_time      TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.open_approvals_count TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.approval_pass_rate   TO `{{principal}}`;
