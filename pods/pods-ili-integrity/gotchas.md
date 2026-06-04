# PODS ILI Integrity — Gotchas

## Contents
1. "Worst" means ERF, not depth
2. Pick the latest run — and the right TOOL type; don't union vintages
3. Tool/vendor changes break growth comparisons
4. Box-match across runs with a tolerance, not equality
5. B31G is for blunt metal loss only
6. B31G validity limits
7. ERF needs a safety factor — confirm it
8. Missing pipe attributes → NULL, not zero
9. Never declare a segment safe
10. Units, again
11. Assess on tolerance-adjusted depth, not call depth (POE)
12. Cluster interacting metal loss before assessing
13. Response classes are illustrative, not compliance rulings

## 1. "Worst" means ERF, not depth

The integrity-naive answer ranks by `depth_pct`. A long, shallow corrosion can have a lower predicted failure pressure (higher ERF) than a short deep pit, because B31G accounts for axial length via the Folias factor. **Always rank severity by ERF / predicted failure pressure.** Report depth alongside, but don't rank on it. This is the single most common way Genie gets integrity wrong unaided.

## 2. Pick the latest run — and the right TOOL type; don't union vintages

A line has many ILI runs, run by **different tools**: MFL/UT (metal loss), EMAT (cracks), caliper/IMU (geometry/dents). "Anomalies on line 4" for a corrosion/ERF question means the **latest metal-loss run** — use `v_latest_metal_loss_run`, NOT `v_latest_ili_run` (which is per-tool) and definitely not "whatever ran last," because a recent caliper run would hide the relevant MFL run and report no metal loss. Unioning vintages double-counts and conflates growth. State which run (and tool) you used.

## 3. Tool/vendor changes break growth comparisons

Comparing a 2019 Baker UT run to a 2024 Rosen MFL run: the tools size depth differently. Reported "growth" may be tool variance, not real corrosion. **Always surface the vendor + tool of each run and warn when they differ.** Don't silently present a growth number.

## 4. Box-match across runs with a tolerance, not equality

The same physical defect has slightly different reported measures between runs (recalibration, tool positioning). Match within a tolerance window on `measure_m`; report the match rate. Exact-measure joins return near-nothing — a classic silent failure.

## 5. B31G is for blunt metal loss only

Modified B31G / the shipped UDF is valid for **blunt corrosion metal loss**. It is NOT valid for:
- **Cracks / SCC** → need crack-specific methods (e.g. from EMAT data)
- **Dents** → geometry assessment
- **Dents with metal loss / gouges** → interaction assessment
The severity view returns NULL and flags these. Don't push them through the metal-loss UDF.

## 6. B31G validity limits

- Very deep defects (d/t ≥ 0.80): the UDF returns NULL to force engineer review — don't substitute a guess.
- Very long defects fall into the rectangular-area regime (handled by the Folias branch), but extreme geometries warrant a more rigorous method (RSTRENG effective area). Note when a result is near the model's edge.

## 7. ERF needs a safety factor — confirm it

ERF = MAOP × safety_factor / predicted_failure_pressure. The safety factor depends on code/class (hazardous liquid vs gas, class location). **Never default it silently** — confirm with the user and state the value used. A different SF changes who's on the dig list.

## 8. Missing pipe attributes → NULL, not zero

If OD/wall/SMYS/MAOP aren't enriched at an anomaly's location, B31G/ERF are NULL. The severity view flags `MISSING_PIPE_ATTRIBUTES`. Surface the count of excluded anomalies so coverage is honest — don't let them silently drop off the dig list. Fix enrichment in `pods-data-engineering` / diagnose with `pods-data-quality`.

## 9. Never declare a segment safe

You can rank, estimate failure pressure, and compute ERF. You must not conclude "this is safe to operate at X psig" or recommend a derate. That is a fitness-for-service determination requiring current operating pressure, the full feature set, and a qualified engineer. Screen, rank, hand off — and say that's what you're doing.

## 10. Units, again

Depth in inches, lengths in inches, pressures in psi/psig, OD/wall in inches. Mixing (e.g. mm wall with inch OD) silently corrupts B31G. The UDFs assume inches/psi — confirm the glossary units and convert before calling. Note clustering math also crosses units: `measure_m` is meters while `length_in`/`wt_in` are inches — `v_anomaly_clusters` converts to meters (× 0.0254) before computing gaps. Don't compare measure (m) to length (in) raw.

## 11. Assess on tolerance-adjusted depth, not call depth (POE)

ILI tools report depth with a specified accuracy (e.g. ±10% wall at 80% confidence for MFL). Assessing on the reported **call depth** under-sizes features and produces a dig list that won't match the operator's. Use an **upper-bound depth** — `pods_depth_in_tol(depth_pct, wt, tool_tolerance_pct_wall)` — feeding the conservative ERF. The tolerance comes from the runs dim / glossary (`tool_tolerance_pct_wall`). If it's **unknown**, fall back to call depth but **say so explicitly** (`severity_note = 'CALL_DEPTH_ONLY'`) — never present call-depth results as if they were tolerance-adjusted. Full POE (probability of exceedance) modeling is more rigorous than a single upper-bound; this is screening.

## 12. Cluster interacting metal loss before assessing

Adjacent corrosion features within interaction spacing must be assessed as **one effective defect**, not independently — independent evaluation under-calls the most common real failure mode (clustered corrosion). `v_cluster_severity` does an **axial interval-merge** (default window **3 × wall thickness**, configurable) and assesses the cluster envelope with the deepest member's governing depth. Caveats: (a) **axial only** — circumferential clustering needs clock position / width that many exports lack; (b) the envelope conservatively treats inter-feature gaps as corroded; (c) true interaction / **RSTRENG effective-area** (river-bottom profile) is more rigorous and should be the operator's certified method when available. State the window and that it's screening.

## 13. Response classes are illustrative, not compliance rulings

The `ERF ≥ 1 → immediate / ≥ 0.8 → scheduled` style buckets in the examples are **illustrative defaults**, not regulatory determinations. Real response criteria are defined by **49 CFR 195.452(h)** (hazardous liquid: immediate / 60-day / 180-day) and **49 CFR 192.933 + ASME B31.8S** (gas), plus the operator's own IM program thresholds. Present these as candidates for engineer review, parameterize the thresholds, and tie them to the operator's confirmed criteria. Getting this wrong is both a correctness and a liability problem.
