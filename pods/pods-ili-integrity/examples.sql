-- =============================================================================
-- PODS ILI Integrity — Gold-Standard Query Examples
-- =============================================================================
-- Substitute {{catalog}}.{{gold_schema}} / {{metrics_schema}} and the
-- {{safety_factor}} (confirm with the operator — never default silently).
-- All assume v_anomaly_severity / v_dig_candidates from views.sql.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. "Worst anomalies on line 4"  (ERF-ranked, latest run — NOT depth)
-- -----------------------------------------------------------------------------
-- Assumptions to state back to the user: latest run, ERF ranking, safety factor.
SELECT
    feature_id, measure_m, feature_type, depth_pct, length_in,
    ROUND(pred_failure_pressure_psig, 0) AS pred_fail_psig,
    ROUND({{catalog}}.{{metrics_schema}}.pods_erf(maop_psig, pred_failure_pressure_psig, {{safety_factor}}), 3) AS erf,
    vendor, tool_type, run_date
FROM {{catalog}}.{{gold_schema}}.v_dig_candidates
WHERE route_id = '{{route_id}}'
ORDER BY erf DESC
LIMIT 25;


-- -----------------------------------------------------------------------------
-- 2. "Where do I dig"  (immediate vs scheduled by ERF)
-- -----------------------------------------------------------------------------
SELECT
    feature_id, measure_m, depth_pct, length_in,
    ROUND({{catalog}}.{{metrics_schema}}.pods_erf(maop_psig, pred_failure_pressure_psig, {{safety_factor}}), 3) AS erf,
    CASE
        WHEN {{catalog}}.{{metrics_schema}}.pods_erf(maop_psig, pred_failure_pressure_psig, {{safety_factor}}) >= 1.0
            THEN 'IMMEDIATE (ERF >= 1)'
        WHEN {{catalog}}.{{metrics_schema}}.pods_erf(maop_psig, pred_failure_pressure_psig, {{safety_factor}}) >= 0.8
            THEN 'SCHEDULED'
        ELSE 'MONITOR'
    END AS response_class
FROM {{catalog}}.{{gold_schema}}.v_dig_candidates
WHERE route_id = '{{route_id}}'
ORDER BY erf DESC;


-- -----------------------------------------------------------------------------
-- 3. %SMYS at MAOP for the deepest metal-loss features
-- -----------------------------------------------------------------------------
SELECT feature_id, measure_m, depth_pct,
       ROUND(pct_smys_at_maop, 1) AS pct_smys_at_maop
FROM {{catalog}}.{{gold_schema}}.v_anomaly_severity
WHERE route_id = '{{route_id}}'
  AND severity_note = 'OK'
ORDER BY depth_pct DESC
LIMIT 25;


-- -----------------------------------------------------------------------------
-- 4. "Compare the last two runs on line 4"  (growth + comparability warning)
-- -----------------------------------------------------------------------------
-- Box-match by measure within tolerance {{tol_m}}. SURFACE vendor/tool of each.
WITH runs AS (
    SELECT run_id, run_date, vendor, tool_type,
           ROW_NUMBER() OVER (ORDER BY run_date DESC) AS rn
    FROM {{catalog}}.{{gold_schema}}.v_latest_ili_run    -- replace with per-line run list if needed
    WHERE route_id = '{{route_id}}'
),
latest AS (SELECT * FROM {{catalog}}.{{gold_schema}}.v_anomaly_severity
           WHERE route_id = '{{route_id}}' AND run_id = (SELECT run_id FROM runs WHERE rn = 1)),
prev   AS (SELECT * FROM {{catalog}}.{{gold_schema}}.v_anomaly_severity
           WHERE route_id = '{{route_id}}' AND run_id = (SELECT run_id FROM runs WHERE rn = 2))
SELECT
    l.feature_id AS latest_id, p.feature_id AS prev_id,
    l.measure_m, ABS(l.measure_m - p.measure_m) AS match_sep_m,
    p.depth_pct AS prev_depth_pct, l.depth_pct AS latest_depth_pct,
    (l.depth_pct - p.depth_pct) AS depth_change_pct,
    l.vendor AS latest_vendor, l.tool_type AS latest_tool,
    p.vendor AS prev_vendor,  p.tool_type AS prev_tool,
    CASE WHEN l.tool_type <> p.tool_type OR l.vendor <> p.vendor
         THEN 'WARNING: different tool/vendor — growth may reflect tool variance, not real corrosion'
         ELSE 'comparable tooling' END AS comparability
FROM latest l
JOIN prev p
  ON p.route_id = l.route_id
 AND p.feature_type = l.feature_type
 AND ABS(l.measure_m - p.measure_m) <= {{tol_m}}
ORDER BY depth_change_pct DESC;


-- -----------------------------------------------------------------------------
-- 5. Features needing a non-B31G method or attribute enrichment (transparency)
-- -----------------------------------------------------------------------------
-- Surface what was EXCLUDED from the ERF ranking so coverage is honest.
SELECT severity_note, COUNT(*) AS feature_count
FROM {{catalog}}.{{gold_schema}}.v_anomaly_severity
WHERE route_id = '{{route_id}}'
GROUP BY severity_note;
