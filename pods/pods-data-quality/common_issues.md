# PODS Data Quality — Symptom → Cause → Fix

| Symptom (what the user reports) | Likely cause | Fix (and where) |
|---|---|---|
| "HCA overlap returned **nothing**" | ILI measure in feet, HCA measure in meters — ranges never intersect | Normalize to meters at Silver→Gold (`pods-data-engineering`); confirm units in glossary |
| "HCA overlap returned **way too much**" | Missing `route_id` in the overlap join → cross-line matches | Add `route_id` to the join (`pods-linear-referencing` patterns) |
| "Anomaly count is **double** what I expect" | No ILI run-vintage filter → multiple runs unioned | Filter to latest run (`v_latest_ili_run`) or the run the user means |
| "This anomaly **isn't in any HCA** but should be" | Route gap/overlap, or orphan event (no centerline row) | Diagnostics #3/#4; fix LRS segmentation in conformed layer |
| "**Growth** between runs looks impossible" | Runs from different tools/vendors (MFL vs UT) — depth not comparable | Surface vendor/tool; warn (`pods-ili-integrity`); don't fix data, flag it |
| "**ERF/B31G is NULL** for many anomalies" | Missing OD/wall/SMYS/MAOP at the anomaly's location | Diagnostics #6; enrich pipe attributes via range-overlap; SCD to run date |
| "Numbers shifted vs last quarter at the same station" | Recalibration / re-survey changed measures between vintages | Expected; match across runs with a tolerance window, not exact measure |
| "Upstream/downstream is backwards" | Assumed increasing measure = downstream, but route digitized against flow | Confirm flow direction (glossary); fix direction logic |
| "Stationing math is off after a reroute" | Station equation / restart not handled | Prefer `CONTINUOUS_MEAS_NETWORK` over station parsing; record equation in glossary |

## Reporting template

When you find an issue, report it like this so the engineer can act:

> **Finding:** 12% of anomalies on `L07` fall in a 1.4 km measure gap between segments.
> **Analytical impact:** these anomalies return no HCA/pipe-attribute match → excluded from ERF ranking and HCA reports.
> **Recommended fix:** repair route segmentation on `L07` in the Silver→Gold conform step (`pods-data-engineering`), not in individual queries.

Always quantify, always tie to the analytical symptom, always fix at the conformed layer.
