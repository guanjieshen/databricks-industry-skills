---
name: pods-overview
description: |
  Use whenever the user mentions PODS, Pipeline Open Data Standard, pipeline
  integrity data, ILI / inline inspection, centerline, stationing, route
  measures, milepost, anomalies, cathodic protection, HCA, or any pipeline
  GIS / linear-referencing concept. Orients Genie on the PODS 7 data model —
  the pipeline hierarchy, the linear-referencing networks
  (CONTINUOUS_MEAS_NETWORK, ENGINEERING_STATION_NETWORK), the six optional
  modules (IR, TVC, ILI, CP, SL, OFF), and the universal gotchas that cause
  wrong answers (foot-vs-meter units, ILI run vintage, route-vs-measure,
  conforms-to-PODS-but-not-exactly). This is the foundation skill loaded for
  any PODS / pipeline-integrity question — other PODS skills layer on top.
metadata:
  version: "0.1.0"
---

# PODS Overview

This skill gives you the baseline literacy needed to work with PODS-modeled pipeline data in Databricks. Load it whenever a user mentions PODS, pipeline integrity, ILI, centerlines, stationing, or any pipeline GIS concept.

You are not a PODS specialist out of the box. With this skill loaded, you behave like one — you know the linear-referencing model, the module map, and the joins/units that always go wrong. **The persona asking is usually a domain expert (ILI, NDE, corrosion) who is NOT a PODS-data-model expert and prompts tersely.** Read intent generously, surface your assumptions, and ask when ambiguous.

## Genie Code tips (apply to every PODS question)

- **Auth is ambient in the workspace** — Genie Code is already authenticated to the current workspace, so do **not** pass `--profile` (there's usually no named profile and it would fail). Use `--profile <name>` only when running these skills from a local machine against a `~/.databrickscfg` profile.
- **Reference tables explicitly** with `@catalog.schema.table` and use **`/findTables`** to locate them — don't guess names.
- Skills load **only in Agent mode**, and Genie selects them **only by matching their `description`**. If you edit a skill, start a **new chat** for the change to take effect.
- If `pods-setup` has not been run in this workspace, the physical→PODS column mapping and measure UNITS may be unknown, and analytical skills then produce confident, invisible errors. Offer to run it.

## When to use

- Any user mention of: PODS, Pipeline Open Data Standard, pipeline integrity, ILI, inline inspection, smart pig, anomaly, metal loss, dent, crack, centerline, route, measure, stationing, milepost (MP), station (e.g. `1240+00`), HCA, high-consequence area, cathodic protection (CP), %SMYS, ERF, MAOP, B31G, RSTRENG
- Any request to query, analyze, or build pipelines/dashboards/ML on pipeline integrity / GIS data
- Before activating any other PODS skill — this one provides the shared baseline

If the question is module-specific (ILI anomalies, HCA, CP), the matching module skill (`pods-ili-integrity`, etc.) will also load. Compose them. For the route/measure math underneath almost every question, `pods-linear-referencing` is the workhorse.

## Pre-flight (ask once per session, then cache)

1. **Catalog/schema location**: "Which Unity Catalog catalog/schema holds your PODS data?" (e.g. `pipeline.pods_silver`). If the user doesn't know where their pipeline data lives, use the repo's [`data-exploration`](../../_common/data-exploration/) cross-cutting skill to find it — `databricks experimental aitools tools query "SELECT table_catalog, table_schema, table_name FROM system.information_schema.tables WHERE table_name ILIKE '%pipe%' OR table_name ILIKE '%ili%' OR table_name ILIKE '%anomal%'"` — then `discover-schema` the hits.
2. **Workspace glossary**: Check whether a `<customer>-pods-glossary` workspace skill is installed. If yes, defer physical-column resolution to it. If no, suggest running `pods-setup` once for the workspace — it introspects the schema (via the same data-exploration tooling) and generates that glossary.
3. **"Conforms to PODS but not exactly"**: Almost every operator has renamed columns, different units, or only some modules. **Never assume a canonical PODS column name exists physically — resolve it through the glossary, or ask.**

## The universal gotchas (apply to almost every PODS query)

Read these every time. They cause the majority of wrong — and *invisibly* wrong — answers Genie gives on PODS data without this skill.

1. **Units: ILI stationing is often FEET; centerline / HCA measures are often METERS.** Joining a foot-based station to a meter-based measure produces a silent ~3.28× error that returns a plausible-but-wrong set. **Always confirm the unit of each measure column (via glossary) and normalize before any route-measure comparison.** This is the #1 invisible failure. See `pods-linear-referencing`.

2. **"Worst" anomaly = highest ERF / lowest predicted failure pressure, NOT deepest.** A long, shallow corrosion can be more severe than a deep pit. Ranking by raw `depth_pct` is the integrity-naive answer. Use ERF / B31G — see `pods-ili-integrity`.

3. **Pick the right ILI run vintage.** A line has multiple inspections over time. "Show me anomalies on line 4" almost always means the **latest run**, not all runs unioned. Mixing vintages double-counts and conflates. Filter to a single `inspection_id` (latest by run date) unless the user asks to compare.

4. **Tool/vendor changes break comparability.** Different ILI vendors/tools (MFL vs UT vs EMAT) size depth differently. Comparing "growth" across runs from different tools may reflect tool variance, not real corrosion. Always surface the vendor/tool of each run being compared.

5. **Events are located by route + measure, not independent geometry.** PODS uses dynamic segmentation: an anomaly, weld, valve, or HCA is a *route event* defined by `(route_id, measure)` (point) or `(route_id, begin_measure, end_measure)` (linear). To find "what's between station X and Y" or "what overlaps an HCA" you do **range-overlap joins on measure**, not spatial distance. See `pods-linear-referencing`.

## The PODS 7 model map (what lives where)

PODS 7 organizes the model into named conceptual groupings. Tables/feature classes Genie should know exist (canonical names — **map to the operator's physical names via the glossary**):

### Linear Referencing (APR) — the spatial backbone
- **`CENTERLINE`** — the single source of polyline geometry; each centerline feature ≈ one unit of pipe. M-aware.
- **`CONTINUOUS_MEAS_NETWORK`** — continuous, uninterrupted measure values along a route (PODS 7 replacement for legacy "PODS Routes"). `NETWORK_ID` domain value `ContinuousMeasureNetwork`.
- **`ENGINEERING_STATION_NETWORK`** — engineering station values along each route (PODS 7 replacement for legacy "PODS Series"). `NETWORK_ID` domain value `EngineeringStationNetwork`. Stations look like `1240+00`.
- **Calibration points** — tie measures to real-world positions.

### Pipeline Hierarchy
- The organizing structure: **system → line/route → segment**. Point, polyline, and polygon feature classes describing the pipe network and its grouping.

### Assets
- Physical components located on the line: **valves, fittings, welds, pipe segments, casings, crossings, pump/compressor stations**, etc. Located as point or linear route events.

### Locations
- Point reference features — **markers, mileposts, AGMs (above-ground markers), test stations, facilities**.

### Operations
- **Operating pressure, MAOP, product, flow direction, class location** — linear route events describing how the pipe operates.

### Conditions
- Point/linear features describing the **state of the pipe** — coating condition, soil, depth-of-cover, repairs.

### ILI (Inline Inspection module)
- **Inspection runs, anomalies / features** (metal loss, dents, cracks, mfg), tool/vendor metadata. The core of `pods-ili-integrity`.

### Documents & Activities
- Records, attachments, and the activity log tying data to source documentation (supports TVC).

### Metadata Tables
- **`MODULE_METADATA`** — which optional modules are present in this implementation (check this to know whether CP/TVC/OFF data even exists).
- **`TABLE_METADATA`** — table-level descriptive metadata.
- **`IS_OFFSHORE`** — attribute flag for offshore segments (OFF module).

## The six optional modules

An operator adopts only some of these. **Check `MODULE_METADATA` (or the glossary) before querying a module's tables** — if the module isn't adopted, say so rather than generating SQL against tables that don't exist.

| Module | Name | What it adds |
|---|---|---|
| **IR** | Integrity Regulatory | Regulatory / integrity-management data, assessment records |
| **TVC** | Traceable, Verifiable, Complete | Material & attribute provenance / records-quality |
| **ILI** | Inline Inspection | Smart-pig run + anomaly data |
| **CP** | Cathodic Protection | Corrosion-protection systems, survey readings |
| **SL** | SCADA Link | Physical ties to sensor / SCADA locations along the line |
| **OFF** | Offshore | Offshore-specific attributes (`IS_OFFSHORE`) |

## Linear-referencing vocabulary (so terse questions parse correctly)

| Term | Meaning |
|---|---|
| **Centerline** | The polyline geometry of the pipe; the geometric source for routes |
| **Route** | A linear LRS feature carrying monotonically increasing/decreasing **m-measures** built on centerlines |
| **Measure (M)** | Position along a route (continuous), e.g. meters or feet from route origin |
| **Station / stationing** | Engineering position notation like `1240+00` (= 124,000 ft); from the station network |
| **Milepost (MP)** | Position in miles; common in business conversation ("near MP 42") |
| **Route event** | A feature located by `(route_id, measure)` or `(route_id, begin_measure, end_measure)` rather than its own stored geometry |
| **Dynamic segmentation** | Deriving a feature's geometry/extent on the fly from route + measure(s) |

## What NOT to do

- **Don't compare measures across columns without confirming units.** Foot-vs-meter is the #1 invisible error. Normalize first (see `pods-linear-referencing`).
- **Don't rank anomalies by raw depth when the user says "worst" / "most severe".** Use ERF / predicted failure pressure.
- **Don't union ILI runs across vintages** for a current-state question. Pick the latest run; surface which one.
- **Don't compare runs from different tools/vendors** without flagging that depth sizing may not be comparable.
- **Don't fabricate PODS column names.** Use canonical concepts from this document, then resolve to physical columns via the glossary or by asking. The data "conforms to PODS but not exactly."
- **Don't query a module's tables before confirming the module is adopted** (`MODULE_METADATA` / glossary).
- **Don't declare a segment safe to operate.** You can screen and rank; fitness-for-service is an engineer's call (see `pods-ili-integrity`).

## References

- PODS data models: `https://pods.org/data-models/pods-data-models/`
- PODS 7 conceptual poster (PDF): `https://pods.org/wp-content/uploads/2024/11/PODS7-Poster.pdf`
- Esri ArcGIS Pipeline Referencing — LRS data model: `https://pro.arcgis.com/en/pro-app/latest/help/production/location-referencing-pipelines/alrs-data-model.htm`
- Essential pipeline-referencing vocabulary: `https://pro.arcgis.com/en/pro-app/latest/help/production/location-referencing-pipelines/essential-pipeline-referencing-vocabulary.htm`
