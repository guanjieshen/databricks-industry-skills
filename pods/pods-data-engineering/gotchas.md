# PODS Data Engineering — Gotchas

## 1. Normalize units exactly once, at Silver→Gold

The biggest modeling decision in the family. Convert all measures to one unit (meters) at the Silver→Gold boundary, materialize it as `measure_m`, and never convert again downstream. Scattered conversions in queries/views drift and reintroduce the foot-vs-meter bug.

## 2. Keep ILI run vintages — never collapse to "current"

Tempting to keep only the latest anomalies. Don't. Run comparison, growth analysis, and audit history all need historical runs. Keep one row per anomaly per run with `run_id`; let queries pick the vintage (`v_latest_ili_run` for current-state).

## 3. Preserve run metadata for comparability

Vendor and tool type (MFL/UT/EMAT) must survive into Gold. Cross-run "growth" is meaningless without knowing whether the two runs used comparable tools. The `pods-ili-integrity` comparability warning depends on this dimension.

## 4. SCD on slowly-changing PODS attributes

Pipe attributes (OD, wall thickness, MAOP, class location) change over time (re-rating, replacement). If point-in-time accuracy matters (audits), model these as SCD2 and time-travel to the run date when joining anomalies to attributes — don't join an old anomaly to today's MAOP.

## 5. Range-overlap joins for attribute enrichment

Pipe attributes are linear route events. Joining anomaly (point) to attributes (range) is a half-open range-overlap on `measure_m`, not an equality join. See `v_anomalies_enriched`.

## 6. Idempotency

ILI feeds get reloaded (corrections, reprocessing). Dedup on `(feature_id, run_id)` and make the pipeline idempotent so a reload doesn't double-count anomalies.

## 7. Geometry is optional and separate

Load centerline `GEOMETRY` only if map-distance/crossings questions are in scope. Most integrity questions are measure operations. Don't block the route-measure spine on geospatial loading.

## 8. Validate monotonicity in the pipeline

Add expectations that catch non-monotonic measures and route gaps/overlaps at ingest (see `pods-data-quality`), so bad LRS data is flagged before it silently breaks overlap joins downstream.
