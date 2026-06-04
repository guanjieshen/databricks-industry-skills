-- =============================================================================
-- PODS ILI Integrity — Gold-Standard Query Examples
-- =============================================================================
-- Substitute {{catalog}}.{{gold_schema}} / {{silver_schema}} / {{metrics_schema}}
-- and {{safety_factor}} (confirm with the operator — never default silently).
-- Build on the cluster-aware, tool-aware views in views.sql.
--
-- Contents:
--   1. Worst anomalies (conservative ERF, latest metal-loss run, clustered)
--   2. Where do I dig (ILLUSTRATIVE reg-tied, configurable thresholds)
--   3. %SMYS at MAOP for the deepest features
--   4. Cluster report (effective defects)
--   5. Compare last two metal-loss runs (growth + comparability)
--   6. Coverage / transparency (what was excluded)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. "Worst anomalies on line 4"  (conservative ERF, latest MFL run, clustered)
-- -----------------------------------------------------------------------------
-- State back to the user: latest METAL-LOSS run, ERF on tolerance-adjusted depth,
-- clustered, safety factor used. v_dig_candidates already selects the latest
-- metal-loss run and collapses interacting features into clusters.
SELECT
    cluster_id, assessment_basis, cluster_member_count,
    ROUND(cluster_begin_m, 1) AS begin_m, ROUND(effective_length_in, 1) AS eff_length_in,
    governing_depth_pct,
    ROUND(pred_failure_pressure_psig, 0) AS pred_fail_psig, pressure_basis,
    ROUND({{catalog}}.{{metrics_schema}}.pods_erf(maop_psig, pred_failure_pressure_psig, {{safety_factor}}), 3) AS erf
FROM {{catalog}}.{{gold_schema}}.v_dig_candidates
WHERE route_id = '{{route_id}}'
ORDER BY erf DESC
LIMIT 25;


-- -----------------------------------------------------------------------------
-- 2. "Where do I dig"  (ILLUSTRATIVE response classes — NOT a compliance ruling)
-- -----------------------------------------------------------------------------
-- The thresholds below are ILLUSTRATIVE defaults. Real response criteria are
-- defined by the regulation and the operator's IM program:
--   * Hazardous liquid:  49 CFR 195.452(h)  (immediate / 60-day / 180-day)
--   * Gas transmission:  49 CFR 192.933 + ASME B31.8S
-- Confirm the operator's actual ERF thresholds and condition definitions; pass
-- them as parameters. Do not present this as a regulatory determination.
SELECT
    cluster_id, assessment_basis, cluster_member_count,
    ROUND(cluster_begin_m, 1) AS begin_m, governing_depth_pct,
    ROUND({{catalog}}.{{metrics_schema}}.pods_erf(maop_psig, pred_failure_pressure_psig, {{safety_factor}}), 3) AS erf,
    pressure_basis,
    CASE
        WHEN {{catalog}}.{{metrics_schema}}.pods_erf(maop_psig, pred_failure_pressure_psig, {{safety_factor}}) >= {{immediate_erf}}
            THEN 'review as IMMEDIATE candidate (illustrative)'
        WHEN {{catalog}}.{{metrics_schema}}.pods_erf(maop_psig, pred_failure_pressure_psig, {{safety_factor}}) >= {{scheduled_erf}}
            THEN 'review as SCHEDULED candidate (illustrative)'
        ELSE 'monitor (illustrative)'
    END AS response_class_illustrative
FROM {{catalog}}.{{gold_schema}}.v_dig_candidates
WHERE route_id = '{{route_id}}'
ORDER BY erf DESC;


-- -----------------------------------------------------------------------------
-- 3. %SMYS at MAOP for the deepest metal-loss features
-- -----------------------------------------------------------------------------
SELECT feature_id, measure_m, depth_pct,
       ROUND(pct_smys_at_maop, 1) AS pct_smys_at_maop, severity_note
FROM {{catalog}}.{{gold_schema}}.v_anomaly_severity
WHERE route_id = '{{route_id}}'
  AND severity_note IN ('OK', 'CALL_DEPTH_ONLY')
ORDER BY depth_pct DESC
LIMIT 25;


-- -----------------------------------------------------------------------------
-- 4. Cluster report — interacting features assessed as effective defects
-- -----------------------------------------------------------------------------
-- Trigger: "are there any interacting / clustered corrosion features on line 4"
SELECT
    cluster_id, cluster_member_count, assessment_basis,
    ROUND(cluster_begin_m, 1) AS begin_m, ROUND(cluster_end_m, 1) AS end_m,
    ROUND(effective_length_in, 1) AS eff_length_in, governing_depth_pct,
    ROUND(pred_failure_pressure_conservative_psig, 0) AS pred_fail_psig
FROM {{catalog}}.{{gold_schema}}.v_cluster_severity
WHERE route_id = '{{route_id}}'
  AND cluster_member_count > 1          -- the genuinely interacting ones
ORDER BY pred_failure_pressure_conservative_psig ASC NULLS LAST;


-- -----------------------------------------------------------------------------
-- 5. "Compare the last two runs on line 4"  (metal-loss runs only + comparability)
-- -----------------------------------------------------------------------------
-- Select the latest two METAL-LOSS runs (not whatever ran last). Box-match by
-- measure within tolerance {{tol_m}}. SURFACE vendor/tool of each run.
WITH ml_runs AS (
    SELECT run_id, run_date, vendor, tool_type,
           ROW_NUMBER() OVER (ORDER BY run_date DESC) AS rn
    FROM {{catalog}}.{{silver_schema}}.silver_ili_runs
    WHERE route_id = '{{route_id}}'
      AND upper(tool_type) IN ('MFL', 'UT')      -- metal-loss tools; glossary-configurable
),
latest AS (SELECT * FROM {{catalog}}.{{gold_schema}}.v_anomaly_severity
           WHERE route_id = '{{route_id}}' AND run_id = (SELECT run_id FROM ml_runs WHERE rn = 1)),
prev   AS (SELECT * FROM {{catalog}}.{{gold_schema}}.v_anomaly_severity
           WHERE route_id = '{{route_id}}' AND run_id = (SELECT run_id FROM ml_runs WHERE rn = 2))
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
-- 6. Coverage / transparency — what was EXCLUDED from the ERF ranking
-- -----------------------------------------------------------------------------
-- Surface non-metal-loss, missing-attribute, and call-depth-only counts so the
-- engineer knows the dig list's coverage and caveats.
SELECT severity_note, COUNT(*) AS feature_count
FROM {{catalog}}.{{gold_schema}}.v_anomaly_severity
WHERE route_id = '{{route_id}}'
GROUP BY severity_note
ORDER BY feature_count DESC;
