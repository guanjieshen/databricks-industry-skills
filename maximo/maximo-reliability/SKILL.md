---
name: maximo-reliability
description: |
  Use for asset reliability and maintenance-performance metrics on IBM Maximo
  (Maximo, EAM, CMMS) data — MTBF, MTTR, PM compliance, failure-mode / failure-rate
  analysis, bad-actor assets, time-between-failures, time-since-last-failure, and
  SMRP reactive-vs-proactive / planned-vs-unplanned / schedule-compliance ratios.
  Reads FAILUREREPORT, FAILURECODE (PROBLEM/CAUSE/REMEDY), PM, PMANCESTOR,
  ASSETMETER, METERREADING and WORKORDER failure events; joins LABTRANS for
  labor-hour-based reliability ratios. Ships UC SQL Trusted-Asset functions for
  the canonical formulas (matching IBM's published O&G MTBF/MTTR definitions) so
  reliability engineers can reconcile to the Maximo UI. Triggers on: "MTBF",
  "MTTR", "PM compliance", "failure analysis", "failure rate", "bad actor",
  "reliability scorecard", "mean time between failures", "mean time to repair",
  "RCM", "SMRP metric", "reactive vs proactive", "schedule compliance",
  "meter excursion", "condition monitoring".
metadata:
  version: "0.2.0"
parent: maximo-overview
---

# Maximo Reliability

Compute asset reliability and maintenance-performance metrics on Maximo data — MTBF, MTTR, PM compliance, failure-mode / failure-rate analysis, bad-actor ranking, and SMRP reactive-vs-proactive ratios.

The defining quality of this skill: **registered Trusted UDFs whose output matches what's displayed in the Maximo UI**, so reliability engineers can reconcile dashboard numbers against Maximo screens.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas (SITEID composite keys, `WOCLASS` filtering, `ISTASK` dedup, status-is-a-synonym-domain / `SYNONYMDOMAIN` resolution, `HISTORYFLAG`, app-server-timezone datetimes, current-`STATUS`-vs-`WOSTATUS`-history). This skill builds on that foundation and APPLIES those patterns in its own SQL.

## When to use

- "What's the MTBF for centrifugal pumps?"
- "MTTR by asset class last year"
- "PM compliance for Q3"
- "Top failure modes / failure rate on our rotating equipment"
- "Which assets are bad actors?"
- "Reliability scorecard"
- "Reactive vs proactive ratio" / "planned vs unplanned" / "schedule compliance"
- "Time-since-last-failure for asset X"

For raw WO analytics (backlog, status, aging, labor actuals), defer to `maximo-work-orders`. For **forward-looking** PM forecasting / job-plan content / frequency, defer to `maximo-pm-planning` — this skill is **backward-looking** PM performance. For regulatory inspection / integrity / RBI compliance (different from SMRP-style PM compliance), defer to `maximo-integrity`.

## Top gotchas

These traps silently produce wrong reliability numbers. Read before writing any non-trivial query (full set in [gotchas.md](gotchas.md); `maximo-overview` carries the universal mechanics):

1. **A "failure event" ≠ "WO closed", and reactive ≠ corrective.** Per SMRP, reactive-vs-proactive and planned-vs-unplanned ratios must be computed on **labor hours** (`LABTRANS`), not WO counts; and "corrective" is ORTHOGONAL to "reactive" — corrective work identified pre-failure from PM/PdM is PROACTIVE. Do not equate `WORKTYPE = 'CM'` with reactive (gotcha 9).
2. **`HISTORYFLAG` hides the very records reliability needs.** Closed/cancelled records get `HISTORYFLAG = 1` and standard Maximo views filter `HISTORYFLAG = 0`. Reliability metrics are computed almost entirely on completed/closed work — confirm closed records are present before trusting any MTBF/MTTR/compliance number. Universal mechanic — see `maximo-overview`.
3. **Status is a synonym domain — resolve, don't hard-code.** `WORKORDER.STATUS` stores the customer-renamable synonym (`VALUE`), not the internal `MAXVALUE`. A literal `status IN ('COMP','CLOSE')` silently misses custom synonyms; resolve the "completed" set via `SYNONYMDOMAIN` (`DOMAINID = 'WOSTATUS'`). Universal mechanic — see `maximo-overview`. The shipped UDFs/views apply this pattern.
4. **Failure-event timestamp ≠ repair-completion timestamp.** Reliability anchors on *when the failure occurred*, not when the WO closed. Use `COALESCE(ACTSTART, REPORTDATE)` as the failure-time default; `ACTFINISH` is biased toward repair completion (gotcha 4). When bucketing failures by day/week/month across sites, remember datetimes are app-server-TZ, not per-row UTC (`maximo-overview`).
5. **Effective PM due date is `COALESCE(EXTDATE, NEXTDATE)`, only on `ACTIVE` PMs.** `PM.EXTDATE` is a one-time override that supersedes `NEXTDATE` (and auto-clears after WO generation); using only `NEXTDATE` mis-classifies legitimate extensions as overdue. Only `PM.STATUS = 'ACTIVE'` PMs forecast (gotchas 2a–2c). Use `PMANCESTOR` (not naive `PARENT`) for PM-hierarchy roll-ups (gotcha 2d).

## Questions to surface first

Surface these *before* answering — there is no defensible default:

1. **PM-compliance definition.** At least three valid definitions exist: SMRP (completed within a tolerance window / scheduled), strict on-time (completed by effective due date / due in period), or a customer-specific tolerance/denominator. Confirm which, and the tolerance %. Default ships as SMRP 10% (gotcha 2).
2. **"Bad actor" framing.** Four valid framings: top-N by failure count, by total downtime, by repair cost, or by criticality-weighted failure count. Confirm which (gotcha 7). For the cost-weighted framing, cost methodology belongs to `maximo-maintenance-cost`.
3. **Failure-classification depth.** `FAILURECODE` is a tree (PROBLEM → CAUSE → REMEDY). Confirm which level the user wants aggregations at — `GROUP BY FAILURECODE` aggregates at the leaf and is usually too granular (gotcha 3).
4. **Reactive vs proactive vs corrective.** Confirm the user's intended split. SMRP reactive-vs-proactive is a labor-hour ratio and is *not* the `WORKTYPE` corrective-vs-preventive split (gotcha 9). Also confirm whether schedule compliance excludes break-in work and whether a planned-flag exists in this deployment (often not derivable from raw MBO).

## Pre-flight (per session)

One-time session config — cache, don't re-ask:

1. **Catalog/schema** — confirm via the customer's workspace glossary skill if installed, or ask.
2. **Glossary skill** — is a `<customer>-maximo-glossary` installed? Prefer it for asset-class resolution ("centrifugal pumps" → `CLASSSTRUCTUREID` IDs, gotcha 8) and status-synonym sets.

If a business term is ambiguous and no glossary covers it, **ask before guessing**.

## Workflow

For any new question, resolve in this order:

1. **Trusted UDF** — if a registered UC SQL function in [metric_udfs.sql](metric_udfs.sql) computes what's asked (`mtbf`, `mttr`, `pm_compliance`, `time_since_last_failure`, `time_since_last_pm`), call it directly. These earn the Trusted-asset badge in Genie. Do not reinvent the MTBF/MTTR formula or the number won't reconcile to the Maximo screen.
2. **Parameterized example** — check [examples.sql](examples.sql) for an existing pattern; use it with the user's parameters.
3. **Pre-joined view** — compose against `v_failure_events`, `v_pm_schedule`, `v_meter_excursions`, `v_asset_reliability_summary` from [views.sql](views.sql).
4. **Raw tables** — last resort; explain why the view layer doesn't cover the join shape.

## What's in this skill

- [schema.md](schema.md) — load when joining or selecting columns. `FAILUREREPORT`, `FAILURECODE`, `PM`, `PMANCESTOR`, `PMSEQUENCE`, `ASSETMETER`, `METERREADING`, and `WORKORDER` filtered to failure events.
- [gotchas.md](gotchas.md) — load before writing non-trivial joins. MTBF/MTTR definitional traps, PM-compliance ambiguity (`COALESCE(EXTDATE, NEXTDATE)`, fixed-vs-floating, `ACTIVE`-only, `PMANCESTOR`), failure-code hierarchy flattening, failure-timestamp choice, SMRP reactive-vs-proactive on labor hours, bad-actor framings, asset-class resolution.
- [examples.sql](examples.sql) — load when the question matches a pattern (MTBF/MTTR by class, PM compliance by site, failure-mode pareto, bad actors, time-since-last-failure, overdue PMs, meter excursions, PM-tree roll-ups).
- [views.sql](views.sql) — DDL for `v_meter_excursions`, `v_asset_reliability_summary` (composes `v_failure_events`, `v_pm_schedule` from `maximo-data-engineering`). Register once via `maximo-setup`.
- [metric_udfs.sql](metric_udfs.sql) — Trusted Asset UC SQL functions Genie Code calls as governed metrics instead of regenerating ad-hoc SQL. Register once via `maximo-setup`.

## What NOT to do

- **Don't invent MTBF/MTTR formulas.** Use the registered UDFs (matched to IBM's O&G definitions). If the customer has a non-standard definition, register a customer-prefixed UDF alongside — don't replace the canonical one.
- **Don't equate `WORKTYPE = 'CM'` with "reactive."** Reactive-vs-proactive is an SMRP labor-hour ratio; corrective work found pre-failure is proactive (gotcha 9).
- **Don't aggregate `FAILURECODE` without flattening** the hierarchy to the level the user asked for (gotcha 3).
- **Don't conflate PM compliance (operational) with regulatory inspection compliance** — different metrics, different stakes. Regulatory/RBI compliance lives in `maximo-integrity`.
- **Don't trust counts without confirming closed records are present** (`HISTORYFLAG`) and without filtering `WOCLASS = 'WORKORDER'` (both universal — `maximo-overview`).
- **Don't compute cost-based bad-actor rankings or multi-currency sums here** — cost rollup, repair-cost methodology, and `WOCURRENCY` normalization belong to `maximo-maintenance-cost`.
- **Don't write or alter UC comments / table metadata** from this skill — owned by `maximo-setup` (preview-then-apply, gated on explicit user approval).

## Composes with

- **`maximo-work-orders`** for the raw WO analytics reliability builds on (backlog, status, aging, labor actuals). This skill reads WORKORDER failure events but doesn't own WO-lifecycle mechanics.
- **`maximo-pm-planning`** for forward-looking PM forecasting, job-plan content, and frequency. This skill is backward-looking PM performance only; several PM gotchas (`COALESCE(EXTDATE, NEXTDATE)`, `USETARGETDATE`, `ACTIVE` filter, `PMANCESTOR`) are shared.
- **`maximo-asset-hierarchy`** for hierarchical roll-ups and closure-table mechanics (`PMANCESTOR` follows the same probe-before-use / recursive-CTE-fallback patterns as `LOCANCESTOR` / `ASSETANCESTOR`).
- **`maximo-maintenance-cost`** for any cost-weighted reliability question — repair-cost-ranked bad actors, cost-per-failure, and multi-currency (`WOCURRENCY`/`EXCHANGERATE`) normalization. This skill ranks on failure count / downtime / criticality, not cost.
- **`maximo-integrity`** for regulatory inspection / RBI compliance (distinct from SMRP PM compliance).
- **`maximo-setup`** to register the views and Trusted UDFs. Never run those scripts from this skill — defer to setup's preview-then-apply workflow.

## References

- [schema.md](schema.md) · [gotchas.md](gotchas.md) · [examples.sql](examples.sql) · [views.sql](views.sql) · [metric_udfs.sql](metric_udfs.sql)
- IBM MTBF/MTTR fields explained (O&G): https://www.ibm.com/support/pages/mttr-and-mtbf-fields-explained-maximo-oil-gas-asset-oil-application
- IBM PM forecast logic: https://www.ibm.com/docs/en/mas-cd/maximo-manage/continuous-delivery?topic=forecasting-preventive-maintenance-forecast-logic
- SMRP best practices: https://smrp.org/
