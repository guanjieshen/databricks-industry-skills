# PODS ILI Integrity — Gotchas

## 1. "Worst" means ERF, not depth

The integrity-naive answer ranks by `depth_pct`. A long, shallow corrosion can have a lower predicted failure pressure (higher ERF) than a short deep pit, because B31G accounts for axial length via the Folias factor. **Always rank severity by ERF / predicted failure pressure.** Report depth alongside, but don't rank on it. This is the single most common way Genie gets integrity wrong unaided.

## 2. Pick the latest run; don't union vintages

A line has many ILI runs. "Anomalies on line 4" means the **latest** run unless the user says otherwise. Unioning vintages double-counts and conflates growth. Use `v_latest_ili_run`; state which run you used.

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

Depth in inches, lengths in inches, pressures in psi/psig, OD/wall in inches. Mixing (e.g. mm wall with inch OD) silently corrupts B31G. The UDFs assume inches/psi — confirm the glossary units and convert before calling.
