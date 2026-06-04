-- =============================================================================
-- Maximo PM Planning — UC SQL Function (Metric UDF) DDL
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} and {{catalog}}.{{metrics_schema}}.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS {{catalog}}.{{metrics_schema}}
COMMENT 'Trusted-asset SQL functions for Maximo PM planning metrics';


-- -----------------------------------------------------------------------------
-- pms_due_in_window — count of active PMs effectively due in a window
-- -----------------------------------------------------------------------------
-- Counts each PMSEQUENCE row separately (multi-frequency PMs expand).
-- Uses COALESCE(EXTDATE, NEXTDATE) for the effective due date.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.pms_due_in_window(
    site_id STRING COMMENT 'SITEID. NULL for all sites.',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of active PMs (with PMSEQUENCE expansion) effectively due in the window. Uses COALESCE(EXTDATE, NEXTDATE).'
RETURN (
    -- Single-cadence PMs (no PMSEQUENCE rows)
    SELECT COUNT(*) AS cnt FROM (
        SELECT pm.pmnum, pm.siteid
        FROM {{catalog}}.{{silver_schema}}.pm pm
        WHERE pm.__END_AT IS NULL
          AND pm.status = 'ACTIVE'
          AND COALESCE(pm.extdate, pm.nextdate) BETWEEN window_start AND window_end
          AND (site_id IS NULL OR pm.siteid = site_id)
          AND NOT EXISTS (
              SELECT 1 FROM {{catalog}}.{{silver_schema}}.pmsequence seq
              WHERE seq.pmnum = pm.pmnum AND seq.siteid = pm.siteid
          )

        UNION ALL

        -- Multi-cadence: each sequence counts once
        SELECT pm.pmnum, pm.siteid
        FROM {{catalog}}.{{silver_schema}}.pm pm
        JOIN {{catalog}}.{{silver_schema}}.pmsequence seq
            ON seq.pmnum = pm.pmnum AND seq.siteid = pm.siteid
        WHERE pm.__END_AT IS NULL
          AND pm.status = 'ACTIVE'
          AND COALESCE(pm.extdate, pm.nextdate) BETWEEN window_start AND window_end
          AND (site_id IS NULL OR pm.siteid = site_id)
    )
);


-- -----------------------------------------------------------------------------
-- pm_workload_hours — sum of JPLABOR hours for forecast PMs by craft
-- -----------------------------------------------------------------------------
-- Uses JPLABOR.LABORHRS via JOBPLAN reference. Filters by craft if provided.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.pm_workload_hours(
    site_id STRING COMMENT 'SITEID. NULL for all sites.',
    craft_filter STRING COMMENT 'Craft code (e.g. ELEC, MECH). NULL for all crafts.',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: total planned labor hours for active PMs effectively due in the window. Sums JPLABOR.LABORHRS through JOBPLAN reference.'
RETURN (
    SELECT SUM(jpl.laborhrs)
    FROM {{catalog}}.{{silver_schema}}.pm pm
    JOIN {{catalog}}.{{silver_schema}}.jplabor jpl
        ON jpl.jpnum = pm.jpnum AND jpl.__END_AT IS NULL
    WHERE pm.__END_AT IS NULL
      AND pm.status = 'ACTIVE'
      AND COALESCE(pm.extdate, pm.nextdate) BETWEEN window_start AND window_end
      AND (site_id IS NULL OR pm.siteid = site_id)
      AND (craft_filter IS NULL OR jpl.craft = craft_filter)
);


-- -----------------------------------------------------------------------------
-- pm_to_cm_ratio — count ratio of PM-generated WOs to corrective WOs
-- -----------------------------------------------------------------------------
-- Different from pm_vs_cm_cost_ratio (maintenance-cost skill) — that uses cost.
-- This counts WOs. Both have valid use cases (count for workload; cost for spend).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.pm_to_cm_ratio(
    site_id STRING COMMENT 'SITEID. NULL for all sites.',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: PM-generated WO count / non-PM (corrective) WO count for a window. Counts WOs (not cost). Uses WORKORDER.PMNUM IS NOT NULL.'
RETURN (
    WITH counts AS (
        SELECT
            SUM(CASE WHEN pmnum IS NOT NULL THEN 1 ELSE 0 END) AS pm_count,
            SUM(CASE WHEN pmnum IS NULL     THEN 1 ELSE 0 END) AS cm_count
        FROM {{catalog}}.{{silver_schema}}.workorder
        WHERE woclass = 'WORKORDER'
          AND status IN ('COMP', 'CLOSE')
          AND actfinish BETWEEN window_start AND window_end
          AND (site_id IS NULL OR siteid = site_id)
    )
    SELECT CASE WHEN cm_count > 0 THEN pm_count * 1.0 / cm_count ELSE NULL END
    FROM counts
);


-- -----------------------------------------------------------------------------
-- next_pm_due — earliest effective due date across all active PMs on an asset
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.next_pm_due(
    assetnum_param STRING,
    siteid_param STRING
)
RETURNS TIMESTAMP
COMMENT 'Trusted metric: earliest effective due date (COALESCE(EXTDATE, NEXTDATE)) across active PMs on an asset.'
RETURN (
    SELECT MIN(COALESCE(pm.extdate, pm.nextdate))
    FROM {{catalog}}.{{silver_schema}}.pm pm
    WHERE pm.__END_AT IS NULL
      AND pm.status = 'ACTIVE'
      AND pm.assetnum = assetnum_param
      AND pm.siteid = siteid_param
);


-- -----------------------------------------------------------------------------
-- meter_based_pm_forecast — forecast next due for a meter-based PM
-- -----------------------------------------------------------------------------
-- (Moved from maximo-reliability — forward-looking forecasting belongs here.)
-- Forecast date = LASTREADINGDATE + (FREQUENCY - LASTREADING) / AVERAGE.
-- NULL if AVERAGE is null/zero (new meter).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.meter_based_pm_forecast(
    pmnum_param STRING,
    siteid_param STRING
)
RETURNS TIMESTAMP
COMMENT 'Trusted metric: forecast next due date for a meter-based PM. Uses ASSETMETER.AVERAGE (per-day rate) + LASTREADING. NULL when AVERAGE is NULL/zero.'
RETURN (
    SELECT
        CASE
            WHEN am.average IS NULL OR am.average <= 0 THEN NULL
            WHEN pm.frequency - am.lastreading <= 0     THEN current_timestamp()
            ELSE am.lastreadingdate
                 + INTERVAL '1' DAY * ((pm.frequency - am.lastreading) / am.average)
        END
    FROM {{catalog}}.{{silver_schema}}.pm pm
    JOIN {{catalog}}.{{silver_schema}}.assetmeter am
        ON am.assetnum = pm.assetnum AND am.siteid = pm.siteid
       AND am.__END_AT IS NULL
       AND am.metername = pm.metername
    WHERE pm.__END_AT IS NULL
      AND pm.status = 'ACTIVE'
      AND pm.pmnum = pmnum_param
      AND pm.siteid = siteid_param
      AND pm.frequnit IN ('HOURS', 'MILES', 'READINGS')
);


-- =============================================================================
-- Grants (uncomment + substitute principal)
-- =============================================================================
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.pms_due_in_window         TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.pm_workload_hours         TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.pm_to_cm_ratio            TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.next_pm_due               TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.meter_based_pm_forecast   TO `{{principal}}`;
