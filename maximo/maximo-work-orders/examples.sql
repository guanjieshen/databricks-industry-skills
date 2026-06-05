-- =============================================================================
-- Maximo Work Orders — Gold-Standard Query Examples
-- =============================================================================
-- Each block is a parameterized template that maps to a single analytical
-- question. Bind these Databricks SQL parameters at execution time:
--   :catalog          → the customer's UC catalog (e.g. eam)
--   :silver_schema    → Silver schema with the MBO tables (e.g. maximo_silver)
--   :gold_schema      → Gold/metrics schema with Trusted UDFs (e.g. maximo_metrics)
--                       — only needed for examples that call a Trusted UDF
--   :open_statuses    → multi-value list, e.g. ('WAPPR','APPR','INPRG','WMATL','WSCH')
--   :wonum, :siteid, :worktype, :asset_class_id  → per-query value parameters
-- These examples assume views.sql and metric_udfs.sql have been registered.
-- Workflow priority: if a Trusted UDF matches the question, prefer it over the
-- view-based query (see SKILL.md §Workflow).
--
-- STATUS FILTERING: examples below use literal status sets (e.g. ('COMP','CLOSE'))
-- for readability. That is correct in a STOCK deployment, but WORKORDER.STATUS
-- stores the synonym VALUE, so when a customer has added status synonyms, resolve
-- the set from the internal MAXVALUE via SYNONYMDOMAIN — see example 11 for the
-- canonical pattern (gotcha 5). Also decide deliberately whether closed/cancelled
-- WOs (HISTORYFLAG = 1) are in scope before computing completion/trend metrics
-- (gotcha 11), and prefer COMP-or-later (not CLOSE-only) for "completed work".
-- =============================================================================
--
-- Contents (load the block that matches the question):
--   1a. Open WO count at a single site (Trusted UDF)
--   1b. Open WO backlog by site and work type (view-based)
--   2.  Aging buckets on open WOs (wo_aging_bucket UDF)
--   3.  Mean time-to-complete by work type (p50/p90)
--   4.  Actual vs planned labor hours by WO (variance)
--   5.  Top assets by WO count this year (bad-actor by volume)
--   6.  Status history for a single WO
--   7.  Time spent in each status (dwell, aggregated)
--   8.  Completed WOs per month (throughput trend)
--   9.  Labor hours by craft over a period
--   10. Failure-mode pareto for a class of asset
--   11. Completed-work count, synonym-safe + HISTORYFLAG-aware (canonical)
--   12. Rework: follow-up WOs and their originating work order
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1a. Open WO count at a single site (Trusted UDF — prefer this)
-- -----------------------------------------------------------------------------
-- Trigger: "how many open WOs at site X", "current open count for <site>"
-- The open_wo_count UDF is the governed metric. Use this when the user wants a
-- single number for one site. For breakdowns (by worktype, age bucket, etc.),
-- fall through to the view-based queries below.
SELECT :catalog.:gold_schema.open_wo_count(:siteid, current_timestamp()) AS open_wo_count;


-- -----------------------------------------------------------------------------
-- 1b. Open WO backlog by site and work type (view-based — when UDF grain doesn't fit)
-- -----------------------------------------------------------------------------
-- Trigger: "what's our open WO backlog by site", "open WOs split by worktype"
-- The open_wo_count UDF returns per-site only. For multi-dimensional breakdowns,
-- query v_workorder_enriched directly.
SELECT
    siteid,
    worktype,
    COUNT(*) AS open_wo_count
FROM :catalog.:silver_schema.v_workorder_enriched
WHERE woclass = 'WORKORDER'
  AND istask = 0
  AND status IN (:open_statuses)
GROUP BY siteid, worktype
ORDER BY siteid, open_wo_count DESC;


-- -----------------------------------------------------------------------------
-- 2. Aging buckets on open WOs (uses wo_aging_bucket Trusted UDF)
-- -----------------------------------------------------------------------------
-- Trigger: "how aged is our backlog", "WOs older than 90 days"
-- Calls the wo_aging_bucket UDF for the standard 30/60/90 bucket assignment
-- instead of inlining a CASE statement — Genie should prefer this pattern.
SELECT
    siteid,
    :catalog.:gold_schema.wo_aging_bucket(reportdate) AS age_bucket,
    COUNT(*) AS wo_count
FROM :catalog.:silver_schema.v_workorder_enriched
WHERE woclass = 'WORKORDER'
  AND istask = 0
  AND status IN (:open_statuses)
GROUP BY siteid, age_bucket
ORDER BY siteid,
    CASE age_bucket
        WHEN '0-30 days' THEN 1
        WHEN '31-60 days' THEN 2
        WHEN '61-90 days' THEN 3
        ELSE 4
    END;


-- -----------------------------------------------------------------------------
-- 3. Mean time-to-complete by work type (completed in last 90 days)
-- -----------------------------------------------------------------------------
-- Trigger: "average completion time by work type", "how long are CM WOs taking"
-- Note: the mean_time_to_complete Trusted UDF returns a single AVG for one
-- worktype + window; use this view-based version when the user wants p50/p90
-- percentiles or a multi-worktype breakdown.
SELECT
    worktype,
    COUNT(*) AS completed_count,
    ROUND(AVG(datediff(DAY, reportdate, actfinish)), 1) AS avg_days_to_complete,
    ROUND(PERCENTILE(datediff(DAY, reportdate, actfinish), 0.5), 1) AS p50_days,
    ROUND(PERCENTILE(datediff(DAY, reportdate, actfinish), 0.9), 1) AS p90_days
FROM :catalog.:silver_schema.WORKORDER
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
    FROM :catalog.:silver_schema.LABTRANS
    GROUP BY wonum, siteid
),
planned AS (
    SELECT wonum, siteid, SUM(laborhrs) AS planned_hrs
    FROM :catalog.:silver_schema.WPLABOR
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
FROM :catalog.:silver_schema.WORKORDER w
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
FROM :catalog.:silver_schema.WORKORDER w
JOIN :catalog.:silver_schema.ASSET a
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
FROM :catalog.:silver_schema.WOSTATUS s
WHERE s.wonum = :wonum AND s.siteid = :siteid
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
    FROM :catalog.:silver_schema.WOSTATUS s
)
SELECT
    d.status,
    COUNT(*) AS observations,
    ROUND(AVG(d.hours_in_status), 1)    AS avg_hours,
    ROUND(PERCENTILE(d.hours_in_status, 0.5), 1) AS p50_hours,
    ROUND(PERCENTILE(d.hours_in_status, 0.9), 1) AS p90_hours
FROM dwell d
JOIN :catalog.:silver_schema.WORKORDER w
    ON w.wonum = d.wonum AND w.siteid = d.siteid
WHERE w.woclass = 'WORKORDER'
  AND w.worktype = :worktype
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
FROM :catalog.:silver_schema.WORKORDER
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
FROM :catalog.:silver_schema.LABTRANS lt
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
FROM :catalog.:silver_schema.FAILUREREPORT fr
JOIN :catalog.:silver_schema.WORKORDER w
    ON w.wonum = fr.wonum AND w.siteid = fr.siteid
JOIN :catalog.:silver_schema.ASSET a
    ON a.assetnum = w.assetnum AND a.siteid = w.siteid
LEFT JOIN :catalog.:silver_schema.FAILURECODE fc
    ON fc.failurecode = fr.failurecode
WHERE w.woclass = 'WORKORDER'
  AND w.status IN ('COMP', 'CLOSE')
  AND a.classstructureid = :asset_class_id
  AND w.actfinish >= add_months(current_date(), -12)
GROUP BY fr.failurecode, fc.description
ORDER BY event_count DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- 11. Completed-work count, synonym-safe + HISTORYFLAG-aware (canonical pattern)
-- -----------------------------------------------------------------------------
-- Trigger: "how many WOs did we complete", "completion count" — when the
-- deployment uses custom status synonyms, or you must be sure closed WOs count.
-- Resolves every synonym of the internal COMP/CLOSE values via SYNONYMDOMAIN
-- (the IBM WORKVIEW pattern, gotcha 5). "Completed" = COMP-or-later (gotcha 11).
SELECT
    siteid,
    worktype,
    COUNT(*) AS completed_count
FROM :catalog.:silver_schema.WORKORDER w
WHERE w.woclass = 'WORKORDER'
  AND w.istask = 0
  AND w.status IN (
        SELECT value
        FROM :catalog.:silver_schema.SYNONYMDOMAIN
        WHERE domainid = 'WOSTATUS'
          AND maxvalue IN ('COMP', 'CLOSE')   -- COMP-or-later; drop 'CLOSE' for COMP-only
      )
  AND w.actfinish >= add_months(current_date(), -12)
GROUP BY siteid, worktype
ORDER BY completed_count DESC;


-- -----------------------------------------------------------------------------
-- 12. Rework: follow-up WOs and their originating work order
-- -----------------------------------------------------------------------------
-- Trigger: "repeat work on the same asset", "follow-up work orders", "rework".
-- Follow-ups live in SEPARATE hierarchies from the originator (their cost/labor
-- do NOT roll up to it), so trace them via ORIGRECORDID/ORIGRECORDCLASS, not
-- PARENT (gotcha 12). This finds follow-up WOs spawned from another WO and pairs
-- each with its originator. Rework *rate* as a KPI belongs to maximo-reliability.
SELECT
    f.wonum                          AS followup_wonum,
    f.siteid,
    f.worktype                       AS followup_worktype,
    f.reportdate                     AS followup_reported,
    o.wonum                          AS originator_wonum,
    o.worktype                       AS originator_worktype,
    o.assetnum                       AS originator_assetnum,
    o.actfinish                      AS originator_finished,
    datediff(DAY, o.actfinish, f.reportdate) AS days_to_followup
FROM :catalog.:silver_schema.WORKORDER f
JOIN :catalog.:silver_schema.WORKORDER o
    ON o.wonum  = f.origrecordid
   AND o.siteid = f.siteid
WHERE f.woclass = 'WORKORDER'
  AND f.origrecordclass = 'WORKORDER'   -- follow-ups spawned from a WO (not a ticket)
  AND f.origrecordid IS NOT NULL
ORDER BY f.reportdate DESC
LIMIT 100;
