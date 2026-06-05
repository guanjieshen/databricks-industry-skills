---
name: maximo-pm-planning
description: |
  Use for forward-looking IBM Maximo / Maximo / EAM / CMMS preventive-maintenance
  planning analytics — forecasting upcoming PMs, planned workload by craft, route
  grouping by location, capacity-vs-demand balancing, JOBPLAN content management,
  PM coverage-gap analysis, PM-to-CM ratio (program health), meter-based PM
  forecasts. Operates on PM, PMSEQUENCE, JOBPLAN, JPLABOR, JPMATERIAL, JPSERVICE,
  JPSEGMENT, ASSETMETER. Triggers on: "PM forecast", "PMs due", "upcoming PMs",
  "PM workload", "craft workload", "PM coverage gap", "JOBPLAN", "JPLABOR",
  "JPMATERIAL", "route optimization", "PM schedule", "next PM due",
  "PM-to-CM ratio", "PM planning", "weekly PM workload", "meter-based PM",
  "NEXTDATE", "EXTDATE", "are we over-scheduled". For backward-looking PM
  performance (compliance %, MTBF) use maximo-reliability; for PM cost compose
  with maximo-maintenance-cost.
metadata:
  version: "0.2.0"
parent: maximo-overview
---

# Maximo PM Planning

Help maintenance planners and reliability engineers forecast PM workload, plan resource capacity, manage JOBPLAN content, and optimize PM strategy. The **forward-looking** companion to `maximo-reliability` (backward-looking). Adds the planning-specific schema, gold-standard forecast queries, reusable views, and Trusted UDFs on top of `maximo-overview`'s baseline data-model literacy and universal gotchas.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas (SITEID composite keys, status-is-a-synonym-domain / `SYNONYMDOMAIN` resolution, `HISTORYFLAG`, app-server-timezone datetimes, `WOCLASS`, `ISTASK`). This skill builds on that foundation and does NOT re-teach those mechanics.

## When to use

Triggered by forward-looking PM-planning questions:
- "Forecast PMs due in next 30 / 60 / 90 days"
- "Craft workload forecast next quarter"
- "What's in JOBPLAN JP-PUMP-3MO?"
- "JOBPLAN edit impact — which PMs use this template?"
- "Critical assets without any PMs"
- "PM-to-CM ratio trend"
- "Route clustering — PMs grouped by location"
- "Next PM due for asset X" / "Meter-based PM forecast for ASSET-123"
- "Are we over-scheduled this week?"

**Defer to siblings when:**
- Backward-looking PM performance — compliance %, time-since-last-PM, MTBF → `maximo-reliability`
- PM cost (PM-vs-CM *cost*, planned-vs-actual cost variance) → `maximo-maintenance-cost`
- Crew capacity / availability master (`CALENDAR`, `WORKPERIOD`, `AVAILREFLY`) → `maximo-labor-resources`

Both this skill and `maximo-reliability` touch the `PM` table. Direction decides: forecast / upcoming workload / JOBPLAN content / strategy design → here; "how well did our PMs perform?" → reliability.

## Top gotchas

These traps silently produce wrong forecasts. Read before writing any non-trivial query (full set in [gotchas.md](gotchas.md); `maximo-overview` carries the universal ones — apply them, don't re-derive them):

1. **The `PM` is the schedule; the `WORKORDER` is the instance.** Forecast against `PM` using `COALESCE(EXTDATE, NEXTDATE)` as the effective due date. Historical execution lives in `WORKORDER WHERE PMNUM IS NOT NULL` (that's `maximo-reliability`'s territory). Never mix both directions in one query.
2. **Expand `PMSEQUENCE` before counting or summing.** One PM row can fire multiple cadences (e.g. 30-day lube + 90-day inspection + 365-day rebuild), each a `PMSEQUENCE` row with its own `JPNUM`/`FREQUENCY`. A naive `COUNT(*) FROM PM` undercounts workload. `LEFT JOIN pmsequence` so single-cadence PMs (no sequence rows) survive.
3. **Only active PMs generate work — and `PM.STATUS` is a synonym domain.** Inactive/draft PMs sit in the table but never fire. Filter to the active set, but note `PM.STATUS` stores the customer-renamable synonym `VALUE` (domain `PMSTATUS`), not the internal `MAXVALUE` — a literal `status = 'ACTIVE'` is correct only in a stock deployment. Resolve via `SYNONYMDOMAIN` when the customer has renamed it (see `maximo-overview` status-synonym gotcha; example 11 in [examples.sql](examples.sql)).
4. **`COALESCE(EXTDATE, NEXTDATE)` is the effective due date — always.** `EXTDATE` (PM Extended Date) is a one-time override of `NEXTDATE`. Forecasting on `NEXTDATE` alone ignores deferrals/advances and is wrong.
5. **`SITEID` in every PM/PMSEQUENCE/asset join; `ORGID` for JOBPLAN joins.** PMs key on `(PMNUM, SITEID)`, but job-plan templates are **org-scoped** — join `JOBPLAN`/`JPLABOR`/`JPMATERIAL` on `(JPNUM, ORGID)`, not `SITEID`. Mixing the two grains cross-products or drops rows. (SITEID composite-key rule: `maximo-overview`.)

## Questions to surface first

Surface these to the user *before* answering — there is no defensible default:

1. **Forecast horizon.** "Over what window — next 30, 60, 90 days, or a quarter/year?" Bucket thresholds and the workload sum all depend on it.
2. **On-time tolerance convention.** "What tolerance defines a PM as 'on time' — SMRP 10% of frequency, a fixed number of days, or customer-specific?" The shipped views use tolerance-independent due buckets (OVERDUE / DUE_30D / DUE_60D / DUE_90D / FUTURE); compliance-style on-time bucketing needs this answer.
3. **Active-PM set.** "Which `PM.STATUS` value(s) mean a PM is live?" Default `'ACTIVE'` is correct in stock Maximo, but `PMSTATUS` is a synonym domain — confirm the customer hasn't renamed it before hard-coding.
4. **Meter-based PM runtime meter.** "Which `ASSETMETER.METERNAME` is the runtime meter for meter-based PMs?" Required for meter-based forecasts; the workspace glossary should hold the answer.
5. **Capacity-table population.** "Are `CALENDAR` / `WORKPERIOD` populated for crew schedules?" If sparse, the "are we over-scheduled?" math is unreliable — say so rather than reporting a false gap.

## Pre-flight (per session)

One-time session config — cache, don't re-ask:

1. **Catalog/schema** — confirm via the customer's workspace glossary skill if installed, or ask.
2. **Glossary skill** — is a `<customer>-maximo-glossary` workspace skill installed? Prefer it for business-term and meter-name resolution.

If a planning convention is ambiguous and no glossary covers it, **ask before guessing** (see *Questions to surface first*).

## Workflow

For any new question, resolve in this order:

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `pms_due_in_window`, `pm_workload_hours`, `pm_to_cm_ratio`, `next_pm_due`, `meter_based_pm_forecast`. If a UDF matches, call it.
2. **Pre-joined views** in [views.sql](views.sql) — `v_pm_forecast`, `v_pm_workload_by_craft`, `v_jobplan_assets`, `v_pm_route_clusters`.
3. **Parameterized examples** in [examples.sql](examples.sql) — use the matching pattern with the user's parameters.
4. **Raw tables** — only when the view layer doesn't cover the join shape. Explain why you're skipping the views.

## What's in this skill

- [schema.md](schema.md) — load when joining or selecting columns. Planning-specific tables: `PM` forecast columns, `PMSEQUENCE`, `JOBPLAN`, `JPLABOR`, `JPMATERIAL`, `JPSERVICE`, `JPSEGMENT`, `ASSETMETER`, `CALENDAR`/`WORKPERIOD`. The full `PM` reference lives in `maximo-reliability/schema.md`.
- [gotchas.md](gotchas.md) — load before writing non-trivial forecasts. PMs-vs-WOs, `PMSEQUENCE` expansion, `COALESCE(EXTDATE, NEXTDATE)`, active-PM synonym set, fixed-vs-floating anchor, `ALERTLEAD`, tolerance windows, meter forecasts, capacity-table deferral, JOBPLAN org-scoping/sharing.
- [examples.sql](examples.sql) — load when the user's question matches a pattern (forecast by bucket, craft workload, coverage gap, PM-to-CM, route clustering, meter forecast, JOBPLAN impact, sequence expansion, synonym-safe active set).
- [views.sql](views.sql) — DDL for `v_pm_forecast`, `v_pm_workload_by_craft`, `v_jobplan_assets`, `v_pm_route_clusters`. Register once via `maximo-setup`.
- [metric_udfs.sql](metric_udfs.sql) — Trusted Asset UC SQL functions Genie Code calls as governed metrics instead of regenerating ad-hoc SQL. Register once via `maximo-setup`.

## What NOT to do

- **Don't use historical-performance UDFs from `maximo-reliability` for forecasting** — `pm_compliance` measures past compliance, not future workload. Use this skill's forecast UDFs.
- **Don't forecast on `NEXTDATE` alone** — always `COALESCE(EXTDATE, NEXTDATE)`.
- **Don't ignore `PMSEQUENCE`** when summing PM workload — one PM may produce 3 cadences of work.
- **Don't hard-code `status = 'ACTIVE'` blindly** — `PMSTATUS` is a synonym domain; resolve via `SYNONYMDOMAIN` if the customer renamed it (`maximo-overview`).
- **Don't claim "we're over-scheduled" without checking `CALENDAR`/`WORKPERIOD` population** — sparse capacity data makes the gap math wrong. Capacity master is owned by `maximo-labor-resources` — defer there, don't re-document it here.
- **Don't ignore the universal gotchas from `maximo-overview`** (SITEID composite keys, status-synonym resolution, `HISTORYFLAG` on `WORKORDER` queries, app-server-timezone date bucketing).
- **Don't fabricate columns** not in [schema.md](schema.md). If the user names a custom column, check the workspace glossary or ask.
- **Don't write or alter UC comments / table metadata** from this skill — those are owned by `maximo-setup` (preview-then-apply, gated on explicit approval). Defer to it.

## Composes with

- **`maximo-labor-resources`** — **the highest-value composition.** Workload-vs-capacity gap analytics: this skill provides forecast workload (`v_pm_workload_by_craft`, `pm_workload_hours` UDF); labor-resources provides matching capacity (`v_crew_capacity`, `crew_capacity_hours` UDF) and owns the `CALENDAR`/`WORKPERIOD`/`AVAILREFLY` availability master. The joined query — gap by craft × week — is the canonical answer to "are we over-scheduled?"
- **`maximo-asset-hierarchy`** — for forecast-PMs-rolled-up-to-region. The shipped `v_pm_route_clusters` uses `LOCATIONS.PARENT` (one level); for deeper grouping, compose with `LOCANCESTOR` / `v_location_rollup_keys`.
- **`maximo-reliability`** — shares the `PM` schema and owns the full `PM` reference; defer all backward-looking analytics (compliance %, MTBF, time-since-last) there.
- **`maximo-work-orders`** — PM-generated WOs are instances (`WORKORDER.PMNUM`); backlog and execution status of forecast PMs surface there. When querying generated WOs, apply `maximo-overview`'s `HISTORYFLAG`/`WOCLASS` rules.
- **`maximo-inventory`** — `JPMATERIAL` aggregated across forecast PMs feeds future material demand / stockout-risk checks (`INVENTORY`/`INVBALANCES`).
- **`maximo-maintenance-cost`** — PM-vs-CM *cost* and planned-vs-actual cost variance. This skill counts WOs and sums planned `JPLABOR`/`JPMATERIAL` line cost but does NOT own cost methodology or multi-currency normalization — defer there.
- **`maximo-setup`** — to register the views and Trusted UDFs. Never run those scripts from this skill — defer to setup's preview-then-apply workflow.

## References

- [schema.md](schema.md) · [gotchas.md](gotchas.md) · [examples.sql](examples.sql) · [views.sql](views.sql) · [metric_udfs.sql](metric_udfs.sql)
- IBM PM forecast logic: https://www.ibm.com/docs/en/mas-cd/maximo-manage/continuous-delivery?topic=forecasting-preventive-maintenance-forecast-logic
- Maximo Secrets — meter-based PMs + PM hierarchies: https://maximosecrets.com/2023/04/05/meter-based-pms-and-pm-hierarchies-2/
