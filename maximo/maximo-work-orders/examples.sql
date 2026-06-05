-- =============================================================================
-- Maximo Work Orders — Gold-Standard Query Examples
-- =============================================================================
-- Each block is a parameterized template that maps to a single analytical
-- question. Substitute the placeholders:
--   {{maximo_catalog}}.{{maximo_schema}}  →  e.g. eam.maximo_silver
--   {{open_statuses}}                     →  e.g. ('WAPPR','APPR','INPRG','WMATL','WSCH')
-- These examples assume the views in views.sql have been created.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Open work-order backlog by site and work type
-- -----------------------------------------------------------------------------
-- Trigger: "what's our open WO backlog by site"
SELECT
    siteid,
    worktype,
    COUNT(*) AS open_wo_count
FROM {{maximo_catalog}}.{{maximo_schema}}.v_workorder_enriched
WHERE woclass = 'WORKORDER'
  AND istask = 0
  AND status IN {{open_statuses}}
GROUP BY siteid, worktype
ORDER BY siteid, open_wo_count DESC;


-- -----------------------------------------------------------------------------
-- 2. Aging buckets on open WOs
-- -----------------------------------------------------------------------------
-- Trigger: "how aged is our backlog", "WOs older than 90 days"
SELECT
    siteid,
    CASE
        WHEN datediff(day, reportdate, current_date()) <= 30  THEN '0-30 days'
        WHEN datediff(day, reportdate, current_date()) <= 60  THEN '31-60 days'
        WHEN datediff(day, reportdate, current_date()) <= 90  THEN '61-90 days'
        ELSE '90+ days'
    END AS age_bucket,
    COUNT(*) AS wo_count
FROM {{maximo_catalog}}.{{maximo_schema}}.v_workorder_enriched
WHERE woclass = 'WORKORDER'
  AND istask = 0
  AND status IN {{open_statuses}}
GROUP BY siteid, age_bucket
ORDER BY siteid,
    CASE age_bucket
        WHEN '0-30 days' THEN 1
        WHEN '31-60 days' THEN 2
        WHEN '61-90 days' THEN 3
        ELSE 4
    END;


-- -----------------------------------------------------------------------------
-- 3. Mean time-to-complete by work type (completed in last N days)
-- -----------------------------------------------------------------------------
-- Trigger: "average completion time by work type", "how long are CM WOs taking"
SELECT
    worktype,
    COUNT(*) AS completed_count,
    ROUND(AVG(datediff(day, reportdate, actfinish)), 1) AS avg_days_to_complete,
    ROUND(PERCENTILE(datediff(day, reportdate, actfinish), 0.5), 1) AS p50_days,
    ROUND(PERCENTILE(datediff(day, reportdate, actfinish), 0.9), 1) AS p90_days
FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER
WHERE woclass = 'WORKORDER'
  AND istask = 0
  AND status IN ('COMP', 'CLOSE')
  AND actfinish IS NOT NULL
  AND actfinish >= current_date() - INTERVAL 90 DAYS
GROUP BY worktype
ORDER BY completed_count DESC;


-- -----------------------------------------------------------------------------
-- 4. Actual vs planned labor hours by WO (variance analysis)
-- -----------------------------------------------------------------------------
-- Trigger: "labor variance", "actual vs planned hours"
WITH actual AS (
    SELECT wonum, siteid, SUM(regularhrs + COALESCE(premiumpayhours, 0)) AS actual_hrs
    FROM {{maximo_catalog}}.{{maximo_schema}}.LABTRANS
    GROUP BY wonum, siteid
),
planned AS (
    SELECT wonum, siteid, SUM(laborhrs) AS planned_hrs
    FROM {{maximo_catalog}}.{{maximo_schema}}.WPLABOR
    GROUP BY wonum, siteid
)
SELECT
    w.wonum, w.siteid, w.worktype, w.status,
    p.planned_hrs,
    a.actual_hrs,
    a.actual_hrs - p.planned_hrs AS variance_hrs,
    CASE WHEN p.planned_hrs > 0
         THEN ROUND(100.0 * (a.actual_hrs - p.planned_hrs) / p.planned_hrs, 1)
         ELSE NULL END AS variance_pct
FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER w
LEFT JOIN actual  a ON a.wonum = w.wonum AND a.siteid = w.siteid
LEFT JOIN planned p ON p.wonum = w.wonum AND p.siteid = w.siteid
WHERE w.woclass = 'WORKORDER'
  AND w.istask = 0
  AND w.status IN ('COMP', 'CLOSE')
ORDER BY ABS(COALESCE(a.actual_hrs, 0) - COALESCE(p.planned_hrs, 0)) DESC
LIMIT 100;


-- -----------------------------------------------------------------------------
-- 5. Top assets by WO count this year
-- -----------------------------------------------------------------------------
-- Trigger: "which assets generate the most work", "bad-actor assets"
SELECT
    a.assetnum, a.siteid, a.description AS asset_description,
    a.classstructureid,
    COUNT(*) AS wo_count
FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER w
JOIN {{maximo_catalog}}.{{maximo_schema}}.ASSET a
    ON a.assetnum = w.assetnum AND a.siteid = w.siteid
WHERE w.woclass = 'WORKORDER'
  AND w.istask = 0
  AND w.reportdate >= date_trunc('YEAR', current_date())
GROUP BY a.assetnum, a.siteid, a.description, a.classstructureid
ORDER BY wo_count DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- 6. Status history for a single WO
-- -----------------------------------------------------------------------------
-- Trigger: "show me the status history of WO X"
SELECT
    s.status,
    s.changedate,
    s.changeby,
    s.memo,
    datediff(SECOND, s.changedate,
             LEAD(s.changedate) OVER (PARTITION BY s.wonum, s.siteid ORDER BY s.changedate)
            ) / 3600.0 AS hours_in_status
FROM {{maximo_catalog}}.{{maximo_schema}}.WOSTATUS s
WHERE s.wonum = '{{wonum}}' AND s.siteid = '{{siteid}}'
ORDER BY s.changedate;


-- -----------------------------------------------------------------------------
-- 7. Time spent in each status (aggregated across all WOs of a type)
-- -----------------------------------------------------------------------------
-- Trigger: "average time in INPRG", "where do WOs sit longest"
WITH dwell AS (
    SELECT
        s.wonum, s.siteid, s.status,
        datediff(SECOND, s.changedate,
                 LEAD(s.changedate) OVER (PARTITION BY s.wonum, s.siteid ORDER BY s.changedate)
                ) / 3600.0 AS hours_in_status
    FROM {{maximo_catalog}}.{{maximo_schema}}.WOSTATUS s
)
SELECT
    d.status,
    COUNT(*) AS observations,
    ROUND(AVG(d.hours_in_status), 1)    AS avg_hours,
    ROUND(PERCENTILE(d.hours_in_status, 0.5), 1) AS p50_hours,
    ROUND(PERCENTILE(d.hours_in_status, 0.9), 1) AS p90_hours
FROM dwell d
JOIN {{maximo_catalog}}.{{maximo_schema}}.WORKORDER w
    ON w.wonum = d.wonum AND w.siteid = d.siteid
WHERE w.woclass = 'WORKORDER'
  AND w.worktype = '{{worktype}}'
  AND d.hours_in_status IS NOT NULL
GROUP BY d.status
ORDER BY avg_hours DESC;


-- -----------------------------------------------------------------------------
-- 8. Completed WOs per month
-- -----------------------------------------------------------------------------
-- Trigger: "completion trend", "throughput by month"
SELECT
    date_trunc('MONTH', actfinish) AS month,
    siteid,
    worktype,
    COUNT(*) AS completed_count,
    ROUND(SUM(actlabcost + actmatcost), 2) AS total_actual_cost
FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER
WHERE woclass = 'WORKORDER'
  AND istask = 0
  AND status IN ('COMP', 'CLOSE')
  AND actfinish IS NOT NULL
  AND actfinish >= add_months(current_date(), -12)
GROUP BY date_trunc('MONTH', actfinish), siteid, worktype
ORDER BY month DESC, completed_count DESC;


-- -----------------------------------------------------------------------------
-- 9. Labor hours by craft over a period
-- -----------------------------------------------------------------------------
-- Trigger: "labor hours by craft", "craft utilization"
SELECT
    lt.craft,
    date_trunc('WEEK', lt.startdate) AS week_starting,
    COUNT(DISTINCT lt.wonum) AS wo_count,
    ROUND(SUM(lt.regularhrs), 1) AS regular_hrs,
    ROUND(SUM(COALESCE(lt.premiumpayhours, 0)), 1) AS premium_hrs,
    ROUND(SUM(lt.linecost), 2) AS total_cost
FROM {{maximo_catalog}}.{{maximo_schema}}.LABTRANS lt
WHERE lt.startdate >= current_date() - INTERVAL 90 DAYS
  AND lt.transtype = 'WORK'
GROUP BY lt.craft, date_trunc('WEEK', lt.startdate)
ORDER BY week_starting DESC, total_cost DESC;


-- -----------------------------------------------------------------------------
-- 10. Failure-mode pareto for completed WOs on a class of asset
-- -----------------------------------------------------------------------------
-- Trigger: "top failure modes", "pareto of failures"
SELECT
    fr.failurecode,
    fc.description AS failure_description,
    COUNT(*) AS event_count,
    ROUND(100.0 * COUNT(*) /
          SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM {{maximo_catalog}}.{{maximo_schema}}.FAILUREREPORT fr
JOIN {{maximo_catalog}}.{{maximo_schema}}.WORKORDER w
    ON w.wonum = fr.wonum AND w.siteid = fr.siteid
JOIN {{maximo_catalog}}.{{maximo_schema}}.ASSET a
    ON a.assetnum = w.assetnum AND a.siteid = w.siteid
LEFT JOIN {{maximo_catalog}}.{{maximo_schema}}.FAILURECODE fc
    ON fc.failurecode = fr.failurecode
WHERE w.woclass = 'WORKORDER'
  AND w.status IN ('COMP', 'CLOSE')
  AND a.classstructureid = {{asset_class_id}}
  AND w.actfinish >= add_months(current_date(), -12)
GROUP BY fr.failurecode, fc.description
ORDER BY event_count DESC
LIMIT 20;
