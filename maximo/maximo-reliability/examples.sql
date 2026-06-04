-- =============================================================================
-- Maximo Reliability — Gold-Standard Query Examples
-- =============================================================================
-- Each block is a parameterized template tied to a single analytical question.
-- Substitute {{catalog}}.{{gold_schema}} (e.g. eam.maximo_gold) and
-- {{catalog}}.{{metrics_schema}} (e.g. eam.maximo_metrics) before running.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. MTBF by asset class, last 12 months
-- -----------------------------------------------------------------------------
-- Trigger: "MTBF for centrifugal pumps last year"
SELECT
    {{catalog}}.{{metrics_schema}}.mtbf(
        {{asset_class_id}},
        current_timestamp() - INTERVAL 365 DAYS,
        current_timestamp()
    ) AS mtbf_hours;


-- -----------------------------------------------------------------------------
-- 2. MTTR by asset class, last quarter
-- -----------------------------------------------------------------------------
-- Trigger: "MTTR for compressors Q3"
SELECT
    {{catalog}}.{{metrics_schema}}.mttr(
        {{asset_class_id}},
        '{{quarter_start}}',
        '{{quarter_end}}'
    ) AS mttr_hours;


-- -----------------------------------------------------------------------------
-- 3. PM compliance by site, last quarter
-- -----------------------------------------------------------------------------
-- Trigger: "PM compliance for Q3 by site"
SELECT
    siteid,
    {{catalog}}.{{metrics_schema}}.pm_compliance(
        siteid,
        '{{quarter_start}}',
        '{{quarter_end}}'
    ) AS pm_compliance_pct
FROM (SELECT DISTINCT siteid FROM {{catalog}}.{{gold_schema}}.v_pm_schedule)
ORDER BY pm_compliance_pct DESC;


-- -----------------------------------------------------------------------------
-- 4. Failure-mode pareto for completed WOs on a class of asset
-- -----------------------------------------------------------------------------
-- Trigger: "top failure modes for compressors"
WITH problems AS (
    SELECT failurecode AS problem_code, description AS problem_desc
    FROM {{catalog}}.{{silver_schema}}.failurecode
    WHERE type = 'PROBLEM'
)
SELECT
    p.problem_desc,
    COUNT(*)                                   AS event_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM {{catalog}}.{{gold_schema}}.v_failure_events fe
JOIN problems p
    ON fe.failurecode = p.problem_code
    OR p.problem_code IN (
        SELECT failurecode
        FROM {{catalog}}.{{silver_schema}}.failurecode
        WHERE failurecode = fe.failurecode
           OR parent = fe.failurecode
    )
WHERE fe.asset_class_id = {{asset_class_id}}
  AND fe.event_start >= add_months(current_date(), -12)
GROUP BY p.problem_desc
ORDER BY event_count DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- 5. Bad-actor assets by failure count
-- -----------------------------------------------------------------------------
-- Trigger: "bad actor assets", "which assets fail the most"
SELECT
    fe.assetnum,
    fe.asset_class_id,
    a.description,
    a.criticality,
    COUNT(*) AS failure_count_last_12mo
FROM {{catalog}}.{{gold_schema}}.v_failure_events fe
JOIN {{catalog}}.{{silver_schema}}.asset a
    ON a.assetnum = fe.assetnum AND a.__END_AT IS NULL
WHERE fe.event_start >= add_months(current_date(), -12)
GROUP BY fe.assetnum, fe.asset_class_id, a.description, a.criticality
ORDER BY failure_count_last_12mo DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- 6. Bad-actor assets weighted by criticality
-- -----------------------------------------------------------------------------
-- Trigger: "bad actors weighted by criticality"
SELECT
    fe.assetnum,
    a.description,
    a.criticality,
    COUNT(*) AS failure_count,
    COUNT(*) * COALESCE(a.criticality, 1) AS criticality_weighted_failures
FROM {{catalog}}.{{gold_schema}}.v_failure_events fe
JOIN {{catalog}}.{{silver_schema}}.asset a
    ON a.assetnum = fe.assetnum AND a.__END_AT IS NULL
WHERE fe.event_start >= add_months(current_date(), -12)
GROUP BY fe.assetnum, a.description, a.criticality
ORDER BY criticality_weighted_failures DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- 7. Time-since-last-failure for an asset
-- -----------------------------------------------------------------------------
-- Trigger: "how long since the last failure on asset X"
SELECT
    {{catalog}}.{{metrics_schema}}.time_since_last_failure(
        '{{assetnum}}',
        '{{siteid}}'
    ) AS hours_since_last_failure;


-- -----------------------------------------------------------------------------
-- 8. PMs overdue right now
-- -----------------------------------------------------------------------------
-- Trigger: "what PMs are overdue"
SELECT
    pmnum, siteid, assetnum, nextdate, days_overdue, due_bucket
FROM {{catalog}}.{{gold_schema}}.v_pm_schedule
WHERE due_bucket = 'OVERDUE'
ORDER BY days_overdue DESC
LIMIT 100;


-- -----------------------------------------------------------------------------
-- 9. Meter readings exceeding action threshold
-- -----------------------------------------------------------------------------
-- Trigger: "assets with meter readings above threshold"
SELECT
    mr.assetnum, mr.siteid, mr.metername, mr.readingdate, mr.reading,
    am.actionlimithi
FROM {{catalog}}.{{silver_schema}}.meterreading mr
JOIN {{catalog}}.{{silver_schema}}.assetmeter am
    ON am.assetnum = mr.assetnum AND am.siteid = mr.siteid AND am.metername = mr.metername
   AND am.__END_AT IS NULL
WHERE am.actionlimithi IS NOT NULL
  AND mr.reading > am.actionlimithi
  AND mr.readingdate >= current_date() - INTERVAL 30 DAYS
ORDER BY mr.readingdate DESC
LIMIT 100;
