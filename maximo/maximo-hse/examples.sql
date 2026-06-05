-- =============================================================================
-- Maximo HSE — Gold-Standard Query Examples
-- =============================================================================
-- Bind :catalog, :gold_schema, :silver_schema, :metrics_schema and the runtime
-- params (:hours_worked_q3, :quarter_start, :quarter_end, :assetnum, :siteid)
-- as Databricks SQL parameters at execution.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Open permits right now
-- -----------------------------------------------------------------------------
-- Trigger: "how many permits are open", "active PTW"
SELECT
    permit_type_code, permit_type_description,
    COUNT(*) AS active_count,
    SUM(CASE WHEN expiry_status = 'EXPIRED_STILL_OPEN' THEN 1 ELSE 0 END) AS expired_still_open,
    SUM(CASE WHEN expiry_status = 'EXPIRING_TODAY'     THEN 1 ELSE 0 END) AS expiring_today,
    SUM(CASE WHEN expiry_status = 'EXPIRING_7D'        THEN 1 ELSE 0 END) AS expiring_7d
FROM :catalog.:gold_schema.v_open_permits
GROUP BY permit_type_code, permit_type_description
ORDER BY active_count DESC;


-- -----------------------------------------------------------------------------
-- 2. Permits expired but still open (compliance issue)
-- -----------------------------------------------------------------------------
-- Trigger: "expired permits still active", "permit compliance gaps"
SELECT permitworknum, siteid, permit_type_code, enddate,
       datediff(DAY, enddate, current_timestamp()) AS days_overdue
FROM :catalog.:gold_schema.v_open_permits
WHERE expiry_status = 'EXPIRED_STILL_OPEN'
ORDER BY enddate;


-- -----------------------------------------------------------------------------
-- 3. TRIR for last quarter
-- -----------------------------------------------------------------------------
-- Trigger: "TRIR Q3", "total recordable rate"
-- IMPORTANT: hours_worked must be sourced from HR; recordable categories are
-- deployment-specific (no stock recordable column).
SELECT
    :catalog.:metrics_schema.trir(
        NULL,                       -- all sites
        'RECORDABLE,LOST_TIME',     -- customer's recordable categories
        :hours_worked_q3,           -- e.g. 1500000.0 — from HR system
        :quarter_start,
        :quarter_end
    ) AS trir_q3;


-- -----------------------------------------------------------------------------
-- 4. Incident counts by category, last 12 months
-- -----------------------------------------------------------------------------
-- Trigger: "incident summary", "incidents by category"
SELECT
    incidentcategory,
    severity,
    COUNT(*) AS incident_count,
    SUM(persons_involved_count) AS persons_involved_total,
    SUM(injured_persons_count)  AS injured_total
FROM :catalog.:gold_schema.v_incidents_enriched
WHERE reportdate >= add_months(current_date(), -12)
GROUP BY incidentcategory, severity
ORDER BY incident_count DESC;


-- -----------------------------------------------------------------------------
-- 5. Open corrective actions older than 30 days
-- -----------------------------------------------------------------------------
-- Trigger: "open actions from incidents", "overdue corrective actions"
SELECT
    mocid, moc_reason, action_wonum, action_status, action_due_date,
    datediff(DAY, action_due_date, current_date()) AS days_overdue
FROM :catalog.:gold_schema.v_moc_actions
WHERE action_status_bucket = 'OVERDUE'
  AND datediff(DAY, action_due_date, current_date()) > 30
ORDER BY days_overdue DESC;


-- -----------------------------------------------------------------------------
-- 6. Near-miss trend (last 12 months by month)
-- -----------------------------------------------------------------------------
-- Trigger: "near-miss trend", "near-miss reporting rate"
-- Caveat: near-miss reporting lags ~1-2 weeks; recent buckets look low (gotcha 11).
SELECT
    date_trunc('MONTH', reportdate) AS month,
    siteid,
    COUNT(*) AS near_miss_count
FROM :catalog.:gold_schema.v_incidents_enriched
WHERE incidentcategory IN ('NEAR_MISS', 'NEARMISS')   -- customer-configured set
  AND reportdate >= add_months(current_date(), -12)
GROUP BY date_trunc('MONTH', reportdate), siteid
ORDER BY month DESC, near_miss_count DESC;


-- -----------------------------------------------------------------------------
-- 7. Incidents tied to a specific asset (last 5 years)
-- -----------------------------------------------------------------------------
-- Trigger: "incidents on asset X"
SELECT
    ticketid, reportdate, incidentcategory, severity,
    persons_involved_count, injured_persons_count
FROM :catalog.:gold_schema.v_incidents_enriched
WHERE assetnum = :assetnum
  AND siteid = :siteid
  AND reportdate >= add_months(current_date(), -60)
ORDER BY reportdate DESC;
