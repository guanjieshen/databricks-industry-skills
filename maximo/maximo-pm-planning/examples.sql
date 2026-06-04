-- =============================================================================
-- Maximo PM Planning — Gold-Standard Query Examples
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}}, {{catalog}}.{{gold_schema}},
-- {{catalog}}.{{metrics_schema}} before running.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. PMs forecast due in next 30 / 60 / 90 days, by site
-- -----------------------------------------------------------------------------
-- Trigger: "PMs due", "upcoming PMs", "forecast PMs"
SELECT
    siteid,
    due_bucket,
    COUNT(*)                                       AS pm_count
FROM {{catalog}}.{{gold_schema}}.v_pm_forecast
WHERE due_bucket IN ('OVERDUE', 'DUE_30D', 'DUE_60D', 'DUE_90D')
GROUP BY siteid, due_bucket
ORDER BY siteid,
    CASE due_bucket
        WHEN 'OVERDUE' THEN 1
        WHEN 'DUE_30D' THEN 2
        WHEN 'DUE_60D' THEN 3
        WHEN 'DUE_90D' THEN 4
    END;


-- -----------------------------------------------------------------------------
-- 2. Craft workload forecast — planned labor hours by craft × week
-- -----------------------------------------------------------------------------
-- Trigger: "craft workload", "labor demand forecast", "are we over-scheduled"
SELECT
    siteid,
    week_starting,
    craft,
    SUM(planned_labor_hours)                       AS forecast_labor_hours
FROM {{catalog}}.{{gold_schema}}.v_pm_workload_by_craft
WHERE week_starting BETWEEN current_date()
                        AND current_date() + INTERVAL 90 DAYS
GROUP BY siteid, week_starting, craft
ORDER BY siteid, week_starting, forecast_labor_hours DESC;


-- -----------------------------------------------------------------------------
-- 3. Critical assets without any PMs (coverage gap)
-- -----------------------------------------------------------------------------
-- Trigger: "critical assets missing PMs", "PM coverage gap"
SELECT
    a.assetnum, a.siteid, a.description, a.classstructureid, a.criticality
FROM {{catalog}}.{{silver_schema}}.asset a
LEFT JOIN {{catalog}}.{{silver_schema}}.pm p
    ON p.assetnum = a.assetnum
   AND p.siteid = a.siteid
   AND p.__END_AT IS NULL
   AND p.status = 'ACTIVE'
WHERE a.__END_AT IS NULL
  AND a.status = 'OPERATING'
  AND a.criticality >= {{critical_threshold}}
  AND p.pmnum IS NULL
ORDER BY a.criticality DESC
LIMIT 50;


-- -----------------------------------------------------------------------------
-- 4. PM-to-CM ratio trend (program-health indicator)
-- -----------------------------------------------------------------------------
-- Trigger: "PM to CM ratio", "preventive vs corrective", "program health"
SELECT
    date_trunc('MONTH', actfinish)                 AS month,
    siteid,
    SUM(CASE WHEN pmnum IS NOT NULL THEN 1 ELSE 0 END)        AS pm_count,
    SUM(CASE WHEN pmnum IS NULL     THEN 1 ELSE 0 END)        AS cm_count,
    ROUND(
        SUM(CASE WHEN pmnum IS NOT NULL THEN 1.0 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN pmnum IS NULL THEN 1.0 ELSE 0 END), 0),
        2
    )                                              AS pm_to_cm_ratio
FROM {{catalog}}.{{silver_schema}}.workorder
WHERE woclass = 'WORKORDER'
  AND status IN ('COMP', 'CLOSE')
  AND actfinish >= add_months(current_date(), -12)
GROUP BY date_trunc('MONTH', actfinish), siteid
ORDER BY month, siteid;


-- -----------------------------------------------------------------------------
-- 5. Route clustering — forecast PMs grouped by location parent
-- -----------------------------------------------------------------------------
-- Trigger: "route optimization", "group PMs by location"
SELECT
    location_parent                                AS route_cluster,
    forecast_week,
    COUNT(*)                                       AS pm_count,
    SUM(planned_labor_hours)                       AS total_labor_hours,
    array_agg(DISTINCT pmnum)                      AS pmnums_in_cluster
FROM {{catalog}}.{{gold_schema}}.v_pm_route_clusters
WHERE forecast_week BETWEEN current_date()
                        AND current_date() + INTERVAL 30 DAYS
GROUP BY location_parent, forecast_week
ORDER BY forecast_week, total_labor_hours DESC;


-- -----------------------------------------------------------------------------
-- 6. Meter-based PM forecast for a specific asset
-- -----------------------------------------------------------------------------
-- Trigger: "when is next PM due for asset X", "meter-based PM forecast"
-- (Moved from maximo-reliability — forward-looking content lives here.)
SELECT
    pm.pmnum, pm.siteid, pm.assetnum,
    pm.frequency, pm.frequnit,
    am.metername,
    am.lastreading,
    am.lastreadingdate,
    am.average                                     AS avg_per_day,
    {{catalog}}.{{metrics_schema}}.meter_based_pm_forecast(
        pm.pmnum, pm.siteid
    )                                              AS forecast_next_due
FROM {{catalog}}.{{silver_schema}}.pm pm
JOIN {{catalog}}.{{silver_schema}}.assetmeter am
    ON am.assetnum = pm.assetnum AND am.siteid = pm.siteid
   AND am.__END_AT IS NULL
WHERE pm.__END_AT IS NULL
  AND pm.status = 'ACTIVE'
  AND pm.frequnit IN ('HOURS', 'MILES', 'READINGS')
  AND pm.assetnum = '{{assetnum}}'
  AND pm.siteid = '{{siteid}}';


-- -----------------------------------------------------------------------------
-- 7. JOBPLAN edit impact — assets / PMs affected by a JOBPLAN change
-- -----------------------------------------------------------------------------
-- Trigger: "if I change JOBPLAN X, what's affected"
SELECT
    pm.jpnum,
    COUNT(DISTINCT pm.pmnum)                       AS distinct_pms,
    COUNT(DISTINCT pm.assetnum)                    AS distinct_assets,
    COUNT(DISTINCT pm.siteid)                      AS distinct_sites,
    array_agg(DISTINCT pm.siteid)                  AS sites
FROM {{catalog}}.{{silver_schema}}.pm pm
WHERE pm.jpnum = '{{jpnum}}'
  AND pm.__END_AT IS NULL
  AND pm.status = 'ACTIVE'
GROUP BY pm.jpnum;


-- -----------------------------------------------------------------------------
-- 8. Multi-frequency PM expansion (`PMSEQUENCE`)
-- -----------------------------------------------------------------------------
-- Trigger: "PMs with multiple cadences", "expand PM sequences"
SELECT
    pm.pmnum, pm.siteid, pm.description AS pm_description,
    seq.sequence,
    seq.jpnum                                      AS sequence_jpnum,
    seq.frequency, seq.frequnit,
    jp.description                                 AS sequence_jp_description
FROM {{catalog}}.{{silver_schema}}.pm pm
JOIN {{catalog}}.{{silver_schema}}.pmsequence seq
    ON seq.pmnum = pm.pmnum AND seq.siteid = pm.siteid
LEFT JOIN {{catalog}}.{{silver_schema}}.jobplan jp
    ON jp.jpnum = seq.jpnum AND jp.__END_AT IS NULL
WHERE pm.__END_AT IS NULL
  AND pm.status = 'ACTIVE'
ORDER BY pm.pmnum, seq.sequence;


-- -----------------------------------------------------------------------------
-- 9. PM tolerance utilization — generation timing vs NEXTDATE
-- -----------------------------------------------------------------------------
-- Trigger: "PM tolerance utilization", "are PMs generating early or late"
WITH pm_actuals AS (
    SELECT
        w.pmnum, w.siteid,
        w.actstart, w.actfinish,
        pm.nextdate AS target_date,
        datediff(DAY, pm.nextdate, w.actstart) AS days_offset_from_target
    FROM {{catalog}}.{{silver_schema}}.workorder w
    JOIN {{catalog}}.{{silver_schema}}.pm pm
        ON pm.pmnum = w.pmnum AND pm.siteid = w.siteid AND pm.__END_AT IS NULL
    WHERE w.pmnum IS NOT NULL
      AND w.status IN ('COMP', 'CLOSE')
      AND w.actstart >= add_months(current_date(), -6)
)
SELECT
    CASE
        WHEN days_offset_from_target < -7 THEN 'EARLY_>7d'
        WHEN days_offset_from_target < 0  THEN 'EARLY_0-7d'
        WHEN days_offset_from_target = 0  THEN 'ON_TIME'
        WHEN days_offset_from_target <= 7 THEN 'LATE_0-7d'
        ELSE                                   'LATE_>7d'
    END                                            AS timing_bucket,
    COUNT(*)                                       AS pm_executions
FROM pm_actuals
GROUP BY
    CASE
        WHEN days_offset_from_target < -7 THEN 'EARLY_>7d'
        WHEN days_offset_from_target < 0  THEN 'EARLY_0-7d'
        WHEN days_offset_from_target = 0  THEN 'ON_TIME'
        WHEN days_offset_from_target <= 7 THEN 'LATE_0-7d'
        ELSE                                   'LATE_>7d'
    END
ORDER BY pm_executions DESC;


-- -----------------------------------------------------------------------------
-- 10. Next PM due for each critical asset
-- -----------------------------------------------------------------------------
-- Trigger: "next PM for critical assets", "when are critical asset PMs due"
SELECT
    a.assetnum, a.siteid, a.description, a.criticality,
    {{catalog}}.{{metrics_schema}}.next_pm_due(a.assetnum, a.siteid) AS next_pm_due
FROM {{catalog}}.{{silver_schema}}.asset a
WHERE a.__END_AT IS NULL
  AND a.criticality >= {{critical_threshold}}
ORDER BY next_pm_due NULLS LAST;
