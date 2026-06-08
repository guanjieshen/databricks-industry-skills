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
  version: "0.2.0"
parent: maximo-overview
---

# Maximo Asset & Location Hierarchy

The cross-cutting "hierarchical query" skill. Use when any other Maximo question crosses parent-child boundaries: rolling work-order cost up to a region, listing all assets under a process system, finding leaf locations under a station, traversing asset classification trees.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, module map, and universal gotchas (SITEID composite keys, status-is-a-synonym-domain / SYNONYMDOMAIN, HISTORYFLAG, WOCLASS/ISTASK, app-server-timezone datetimes). This skill builds on that foundation by going deep on hierarchy traversal mechanics, which `maximo-overview` does not cover.

## When to use

- "Show me maintenance cost rolled up by region" (composes with `maximo-maintenance-cost`)
- "All open work orders under compressor station 4" (composes with `maximo-work-orders`)
- "All assets in the North Region transmission system"
- "What's the parent location of valve V-42?"
- "Walk the asset class hierarchy under Rotating Equipment"
- "How many descendant assets does location L-PLANT-1 have?"
- "PM compliance rolled up to region" (composes with `maximo-reliability`)
- Anything with "by region / by station / by area / by system / rollup / under".

This skill rarely answers a question solo. It **enables** hierarchical rollups in every other module's analytics. Load it alongside whichever module owns the metric.

## Top gotchas (inline — Genie may not load `gotchas.md` at decision time)

These traps silently produce wrong rollup numbers. Full set (10) in [gotchas.md](gotchas.md); `maximo-overview` carries the universal mechanics (SITEID composite keys, SYNONYMDOMAIN status resolution, HISTORYFLAG, WOCLASS/ISTASK) — apply them in the metric you roll up, don't re-derive them here.

1. **Use closure tables (`LOCANCESTOR`, `ASSETANCESTOR`), not naïve `PARENT` self-joins** — `JOIN locations c ON c.parent = p.location` walks one level only. For "all assets under region X" at arbitrary depth, the closure tables (one row per ancestor-descendant pair across all depths) are the IBM-canonical answer. The shipped UDFs and views use them.

2. **`LOCHIERARCHY.SYSTEMID`** — locations belong to multiple hierarchies (Operating, Storeroom, Network) in `LOCHIERARCHY`, each with its own `SYSTEMID`. Always filter to the system you mean (typically `'PRIMARY'` for the operational hierarchy). Without the filter, a single location appears multiple times and rollup counts inflate.

3. **Closure tables may not be materialized at all customers** — if Bronze ingestion didn't capture `LOCANCESTOR`/`ASSETANCESTOR`, fall back to a recursive CTE on `LOCHIERARCHY` (system-aware) or `LOCATIONS.PARENT` (single-system). The shipped views check existence; ad-hoc queries should too. See `gotchas.md` for the probe and the recursive fallback.

4. **Physical hierarchy ≠ classification hierarchy** — `LOCATIONS.PARENT` is the **physical** tree ("valve V-42 → process unit 4 → plant 1"). `CLASSSTRUCTURE` is the **classification** tree ("centrifugal pump → rotating equipment → mechanical"). Both are hierarchies; both have closure-style traversal; **they answer different questions**. Don't conflate. "All compressors" needs CLASSSTRUCTURE; "all assets at station 4" needs LOCATIONS. Note: Maximo ships **no** `CLASSANCESTOR` closure table — use the `v_class_tree` view or a recursive CTE for class rollups.

5. **The hierarchy is site-scoped — and so is the metric you roll up.** `LOCANCESTOR`/`ASSETANCESTOR` rows carry `SITEID`; the closure JOIN and the metric JOIN both need it. This is the universal SITEID composite-key gotcha (see `maximo-overview`) — it bites hierarchy queries doubly because there are two joins to thread it through. When rolling up a *status-bearing* or *closeable* metric (open WOs, completed work, costs), resolve statuses via `SYNONYMDOMAIN` and confirm `HISTORYFLAG` handling **in the owning module's metric** (work-orders / cost / reliability) — apply `maximo-overview`'s pattern; don't filter on raw literals in the rollup.

## Questions to surface first

Surface these to the user *before* answering — hierarchy rollups have conventions with no defensible default, and guessing produces confidently-wrong totals:

1. **Which hierarchy system?** A location lives in multiple `LOCHIERARCHY` systems (`SYSTEMID` — Operating, Storeroom, Network, plus custom O&G systems like `PROCESS`/`UTILITY`). "Roll up by region" means a different tree in each. Default to `'PRIMARY'` (the operational hierarchy) but confirm — the customer's reporting region may be a non-primary system. The workspace glossary should record their convention.

2. **Location hierarchy or classification hierarchy?** "All pumps in the West region" mixes two trees: the **physical** tree (`LOCATIONS`/`LOCANCESTOR` — "in the West region") and the **classification** tree (`CLASSSTRUCTURE` — "pumps"). Confirm whether the user wants a physical rollup, a class rollup, or the intersection. "All compressors" alone is classification; "everything at station 4" alone is physical.

3. **Include the parent node itself, or descendants only?** "Cost under station 4" — does it include work booked directly against STN-04, or only its children? Self-inclusion in `LOCANCESTOR` varies by deployment (gotcha 6). The shipped `v_*_rollup_keys` views force a self-row at depth 0 so "at or under X" is unambiguous; confirm which the user means before using a raw closure-table query.

4. **Roll up by location, or by asset parent?** A metric can roll up the **location** tree (work happened *at* a place) or the **asset** tree (`ASSET.PARENT`/`ASSETANCESTOR` — a sub-component under a parent asset like a skid or train). These give different groupings; confirm which dimension the question is really about.

## Pre-flight (per session)

Cache these once; don't re-ask each turn:

1. **Silver catalog/schema** — confirm via workspace glossary.
2. **Closure tables materialized?** — check whether `LOCANCESTOR` and `ASSETANCESTOR` are populated in Bronze/Silver. If not, fall back to a recursive CTE on `LOCHIERARCHY`/`PARENT`. See `gotchas.md` for the probe.
3. **Default hierarchy system** — `LOCHIERARCHY.SYSTEMID` default is `'PRIMARY'`; record the customer's reporting-system convention from the workspace glossary so the per-request question above resolves fast.

## Workflow

Resolution priority — prefer the highest-level asset that fits the request:

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

## What NOT to do

- Don't use naïve `PARENT` self-joins for multi-level rollups. Use closure tables.
- Don't omit `SITEID` from the closure JOIN *or* the metric JOIN (universal SITEID gotcha — see `maximo-overview`).
- Don't omit the `SYSTEMID` filter on `LOCHIERARCHY`/`LOCANCESTOR`.
- Don't conflate physical hierarchy (LOCATIONS) with classification hierarchy (CLASSSTRUCTURE), and don't expect a `CLASSANCESTOR` table — it doesn't ship.
- Don't assume closure tables exist — probe first.
- **Don't author the metric here.** This skill supplies the *grouping dimension*, not the number. Resolve open/closed statuses via `SYNONYMDOMAIN` and `HISTORYFLAG` per `maximo-overview`, and **DEFER** the metric definition to its owner: cost rollups / estimate-vs-actual / multi-currency → `maximo-maintenance-cost`; PM compliance / failure-rate / reactive-vs-proactive → `maximo-reliability`. Do not equate `WORKTYPE='CM'` with reactive work — that framing belongs to `maximo-reliability`.

## Composes with (this skill enables — it rarely owns the metric)

- **`maximo-maintenance-cost`** (OWNER of cost semantics) — `cost_rolled_up_to_ancestor` UDF here supplies descendants + `v_asset_cost_summary` there supplies the per-asset cost → "cost by region". Note cost columns are per-record and do NOT auto-roll-up; the rollup happens via this skill's descendant set, not a parent column.
- **`maximo-work-orders`** — "all open WOs under system X" via descendant lookup; resolve the open-status set in work-orders, group by ancestor here.
- **`maximo-reliability`** (OWNER of PM-compliance / failure-rate / SMRP ratios) — failure-mode pareto rolled up to asset class via CLASSSTRUCTURE; this skill only provides the class subtree.
- **`maximo-integrity`** — "all vessels in process unit 4 due for inspection" via LOCANCESTOR
- **`maximo-pm-planning`** — route clustering at arbitrary depth (its `v_pm_route_clusters` uses one-level `LOCATIONS.PARENT`; this skill enables deeper grouping)
- **`maximo-hse`** — incident/permit counts rolled up to a parent location or business region
- **`maximo-inventory`** — for queries spanning storerooms across regions

## References

- IBM Maximo Manage — Locations & Asset hierarchy docs
- Authoring standard: see `_authoring/authoring-industry-skills/SKILL.md`
