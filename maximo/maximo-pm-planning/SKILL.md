---
name: maximo-pm-planning
description: |
  Use for forward-looking PM planning analytics on Maximo data — forecasting
  upcoming PMs, planned workload by craft, route grouping by location,
  capacity-vs-demand balancing, JOBPLAN content management, PM coverage gap
  analysis, PM-to-CM ratio (program-health), meter-based PM forecasts.
  Triggers on: "PM forecast", "PMs due", "upcoming PMs", "PM workload",
  "craft workload", "PM coverage", "JOBPLAN", "JPLABOR", "JPMATERIAL",
  "route optimization", "PM schedule", "next PM due", "PM-to-CM ratio",
  "PM planning", "weekly PM workload".
tags:
  - data-source:ibm-maximo
  - tier:module
  - module:pm-planning
  - industry:oil-and-gas
  - industry:utilities
  - industry:mining
  - industry:manufacturing
  - persona:maintenance-planner
  - persona:reliability-engineer
  - persona:da-platform
---

# Maximo PM Planning

Help maintenance planners and reliability engineers forecast PM workload, plan resource capacity, manage JOBPLAN content, and optimize PM strategy. The **forward-looking** companion to `maximo-reliability` (backward-looking).

## Boundary with `maximo-reliability`

Both skills touch the `PM` table. Use the right one based on direction:

| | `maximo-reliability` | `maximo-pm-planning` (this skill) |
|---|---|---|
| Direction | **Backward-looking** | **Forward-looking** |
| Question | "How well did our PMs perform?" | "What should we plan for next?" |
| Outputs | MTBF, MTTR, PM compliance % | PM forecast, workload by craft, route grouping |
| Time orientation | Past completions | Future due dates |
| Primary persona | Reliability engineer | Maintenance planner |

If the user is asking about historical PM performance (compliance, time-since-last), defer to `maximo-reliability`. If they're asking about upcoming workload, JOBPLAN content, or PM strategy design, this is the right skill.

## When to use

- "Forecast PMs due in next 30 / 60 / 90 days"
- "Craft workload forecast next quarter"
- "What's in JOBPLAN JP-PUMP-3MO?"
- "JOBPLAN edit impact — which PMs use this template?"
- "Critical assets without any PMs"
- "PM-to-CM ratio trend"
- "Route clustering — PMs grouped by location"
- "Next PM due for asset X"
- "Meter-based PM forecast for ASSET-123"
- "Are we over-scheduled this week?"

For backward-looking PM performance metrics (compliance %, time-since-last-PM), use `maximo-reliability`. For PM cost analytics, compose with `maximo-maintenance-cost`.

## Pre-flight (per session)

1. **Silver catalog/schema**: confirm via workspace glossary.
2. **Tolerance convention**: "What tolerance does your customer use for PM 'on-time'? SMRP 10%, fixed days, customer-specific?" — affects due-bucket thresholds.
3. **Capacity tables availability**: "Are `CALENDAR` and `WORKPERIOD` populated for crew schedules?" If not, skip workload-vs-capacity analytics or use a customer-specific source.
4. **Meter-based PM convention**: "Which `ASSETMETER.METERNAME` is your runtime meter for meter-based PMs?" Workspace glossary should hold the answer.

## Workflow priority

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `pms_due_in_window`, `pm_workload_hours`, `pm_to_cm_ratio`, `next_pm_due`, `meter_based_pm_forecast`
2. **Pre-joined views** in [views.sql](views.sql) — `v_pm_forecast`, `v_pm_workload_by_craft`, `v_jobplan_assets`, `v_pm_route_clusters`
3. **Parameterized examples** in [examples.sql](examples.sql)
4. **Raw tables** — last resort

## What's in this skill

- [schema.md](schema.md) — PM, PMSEQUENCE, JOBPLAN, JPLABOR, JPMATERIAL, JPSERVICE, JPSEGMENT, CALENDAR/WORKPERIOD references
- [gotchas.md](gotchas.md) — PMs vs WOs, PMSEQUENCE multi-frequency, EXTDATE coalesce (cross-ref), USETARGETDATE (cross-ref), ALERTLEAD, tolerance, meter forecasts, capacity tables, JOBPLAN sharing
- [examples.sql](examples.sql) — ~10 parameterized planning queries (incl. meter-based PM forecast moved from reliability)
- [views.sql](views.sql) — DDL for `v_pm_forecast`, `v_pm_workload_by_craft`, `v_jobplan_assets`, `v_pm_route_clusters`
- [metric_udfs.sql](metric_udfs.sql) — Trusted UC SQL functions

## What NOT to do

- **Don't use historical-performance UDFs from `maximo-reliability` for forecasting** — `pm_compliance` measures past compliance, not future workload. Use this skill's UDFs for forecasts.
- **Don't ignore `EXTDATE`** when forecasting — always `COALESCE(EXTDATE, NEXTDATE)` for the effective due date.
- **Don't forecast `STATUS != 'ACTIVE'` PMs** — inactive/draft PMs don't generate WOs.
- **Don't claim "we're overscheduled" without checking capacity table population** — if `CALENDAR`/`WORKPERIOD` are sparse, the math is wrong.
- **Don't ignore PMSEQUENCE** when summing PM workload — same PM may produce 3 different cadences of work.

## Composes with

- **`maximo-labor-resources`** — **the highest-value composition.** Workload-vs-capacity gap analytics: this skill provides forecast workload (`v_pm_workload_by_craft`, `pm_workload_hours` UDF); labor-resources provides matching capacity (`v_crew_capacity`, `crew_capacity_hours` UDF). The joined query — gap by craft × week — is the canonical answer to "are we over-scheduled?"
- **`maximo-asset-hierarchy`** — for forecast-PMs-rolled-up-to-region queries. The shipped `v_pm_route_clusters` uses `LOCATIONS.PARENT` (one-level); for deeper grouping, compose with `LOCANCESTOR` / `v_location_rollup_keys`.
- `maximo-reliability` — shares the PM schema; defer historical analytics to that skill.
- `maximo-work-orders` — PM-generated WOs are instances; backlog and execution status of forecast PMs surface there.
- `maximo-inventory` — `JPMATERIAL` aggregated for forecast PMs feeds future material demand.
- `maximo-maintenance-cost` — PM-vs-CM cost analysis (use `maintenance-cost`'s UDF).

## References

- [schema.md](schema.md)
- [gotchas.md](gotchas.md)
- [examples.sql](examples.sql)
- [views.sql](views.sql)
- [metric_udfs.sql](metric_udfs.sql)
- IBM PM forecast logic: https://www.ibm.com/docs/en/mas-cd/maximo-manage/continuous-delivery?topic=forecasting-preventive-maintenance-forecast-logic
- Maximo Secrets — PM forecasting + hierarchies: https://maximosecrets.com/2023/04/05/meter-based-pms-and-pm-hierarchies-2/
