-- ─────────────────────────────────────────────────────────────────────────────
-- Trusted Asset functions for Genie.
-- These are UC SQL functions: register them once (CREATE FUNCTION) so Genie
-- Spaces can call them as certified, governed metrics rather than regenerating
-- ad-hoc SQL. Substitute your catalog.schema before running.
-- See: https://docs.databricks.com/aws/en/genie/trusted-assets
-- ─────────────────────────────────────────────────────────────────────────────

-- =============================================================================
-- Maximo Work Management — UC SQL Function (Metric UDF) DDL
-- =============================================================================
-- Substitute {{maximo_catalog}}.{{maximo_schema}} with the customer's silver
-- catalog/schema, and {{metrics_schema}} with a Gold-layer schema for metric
-- functions (e.g. eam.maximo_metrics).
--
-- Once registered with EXECUTE granted, Genie (Code or Space) treats results
-- from these functions as "Trusted assets" — they earn a badge and are
-- preferred over ad-hoc SQL for the same metric.
--
-- Pattern: each function is a single SQL statement (no procedural logic) so
-- it can be inlined into Genie's generated queries.
-- =============================================================================

-- Ensure the metrics schema exists
CREATE SCHEMA IF NOT EXISTS {{maximo_catalog}}.{{metrics_schema}}
COMMENT 'Trusted-asset SQL functions for Maximo work-management metrics';


-- -----------------------------------------------------------------------------
-- open_wo_count
-- -----------------------------------------------------------------------------
-- Trigger: "how many open work orders at <site>"
-- Returns the count of open (non-COMP, non-CLOSE, non-CAN) parent WOs at a
-- site as of a point in time.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{maximo_catalog}}.{{metrics_schema}}.open_wo_count(
    site STRING COMMENT 'SITEID',
    as_of TIMESTAMP COMMENT 'Point in time (use current_timestamp() for "now")'
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of open parent work orders at a site as of a given time. Excludes child tasks (ISTASK=1) and non-WO classes.'
RETURN (
    SELECT COUNT(*)
    FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER w
    WHERE w.siteid = site
      AND w.woclass = 'WORKORDER'
      AND w.istask = 0
      AND w.reportdate <= as_of
      AND w.status NOT IN ('COMP', 'CLOSE', 'CAN')
);


-- -----------------------------------------------------------------------------
-- wo_aging_bucket
-- -----------------------------------------------------------------------------
-- Trigger: "what aging bucket does this WO fall into"
-- Standard 30/60/90 day buckets from REPORTDATE.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{maximo_catalog}}.{{metrics_schema}}.wo_aging_bucket(
    reportdate TIMESTAMP COMMENT 'WORKORDER.REPORTDATE'
)
RETURNS STRING
COMMENT 'Trusted metric: aging bucket for an open WO based on REPORTDATE. Returns one of 0-30 days, 31-60 days, 61-90 days, 90+ days.'
RETURN (
    SELECT CASE
        WHEN datediff(DAY, reportdate, current_date()) <= 30 THEN '0-30 days'
        WHEN datediff(DAY, reportdate, current_date()) <= 60 THEN '31-60 days'
        WHEN datediff(DAY, reportdate, current_date()) <= 90 THEN '61-90 days'
        ELSE '90+ days'
    END
);


-- -----------------------------------------------------------------------------
-- mean_time_to_complete
-- -----------------------------------------------------------------------------
-- Trigger: "average days to complete WOs of type X"
-- Mean elapsed days from REPORTDATE to ACTFINISH for completed WOs in a
-- window, filterable by work type.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{maximo_catalog}}.{{metrics_schema}}.mean_time_to_complete(
    worktype STRING COMMENT 'WORKORDER.WORKTYPE — e.g. CM, PM, EM. Pass NULL for all.',
    window_days INT COMMENT 'Look-back window for completed WOs (e.g. 90)'
)
RETURNS DOUBLE
COMMENT 'Trusted metric: mean days from REPORTDATE to ACTFINISH for completed WOs in the given work type and window.'
RETURN (
    SELECT AVG(datediff(DAY, w.reportdate, w.actfinish))
    FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER w
    WHERE w.woclass = 'WORKORDER'
      AND w.istask = 0
      AND w.status IN ('COMP', 'CLOSE')
      AND w.actfinish IS NOT NULL
      AND w.actfinish >= current_date() - make_interval(0, 0, 0, window_days, 0, 0, 0)
      AND (worktype IS NULL OR w.worktype = worktype)
);


-- -----------------------------------------------------------------------------
-- backlog_age_days
-- -----------------------------------------------------------------------------
-- Trigger: "how old is this WO"
-- Days between REPORTDATE and the as-of time. Negative if reportdate is in the future.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{maximo_catalog}}.{{metrics_schema}}.backlog_age_days(
    reportdate TIMESTAMP COMMENT 'WORKORDER.REPORTDATE',
    as_of TIMESTAMP COMMENT 'As-of time, typically current_timestamp()'
)
RETURNS INT
COMMENT 'Trusted metric: integer days between WO REPORTDATE and the as-of timestamp.'
RETURN datediff(DAY, reportdate, as_of);


-- -----------------------------------------------------------------------------
-- time_in_current_status
-- -----------------------------------------------------------------------------
-- Trigger: "how long has this WO been in current status"
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{maximo_catalog}}.{{metrics_schema}}.time_in_current_status(
    wonum STRING,
    siteid STRING
)
RETURNS DOUBLE
COMMENT 'Trusted metric: hours since the most recent WOSTATUS transition for a given WO.'
RETURN (
    SELECT datediff(SECOND, MAX(s.changedate), current_timestamp()) / 3600.0
    FROM {{maximo_catalog}}.{{maximo_schema}}.WOSTATUS s
    WHERE s.wonum = wonum AND s.siteid = siteid
);


-- =============================================================================
-- Grants — required for Genie to register these as Trusted assets.
-- Substitute {{principal}} (a group preferred, e.g. `genie-users`).
-- =============================================================================

-- GRANT USAGE ON SCHEMA {{maximo_catalog}}.{{metrics_schema}} TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{maximo_catalog}}.{{metrics_schema}}.open_wo_count            TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{maximo_catalog}}.{{metrics_schema}}.wo_aging_bucket          TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{maximo_catalog}}.{{metrics_schema}}.mean_time_to_complete    TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{maximo_catalog}}.{{metrics_schema}}.backlog_age_days         TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{maximo_catalog}}.{{metrics_schema}}.time_in_current_status   TO `{{principal}}`;
