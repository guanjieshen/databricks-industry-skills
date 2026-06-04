-- =============================================================================
-- PODS ILI Integrity — Severity & Dig-Candidate Views
-- =============================================================================
-- Substitute {{catalog}}.{{gold_schema}} / {{metrics_schema}}. Builds on
-- v_anomalies_enriched (from pods-data-engineering): anomalies + run metadata +
-- pipe attributes + measure_m. Severity is ERF-based, NOT raw depth.
--
-- The safety factor is parameterized in the examples; these views compute the
-- predicted failure pressure and depth, and leave ERF to be applied with the
-- operator's confirmed safety factor (so it is never defaulted silently).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_anomaly_severity
-- Every metal-loss anomaly with depth (in), predicted failure pressure, and
-- %SMYS at MAOP. One row per anomaly per run. Crack/dent feature types are
-- excluded from B31G (metal-loss only) and flagged.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_anomaly_severity
COMMENT 'Per-anomaly integrity severity: depth_in, predicted failure pressure (Modified B31G, metal loss only), %SMYS at MAOP. Apply ERF with the operator safety factor downstream.'
AS
SELECT
    e.feature_id,
    e.run_id,
    e.route_id,
    e.measure_m,
    e.feature_type,
    e.depth_pct,
    e.length_in,
    e.od_in, e.wt_in, e.smys_psi, e.maop_psig,
    e.run_date, e.vendor, e.tool_type,
    {{catalog}}.{{metrics_schema}}.pods_depth_in(e.depth_pct, e.wt_in) AS depth_in,
    CASE
        WHEN upper(e.feature_type) IN ('METAL LOSS', 'MLOSS', 'CORROSION', 'EXT_CORR', 'INT_CORR')
        THEN {{catalog}}.{{metrics_schema}}.pods_failure_pressure_b31g_mod(
                 e.od_in, e.wt_in,
                 {{catalog}}.{{metrics_schema}}.pods_depth_in(e.depth_pct, e.wt_in),
                 e.length_in, e.smys_psi)
        ELSE NULL   -- B31G not valid for cracks/dents/etc.
    END AS pred_failure_pressure_psig,
    {{catalog}}.{{metrics_schema}}.pods_pct_smys(e.maop_psig, e.od_in, e.wt_in, e.smys_psi) AS pct_smys_at_maop,
    CASE
        WHEN upper(e.feature_type) NOT IN ('METAL LOSS', 'MLOSS', 'CORROSION', 'EXT_CORR', 'INT_CORR')
        THEN 'NON_METAL_LOSS — needs a different assessment method'
        WHEN e.od_in IS NULL OR e.wt_in IS NULL OR e.smys_psi IS NULL OR e.maop_psig IS NULL
        THEN 'MISSING_PIPE_ATTRIBUTES — enrich before assessing'
        ELSE 'OK'
    END AS severity_note
FROM {{catalog}}.{{gold_schema}}.v_anomalies_enriched e;


-- -----------------------------------------------------------------------------
-- v_dig_candidates
-- Latest-run metal-loss anomalies ranked by predicted failure pressure
-- (lower = more severe). ERF is applied in queries with the confirmed safety
-- factor. This view does the latest-run selection and severity ordering.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_dig_candidates
COMMENT 'Latest-run metal-loss anomalies ordered by predicted failure pressure (ascending = most severe). Apply ERF threshold with the operator safety factor.'
AS
SELECT s.*
FROM {{catalog}}.{{gold_schema}}.v_anomaly_severity s
JOIN {{catalog}}.{{gold_schema}}.v_latest_ili_run lr
    ON lr.route_id = s.route_id AND lr.run_id = s.run_id
WHERE s.pred_failure_pressure_psig IS NOT NULL;
