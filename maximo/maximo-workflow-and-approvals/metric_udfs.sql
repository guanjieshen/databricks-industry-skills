-- ─────────────────────────────────────────────────────────────────────────────
-- Trusted Asset functions for Genie.
-- These are UC SQL functions: register them once (CREATE FUNCTION) so Genie
-- Spaces call them as certified, governed metrics rather than regenerating
-- ad-hoc SQL. Substitute :catalog.:silver_schema and :catalog.:metrics_schema.
-- See: https://docs.databricks.com/aws/en/genie/trusted-assets
-- ─────────────────────────────────────────────────────────────────────────────

-- =============================================================================
-- Maximo Workflow & Approvals — UC SQL Function (Metric UDF) DDL
-- Column notes: route disposition is in WFTRANSACTION (TRANSTYPE, a WFTRANSTYPE
-- synonym), NOT in a WFASSIGNMENT.RESULT/COMPLETED column. Pass the deployment's
-- positive-outcome synonyms into approval_pass_rate as an array. See gotchas.md.
-- =============================================================================


-- Ensure the metrics schema exists
CREATE SCHEMA IF NOT EXISTS :catalog.:metrics_schema
COMMENT 'Trusted-asset SQL functions for Maximo workflow & approval metrics';


-- -----------------------------------------------------------------------------
-- current_approval_age — hours a specific business record has been in workflow
-- -----------------------------------------------------------------------------
-- Use to answer "how long has WO-12345 been waiting for approval?"
-- Returns NULL if the record is not currently in workflow.
-- owner_id is the SURROGATE unique-ID column (e.g. WORKORDER.WORKORDERID), not WONUM.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.current_approval_age(
    owner_table STRING COMMENT 'Business-object table name, e.g. WORKORDER, PO, INVOICE, TICKET',
    owner_id BIGINT COMMENT 'Surrogate unique-ID column of the business record (e.g. WORKORDER.WORKORDERID; ticket family uses TICKETUID) — NOT the displayable key like WONUM'
)
RETURNS DOUBLE
COMMENT 'Trusted metric: hours since the active workflow on a business record started. NULL if no active workflow. (WAPPR status does not imply an active workflow — this keys on WFINSTANCE.ACTIVE=1.)'
RETURN (
    SELECT datediff(SECOND, MIN(wi.startdate), current_timestamp()) / 3600.0
    FROM :catalog.:silver_schema.wfinstance wi
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
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.mean_cycle_time(
    process_name STRING COMMENT 'WFINSTANCE.PROCESSNAME, e.g. WOAPPR, POAPPR, INVCAPPR. NULL for all.',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: mean cycle hours for closed workflows (active=0) of the given process in the window (WFINSTANCE.STARTDATE to last WFTRANSACTION). Datetimes are app-server-local.'
RETURN (
    WITH closed AS (
        SELECT
            wi.wfid,
            wi.startdate,
            MAX(wt.transdate) AS endtime
        FROM :catalog.:silver_schema.wfinstance wi
        JOIN :catalog.:silver_schema.wftransaction wt ON wt.wfid = wi.wfid
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
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.open_approvals_count(
    process_name STRING COMMENT 'WFINSTANCE.PROCESSNAME. NULL for all.',
    older_than_hours INT COMMENT 'Only count assignments whose STARTDATE is older than this. 0 for all.'
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of distinct workflows with an ACTIVE assignment for a process, optionally only those whose assignment entered the inbox more than N hours ago.'
RETURN (
    SELECT COUNT(DISTINCT wa.wfid)
    FROM :catalog.:silver_schema.wfassignment wa
    JOIN :catalog.:silver_schema.wfinstance wi ON wi.wfid = wa.wfid
    WHERE wa.assignstatus = 'ACTIVE'
      AND wi.active = 1
      AND (process_name IS NULL OR wi.processname = process_name)
      AND datediff(HOUR, wa.startdate, current_timestamp()) >= older_than_hours
);


-- -----------------------------------------------------------------------------
-- approval_pass_rate — % of closed workflows ending on a positive route
-- -----------------------------------------------------------------------------
-- Disposition is NOT on WFASSIGNMENT (no RESULT column by default) — it is the
-- terminating WFTRANSACTION.TRANSTYPE. TRANSTYPE is a synonym domain, so the
-- caller passes the deployment's positive-outcome synonyms (enumerate them from
-- SYNONYMDOMAIN WHERE DOMAINID='WFTRANSTYPE'; e.g. ARRAY('WFACCEPT')).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.approval_pass_rate(
    process_name STRING COMMENT 'WFINSTANCE.PROCESSNAME. NULL for all.',
    positive_transtypes ARRAY<STRING> COMMENT 'Deployment WFTRANSTYPE synonyms that mean a positive/approved outcome (resolve via SYNONYMDOMAIN WHERE DOMAINID=''WFTRANSTYPE''), e.g. ARRAY(''WFACCEPT'').',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: % of closed workflows whose terminating WFTRANSACTION.TRANSTYPE is in the supplied positive set, in the window. Disposition comes from WFTRANSACTION, not a WFASSIGNMENT.RESULT column.'
RETURN (
    WITH terminating AS (
        SELECT
            wi.wfid,
            wt.transtype,
            ROW_NUMBER() OVER (PARTITION BY wi.wfid ORDER BY wt.transdate DESC) AS rn
        FROM :catalog.:silver_schema.wfinstance wi
        JOIN :catalog.:silver_schema.wftransaction wt ON wt.wfid = wi.wfid
        WHERE wi.active = 0
          AND (process_name IS NULL OR wi.processname = process_name)
          AND wi.startdate BETWEEN window_start AND window_end
    )
    SELECT
        CASE WHEN COUNT(*) > 0
             THEN 100.0 * SUM(CASE WHEN array_contains(positive_transtypes, transtype) THEN 1 ELSE 0 END) / COUNT(*)
             ELSE NULL
        END
    FROM terminating
    WHERE rn = 1
);


-- =============================================================================
-- Grants (uncomment + substitute principal)
-- =============================================================================
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.current_approval_age TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.mean_cycle_time      TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.open_approvals_count TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.approval_pass_rate   TO `:principal`;
