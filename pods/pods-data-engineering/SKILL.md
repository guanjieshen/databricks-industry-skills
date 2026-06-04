---
name: pods-data-engineering
description: |
  Use to model raw pipeline / GIS / ILI feeds into conformed PODS Silver/Gold
  tables in Databricks — building the centerline, the route-measure event
  spine, and the normalized analytical layer the other PODS skills query.
  Triggers on: "build a pipeline for our PODS data", "model our ILI data",
  "bronze silver gold for pipeline data", "Lakeflow pipeline for PODS",
  "conform our pipeline tables", "create the centerline table", "ingest ILI
  runs". For querying existing PODS data, use pods-overview + the module skills
  instead.
metadata:
  version: "0.1.0"
parent: pods-overview
---

# PODS Data Engineering

Help D&A / platform engineers model raw pipeline feeds into a conformed PODS layer on Databricks. The goal is a Silver/Gold layer where the analytical skills (`pods-linear-referencing`, `pods-ili-integrity`, …) work reliably — which above all means **a normalized route-measure spine with one route key and one measure unit.**

This skill is about *modeling* PODS data already landed in Databricks, not about connectors/replication from Esri or ILI vendors (out of scope — see family README).

> **FIRST:** load the `pods-overview` skill — it carries the PODS 7 data model, the linear-referencing networks, the module map, and the universal gotchas (foot-vs-meter units, route-vs-measure, ILI run vintage). This skill builds on that foundation.

## When to use

- "Build a Lakeflow pipeline for our pipeline / ILI data"
- "Model bronze → silver → gold for PODS"
- "Conform our anomaly / centerline / HCA tables"
- "Create the normalized event spine the analytical skills need"

## Pre-flight

1. **Run `pods-setup` first if not done.** Modeling without the unit/route-key/module mapping bakes the invisible errors into the Gold layer. The glossary is the spec for this work.
2. Confirm the medallion target schemas (e.g. `pipeline.pods_bronze` / `_silver` / `_gold`).
3. Confirm serverless / Lakeflow Declarative Pipelines (SDP) vs notebook jobs.

## Modeling principles (the order that matters)

1. **Bronze** — land raw feeds as-is (ILI vendor files, GIS exports, centerline). No reshaping.
2. **Silver** — typed, deduped, SCD where needed; preserve PODS feature-class structure. **Record the unit of every measure column as a UC column comment here.**
3. **Gold (the spine)** — the normalized analytical layer:
   - One **route key** across all event tables (alias the per-table keys from the glossary).
   - One **measure unit** (meters) — apply `pods_ft_to_m` to feet-based columns.
   - The unified **`v_route_events_m`** spine (see `pods-linear-referencing/views.sql`).
   - Materialize heavy overlaps (anomaly↔HCA) if query latency matters.

The single most important transformation is **measure-unit normalization at the Silver→Gold boundary**. Do it once here so every downstream skill is safe.

See [pipeline.py](pipeline.py) for a Lakeflow SDP skeleton and [gold_views.sql](gold_views.sql) for the conformed Gold layer. [gotchas.md](gotchas.md) covers SCD on ILI runs, idempotency, and centerline geometry handling.

## ILI-specific modeling notes

- **One row per anomaly per run.** Keep `run_id` on every anomaly so latest-run filtering and run comparison work.
- **Preserve run metadata** (vendor, tool type, run date) in a dimension — comparability warnings depend on it.
- **Don't pre-aggregate away depth/length/width** — B31G/RSTRENG need the raw geometry of each anomaly.

## Geospatial modeling notes

- Load centerline geometry as Databricks `GEOMETRY`/`GEOGRAPHY` (Spatial SQL, public preview) when map-distance / crossings questions are in scope. Index with **H3** for proximity at scale.
- But remember: most integrity questions are **measure** operations, not geometry — the route-measure spine is the primary deliverable; geometry is complementary.

## What NOT to do

- Don't normalize units in the analytical skills — do it once at Silver→Gold. Scattered conversions drift.
- Don't drop `run_id` / run metadata when conforming anomalies.
- Don't collapse multiple ILI runs into one "current" anomaly table — keep vintages; let queries pick.
- Don't build the Gold spine before `pods-setup` has pinned the units and route key.

## References

- [pipeline.py](pipeline.py) — Lakeflow SDP skeleton (bronze→silver→gold)
- [gold_views.sql](gold_views.sql) — conformed Gold layer / route-measure spine
- [gotchas.md](gotchas.md) — SCD, idempotency, geometry, units
- `pods-linear-referencing/views.sql` — the canonical `v_route_events_m` spine this layer feeds
- [Lakeflow Declarative Pipelines](https://docs.databricks.com/aws/en/dlt/)
