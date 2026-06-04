-- =============================================================================
-- Maximo PM Planning — Gold Views
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} and {{catalog}}.{{gold_schema}}.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_pm_forecast
-- One row per (PM, sequence). Forecasts effective next due date with bucket.
-- Pre-joins JOBPLAN and aggregates JPLABOR / JPMATERIAL for planned cost.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_pm_forecast
COMMENT 'Per-(PM, sequence) forecast with effective due date and due-bucket. Includes planned labor hours + material cost from referenced JOBPLAN.'
AS
WITH pm_expanded AS (
    -- PMs without sequences (single cadence)
    SELECT
        pm.pmnum, pm.siteid,
        NULL                                                AS sequence_num,
        pm.jpnum                                            AS effective_jpnum,
        pm.orgid,
        pm.assetnum,
        pm.location,
        pm.frequency, pm.frequnit,
        pm.usetargetdate,
        pm.alertlead,
        COALESCE(pm.extdate, pm.nextdate)                   AS effective_due_date
    FROM {{catalog}}.{{silver_schema}}.pm pm
    WHERE pm.__END_AT IS NULL
      AND pm.status = 'ACTIVE'
      AND NOT EXISTS (
          SELECT 1 FROM {{catalog}}.{{silver_schema}}.pmsequence seq
          WHERE seq.pmnum = pm.pmnum AND seq.siteid = pm.siteid
      )

    UNION ALL

    -- PMs with sequences (each sequence is its own forecast row)
    SELECT
        pm.pmnum, pm.siteid,
        seq.sequence                                        AS sequence_num,
        seq.jpnum                                           AS effective_jpnum,
        pm.orgid,
        pm.assetnum,
        pm.location,
        seq.frequency, seq.frequnit,
        pm.usetargetdate,
        pm.alertlead,
        COALESCE(pm.extdate, pm.nextdate)                   AS effective_due_date
    FROM {{catalog}}.{{silver_schema}}.pm pm
    JOIN {{catalog}}.{{silver_schema}}.pmsequence seq
        ON seq.pmnum = pm.pmnum AND seq.siteid = pm.siteid
    WHERE pm.__END_AT IS NULL
      AND pm.status = 'ACTIVE'
),
labor_rollup AS (
    SELECT jpnum, orgid, SUM(laborhrs) AS planned_labor_hours, SUM(linecost) AS planned_labor_cost
    FROM {{catalog}}.{{silver_schema}}.jplabor
    WHERE __END_AT IS NULL
    GROUP BY jpnum, orgid
),
material_rollup AS (
    SELECT jpnum, orgid, SUM(linecost) AS planned_material_cost
    FROM {{catalog}}.{{silver_schema}}.jpmaterial
    WHERE __END_AT IS NULL
    GROUP BY jpnum, orgid
)
SELECT
    e.pmnum, e.siteid, e.sequence_num,
    e.effective_jpnum                                       AS jpnum,
    e.assetnum, e.location,
    a.description                                           AS asset_description,
    a.criticality                                           AS asset_criticality,
    e.frequency, e.frequnit,
    e.effective_due_date,
    e.alertlead,
    CASE
        WHEN e.effective_due_date <  current_date()                              THEN 'OVERDUE'
        WHEN e.effective_due_date <= current_date() + INTERVAL 30 DAYS           THEN 'DUE_30D'
        WHEN e.effective_due_date <= current_date() + INTERVAL 60 DAYS           THEN 'DUE_60D'
        WHEN e.effective_due_date <= current_date() + INTERVAL 90 DAYS           THEN 'DUE_90D'
        ELSE                                                                          'FUTURE'
    END                                                     AS due_bucket,
    COALESCE(lr.planned_labor_hours, 0)                     AS planned_labor_hours,
    COALESCE(lr.planned_labor_cost, 0)                      AS planned_labor_cost,
    COALESCE(mr.planned_material_cost, 0)                   AS planned_material_cost
FROM pm_expanded e
LEFT JOIN {{catalog}}.{{silver_schema}}.asset a
    ON a.assetnum = e.assetnum AND a.siteid = e.siteid AND a.__END_AT IS NULL
LEFT JOIN labor_rollup lr
    ON lr.jpnum = e.effective_jpnum AND lr.orgid = e.orgid
LEFT JOIN material_rollup mr
    ON mr.jpnum = e.effective_jpnum AND mr.orgid = e.orgid;


-- -----------------------------------------------------------------------------
-- v_pm_workload_by_craft
-- Per-(site, craft, week) forecast workload. One row per (site, craft,
-- week_starting). Sums planned labor hours from JPLABOR across forecast PMs
-- whose effective due date falls in each week.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_pm_workload_by_craft
COMMENT 'Forecast labor demand by craft × week × site. Aggregates JPLABOR across PMs whose effective due date falls in each week.'
AS
SELECT
    f.siteid,
    jpl.craft,
    date_trunc('WEEK', f.effective_due_date)                AS week_starting,
    SUM(jpl.laborhrs)                                        AS planned_labor_hours,
    COUNT(DISTINCT f.pmnum)                                  AS pm_count
FROM {{catalog}}.{{gold_schema}}.v_pm_forecast f
JOIN {{catalog}}.{{silver_schema}}.jplabor jpl
    ON jpl.jpnum = f.jpnum AND jpl.__END_AT IS NULL
WHERE f.effective_due_date >= current_date()
  AND f.effective_due_date <= current_date() + INTERVAL 365 DAYS
GROUP BY f.siteid, jpl.craft, date_trunc('WEEK', f.effective_due_date);


-- -----------------------------------------------------------------------------
-- v_jobplan_assets
-- Per-JOBPLAN list of PMs and assets that reference it. Use for impact analysis
-- ("if I change JP-PUMP-3MO, what's affected?").
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_jobplan_assets
COMMENT 'Per-JOBPLAN list of referencing PMs/assets/sites. Use for change-impact analysis when modifying a job plan template.'
AS
SELECT
    jp.jpnum, jp.orgid,
    jp.description                                           AS jobplan_description,
    jp.status                                                AS jobplan_status,
    COUNT(DISTINCT pm.pmnum)                                 AS pm_count,
    COUNT(DISTINCT pm.assetnum)                              AS distinct_assets,
    array_agg(DISTINCT pm.siteid)                            AS sites_using,
    COUNT(DISTINCT seq.pmnum)                                AS pmsequence_count
FROM {{catalog}}.{{silver_schema}}.jobplan jp
LEFT JOIN {{catalog}}.{{silver_schema}}.pm pm
    ON pm.jpnum = jp.jpnum AND pm.orgid = jp.orgid
   AND pm.__END_AT IS NULL AND pm.status = 'ACTIVE'
LEFT JOIN {{catalog}}.{{silver_schema}}.pmsequence seq
    ON seq.jpnum = jp.jpnum
WHERE jp.__END_AT IS NULL
GROUP BY jp.jpnum, jp.orgid, jp.description, jp.status;


-- -----------------------------------------------------------------------------
-- v_pm_route_clusters
-- Forecast PMs clustered by LOCATIONS parent for route grouping.
-- One row per (location_parent, forecast_week, pmnum).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_pm_route_clusters
COMMENT 'Forecast PMs grouped by parent location for route optimization. One row per (location_parent, forecast_week, pmnum).'
AS
SELECT
    f.siteid,
    l.parent                                                 AS location_parent,
    date_trunc('WEEK', f.effective_due_date)                AS forecast_week,
    f.pmnum, f.sequence_num,
    f.assetnum, f.location,
    f.jpnum,
    f.planned_labor_hours,
    f.planned_material_cost
FROM {{catalog}}.{{gold_schema}}.v_pm_forecast f
LEFT JOIN {{catalog}}.{{silver_schema}}.locations l
    ON l.location = f.location AND l.siteid = f.siteid AND l.__END_AT IS NULL
WHERE f.effective_due_date >= current_date()
  AND f.effective_due_date <= current_date() + INTERVAL 90 DAYS;
