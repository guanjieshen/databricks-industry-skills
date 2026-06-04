# PODS Linear Referencing — Schema Reference

For the full PODS model map, see `pods-overview/SKILL.md`. This file focuses on the linear-referencing feature classes and the columns route-measure queries depend on.

> **All names here are canonical PODS concepts.** Operators "conform to PODS but not exactly" — resolve every name to the physical column via the `<customer>-pods-glossary` workspace skill (produced by `pods-setup`), or ask. Do not assume these names exist physically.

## The LRS feature classes

### `CENTERLINE`
The single source of polyline geometry for the LRS. Each centerline feature represents roughly one unit of pipe. M-aware (carries measure values). Routes are built on centerlines; multiple routes/networks can share a centerline.

Key concepts:
- `geom` — the polyline geometry (Databricks `GEOMETRY`/`GEOGRAPHY` if loaded spatially)
- A route key tying the centerline to its route(s)

### `CONTINUOUS_MEAS_NETWORK`
Continuous, uninterrupted **measure** values along a route. PODS 7's replacement for the legacy "PODS Routes." This is the network most analytical joins use.
- `route_id` — route identifier
- `measure` — continuous position along the route (confirm UNIT: feet or meters)
- `NETWORK_ID` — domain value `ContinuousMeasureNetwork`

### `ENGINEERING_STATION_NETWORK`
Engineering **station** values along each route (e.g. `1240+00`). PODS 7's replacement for the legacy "PODS Series." Used for human-facing stationing and as-built references.
- `route_id`
- `station` — engineering station notation
- `NETWORK_ID` — domain value `EngineeringStationNetwork`

### Calibration points
Tie measures to known real-world positions; used to (re)calibrate routes. Relevant when measures drift or after re-survey.

## Route-event tables (located features)

Every located feature carries, at minimum:
- A **route key** (`route_id` / `line_no` / `line_id`)
- A **measure** for point events, OR **begin/end measures** for linear events
- A **unit** (often implicit — resolve via glossary!)

Common event tables (canonical concepts):

| Concept | Event type | Locates by |
|---|---|---|
| ILI anomalies / features | point | `(route_id, station/measure)` |
| Welds, valves, fittings, casings | point | `(route_id, station/measure)` |
| HCA segments | linear | `(route_id, begin_m, end_m)` |
| Coating / condition / depth-of-cover | linear | `(route_id, begin_m, end_m)` |
| Operating pressure / MAOP / class location | linear | `(route_id, begin_m, end_m)` |

## Units — the critical column metadata

The most important thing to record per measure column is its **unit**:

| Column source | Typical unit | Note |
|---|---|---|
| ILI stationing | **feet** | Very common; `1240+00` notation = feet |
| Centerline / continuous measure | **meters** OR feet | Operator-dependent — CONFIRM |
| HCA segments | **meters** OR feet | Often matches centerline |
| Milepost (business term) | **miles** | Conversational, not always a stored column |

Mismatched units across these is the #1 invisible error in the family. Normalize to one unit (meters) via the conversion UDFs before any cross-column comparison.

## Cardinality summary

| Relationship | Cardinality |
|---|---|
| `CENTERLINE` → routes | 1 : N (routes can share a centerline) |
| route → point events | 1 : N |
| route → linear events | 1 : N |
| anomaly (point) ∩ HCA (range) | N : 0..1 (an anomaly is in at most one HCA of a type) |
| anomaly (point) ∩ condition (range) | N : 0..N |
