---
name: maximo-work-orders
description: |
  Use for IBM Maximo / Maximo / EAM / CMMS work-order analytics: querying,
  analyzing, or building pipelines on WORKORDER + WOSTATUS data — backlog,
  aging, status history, completion, labor by craft, planned vs actual,
  asset/location/job-plan joins. Triggers on: "open work orders",
  "WO backlog", "WORKORDER", "WOSTATUS", "work order status history",
  "labor hours by craft", "completed WOs", "completed vs closed work",
  "preventive vs corrective maintenance", "WO aging", "actual vs planned
  labor", "top assets by WO volume", "rework", "follow-up work orders",
  "work order optimization dashboard", and any question about work-order
  operations. Compose with maximo-overview for baseline data
  model literacy, maximo-labor-resources for labor master, and
  maximo-asset-hierarchy for hierarchical rollups.
metadata:
  version: "0.3.0"
parent: maximo-overview
---

# Maximo Work Orders

Help the user query, analyze, or build pipelines on IBM Maximo work-order data. This skill adds the work-order-specific schema, gold-standard queries, reusable views, and Trusted UDFs on top of `maximo-overview`'s baseline data-model literacy and universal gotchas.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas. This skill builds on that foundation.

## When to use

Triggered by work-order operational questions:
- "What's our open WO backlog?"
- "Show me WOs aging over 90 days"
- "Labor hours by craft last month"
- "How many corrective vs preventive WOs did we complete?"
- "Status history for WO X"
- "Top assets by WO volume"
- "Actual vs planned labor on completed WOs"
- "Build a work-order-optimization dashboard"

**Defer to siblings when:**
- Reliability metrics (MTBF, MTTR, PM compliance) → `maximo-reliability`
- Forward-looking PM planning (forecasts, JOBPLAN content management) → `maximo-pm-planning`
- Integrity / inspection workflows → `maximo-integrity`

## Top gotchas

These traps silently produce wrong numbers. Read before writing any non-trivial query (full set of 15 in [gotchas.md](gotchas.md); `maximo-overview` carries the universal ones, including `WORKORDER.STATUS`-current-vs-`WOSTATUS`-history):

1. **`WHERE WOCLASS = 'WORKORDER'`.** The `WORKORDER` table also holds `PM`, `CHANGE`, `RELEASE`, `ACTIVITY` records. Almost every WO query must filter to `'WORKORDER'`, or backlog/labor/aging numbers inflate.
2. **`ISTASK = 0` to drop tasks — but mind child WOs.** `ISTASK = 1` rows are tasks *within* a parent (not standalone WOs); `ISTASK = 0` with a `PARENT` set is a *child work order* (independently tracked). Count `ISTASK = 0` for WO counts; for top-level headers only, add `PARENT IS NULL`. `PARENT` is mutable (work packages regroup WOs).
3. **`SITEID` in every join.** `WONUM`, `ASSETNUM`, `LOCATION` are unique only within a site. Multi-site customers reuse the same `WONUM` at different sites — joining without `SITEID` produces a cross product.
4. **`STATUS` is a synonym domain, and `HISTORYFLAG` hides closed work.** `WORKORDER.STATUS` stores the customer-renamable synonym (`VALUE`), not the internal `MAXVALUE` — so a literal `STATUS IN ('COMP',…)` silently misses custom synonyms. Resolve via `SYNONYMDOMAIN` (gotcha 5). Separately, closed/cancelled WOs get `HISTORYFLAG = 1` and standard Maximo views filter `HISTORYFLAG = 0` — confirm closed work is even present before computing completion/trend metrics.
5. **`COMP` ≠ `CLOSE` for "completed work."** `COMP` = physical work done; `CLOSE` = a separate, often-deferred finalization (many shops never CLOSE). Key "completed" on `COMP`-or-later, not `CLOSE`. (`WPLABOR`/`WPMATERIAL` = PLANNED vs `LABTRANS` = ACTUAL, and the rest, are in [gotchas.md](gotchas.md).)

## Questions to surface first

Surface these to the user *before* answering — there is no defensible default:

1. **Open-status set.** "Open" is customer-configurable. Maximo defaults usually mean *every status except* `COMP`, `CLOSE`, `CAN` — but each customer may extend `WOSTATUS` synonyms differently. Default: `('WAPPR','APPR','INPRG','WSCH','WMATL')`. Confirm or override. The canonical lookup is `SYNONYMDOMAIN` filtered to `DOMAINID = 'WOSTATUS'` — and because `STATUS` stores the *synonym* (`VALUE`), resolve the set from the internal `MAXVALUE` rather than hard-coding literals (gotcha 5).
2. **"Completed" definition.** Does the user mean `COMP` (physical work done) or only `CLOSE` (finalized)? Default to `COMP`-or-later, since closing is frequently deferred. Also confirm closed WOs are present in the data at all — some pipelines mirror Maximo's `HISTORYFLAG = 0` filter and silently drop them (gotcha 11).
3. **Backlog age date column.** "Days aged" can mean `current_date() - REPORTDATE` (created) or `current_date() - STATUSDATE` (days in current status). These produce different numbers. Confirm which the user wants.
4. **`WORKTYPE` codes.** Defaults (`CM`, `PM`, `EM`, `PROJ`) are advisory — many customers add 10+ work types or use different codes entirely. If a question depends on the corrective-vs-preventive split, confirm the codes that exist in this deployment. Note: work type is *not* a clean reactive-vs-proactive proxy (gotcha 14) — for that ratio, defer to `maximo-reliability`.

## Pre-flight (per session)

One-time session config — cache, don't re-ask:

1. **Catalog/schema** — confirm via the customer's workspace glossary skill if installed, or ask.
2. **Glossary skill** — is a `<customer>-maximo-glossary` workspace skill installed? Prefer it for business-term resolution.

If a business term is ambiguous and no glossary covers it, **ask before guessing**.

## Workflow

For any new question, resolve in this order:

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `open_wo_count`, `wo_aging_bucket`, `mean_time_to_complete`, `backlog_age_days`, `time_in_current_status`. If a UDF matches the question, call it.
2. **Parameterized example query** — check [examples.sql](examples.sql) for an existing pattern; use it with the user's parameters.
3. **Pre-joined view** — compose using `v_workorder_enriched` / `v_workorder_status_history` / `v_labor_actuals` from [views.sql](views.sql).
4. **Raw tables** — only when the view layer doesn't cover the join shape. Explain why you're skipping the views.

## What's in this skill

- [schema.md](schema.md) — load when joining or selecting columns. Full reference for `WORKORDER`, `WOSTATUS`, `ASSET`, `LOCATIONS`, `LABTRANS`, `WPLABOR`/`WPMATERIAL`, `JOBPLAN`, `FAILUREREPORT`.
- [gotchas.md](gotchas.md) — load before writing non-trivial joins. 15 gotchas: the inline 5 plus status-synonym resolution, `HISTORYFLAG`/`COMP`-vs-`CLOSE`/`HISTEDIT`, follow-up (originator) hierarchies, app-server-timezone date storage, corrective≠reactive, per-record cost columns, REST-API ingestion gap, date semantics, failure-code hierarchy, custom worktypes.
- [examples.sql](examples.sql) — load when the user's question matches a pattern (backlog by site, aging buckets, MTTC, actual vs planned, status history, craft utilization, failure pareto).
- [views.sql](views.sql) — DDL for `v_workorder_enriched`, `v_workorder_status_history`, `v_labor_actuals`. Register once via `maximo-setup`.
- [metric_udfs.sql](metric_udfs.sql) — Trusted Asset UC SQL functions Genie Code calls as governed metrics instead of regenerating ad-hoc SQL. Register once via `maximo-setup`.

## What NOT to do

- Don't write reliability metrics (MTBF / MTTR / PM compliance) — that's `maximo-reliability`'s job.
- Don't ignore the universal gotchas from `maximo-overview` (composite-key joins, status history, ISTASK dedup, WOCLASS filter).
- Don't hard-code the open-status set — surface the question to the user (see *Questions to surface first*) or read from the workspace glossary.
- Don't fabricate columns not in [schema.md](schema.md). If the user mentions a custom column, check the workspace glossary or ask.
- Don't write or alter UC comments / table metadata from this skill — UC comments are owned by `maximo-setup` (preview-then-apply, gated on explicit user approval). Defer to it.

## Composes with

- **`maximo-labor-resources`** for labor master detail (`LABOR`, `PERSON`, qualifications, crews). This skill uses `LABTRANS.LABORCODE` as a foreign key but doesn't document the labor master itself.
- **`maximo-asset-hierarchy`** for hierarchical rollups ("open WOs under station X", "backlog by region"). Use `v_location_rollup_keys` to roll up WO counts/cost to any location parent.
- **`maximo-maintenance-cost`** for any cost question beyond a single-record readout — cost rollup, estimate-vs-actual variance, contractor spend, PM-vs-CM cost, and multi-currency (`WOCURRENCY`) normalization. This skill's views pass `ACTLABCOST`/`ACTMATCOST` through but don't own cost methodology (gotcha 15).
- **`maximo-reliability`** for reliability KPIs computed *from* WO data — MTBF, MTTR, PM compliance, and reactive-vs-proactive / schedule-compliance ratios (which must be measured on labor hours, not WO counts — gotcha 14).
- **`maximo-setup`** to register the views in [views.sql](views.sql) and the Trusted UDFs in [metric_udfs.sql](metric_udfs.sql). Never run those scripts from this skill — defer to setup's preview-then-apply workflow.
