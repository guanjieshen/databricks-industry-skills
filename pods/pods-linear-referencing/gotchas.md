# PODS Linear Referencing — Gotchas

## 1. Foot-vs-meter is the #1 invisible error

ILI stationing is frequently in **feet**; centerline / HCA measures are frequently in **meters**. A join like `anomaly.station BETWEEN hca.begin_m AND hca.end_m` compiles fine, runs fine, and returns a **plausible-but-wrong** set off by ~3.28×. The integrity engineer (domain expert, not data expert) cannot see this from the result.

**Always confirm the unit of every measure column (glossary), convert to one unit (meters) with `pods_ft_to_m`, and state the conversion in your answer.**

## 2. Position-along-pipe is a MEASURE operation, not geometry

"Near MP 42", "between stations", "what's upstream" are all **measure** operations. Using `ST_DWithin` / geometry distance answers "near this map point" — a different question. Two points 50 ft apart along a winding pipe may be far apart in map distance, and two points close in map distance may be on different lines entirely. Default to measure math; use geometry only when the user explicitly asks about map proximity / crossings.

## 3. `route_id` must be in every overlap join

An interval-overlap predicate without `AND a.route_id = b.route_id` overlaps features from *different lines*. Station `1240+00` on line A has nothing to do with `1240+00` on line B. Silent cross-line contamination.

## 4. Increasing measure ≠ downstream (necessarily)

Whether measure increases in the direction of flow depends on how the route was digitized. "Downstream" / "upstream" queries must confirm direction — check the Operations data (flow direction) or ask. Don't assume.

## 5. Monotonicity and gaps

A valid route has **monotonic** measures (strictly increasing or decreasing). Real data has:
- **Reversals** — measure goes backward mid-route (digitization or calibration error)
- **Gaps** — gaps between segments where no measure exists
- **Overlaps** — two segments claiming the same measure range

These break range joins (a point may match 0 or 2 ranges). `pods-data-quality` has diagnostics for all three. When measures look wrong, check monotonicity before trusting an overlap result.

## 6. Stationing equations / restarts

Engineering stationing can **restart** or have **station equations** (e.g. after a re-route, station goes `1500+00 = 1480+00 ahead`). A naive `station_to_measure` parse assumes a continuous station scheme. If the operator has station equations, the continuous measure network is the safer basis — note this and prefer `CONTINUOUS_MEAS_NETWORK`.

## 7. Half-open intervals avoid double-counting

Use `[begin, end)` (>= begin, < end) for range membership. A point exactly on a boundary between two abutting segments otherwise matches both. The shipped `pods_events_overlap` and the views use half-open logic — keep it consistent.

## 8. Calibration changes shift measures between vintages

After a re-survey or recalibration, the same physical point can have a different measure than in an older ILI run. When comparing across runs (see `pods-ili-integrity`), match within a **tolerance window**, not exact measure equality — and be aware large shifts may indicate recalibration, not real movement.
