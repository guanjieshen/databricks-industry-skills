---
name: maximo-asset-hierarchy
description: |
  Use for IBM Maximo / EAM / CMMS hierarchical analytics — rolling up costs,
  work, or events to a location parent, system, region, or asset class.
  Covers LOCATIONS / LOCHIERARCHY / LOCANCESTOR closure tables, ASSET.PARENT
  with ASSETANCESTOR, the SYSTEM virtual hierarchy, and CLASSSTRUCTURE asset
  classification trees. Answers "by region", "by station", "by area",
  "all assets under X", "all descendants of system Y", "what's the parent
  of location Z", "rollup to class level". Triggers on: "rollup", "by region",
  "by area", "by station", "ancestor", "descendant", "LOCANCESTOR",
  "ASSETANCESTOR", "LOCHIERARCHY", "CLASSSTRUCTURE", "asset hierarchy",
  "location hierarchy", "asset class", "class tree", "system", "parent
  location", "all under". Compose with maximo-work-orders / reliability /
  maintenance-cost / pm-planning / integrity / hse for hierarchical rollups
  of their respective domains.
metadata:
  version: "0.1.0"
parent: maximo-overview
---

# Maximo Asset & Location Hierarchy

The cross-cutting "hierarchical query" skill. Use when any other Maximo question crosses parent-child boundaries: rolling work-order cost up to a region, listing all assets under a process system, finding leaf locations under a station, traversing asset classification trees.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, module map, and universal gotchas (SITEID composite keys, status semantics). This skill builds on that foundation by going deep on hierarchy mechanics.

## When to use

- "Show me maintenance cost rolled up by region" (composes with `maximo-maintenance-cost`)
- "All open work orders under compressor station 4" (composes with `maximo-work-orders`)
- "All assets in the East Mainline process system"
- "What's the parent location of valve V-42?"
- "Walk the asset class hierarchy under Rotating Equipment"
- "How many descendant assets does location L-PLANT-1 have?"
- "PM compliance rolled up to region" (composes with `maximo-reliability`)
- Anything with "by region / by station / by area / by system / rollup / under".

This skill rarely answers a question solo. It **enables** hierarchical rollups in every other module's analytics. Load it alongside whichever module owns the metric.

## Pre-flight (cache for the session)

1. **Silver catalog/schema** — confirm via workspace glossary.
2. **Closure tables materialized?** — check whether `LOCANCESTOR` and `ASSETANCESTOR` are populated in Bronze/Silver. If not, fall back to recursive CTE on `PARENT`. See `gotchas.md` for the probe.
3. **Hierarchy system in scope** — `LOCHIERARCHY` carries a `SYSTEMID`. Locations participate in multiple hierarchies (Operating, Storeroom, Network). Default is `'PRIMARY'`. Workspace glossary should specify the customer's system convention.

## Top gotchas (inline — Genie may not load `gotchas.md` at decision time)

1. **Use closure tables (`LOCANCESTOR`, `ASSETANCESTOR`), not naïve `PARENT` self-joins** — `JOIN locations c ON c.parent = p.location` walks one level only. For "all assets under region X" at arbitrary depth, the closure tables (one row per ancestor-descendant pair across all depths) are the IBM-canonical answer. The shipped UDFs and views use them.

2. **`LOCHIERARCHY.SYSTEMID`** — locations belong to multiple hierarchies (Operating, Storeroom, Network) in `LOCHIERARCHY`, each with its own `SYSTEMID`. Always filter to the system you mean (typically `'PRIMARY'` for the operational hierarchy). Without the filter, a single location appears multiple times.

3. **`SITEID` belongs in every join** — closure tables and hierarchy tables are still site-scoped. Cross-site hierarchy queries silently produce a cross product without `SITEID`. (Multi-site customers — most of them — feel this hard.)

4. **Closure tables may not be materialized at all customers** — if Bronze ingestion didn't capture `LOCANCESTOR`, you must fall back to a recursive CTE on `LOCATIONS.PARENT` (which mirrors LOCHIERARCHY semantics). The shipped views check existence; ad-hoc queries should too. See `gotchas.md` for the recursive fallback.

5. **Physical hierarchy ≠ classification hierarchy** — `LOCATIONS.PARENT` is the **physical** tree ("valve V-42 → process unit 4 → plant 1"). `CLASSSTRUCTURE` is the **classification** tree ("centrifugal pump → rotating equipment → mechanical"). Both are hierarchies; both have closure-style traversal; **they answer different questions**. Don't conflate. "All compressors" needs CLASSSTRUCTURE; "all assets at station 4" needs LOCATIONS.

## Workflow priority

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `descendant_count`, `is_ancestor`, `level_in_hierarchy`, `path_to_root`, `cost_rolled_up_to_ancestor` (composes with maintenance-cost)
2. **Pre-joined views** in [views.sql](views.sql) — `v_location_rollup_keys`, `v_asset_rollup_keys`, `v_class_tree`
3. **Parameterized examples** in [examples.sql](examples.sql)
4. **Raw tables** — last resort

## What's in this skill (load when…)

- [schema.md](schema.md) — LOCATIONS, LOCHIERARCHY, LOCANCESTOR, ASSET.PARENT, ASSETANCESTOR, SYSTEM, CLASSSTRUCTURE, CLASSSPEC, ASSETSPEC. **Load when** writing non-trivial hierarchy traversal or class-based filtering.
- [gotchas.md](gotchas.md) — recursive-CTE fallback for missing closure tables, depth-limit caveats, cross-system traversal, SITEID propagation, multi-system mismatches. **Load when** the closure-table probe shows tables are missing, or when crossing systems.
- [examples.sql](examples.sql) — 10 parameterized queries. **Load when** the user's question maps to a common rollup pattern.
- [views.sql](views.sql) — DDL for the gold views. **Load when** registering views in a new customer environment.
- [metric_udfs.sql](metric_udfs.sql) — Trusted UDFs. **Load when** registering metrics.

## Compose with (this skill enables — it rarely owns the metric)

- **`maximo-maintenance-cost`** — `cost_rolled_up_to_ancestor` UDF here + `v_asset_cost_summary` there → "cost by region" answer
- **`maximo-work-orders`** — "all open WOs under system X" via descendant lookup
- **`maximo-reliability`** — failure-mode pareto rolled up to asset class via CLASSSTRUCTURE
- **`maximo-integrity`** — "all vessels in process unit 4 due for inspection" via LOCANCESTOR
- **`maximo-pm-planning`** — route clustering at arbitrary depth (current `v_pm_route_clusters` uses one-level `LOCATIONS.PARENT`; this skill enables deeper grouping)
- **`maximo-hse`** — incident/permit counts rolled up to a parent location or business region
- **`maximo-inventory`** — for queries spanning storerooms across regions

## What NOT to do

- Don't use naïve `PARENT` self-joins for multi-level rollups. Use closure tables.
- Don't omit `SITEID` from cross-site queries.
- Don't omit the `SYSTEMID` filter on `LOCHIERARCHY`.
- Don't conflate physical hierarchy (LOCATIONS) with classification hierarchy (CLASSSTRUCTURE).
- Don't assume closure tables exist — probe first.

## References

- IBM Maximo Manage — Locations & Asset hierarchy docs
- Authoring standard: see `_authoring/authoring-industry-skills/SKILL.md`
