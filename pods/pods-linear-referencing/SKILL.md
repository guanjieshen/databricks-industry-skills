---
name: pods-linear-referencing
description: |
  THE keystone PODS skill. Use for any question that locates, ranges, or
  overlays features along a pipeline by station / measure / milepost — "what
  assets are between station 1240+00 and 1310+00", "what's near MP 42",
  "which anomalies fall inside an HCA", "interacting threats", "co-located
  features", "convert stationing to measure", "what valve is upstream of this
  anomaly". Provides the route-measure / dynamic-segmentation SQL patterns,
  station<->measure<->milepost conversion, foot/meter unit normalization, and
  range-overlap joins that Genie cannot do correctly unaided. Triggers on:
  "between stations", "near milepost", "along the route", "dynamic
  segmentation", "linear referencing", "LRS", "route event", "overlap",
  "stationing", "measure", "centerline".
tags:
  - data-source:pods
  - tier:foundation
  - industry:oil-and-gas
  - persona:integrity-engineer
  - persona:gis-analyst
  - persona:da-platform
---

# PODS Linear Referencing

The PODS model locates almost everything — anomalies, welds, valves, HCAs, coating, pressure, class location — as **route events** on an **M-aware centerline**, not as independent geometry. This skill is how you query that correctly. It composes under `pods-ili-integrity`, `pods-consequence-hca`, and every other module: they all reduce to route-measure operations defined here.

**This is where unaided Genie fails hardest and most invisibly** (unit mismatches, naive distance filters, broken overlaps). Treat the patterns here as authoritative — do not improvise LRS math.

## When to use

- "What assets / welds / valves are between station X and station Y?"
- "What's near MP 42 / station 1240+00?" (proximity along the route)
- "Which anomalies fall inside an HCA?" / "what overlaps this segment?"
- "Interacting / co-located threats" (multiple features within a window)
- "Convert this stationing to a measure" / "what milepost is this measure?"
- "What's the next valve downstream of this anomaly?"
- Any question where the answer depends on **position along the pipe**, not map distance

## Pre-flight (per session, then cache)

1. **Units of each measure column.** Ask or resolve via glossary: is ILI stationing in **feet** or **meters**? Is the centerline / HCA measure in **feet** or **meters**? **They are frequently different.** Record the conversion. This is the single most important check in the whole family.
2. **Route key.** What column identifies the route/line, and does it match across the centerline, the event tables, and the HCA table? (Often `route_id`, `line_no`, `line_id` — resolve via glossary.)
3. **Network used.** Is position carried as a continuous **measure** (`CONTINUOUS_MEAS_NETWORK`) or as engineering **stations** (`ENGINEERING_STATION_NETWORK`), or both? Most analytical joins use a normalized numeric measure.

## Core concepts (read once)

- A **route** is a linear feature with monotonically increasing/decreasing **measures (M)**. Every feature on it is located by measure, not its own geometry.
- A **point event** = `(route_id, measure)`. A **linear event** = `(route_id, begin_measure, end_measure)`.
- **Dynamic segmentation** = deriving a feature's extent/geometry on the fly from route + measure(s). In a relational lakehouse you implement it with **range-overlap joins**, not Esri's engine.
- **Stationing** `1240+00` = `124000` ft = the value `124000` in feet-based measure. Mileposts are measure in miles.

## The patterns (use these; don't reinvent)

### 1. Normalize units FIRST — always
Before any cross-column measure comparison, convert everything to one unit (recommend **meters**). If ILI stationing is feet and centerline is meters:

```sql
-- feet -> meters: multiply by 0.3048
(f.begin_stn * 0.3048) AS measure_m
```

The shipped UDFs in [metric_udfs.sql](metric_udfs.sql) (`pods_ft_to_m`, `pods_station_to_measure`, `pods_measure_to_milepost`) centralize this. Use them so the conversion is consistent and auditable.

### 2. Features between two stations (point events on a route)

```sql
SELECT *
FROM events e
WHERE e.route_id = '{{route_id}}'
  AND e.measure_m BETWEEN {{begin_m}} AND {{end_m}}
ORDER BY e.measure_m;
```

### 3. Range-overlap join (linear event ∩ linear event) — the heart of dynamic segmentation
"Which anomalies fall inside an HCA?" / "what coating covers this segment?":

```sql
SELECT a.*, h.hca_id
FROM anomalies a
JOIN hca_segments h
  ON a.route_id = h.route_id
 AND a.measure_m <  h.end_measure_m      -- overlap test (half-open intervals)
 AND a.measure_m >= h.begin_measure_m;   -- point event inside a range
```

For **range ∩ range** (two linear events overlapping at all):

```sql
... ON a.route_id = b.route_id
   AND a.begin_m < b.end_m
   AND a.end_m   > b.begin_m;            -- classic interval-overlap predicate
```

### 4. Proximity along the route ("near MP 42")
Proximity is a **measure window**, not ST_DWithin:

```sql
WHERE route_id = '{{route_id}}'
  AND measure_m BETWEEN {{target_m}} - {{window_m}}
                    AND {{target_m}} + {{window_m}}
```

### 5. Co-located / interacting features (self-join within a window)
"Interacting threats near station 1240" = different feature types within an interaction window (e.g. ASME B31.8S dent+metal-loss interaction):

```sql
WITH near AS (
  SELECT * FROM anomalies
  WHERE route_id = '{{route_id}}'
    AND measure_m BETWEEN {{target_m}} - {{window_m}} AND {{target_m}} + {{window_m}}
)
SELECT a.feature_id AS a_id, b.feature_id AS b_id,
       a.feature_type AS a_type, b.feature_type AS b_type,
       ABS(a.measure_m - b.measure_m) AS separation_m
FROM near a
JOIN near b
  ON a.route_id = b.route_id
 AND a.feature_id < b.feature_id          -- avoid self & duplicate pairs
 AND a.feature_type <> b.feature_type     -- different threat types
 AND ABS(a.measure_m - b.measure_m) <= {{interaction_window_m}};
```

### 6. Nearest feature upstream/downstream
"Next valve downstream of this anomaly":

```sql
SELECT * FROM valves
WHERE route_id = '{{route_id}}'
  AND measure_m >= {{anomaly_m}}          -- downstream = increasing measure (confirm direction!)
ORDER BY measure_m ASC
LIMIT 1;
```

> Confirm flow direction with the user / Operations data — "downstream" is increasing measure only if the route is digitized with flow.

See [examples.sql](examples.sql) for fully worked, parameterized versions, and [views.sql](views.sql) for `v_route_events_m` (a normalized, unit-converted event spine that the module skills build on).

## Workflow priority

1. **Normalized view** `v_route_events_m` in [views.sql](views.sql) — one measure unit, one route key.
2. **Conversion UDFs** in [metric_udfs.sql](metric_udfs.sql) — `pods_ft_to_m`, `pods_station_to_measure`, `pods_measure_to_milepost`, `pods_events_overlap`.
3. **Parameterized patterns** in [examples.sql](examples.sql).
4. **Raw tables** — last resort, and only after units/route-key are confirmed.

## What NOT to do

- **Don't join measures of different units.** Convert to a common unit first. (The invisible ~3.28× error.)
- **Don't use spatial distance (`ST_DWithin`, geometry) for "near station / between stations".** Position along the pipe is a *measure* operation. Geometry distance answers a different question ("near this map point") and is usually not what an integrity engineer means.
- **Don't assume increasing measure = downstream.** Confirm digitization/flow direction.
- **Don't forget the `route_id` in overlap joins.** Without it you overlap features from different lines — a silent cross-line error.
- **Don't treat stations as plain numbers across routes.** `1240+00` on line A is unrelated to `1240+00` on line B.
- **Don't fabricate the measure/route column names.** Resolve via the glossary; ask if unknown.

## References

- [examples.sql](examples.sql) — parameterized route-measure patterns
- [views.sql](views.sql) — `v_route_events_m` normalized event spine
- [metric_udfs.sql](metric_udfs.sql) — unit conversion + overlap UDFs
- [schema.md](schema.md) — LRS feature classes and columns
- [gotchas.md](gotchas.md) — units, direction, calibration, monotonicity
- Esri APR LRS data model: `https://pro.arcgis.com/en/pro-app/latest/help/production/location-referencing-pipelines/alrs-data-model.htm`
