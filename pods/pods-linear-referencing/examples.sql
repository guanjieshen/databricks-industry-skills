-- =============================================================================
-- PODS Linear Referencing — Gold-Standard Query Examples
-- =============================================================================
-- Substitute {{catalog}}.{{gold_schema}}, {{catalog}}.{{silver_schema}},
-- {{catalog}}.{{metrics_schema}}. All measures normalized to METERS via
-- v_route_events_m. Confirm route_id and units via the workspace glossary first.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Everything between two stations on a route
-- -----------------------------------------------------------------------------
-- Trigger: "what's between station 1240+00 and 1310+00 on line 4"
-- Stations are FEET; convert to meters to match the spine.
SELECT event_class, subtype, event_id,
       {{catalog}}.{{metrics_schema}}.pods_measure_to_milepost(begin_m, 'm') AS milepost
FROM {{catalog}}.{{gold_schema}}.v_route_events_m
WHERE route_id = '{{route_id}}'
  AND begin_m BETWEEN {{catalog}}.{{metrics_schema}}.pods_ft_to_m(
                        {{catalog}}.{{metrics_schema}}.pods_station_to_measure('1240+00'))
                  AND {{catalog}}.{{metrics_schema}}.pods_ft_to_m(
                        {{catalog}}.{{metrics_schema}}.pods_station_to_measure('1310+00'))
ORDER BY begin_m;


-- -----------------------------------------------------------------------------
-- 2. Features near a milepost (proximity = measure window, NOT geometry)
-- -----------------------------------------------------------------------------
-- Trigger: "what's near MP 42 on line 4"
SELECT event_class, subtype, event_id, begin_m
FROM {{catalog}}.{{gold_schema}}.v_route_events_m
WHERE route_id = '{{route_id}}'
  AND begin_m BETWEEN (42 * 1609.344) - {{window_m}}   -- MP 42 -> meters
                  AND (42 * 1609.344) + {{window_m}}
ORDER BY begin_m;


-- -----------------------------------------------------------------------------
-- 3. Anomalies inside an HCA (range-overlap / dynamic segmentation)
-- -----------------------------------------------------------------------------
-- Trigger: "which anomalies are in an HCA on line 4"
SELECT anomaly_id, route_id, anomaly_m, feature_type, hca_id, hca_type
FROM {{catalog}}.{{gold_schema}}.v_anomaly_hca_overlap
WHERE route_id = '{{route_id}}'
  AND hca_id IS NOT NULL
ORDER BY anomaly_m;


-- -----------------------------------------------------------------------------
-- 4. Interacting / co-located threats within a window
-- -----------------------------------------------------------------------------
-- Trigger: "interacting threats near station 1240 on line 4"
-- Looks for DIFFERENT feature types within an interaction window.
WITH near AS (
    SELECT *
    FROM {{catalog}}.{{gold_schema}}.v_route_events_m
    WHERE event_class = 'ANOMALY'
      AND route_id = '{{route_id}}'
      AND begin_m BETWEEN {{target_m}} - {{window_m}} AND {{target_m}} + {{window_m}}
)
SELECT a.event_id AS a_id, b.event_id AS b_id,
       a.subtype  AS a_type, b.subtype AS b_type,
       ROUND(ABS(a.begin_m - b.begin_m), 3) AS separation_m
FROM near a
JOIN near b
  ON a.route_id = b.route_id
 AND a.event_id < b.event_id
 AND a.subtype <> b.subtype
 AND ABS(a.begin_m - b.begin_m) <= {{interaction_window_m}}
ORDER BY separation_m;


-- -----------------------------------------------------------------------------
-- 5. Next valve downstream of an anomaly
-- -----------------------------------------------------------------------------
-- Trigger: "what's the next valve downstream of anomaly X"
-- NOTE: assumes increasing measure = downstream. Confirm flow direction.
SELECT event_id, subtype, begin_m,
       begin_m - {{anomaly_m}} AS distance_downstream_m
FROM {{catalog}}.{{gold_schema}}.v_route_events_m
WHERE event_class = 'ASSET'
  AND subtype = 'VALVE'
  AND route_id = '{{route_id}}'
  AND begin_m >= {{anomaly_m}}
ORDER BY begin_m ASC
LIMIT 1;


-- -----------------------------------------------------------------------------
-- 6. Coating / condition covering an anomaly (range contains point)
-- -----------------------------------------------------------------------------
-- Trigger: "what coating is on the anomaly at station X"
SELECT a.event_id AS anomaly_id, a.begin_m AS anomaly_m,
       c.event_id AS condition_id, c.subtype AS condition_type
FROM {{catalog}}.{{gold_schema}}.v_route_events_m a
JOIN {{catalog}}.{{silver_schema}}.conditions_m c
  ON a.route_id = c.route_id
 AND {{catalog}}.{{metrics_schema}}.pods_events_overlap(a.begin_m, a.end_m, c.begin_m, c.end_m)
WHERE a.event_class = 'ANOMALY'
  AND a.event_id = '{{anomaly_id}}';
