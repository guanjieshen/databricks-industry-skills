-- =============================================================================
-- PODS ILI Integrity — Severity, Clustering & Dig-Candidate Views
-- =============================================================================
-- Substitute {{catalog}}.{{gold_schema}} / {{metrics_schema}}. Builds on
-- v_anomalies_enriched (from pods-data-engineering): anomalies + run metadata +
-- pipe attributes + measure_m + tool_tolerance_pct_wall.
--
-- Contents (views in this file):
--   v_anomaly_severity   — per-anomaly call-depth AND conservative (tolerance-
--                          adjusted) failure pressure + %SMYS; severity_note flags
--   v_anomaly_clusters   — metal-loss features grouped into interacting clusters
--                          (axial interval-merge, default window 3 x wall)
--   v_cluster_severity   — per-cluster effective defect assessed via B31G
--                          (single features fall out as clusters of 1)
--   v_dig_candidates     — clusters on the latest METAL-LOSS run, ranked by
--                          conservative failure pressure (apply ERF + SF in query)
--
-- Severity is ERF-based, NOT raw depth. The safety factor is applied in the
-- examples with the operator's confirmed value (never defaulted silently).
-- Clustering is AXIAL-ONLY screening (see gotchas.md): it conservatively treats
-- the cluster envelope as one defect; true interaction / RSTRENG effective-area
-- is a separate, more rigorous method.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_anomaly_severity
-- One row per anomaly per run. Computes BOTH call-depth and conservative
-- (tolerance-adjusted) failure pressure. Crack/dent feature types are excluded
-- from B31G (metal-loss only) and flagged in severity_note.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_anomaly_severity
COMMENT 'Per-anomaly severity: call-depth and conservative (tolerance-adjusted) predicted failure pressure (Modified B31G, metal loss only) + %SMYS at MAOP. Apply ERF with the operator safety factor downstream.'
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
    e.tool_tolerance_pct_wall,
    e.run_date, e.vendor, e.tool_type,
    {{catalog}}.{{metrics_schema}}.pods_depth_in(e.depth_pct, e.wt_in)      AS depth_in_call,
    {{catalog}}.{{metrics_schema}}.pods_depth_in_tol(e.depth_pct, e.wt_in, e.tool_tolerance_pct_wall) AS depth_in_conservative,
    -- Call-depth failure pressure (metal loss only).
    CASE WHEN upper(e.feature_type) IN ('METAL LOSS','MLOSS','CORROSION','EXT_CORR','INT_CORR','EXTERNAL METAL LOSS','INTERNAL METAL LOSS')
         THEN {{catalog}}.{{metrics_schema}}.pods_failure_pressure_b31g_mod(
                  e.od_in, e.wt_in,
                  {{catalog}}.{{metrics_schema}}.pods_depth_in(e.depth_pct, e.wt_in),
                  e.length_in, e.smys_psi)
         ELSE NULL END AS pred_failure_pressure_call_psig,
    -- Conservative (tolerance-adjusted) failure pressure — preferred for dig
    -- prioritization. NULL when tolerance is unknown (then use the call value
    -- and SAY it's call-depth-only).
    CASE WHEN upper(e.feature_type) IN ('METAL LOSS','MLOSS','CORROSION','EXT_CORR','INT_CORR','EXTERNAL METAL LOSS','INTERNAL METAL LOSS')
         THEN {{catalog}}.{{metrics_schema}}.pods_failure_pressure_b31g_mod(
                  e.od_in, e.wt_in,
                  {{catalog}}.{{metrics_schema}}.pods_depth_in_tol(e.depth_pct, e.wt_in, e.tool_tolerance_pct_wall),
                  e.length_in, e.smys_psi)
         ELSE NULL END AS pred_failure_pressure_conservative_psig,
    {{catalog}}.{{metrics_schema}}.pods_pct_smys(e.maop_psig, e.od_in, e.wt_in, e.smys_psi) AS pct_smys_at_maop,
    CASE
        -- Metal-loss type set is a placeholder — map to the operator's ILI
        -- feature classification via the workspace glossary.
        WHEN upper(e.feature_type) NOT IN ('METAL LOSS','MLOSS','CORROSION','EXT_CORR','INT_CORR','EXTERNAL METAL LOSS','INTERNAL METAL LOSS')
            THEN 'NON_METAL_LOSS — needs a different assessment method'
        WHEN e.od_in IS NULL OR e.wt_in IS NULL OR e.smys_psi IS NULL OR e.maop_psig IS NULL
            THEN 'MISSING_PIPE_ATTRIBUTES — enrich before assessing'
        WHEN e.tool_tolerance_pct_wall IS NULL
            THEN 'CALL_DEPTH_ONLY — tolerance unknown, not POE-adjusted'
        ELSE 'OK'
    END AS severity_note
FROM {{catalog}}.{{gold_schema}}.v_anomalies_enriched e;


-- -----------------------------------------------------------------------------
-- v_anomaly_clusters
-- Groups metal-loss features that interact axially into clusters, per
-- (route_id, run_id), via interval-merge: order by axial begin, start a new
-- cluster when a feature's begin is farther than the interaction window beyond
-- the running-max end of the cluster so far. Window defaults to 3 x wall
-- thickness (configurable). AXIAL ONLY — circumferential clustering needs clock
-- position / width that many exports lack (see gotchas.md). measure_m is assumed
-- to be the feature CENTER; confirm per operator.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_anomaly_clusters
COMMENT 'Metal-loss features grouped into axially-interacting clusters (interval-merge, default window 3x wall). One row per feature with its cluster_id. Screening only; axial-only.'
AS
WITH ml AS (
    SELECT
        feature_id, run_id, route_id, measure_m, depth_pct, length_in,
        od_in, wt_in, smys_psi, maop_psig, tool_tolerance_pct_wall,
        (length_in * 0.0254)                       AS length_m,        -- inches -> meters
        measure_m - (length_in * 0.0254) / 2.0     AS begin_m,
        measure_m + (length_in * 0.0254) / 2.0     AS end_m,
        (3.0 * wt_in * 0.0254)                     AS window_m         -- 3 x wall, configurable
    FROM {{catalog}}.{{gold_schema}}.v_anomaly_severity
    WHERE severity_note IN ('OK', 'CALL_DEPTH_ONLY')   -- metal loss with pipe attributes
),
flagged AS (
    SELECT *,
        CASE
            WHEN LAG(begin_m) OVER (PARTITION BY route_id, run_id ORDER BY begin_m) IS NULL
                THEN 1
            -- new cluster if this feature starts beyond the window past the
            -- furthest end seen so far in the run (running-max handles overlaps).
            WHEN begin_m - MAX(end_m) OVER (
                    PARTITION BY route_id, run_id ORDER BY begin_m
                    ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) > window_m
                THEN 1
            ELSE 0
        END AS is_new_cluster
    FROM ml
),
seq AS (
    SELECT *,
        SUM(is_new_cluster) OVER (PARTITION BY route_id, run_id ORDER BY begin_m) AS cluster_seq
    FROM flagged
)
SELECT
    feature_id, run_id, route_id, measure_m, depth_pct, length_in,
    od_in, wt_in, smys_psi, maop_psig, tool_tolerance_pct_wall,
    begin_m, end_m,
    concat_ws('-', route_id, run_id, CAST(cluster_seq AS STRING)) AS cluster_id
FROM seq;


-- -----------------------------------------------------------------------------
-- v_cluster_severity
-- Assesses each cluster as one effective defect. Effective length = the cluster
-- envelope (conservatively treats inter-feature gaps as corroded). Governing
-- depth = the deepest member (screening). Single features appear as clusters of
-- one. Pipe attributes taken from the governing (deepest) member.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_cluster_severity
COMMENT 'Per-cluster effective-defect severity (Modified B31G). Effective length = cluster envelope; governing depth = deepest member. cluster_member_count=1 => single feature. Screening, axial-only.'
AS
WITH agg AS (
    SELECT
        cluster_id, route_id, run_id,
        COUNT(*)                              AS cluster_member_count,
        MIN(begin_m)                          AS cluster_begin_m,
        MAX(end_m)                            AS cluster_end_m,
        (MAX(end_m) - MIN(begin_m)) / 0.0254  AS effective_length_in,   -- meters -> inches
        MAX(depth_pct)                        AS governing_depth_pct,
        MAX_BY(od_in,  depth_pct)             AS od_in,
        MAX_BY(wt_in,  depth_pct)             AS wt_in,
        MAX_BY(smys_psi, depth_pct)           AS smys_psi,
        MAX_BY(maop_psig, depth_pct)          AS maop_psig,
        MAX_BY(tool_tolerance_pct_wall, depth_pct) AS tool_tolerance_pct_wall
    FROM {{catalog}}.{{gold_schema}}.v_anomaly_clusters
    GROUP BY cluster_id, route_id, run_id
)
SELECT
    a.*,
    CASE WHEN a.cluster_member_count > 1 THEN 'clustered' ELSE 'single' END AS assessment_basis,
    {{catalog}}.{{metrics_schema}}.pods_failure_pressure_b31g_mod(
        a.od_in, a.wt_in,
        {{catalog}}.{{metrics_schema}}.pods_depth_in(a.governing_depth_pct, a.wt_in),
        a.effective_length_in, a.smys_psi) AS pred_failure_pressure_call_psig,
    {{catalog}}.{{metrics_schema}}.pods_failure_pressure_b31g_mod(
        a.od_in, a.wt_in,
        {{catalog}}.{{metrics_schema}}.pods_depth_in_tol(a.governing_depth_pct, a.wt_in, a.tool_tolerance_pct_wall),
        a.effective_length_in, a.smys_psi) AS pred_failure_pressure_conservative_psig
FROM agg a;


-- -----------------------------------------------------------------------------
-- v_dig_candidates
-- Clusters (incl. single features) on the LATEST METAL-LOSS run per route,
-- ranked by conservative failure pressure (lower = more severe). Apply ERF with
-- the operator safety factor in the query. This is the cluster-aware,
-- tool-aware dig list.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_dig_candidates
COMMENT 'Cluster-aware, tool-aware dig list: clusters on the latest metal-loss run ordered by conservative (tolerance-adjusted) predicted failure pressure. Apply ERF threshold with the operator safety factor.'
AS
SELECT
    c.*,
    -- Use the conservative pressure when available, else fall back to call depth.
    COALESCE(c.pred_failure_pressure_conservative_psig, c.pred_failure_pressure_call_psig) AS pred_failure_pressure_psig,
    CASE WHEN c.pred_failure_pressure_conservative_psig IS NULL
         THEN 'call-depth only (tolerance unknown)' ELSE 'tolerance-adjusted' END AS pressure_basis
FROM {{catalog}}.{{gold_schema}}.v_cluster_severity c
JOIN {{catalog}}.{{gold_schema}}.v_latest_metal_loss_run lr
    ON lr.route_id = c.route_id AND lr.run_id = c.run_id
WHERE COALESCE(c.pred_failure_pressure_conservative_psig, c.pred_failure_pressure_call_psig) IS NOT NULL;
