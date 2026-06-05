-- =============================================================================
-- Maximo PM Planning — Gold-Standard Query Examples
-- =============================================================================
-- Each block is a parameterized template mapping to one planning question.
-- Bind these Databricks SQL parameters at execution time:
--   :catalog          → the customer's UC catalog (e.g. eam)
--   :silver_schema    → Silver schema with the MBO tables (e.g. maximo_silver)
--   :gold_schema      → Gold schema holding the views (e.g. maximo_gold)
--   :metrics_schema   → schema holding the Trusted UDFs (e.g. maximo_metrics)
--   :assetnum, :siteid, :jpnum, :critical_threshold → per-query value parameters
-- These examples assume views.sql and metric_udfs.sql have been registered.
-- Workflow priority: prefer a matching Trusted UDF, then a view, then raw tables.
--
-- STATUS FILTERING: examples use the literal active set (status = 'ACTIVE') for
-- readability. That is correct in a STOCK deployment, but PM.STATUS stores the
-- synonym VALUE (domain PMSTATUS), so when a customer renames statuses, resolve
-- the active set from the internal MAXVALUE via SYNONYMDOMAIN — see example 11
-- for the canonical pattern (gotchas.md gotcha 4; mechanic owned by maximo-overview).
-- DATES resolve in the app-server timezone of the stored values — don't assume
-- UTC when bucketing by day/week across sites (maximo-overview).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. PMs forecast due in next 30 / 60 / 90 days, by site
-- -----------------------------------------------------------------------------
-- Trigger: "PMs due", "upcoming PMs", "forecast PMs"
SELECT
    siteid,
    due_bucket,
    COUNT(*)                                       AS pm_count
FROM :catalog.:gold_schema.v_pm_forecast
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
FROM :catalog.:gold_schema.v_pm_workload_by_craft
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
FROM :catalog.:silver_schema.asset a
LEFT JOIN :catalog.:silver_schema.pm p
    ON p.assetnum = a.assetnum
   AND p.siteid = a.siteid
   AND p.__END_AT IS NULL
   AND p.status = 'ACTIVE'
WHERE a.__END_AT IS NULL
  AND a.status = 'OPERATING'
  AND a.criticality >= :critical_threshold
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
FROM :catalog.:silver_schema.workorder
WHERE woclass = 'WORKORDER'                  -- exclude PM/CHANGE/RELEASE rows (maximo-overview)
  AND status IN ('COMP', 'CLOSE')           -- WOSTATUS synonym; resolve via SYNONYMDOMAIN if renamed
  AND actfinish >= add_months(current_date(), -12)
-- NOTE: a trend over completed work needs closed records present — confirm the
-- silver pipeline does not drop HISTORYFLAG=1 rows (maximo-overview).
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
FROM :catalog.:gold_schema.v_pm_route_clusters
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
    :catalog.:metrics_schema.meter_based_pm_forecast(
        pm.pmnum, pm.siteid
    )                                              AS forecast_next_due
FROM :catalog.:silver_schema.pm pm
JOIN :catalog.:silver_schema.assetmeter am
    ON am.assetnum = pm.assetnum AND am.siteid = pm.siteid
   AND am.metername = pm.metername          -- match the runtime meter, not all meters
   AND am.__END_AT IS NULL
WHERE pm.__END_AT IS NULL
  AND pm.status = 'ACTIVE'                   -- PMSTATUS synonym; see example 11
  AND pm.frequnit IN ('HOURS', 'MILES', 'READINGS')
  AND pm.assetnum = :assetnum
  AND pm.siteid = :siteid;


-- -----------------------------------------------------------------------------
-- 7. JOBPLAN edit impact — assets / PMs affected by a JOBPLAN change
-- -----------------------------------------------------------------------------
-- Trigger: "if I change JOBPLAN X, what's affected"
-- JOBPLAN is org-scoped — group by (JPNUM, ORGID) so the same job-plan number
-- reused across orgs is not conflated (gotchas.md gotcha 9).
SELECT
    pm.jpnum, pm.orgid,
    COUNT(DISTINCT pm.pmnum)                       AS distinct_pms,
    COUNT(DISTINCT pm.assetnum)                    AS distinct_assets,
    COUNT(DISTINCT pm.siteid)                      AS distinct_sites,
    array_agg(DISTINCT pm.siteid)                  AS sites
FROM :catalog.:silver_schema.pm pm
WHERE pm.jpnum = :jpnum
  AND pm.__END_AT IS NULL
  AND pm.status = 'ACTIVE'
GROUP BY pm.jpnum, pm.orgid;


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
FROM :catalog.:silver_schema.pm pm
JOIN :catalog.:silver_schema.pmsequence seq
    ON seq.pmnum = pm.pmnum AND seq.siteid = pm.siteid
LEFT JOIN :catalog.:silver_schema.jobplan jp
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
    FROM :catalog.:silver_schema.workorder w
    JOIN :catalog.:silver_schema.pm pm
        ON pm.pmnum = w.pmnum AND pm.siteid = w.siteid AND pm.__END_AT IS NULL
    WHERE w.pmnum IS NOT NULL
      AND w.woclass = 'WORKORDER'            -- exclude PM/CHANGE/RELEASE rows (maximo-overview)
      AND w.status IN ('COMP', 'CLOSE')      -- WOSTATUS synonym; resolve via SYNONYMDOMAIN if renamed
      AND w.actstart >= add_months(current_date(), -6)
    -- NOTE: completed WOs may carry HISTORYFLAG=1; confirm closed work is present
    -- in silver (some pipelines mirror Maximo's HISTORYFLAG=0 filter). maximo-overview.
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
    :catalog.:metrics_schema.next_pm_due(a.assetnum, a.siteid) AS next_pm_due
FROM :catalog.:silver_schema.asset a
WHERE a.__END_AT IS NULL
  AND a.criticality >= :critical_threshold
ORDER BY next_pm_due NULLS LAST;


-- -----------------------------------------------------------------------------
-- 11. Synonym-safe active-PM forecast (customer renamed PMSTATUS)
-- -----------------------------------------------------------------------------
-- Trigger: customer has renamed/added PM statuses; the literal 'ACTIVE' misses rows.
-- Canonical pattern: resolve the active set from the internal MAXVALUE via
-- SYNONYMDOMAIN instead of hard-coding the VALUE literal (gotchas.md gotcha 4;
-- mechanic owned by maximo-overview). Use this shape anywhere examples above
-- hard-code status = 'ACTIVE'.
SELECT
    pm.pmnum, pm.siteid,
    COALESCE(pm.extdate, pm.nextdate)              AS effective_due_date
FROM :catalog.:silver_schema.pm pm
WHERE pm.__END_AT IS NULL
  AND pm.status IN (
      SELECT value
      FROM :catalog.:silver_schema.synonymdomain
      WHERE domainid = 'PMSTATUS' AND maxvalue = 'ACTIVE'
  )
  AND COALESCE(pm.extdate, pm.nextdate)
        BETWEEN current_date() AND current_date() + INTERVAL 90 DAYS
ORDER BY effective_due_date;
