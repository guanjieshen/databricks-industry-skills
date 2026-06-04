---
name: pods-ili-integrity
description: |
  Use for inline-inspection (ILI) anomaly analysis on PODS data — ranking
  anomalies by severity (ERF / predicted failure pressure, NOT raw depth),
  Modified B31G / RSTRENG remaining-strength screening, %SMYS, dig-candidate
  prioritization, comparing ILI runs for corrosion growth (with tool/vendor
  comparability), and finding the most severe features on a line. Triggers on:
  "worst anomalies", "metal loss", "dig list", "where do I dig", "ERF",
  "B31G", "RSTRENG", "remaining strength", "%SMYS", "corrosion growth",
  "compare the last two runs", "smart pig results", "predicted failure
  pressure", "which anomalies should I worry about".
tags:
  - data-source:pods
  - tier:module
  - module:ili
  - industry:oil-and-gas
  - persona:integrity-engineer
---

# PODS ILI Integrity

Help pipeline integrity engineers analyze inline-inspection (ILI) anomalies on PODS data. Composes with `pods-overview` (model literacy) and **depends on `pods-linear-referencing`** for locating anomalies along the route.

**The user is an integrity domain expert (ILI/NDE/corrosion) who is usually NOT a PODS-data-model or SQL expert, and prompts tersely.** Your job is to translate their intent into correct data + integrity math, *show the assumptions you made*, and ask when something is genuinely ambiguous. The three rules below are non-negotiable — they are what make this skill net-positive instead of a confident-error machine.

## The three rules (always)

1. **Surface assumptions; ask when ambiguous.** State the run, line interpretation, method, and thresholds you used (e.g. *"Ranked by ERF on the 2024 Rosen run; I read 'line 4' as `L04`."*). If a term is ambiguous and the answer materially depends on it, ASK before running.
2. **Certified math only — never improvise.** Use the shipped UDFs (`pods_failure_pressure_b31g_mod`, `pods_erf`, `pods_pct_smys`) or a stored ERF/failure-pressure column from the glossary. Never hand-write remaining-strength math inline.
3. **Screen and rank; never declare safe.** You can prioritize and estimate. You must NOT make a fitness-for-service or pressure-derate / "safe to operate" determination — that needs current operating pressure, engineering judgment, and a qualified engineer. Say so and stop.

## When to use

- "Show me the worst anomalies on line 4"
- "Where do I need to dig?" / "build my dig list"
- "Compare the last two ILI runs" / "corrosion growth on line 7"
- "What's the ERF / predicted failure pressure on this anomaly?"
- "Which metal-loss features are above 50% / interacting with a dent?"
- "%SMYS at MAOP for the deepest features"

For HCA overlap / consequence, use `pods-consequence-hca`. For the route-measure math, lean on `pods-linear-referencing`.

## Pre-flight (per session, then cache)

1. **Run + line.** Which ILI run (default: **latest** by run date) and which line (`route_id`)? Resolve business names ("the 30-inch") via glossary.
2. **ERF source.** Is ERF / predicted failure pressure **stored** (glossary) or must it be **computed**? If computed, confirm OD/wall/SMYS/MAOP are available (from `v_anomalies_enriched`).
3. **Safety factor.** ERF needs a code/class safety factor — confirm it; never default silently.
4. **Method.** Modified B31G is the shipped default. If the operator uses RSTRENG/effective-area or a vendor method, prefer their certified UDF and say which was used.

## Intent translation (the terse-question dictionary)

| User says | They mean (do this) |
|---|---|
| "worst / most severe anomalies" | Rank by **ERF desc** (or lowest predicted failure pressure), NOT raw `depth_pct` |
| "where do I dig" / "dig list" | ERF-ranked candidates, typically ERF ≥ threshold or top-N, on the **latest** run; flag immediate vs scheduled |
| "compare the last two runs" | Latest two runs **on the same line**; box-match by measure within tolerance; compute growth; **warn if tools/vendors differ** |
| "deep anomalies" | Here depth IS the metric — but still report ERF alongside |
| "anomalies on line 4" | Latest run on `L04`, single vintage |

## Workflow priority

1. **Enriched view** `v_anomalies_enriched` (from `pods-data-engineering`) — anomalies + run metadata + pipe attributes + measure_m.
2. **Certified UDFs** in [metric_udfs.sql](metric_udfs.sql) — `pods_failure_pressure_b31g_mod`, `pods_erf`, `pods_pct_smys`, `pods_depth_in`.
3. **Ranked views** in [views.sql](views.sql) — `v_anomaly_severity`, `v_dig_candidates`.
4. **Parameterized examples** in [examples.sql](examples.sql).
5. **Raw tables** — last resort, after units/run/attributes confirmed.

## Run comparison (do it carefully)

- Pick the latest two runs **on the same line**. Match anomalies across runs by **measure within a tolerance window** (not exact equality — measures shift with recalibration). Report match rate; don't fake precision.
- **Always surface the vendor + tool of each run.** If they differ (e.g. 2019 Baker UT vs 2024 Rosen MFL), warn explicitly that depth sizing may not be comparable and reported growth may reflect tool variance, not real corrosion.

## What NOT to do

- **Don't rank "worst" by raw depth.** Use ERF / predicted failure pressure. A long shallow corrosion can outrank a deep pit.
- **Don't union runs across vintages** for a current-state question. Pick one; say which.
- **Don't compare runs from different tools** without the comparability warning.
- **Don't hand-write B31G/RSTRENG.** Use the UDFs or a certified stored column.
- **Don't compute ERF on cracks, dents, or dents-with-metal-loss** with the metal-loss B31G UDF — it's for blunt metal loss only. Flag those feature types for a different method.
- **Don't declare a segment safe / fit-for-service.** Screen, rank, and hand off to the engineer.
- **Don't default the safety factor silently.**

## References

- [schema.md](schema.md) — ILI anomaly + run columns (canonical → glossary)
- [gotchas.md](gotchas.md) — ERF vs depth, vendor comparability, B31G limits, box-matching
- [examples.sql](examples.sql) — parameterized severity / dig-list / run-comparison queries
- [views.sql](views.sql) — `v_anomaly_severity`, `v_dig_candidates`
- [metric_udfs.sql](metric_udfs.sql) — `pods_failure_pressure_b31g_mod`, `pods_erf`, `pods_pct_smys`
- ASME B31G (Modified) — remaining strength of corroded pipelines
- PHMSA HL integrity management: `https://www.phmsa.dot.gov/pipeline/hazardous-liquid-integrity-management/hl-im-fact-sheet`
