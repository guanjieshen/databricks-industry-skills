-- =============================================================================
-- Maximo Maintenance Cost — Gold-Standard Query Examples
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}}, {{catalog}}.{{gold_schema}},
-- {{catalog}}.{{metrics_schema}} before running.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Top assets by maintenance cost last year
-- -----------------------------------------------------------------------------
-- Trigger: "top assets by cost", "most expensive assets to maintain"
SELECT
    s.assetnum, s.siteid, s.asset_description, s.asset_criticality,
    s.total_cost,
    s.total_labor_cost,
    s.total_material_cost,
    s.wo_count
FROM {{catalog}}.{{gold_schema}}.v_asset_cost_summary s
WHERE s.period_start = add_months(date_trunc('YEAR', current_date()), -12)
ORDER BY s.total_cost DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- 2. PM vs CM cost ratio by site, last 12 months
-- -----------------------------------------------------------------------------
-- Trigger: "PM vs CM cost", "preventive vs corrective spend ratio"
SELECT
    siteid,
    {{catalog}}.{{metrics_schema}}.pm_vs_cm_cost_ratio(
        siteid,
        add_months(current_timestamp(), -12),
        current_timestamp()
    ) AS pm_to_cm_cost_ratio
FROM (SELECT DISTINCT siteid FROM {{catalog}}.{{silver_schema}}.workorder)
WHERE siteid IS NOT NULL
ORDER BY pm_to_cm_cost_ratio DESC NULLS LAST;


-- -----------------------------------------------------------------------------
-- 3. Cost variance — estimate vs actual on completed WOs
-- -----------------------------------------------------------------------------
-- Trigger: "cost variance", "WOs over budget", "estimate vs actual"
SELECT
    e.wonum, e.siteid, e.worktype,
    e.assetnum, e.asset_description,
    e.estimated_cost,
    e.actual_cost,
    e.variance,
    e.variance_pct
FROM {{catalog}}.{{gold_schema}}.v_wo_cost_enriched e
WHERE e.actfinish >= add_months(current_date(), -3)
  AND e.estimated_cost > 0
ORDER BY ABS(e.variance) DESC
LIMIT 50;


-- -----------------------------------------------------------------------------
-- 4. Monthly cost trend by site, last 12 months
-- -----------------------------------------------------------------------------
-- Trigger: "cost trend", "monthly spend"
SELECT
    date_trunc('MONTH', transdate)            AS month,
    siteid,
    SUM(labor_cost)                           AS monthly_labor_cost,
    SUM(material_cost)                        AS monthly_material_cost,
    SUM(labor_cost + material_cost)           AS monthly_total_cost
FROM (
    SELECT siteid, startdate AS transdate, linecost AS labor_cost, 0 AS material_cost
    FROM {{catalog}}.{{silver_schema}}.labtrans
    WHERE transtype = 'WORK'
    UNION ALL
    SELECT siteid, transdate, 0, linecost
    FROM {{catalog}}.{{silver_schema}}.matusetrans
    WHERE issuetype IN ('ISSUE', 'RETURN')
) costs
WHERE transdate >= add_months(current_date(), -12)
GROUP BY date_trunc('MONTH', transdate), siteid
ORDER BY month, siteid;


-- -----------------------------------------------------------------------------
-- 5. Contractor spend by vendor, last quarter
-- -----------------------------------------------------------------------------
-- Trigger: "contractor spend", "vendor cost"
SELECT
    c.company, c.name AS vendor_name,
    {{catalog}}.{{metrics_schema}}.contractor_spend(
        c.company,
        add_months(current_timestamp(), -3),
        current_timestamp()
    ) AS quarterly_spend
FROM {{catalog}}.{{silver_schema}}.companies c
WHERE c.type = 'V'
  AND c.disabled = 0
ORDER BY quarterly_spend DESC NULLS LAST
LIMIT 25;


-- -----------------------------------------------------------------------------
-- 6. Labor cost by craft, breakdown of regular vs premium
-- -----------------------------------------------------------------------------
-- Trigger: "overtime cost", "labor cost by craft"
SELECT
    lt.craft,
    SUM(lt.regularhrs)                                      AS regular_hours,
    SUM(lt.premiumpayhours)                                 AS premium_hours,
    SUM(lt.regularhrs * lt.payrate)                         AS regular_labor_cost,
    SUM(lt.premiumpayhours * COALESCE(lt.premiumpayrate, lt.payrate * 1.5)) AS premium_labor_cost,
    SUM(lt.linecost)                                        AS total_labor_cost,
    ROUND(
        100.0 * SUM(lt.premiumpayhours) / NULLIF(SUM(lt.regularhrs + lt.premiumpayhours), 0),
        2
    )                                                       AS premium_hours_pct
FROM {{catalog}}.{{silver_schema}}.labtrans lt
WHERE lt.transtype = 'WORK'
  AND lt.startdate >= add_months(current_date(), -3)
GROUP BY lt.craft
ORDER BY total_labor_cost DESC;


-- -----------------------------------------------------------------------------
-- 7. Cost per operating hour for critical assets
-- -----------------------------------------------------------------------------
-- Trigger: "cost per operating hour", "cost normalized by runtime"
-- Requires a runtime meter on each asset.
SELECT
    a.assetnum, a.siteid, a.description,
    {{catalog}}.{{metrics_schema}}.cost_per_operating_hour(
        a.assetnum, a.siteid, '{{runtime_meter_name}}',
        add_months(current_timestamp(), -12),
        current_timestamp()
    ) AS cost_per_operating_hour
FROM {{catalog}}.{{silver_schema}}.asset a
WHERE a.__END_AT IS NULL
  AND a.criticality >= {{critical_threshold}}
ORDER BY cost_per_operating_hour DESC NULLS LAST
LIMIT 25;


-- -----------------------------------------------------------------------------
-- 8. Bad-actor cost ranking — assets ranked by cost × criticality
-- -----------------------------------------------------------------------------
-- Trigger: "bad actor cost", "criticality-weighted spend"
SELECT
    s.assetnum, s.siteid, s.asset_description, s.asset_criticality,
    s.total_cost,
    s.total_cost * COALESCE(s.asset_criticality, 1) AS criticality_weighted_cost
FROM {{catalog}}.{{gold_schema}}.v_asset_cost_summary s
WHERE s.period_start = add_months(date_trunc('YEAR', current_date()), -12)
ORDER BY criticality_weighted_cost DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- 9. Cost of unplanned downtime — failure-driven WOs
-- -----------------------------------------------------------------------------
-- Trigger: "cost of failure", "unplanned downtime cost"
-- Joins failure events (from reliability skill domain) to cost.
SELECT
    fr.failurecode,
    fc.description                                         AS failure_description,
    COUNT(DISTINCT w.wonum)                                AS failure_events,
    SUM(w.actlabcost + w.actmatcost)                       AS total_failure_cost,
    ROUND(AVG(w.actlabcost + w.actmatcost), 2)             AS avg_cost_per_failure
FROM {{catalog}}.{{silver_schema}}.failurereport fr
JOIN {{catalog}}.{{silver_schema}}.workorder w
    ON w.wonum = fr.wonum AND w.siteid = fr.siteid
LEFT JOIN {{catalog}}.{{silver_schema}}.failurecode fc
    ON fc.failurecode = fr.failurecode
WHERE w.woclass = 'WORKORDER'
  AND w.status IN ('COMP', 'CLOSE')
  AND w.actfinish >= add_months(current_date(), -12)
GROUP BY fr.failurecode, fc.description
ORDER BY total_failure_cost DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- 10. Budget vs actual by site (assumes customer budget table; placeholder shown)
-- -----------------------------------------------------------------------------
-- Trigger: "budget vs actual", "spend vs budget"
-- Customer-specific: replace customer_budget_table reference with their actual
-- budget source. Maximo doesn't ship a budget table.
SELECT
    b.siteid, b.fiscal_year,
    b.budget_amount,
    COALESCE(actual.actual_amount, 0)                    AS actual_amount,
    b.budget_amount - COALESCE(actual.actual_amount, 0)  AS remaining,
    ROUND(100.0 * COALESCE(actual.actual_amount, 0) / NULLIF(b.budget_amount, 0), 1)
                                                          AS pct_spent
FROM {{catalog}}.{{customer_budget_table}} b
LEFT JOIN (
    SELECT
        siteid,
        YEAR(transdate) AS fiscal_year,
        SUM(linecost)   AS actual_amount
    FROM (
        SELECT siteid, startdate AS transdate, linecost
        FROM {{catalog}}.{{silver_schema}}.labtrans
        UNION ALL
        SELECT siteid, transdate, linecost
        FROM {{catalog}}.{{silver_schema}}.matusetrans
        WHERE issuetype IN ('ISSUE', 'RETURN')
    ) all_costs
    GROUP BY siteid, YEAR(transdate)
) actual ON actual.siteid = b.siteid AND actual.fiscal_year = b.fiscal_year
WHERE b.fiscal_year = YEAR(current_date())
ORDER BY pct_spent DESC;
