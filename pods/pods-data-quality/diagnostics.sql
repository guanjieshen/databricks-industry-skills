-- =============================================================================
-- PODS Data Quality — Diagnostic Queries
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} / {{gold_schema}}. Run in the order
-- of the playbook (unit inconsistency first — it's the most common).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Unit sanity: profile measure ranges to spot feet-vs-meter mismatches
-- -----------------------------------------------------------------------------
-- Compare the max measure of two columns that SHOULD be the same unit.
-- A ~3.28x ratio between them is the tell-tale foot/meter mismatch.
SELECT 'ili_features.begin_stn'  AS column, MIN(begin_stn) AS min_v, MAX(begin_stn) AS max_v
FROM {{catalog}}.{{silver_schema}}.silver_ili_features
UNION ALL
SELECT 'hca_segments.end_measure', MIN(end_measure_m), MAX(end_measure_m)
FROM {{catalog}}.{{silver_schema}}.hca_segments;


-- -----------------------------------------------------------------------------
-- 2. Non-monotonic measures (reversals) within a route
-- -----------------------------------------------------------------------------
-- Flags routes where ordered measures decrease — breaks range joins.
WITH ordered AS (
    SELECT route_id, measure_m,
           LAG(measure_m) OVER (PARTITION BY route_id ORDER BY measure_m) AS prev_m
    FROM {{catalog}}.{{gold_schema}}.gold_ili_features_m
)
SELECT route_id, COUNT(*) AS reversal_count
FROM ordered
WHERE prev_m IS NOT NULL AND measure_m < prev_m
GROUP BY route_id
ORDER BY reversal_count DESC;


-- -----------------------------------------------------------------------------
-- 3. Route gaps and overlaps in linear segments (e.g. HCA / pipe attributes)
-- -----------------------------------------------------------------------------
-- Within a route, ordered by begin_m: a gap = next begin > current end;
-- an overlap = next begin < current end.
WITH seg AS (
    SELECT route_id, begin_m, end_m,
           LEAD(begin_m) OVER (PARTITION BY route_id ORDER BY begin_m) AS next_begin_m
    FROM {{catalog}}.{{silver_schema}}.pipe_segments_m
)
SELECT route_id,
       SUM(CASE WHEN next_begin_m > end_m THEN 1 ELSE 0 END) AS gap_count,
       SUM(CASE WHEN next_begin_m < end_m THEN 1 ELSE 0 END) AS overlap_count
FROM seg
WHERE next_begin_m IS NOT NULL
GROUP BY route_id
HAVING gap_count > 0 OR overlap_count > 0
ORDER BY gap_count + overlap_count DESC;


-- -----------------------------------------------------------------------------
-- 4. Orphan events: anomalies on a route with no centerline / route row
-- -----------------------------------------------------------------------------
SELECT f.route_id, COUNT(*) AS orphan_anomalies
FROM {{catalog}}.{{gold_schema}}.gold_ili_features_m f
LEFT JOIN {{catalog}}.{{silver_schema}}.centerline c
    ON c.route_id = f.route_id
WHERE c.route_id IS NULL
GROUP BY f.route_id
ORDER BY orphan_anomalies DESC;


-- -----------------------------------------------------------------------------
-- 5. Duplicate anomalies across runs (missing vintage filter symptom)
-- -----------------------------------------------------------------------------
SELECT feature_id, COUNT(DISTINCT run_id) AS run_count
FROM {{catalog}}.{{gold_schema}}.gold_ili_features_m
GROUP BY feature_id
HAVING COUNT(DISTINCT run_id) > 1
ORDER BY run_count DESC
LIMIT 100;


-- -----------------------------------------------------------------------------
-- 6. Anomalies missing pipe attributes at their location (B31G/ERF will be NULL)
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS anomalies_missing_attributes
FROM {{catalog}}.{{gold_schema}}.v_anomalies_enriched
WHERE od_in IS NULL OR wt_in IS NULL OR smys_psi IS NULL OR maop_psig IS NULL;
