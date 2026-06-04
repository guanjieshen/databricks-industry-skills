-- =============================================================================
-- Maximo Reliability — UC SQL Function (Metric UDF) DDL
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} (Maximo Silver — e.g. eam.maximo_silver)
-- and {{catalog}}.{{metrics_schema}} (Gold-layer schema for metric functions —
-- e.g. eam.maximo_metrics) before running.
--
-- Once registered with EXECUTE granted, these earn the "Trusted asset" badge
-- in Genie and are preferred over ad-hoc SQL for the same metric.
--
-- Formula references match IBM's published O&G definitions:
--   https://www.ibm.com/support/pages/mttr-and-mtbf-fields-explained-maximo-oil-gas-asset-oil-application
-- =============================================================================


-- Ensure the metrics schema exists
CREATE SCHEMA IF NOT EXISTS {{catalog}}.{{metrics_schema}}
COMMENT 'Trusted-asset SQL functions for Maximo reliability metrics';


-- -----------------------------------------------------------------------------
-- mtbf — Mean Time Between Failures
-- -----------------------------------------------------------------------------
-- IBM O&G formula: MTBF = (operating time in period) / (number of failures in period)
-- Operating time is approximated as the time span from window_start to window_end.
-- For higher fidelity, customers can register a variant that subtracts downtime.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.mtbf(
    asset_class_id BIGINT COMMENT 'CLASSSTRUCTUREID — the asset class. Pass NULL for all classes.',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: Mean Time Between Failures in HOURS for an asset class in a window. Matches IBM O&G UI formula.'
RETURN (
    WITH failures AS (
        SELECT COUNT(*) AS failure_count
        FROM {{catalog}}.{{silver_schema}}.failurereport fr
        JOIN {{catalog}}.{{silver_schema}}.workorder w
            ON w.wonum = fr.wonum AND w.siteid = fr.siteid
        JOIN {{catalog}}.{{silver_schema}}.asset a
            ON a.assetnum = w.assetnum AND a.siteid = w.siteid AND a.__END_AT IS NULL
        WHERE COALESCE(w.actstart, w.reportdate) BETWEEN window_start AND window_end
          AND w.status IN ('COMP', 'CLOSE')
          AND (asset_class_id IS NULL OR a.classstructureid = asset_class_id)
    ),
    operating_hours AS (
        SELECT (CAST(window_end AS DOUBLE) - CAST(window_start AS DOUBLE)) / 3600 AS hours
    )
    SELECT
        CASE WHEN f.failure_count > 0
             THEN o.hours / f.failure_count
             ELSE NULL
        END
    FROM failures f, operating_hours o
);


-- -----------------------------------------------------------------------------
-- mttr — Mean Time To Repair
-- -----------------------------------------------------------------------------
-- IBM O&G formula: MTTR = SUM(repair durations) / number of failures
-- Repair duration approximated as ACTFINISH - ACTSTART.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.mttr(
    asset_class_id BIGINT COMMENT 'CLASSSTRUCTUREID — the asset class. Pass NULL for all classes.',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: Mean Time To Repair in HOURS for an asset class in a window. Matches IBM O&G UI formula.'
RETURN (
    SELECT AVG(
        (CAST(w.actfinish AS DOUBLE) - CAST(w.actstart AS DOUBLE)) / 3600
    )
    FROM {{catalog}}.{{silver_schema}}.failurereport fr
    JOIN {{catalog}}.{{silver_schema}}.workorder w
        ON w.wonum = fr.wonum AND w.siteid = fr.siteid
    JOIN {{catalog}}.{{silver_schema}}.asset a
        ON a.assetnum = w.assetnum AND a.siteid = w.siteid AND a.__END_AT IS NULL
    WHERE w.actstart IS NOT NULL AND w.actfinish IS NOT NULL
      AND COALESCE(w.actstart, w.reportdate) BETWEEN window_start AND window_end
      AND w.status IN ('COMP', 'CLOSE')
      AND (asset_class_id IS NULL OR a.classstructureid = asset_class_id)
);


-- -----------------------------------------------------------------------------
-- pm_compliance — Preventive Maintenance Compliance
-- -----------------------------------------------------------------------------
-- Default: SMRP standard. PMs completed within 10% tolerance of NEXTDATE divided
-- by PMs scheduled (NEXTDATE within window).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.pm_compliance(
    site_id STRING COMMENT 'SITEID. Pass NULL for all sites.',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: PM compliance % using SMRP standard (10% tolerance). Window applies to NEXTDATE.'
RETURN (
    WITH scheduled AS (
        SELECT pm.pmnum, pm.siteid, pm.nextdate,
            datediff(SECOND, pm.nextdate,
                pm.nextdate + (pm.frequency * 0.1 * INTERVAL 1 DAY)
            ) AS tolerance_seconds
        FROM {{catalog}}.{{silver_schema}}.pm pm
        WHERE pm.__END_AT IS NULL
          AND (site_id IS NULL OR pm.siteid = site_id)
          AND pm.nextdate BETWEEN window_start AND window_end
    ),
    completions AS (
        SELECT s.pmnum, s.siteid, MIN(w.actfinish) AS first_completion
        FROM scheduled s
        LEFT JOIN {{catalog}}.{{silver_schema}}.workorder w
            ON w.pmnum = s.pmnum AND w.siteid = s.siteid
           AND w.status IN ('COMP', 'CLOSE')
           AND w.actfinish IS NOT NULL
           AND w.actfinish <= s.nextdate + INTERVAL 30 DAY
        GROUP BY s.pmnum, s.siteid
    ),
    metrics AS (
        SELECT
            COUNT(*) AS scheduled_count,
            COUNT(c.first_completion) AS completed_count
        FROM completions c
    )
    SELECT
        CASE WHEN scheduled_count > 0
             THEN 100.0 * completed_count / scheduled_count
             ELSE NULL
        END
    FROM metrics
);


-- -----------------------------------------------------------------------------
-- time_since_last_failure — for a specific asset
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.time_since_last_failure(
    assetnum_param STRING,
    siteid_param STRING
)
RETURNS DOUBLE
COMMENT 'Trusted metric: hours since the most recent recorded failure on an asset.'
RETURN (
    SELECT datediff(SECOND, MAX(COALESCE(w.actstart, w.reportdate)), current_timestamp()) / 3600.0
    FROM {{catalog}}.{{silver_schema}}.failurereport fr
    JOIN {{catalog}}.{{silver_schema}}.workorder w
        ON w.wonum = fr.wonum AND w.siteid = fr.siteid
    WHERE w.assetnum = assetnum_param
      AND w.siteid = siteid_param
      AND w.status IN ('COMP', 'CLOSE')
);


-- -----------------------------------------------------------------------------
-- time_since_last_pm — for a specific asset
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.time_since_last_pm(
    assetnum_param STRING,
    siteid_param STRING
)
RETURNS DOUBLE
COMMENT 'Trusted metric: hours since the most recent completed PM-generated WO on an asset.'
RETURN (
    SELECT datediff(SECOND, MAX(w.actfinish), current_timestamp()) / 3600.0
    FROM {{catalog}}.{{silver_schema}}.workorder w
    WHERE w.assetnum = assetnum_param
      AND w.siteid = siteid_param
      AND w.pmnum IS NOT NULL
      AND w.status IN ('COMP', 'CLOSE')
);


-- =============================================================================
-- Grants — required for Genie to register these as Trusted assets.
-- Substitute {{principal}} (a group preferred, e.g. `genie-users`).
-- =============================================================================

-- GRANT USAGE ON SCHEMA {{catalog}}.{{metrics_schema}} TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.mtbf                       TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.mttr                       TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.pm_compliance              TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.time_since_last_failure    TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.time_since_last_pm         TO `{{principal}}`;
