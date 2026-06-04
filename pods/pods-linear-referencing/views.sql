-- =============================================================================
-- PODS Linear Referencing — Normalized Event Spine
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} and {{catalog}}.{{gold_schema}}.
-- These views give the module skills ONE route key and ONE measure unit
-- (meters) to build on, so unit/route bugs are fixed in exactly one place.
--
-- IMPORTANT: the column/table names below are CANONICAL PODS concepts. Replace
-- them with the operator's physical names (resolve via the workspace glossary
-- produced by pods-setup). The unit conversions assume ILI stationing in FEET
-- and centerline measures in METERS — adjust to the operator's actual units.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_route_events_m
-- All located features unified as route events with a normalized measure (m).
-- One row per feature; point events have begin_m = end_m.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_route_events_m
COMMENT 'Unified route-event spine: every located PODS feature with route_id + begin_m/end_m in METERS. Point events have begin_m = end_m. Source-of-truth for dynamic-segmentation joins.'
AS
-- Anomalies (ILI) — stationing in FEET in this example operator, converted to m
SELECT
    'ANOMALY'                              AS event_class,
    CAST(f.feature_id AS STRING)           AS event_id,
    f.route_id,
    {{catalog}}.{{metrics_schema}}.pods_ft_to_m(f.begin_stn) AS begin_m,
    {{catalog}}.{{metrics_schema}}.pods_ft_to_m(f.begin_stn) AS end_m,
    f.feature_type                         AS subtype
FROM {{catalog}}.{{silver_schema}}.ili_features f

UNION ALL

-- Assets (valves, welds, fittings) — point route events
SELECT
    'ASSET'                                AS event_class,
    CAST(a.asset_id AS STRING)             AS event_id,
    a.route_id,
    {{catalog}}.{{metrics_schema}}.pods_ft_to_m(a.station_ft) AS begin_m,
    {{catalog}}.{{metrics_schema}}.pods_ft_to_m(a.station_ft) AS end_m,
    a.asset_type                           AS subtype
FROM {{catalog}}.{{silver_schema}}.pipeline_assets a

UNION ALL

-- HCA segments — linear route events, already in METERS
SELECT
    'HCA'                                  AS event_class,
    CAST(h.hca_id AS STRING)               AS event_id,
    h.route_id,
    h.begin_measure_m                      AS begin_m,
    h.end_measure_m                        AS end_m,
    h.hca_type                             AS subtype
FROM {{catalog}}.{{silver_schema}}.hca_segments h;


-- -----------------------------------------------------------------------------
-- v_anomaly_hca_overlap
-- Anomalies tagged with the HCA they fall inside (dynamic segmentation).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_anomaly_hca_overlap
COMMENT 'Each ILI anomaly with the HCA segment it falls inside (NULL if none). Point-in-range on normalized meters.'
AS
SELECT
    a.event_id          AS anomaly_id,
    a.route_id,
    a.begin_m           AS anomaly_m,
    a.subtype           AS feature_type,
    h.event_id          AS hca_id,
    h.subtype           AS hca_type
FROM {{catalog}}.{{gold_schema}}.v_route_events_m a
LEFT JOIN {{catalog}}.{{gold_schema}}.v_route_events_m h
    ON h.event_class = 'HCA'
   AND a.route_id = h.route_id
   AND a.begin_m >= h.begin_m
   AND a.begin_m <  h.end_m
WHERE a.event_class = 'ANOMALY';
