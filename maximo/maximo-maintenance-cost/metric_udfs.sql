-- =============================================================================
-- Maximo Maintenance Cost — UC SQL Function (Metric UDF) DDL
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} and {{catalog}}.{{metrics_schema}}.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS {{catalog}}.{{metrics_schema}}
COMMENT 'Trusted-asset SQL functions for Maximo maintenance cost metrics';


-- -----------------------------------------------------------------------------
-- asset_maintenance_cost — total cost (labor + material) for an asset in a window
-- -----------------------------------------------------------------------------
-- Uses LABTRANS + MATUSETRANS (transaction-date attribution).
-- Excludes WOs without ASSETNUM (location-only work).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.asset_maintenance_cost(
    assetnum_param STRING,
    siteid_param STRING,
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: total maintenance cost (labor + material) for an asset in a window. Transaction-date attribution.'
RETURN (
    WITH labor AS (
        SELECT SUM(lt.linecost) AS cost
        FROM {{catalog}}.{{silver_schema}}.labtrans lt
        JOIN {{catalog}}.{{silver_schema}}.workorder w
            ON w.wonum = lt.wonum AND w.siteid = lt.siteid
        WHERE w.assetnum = assetnum_param
          AND w.siteid = siteid_param
          AND lt.transtype = 'WORK'
          AND lt.startdate BETWEEN window_start AND window_end
    ),
    materials AS (
        SELECT
            SUM(CASE WHEN mt.issuetype = 'ISSUE'  THEN mt.linecost ELSE 0 END)
          - SUM(CASE WHEN mt.issuetype = 'RETURN' THEN mt.linecost ELSE 0 END) AS cost
        FROM {{catalog}}.{{silver_schema}}.matusetrans mt
        JOIN {{catalog}}.{{silver_schema}}.workorder w
            ON w.wonum = mt.wonum AND w.siteid = mt.siteid
        WHERE w.assetnum = assetnum_param
          AND w.siteid = siteid_param
          AND mt.issuetype IN ('ISSUE', 'RETURN')
          AND mt.transdate BETWEEN window_start AND window_end
    )
    SELECT COALESCE(l.cost, 0) + COALESCE(m.cost, 0)
    FROM labor l, materials m
);


-- -----------------------------------------------------------------------------
-- wo_cost_variance_pct — variance % for a completed WO
-- -----------------------------------------------------------------------------
-- ((actual - estimate) / estimate) × 100. NULL if estimate is zero.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.wo_cost_variance_pct(
    wonum_param STRING,
    siteid_param STRING
)
RETURNS DOUBLE
COMMENT 'Trusted metric: cost variance % ((actual - estimate) / estimate × 100) for a WO. NULL if estimate is zero.'
RETURN (
    SELECT
        CASE
            WHEN (COALESCE(w.estlabcost, 0) + COALESCE(w.estmatcost, 0)) > 0
            THEN 100.0 *
                ((COALESCE(w.actlabcost, 0) + COALESCE(w.actmatcost, 0))
                 - (COALESCE(w.estlabcost, 0) + COALESCE(w.estmatcost, 0)))
                / (COALESCE(w.estlabcost, 0) + COALESCE(w.estmatcost, 0))
            ELSE NULL
        END
    FROM {{catalog}}.{{silver_schema}}.workorder w
    WHERE w.wonum = wonum_param AND w.siteid = siteid_param
);


-- -----------------------------------------------------------------------------
-- pm_vs_cm_cost_ratio — PM-generated cost / corrective cost
-- -----------------------------------------------------------------------------
-- Uses PMNUM IS NOT NULL for PM-generated. For "corrective" (denominator),
-- defaults to all non-PM WORKORDER-class WOs.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.pm_vs_cm_cost_ratio(
    site_id STRING COMMENT 'SITEID. NULL for all sites.',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: PM-generated cost / non-PM corrective cost ratio. Uses WORKORDER.PMNUM IS NOT NULL for PM source.'
RETURN (
    WITH pm_cost AS (
        SELECT SUM(COALESCE(actlabcost, 0) + COALESCE(actmatcost, 0)) AS cost
        FROM {{catalog}}.{{silver_schema}}.workorder
        WHERE woclass = 'WORKORDER'
          AND pmnum IS NOT NULL
          AND status IN ('COMP', 'CLOSE')
          AND actfinish BETWEEN window_start AND window_end
          AND (site_id IS NULL OR siteid = site_id)
    ),
    cm_cost AS (
        SELECT SUM(COALESCE(actlabcost, 0) + COALESCE(actmatcost, 0)) AS cost
        FROM {{catalog}}.{{silver_schema}}.workorder
        WHERE woclass = 'WORKORDER'
          AND pmnum IS NULL
          AND status IN ('COMP', 'CLOSE')
          AND actfinish BETWEEN window_start AND window_end
          AND (site_id IS NULL OR siteid = site_id)
    )
    SELECT
        CASE WHEN COALESCE(c.cost, 0) > 0
             THEN COALESCE(p.cost, 0) / c.cost
             ELSE NULL
        END
    FROM pm_cost p, cm_cost c
);


-- -----------------------------------------------------------------------------
-- cost_per_operating_hour — total cost ÷ runtime hours
-- -----------------------------------------------------------------------------
-- Requires a runtime meter on the asset. Sums METERREADING deltas in the window
-- to approximate runtime hours, then divides asset maintenance cost.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.cost_per_operating_hour(
    assetnum_param STRING,
    siteid_param STRING,
    meter_name STRING COMMENT 'ASSETMETER.METERNAME for the runtime meter',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: maintenance cost divided by operating hours in the window. Operating hours from METERREADING deltas on the named runtime meter.'
RETURN (
    WITH runtime AS (
        SELECT
            MAX(reading) - MIN(reading) AS hours
        FROM {{catalog}}.{{silver_schema}}.meterreading
        WHERE assetnum = assetnum_param
          AND siteid = siteid_param
          AND metername = meter_name
          AND readingdate BETWEEN window_start AND window_end
    ),
    cost AS (
        SELECT {{catalog}}.{{metrics_schema}}.asset_maintenance_cost(
            assetnum_param, siteid_param, window_start, window_end
        ) AS total_cost
    )
    SELECT
        CASE WHEN r.hours > 0 THEN c.total_cost / r.hours ELSE NULL END
    FROM runtime r, cost c
);


-- -----------------------------------------------------------------------------
-- contractor_spend — spend through a specific vendor
-- -----------------------------------------------------------------------------
-- Sums LABTRANS line cost where LABORCODE references the named vendor.
-- Customer convention varies — adjust the join if your customer marks
-- contractors differently.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.contractor_spend(
    vendor_company STRING COMMENT 'COMPANIES.COMPANY identifier',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: labor spend through a specific contractor vendor in the window. Joins LABTRANS via LABOR.VENDOR.'
RETURN (
    SELECT SUM(lt.linecost)
    FROM {{catalog}}.{{silver_schema}}.labtrans lt
    JOIN {{catalog}}.{{silver_schema}}.labor l
        ON l.laborcode = lt.laborcode
       AND l.__END_AT IS NULL
    WHERE l.vendor = vendor_company
      AND lt.startdate BETWEEN window_start AND window_end
);


-- =============================================================================
-- Grants (uncomment + substitute principal)
-- =============================================================================
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.asset_maintenance_cost  TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.wo_cost_variance_pct    TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.pm_vs_cm_cost_ratio     TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.cost_per_operating_hour TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.contractor_spend        TO `{{principal}}`;
