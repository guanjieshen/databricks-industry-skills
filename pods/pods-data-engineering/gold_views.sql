-- =============================================================================
-- PODS Data Engineering — Conformed Gold Layer
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} / {{gold_schema}} / {{metrics_schema}}.
-- This is the analytical contract: ONE route key, ONE measure unit (meters).
-- The canonical event spine lives in pods-linear-referencing/views.sql; this
-- file shows the operator-facing Gold tables that feed it.
-- =============================================================================


-- Latest ILI run per route — the default vintage for "current state" questions.
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_latest_ili_run
COMMENT 'Most recent ILI run per route, with vendor/tool for comparability.'
AS
SELECT route_id, run_id, run_date, vendor, tool_type
FROM (
    SELECT r.*,
           ROW_NUMBER() OVER (PARTITION BY route_id ORDER BY run_date DESC) AS rn
    FROM {{catalog}}.{{silver_schema}}.silver_ili_runs r
)
WHERE rn = 1;


-- Anomalies enriched with run metadata + normalized measure (meters).
-- One row per anomaly per run; measure_m is the single source of position.
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_anomalies_enriched
COMMENT 'ILI anomalies with measure_m (meters), run vendor/tool/date, and pipe attributes for integrity math.'
AS
SELECT
    f.feature_id,
    f.run_id,
    f.route_id,
    f.measure_m,
    f.depth_pct,
    f.length_in,
    f.width_in,
    f.feature_type,
    r.run_date,
    r.vendor,
    r.tool_type,
    p.od_in,
    p.wt_in,
    p.smys_psi,
    p.maop_psig
FROM {{catalog}}.{{gold_schema}}.gold_ili_features_m f
JOIN {{catalog}}.{{silver_schema}}.silver_ili_runs r
    ON r.run_id = f.run_id
-- Pipe attributes applicable at the anomaly's location (range-overlap on meters).
LEFT JOIN {{catalog}}.{{silver_schema}}.pipe_segments_m p
    ON p.route_id = f.route_id
   AND f.measure_m >= p.begin_m
   AND f.measure_m <  p.end_m;
