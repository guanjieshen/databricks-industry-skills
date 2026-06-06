---
name: wellview-daily-ops-cost
description: |
  Use for Peloton WellView daily-operations and cost analytics: the daily
  drilling/workover report, the operations time log, and job cost — NPT
  (non-productive time), days-vs-depth, cost per foot, AFE vs actual / cost
  overrun, daily and cumulative cost, ROP. Works against WVJOBREPORT (daily
  report), the time-log table (WVJOBREPORTOP / operations), WVCOST, and
  WVAFE. Triggers on: "daily drilling report", "tour sheet", "time log",
  "NPT", "non-productive time", "cost per foot", "AFE vs actual", "cost
  overrun", "are we over AFE", "days vs depth", "days per 1000 ft", "ROP",
  "rate of penetration", "cumulative cost", "spend on the last well". Compose
  with wellview-overview for the record tree + master-unit gotchas.
metadata:
  version: "0.1.0"
parent: wellview-overview
---

# WellView Daily Ops & Cost

Help a drilling/workover supervisor or cost/AFE engineer query and analyze WellView
daily-operations and cost data. This skill adds the daily-report / time-log / cost schema,
gold-standard queries, reusable views, Trusted UDFs, and a metric view on top of
`wellview-overview`'s record-tree literacy and universal gotchas.

> **FIRST:** load the `wellview-overview` skill — it carries the WellView record tree
> (`IDREC`/`IDRECPARENT`/`IDWELL`), the `WV`/`LV`/`SYS` grammar, the
> well→job→report→cost spine, and the universal gotchas (master units, calc-vs-stored,
> one-well-many-jobs, AFE allocation, `LV` decode). This skill builds on that.

## When to use

Triggered by daily-ops and cost questions:
- "Pull the daily drilling report for well X on 2026-05-10"
- "How much NPT did we have on the last well, and what caused it?"
- "Cost per foot on our last 5 wells"
- "Are we over AFE on this job? By how much?"
- "Days vs depth curve for the Permian wells"
- "Cumulative cost to date on job Y"
- "Average ROP by hole section"

**Defer to siblings when:**
- ROP/MSE bit-by-bit performance and deep NPT root-cause by phase → `wellview-drilling-npt`
- Completion design, perforations, stimulation, workover scope → `wellview-completions-workovers`
- Barriers, pressure/annulus tests, well status → `wellview-well-integrity`

## Top gotchas

These silently produce wrong numbers. Read before any non-trivial query (full set in
[gotchas.md](gotchas.md); `wellview-overview` carries the universal record-tree + unit gotchas):

1. **Walk the tree by `IDRECPARENT = parent.IDREC`, never `IDWELL`.** Daily reports join to
   their job via `WVJOBREPORT.IDRECPARENT = WVJOB.IDREC`; time-log rows to their report via
   `op.IDRECPARENT = WVJOBREPORT.IDREC`. `IDWELL` only filters to a well; joining the tree on
   it fans out and double-counts.
2. **One well has many jobs — group by `WVJOB.IDREC` before rolling to the well.** Cost/footage/
   days summed across a well that has had drill + workover + re-entry jobs double-counts. For
   "the last well," confirm which **job** (usually the latest drilling job), not the whole well.
3. **Numbers are stored in master units, not display units.** Depth/footage may be feet **or**
   metres; cost carries a currency. Raw columns are unlabeled master units. **Confirm the master
   unit via the glossary and normalize before cost/ft, days/1000ft, or ROP.** The #1 invisible error.
4. **`CostCum`, `DaysFromSpud`, `ROP` may be calc-engine outputs, not stored columns.** If they're
   absent from the extract, recompute via the Trusted UDFs / views here — don't assume they exist.
5. **Decode NPT / operation / cost codes through `LV` tables.** Whether an activity is NPT, and what
   a cost code rolls up to, is customer-configurable in `LVWVCODENPT` / `LVWVCODEOP` / `LVWVCODECOST`.
   Never hard-code code literals; resolve via the glossary or the `LV` join.

## Questions to surface first

Surface these to the user *before* answering — there is no defensible default:

1. **What counts as NPT?** WellView marks productive-vs-NPT via a flag and/or an `LVWVCODENPT`
   reason code, and operators differ on whether **planned** downtime (BOP tests, rig moves, waiting
   on weather) counts. Confirm the NPT rule (productive flag, code set, planned-vs-unplanned) before
   computing NPT % — it changes the number materially.
2. **Cost-per-foot scope.** Over which **interval** (a hole section, a single job, or the whole
   well)? Which **cost codes** (all-in, intangibles-only, rig spread only)? Per **job or per well**?
   These give very different $/ft. Confirm before computing.
3. **AFE variance baseline.** Which AFE amount is "the AFE" — the original, or the latest supplement?
   And because AFEs **allocate across multiple jobs/wells by percentage**, confirm how a shared AFE
   should be attributed before reporting overrun %.
4. **Days-vs-depth anchoring.** Days counted from **spud** or from **job start**? Depth as **MD** or
   **TVD**? And which jobs belong on the same benchmark curve (same well type / section / area)? A
   days-vs-depth chart mixing unlike wells is misleading.

## Pre-flight (per session)

One-time session config — cache, don't re-ask:

1. **Catalog/schema** — confirm via the customer's `<customer>-wellview-glossary` skill if installed, or ask.
2. **Glossary skill** — installed? Prefer it for physical table/column names, **master units**, and `LV` decodes.
3. **Master units known?** If `wellview-setup` hasn't recorded the unit of depth/footage/cost, **stop and
   resolve that first** — every metric here depends on it.

If a business term or code is ambiguous and no glossary covers it, **ask before guessing**.

## Workflow

**Building a semantic layer / Genie Agent / dashboard (the most common ask):** start from
[metric_view.yaml](metric_view.yaml) — the governed daily-ops/cost semantic layer. Its measures
(`cost_per_foot`, `npt_pct`, `afe_variance_pct`, `cumulative_cost`, `days_on_well`, `avg_rop`) and
**agent metadata** (synonyms like "cost/ft", "NPT", "over AFE", "days vs depth") are defined once and
sliceable by well / job / job type / hole section / rig. Defer creation & registration mechanics to the
platform skill [`databricks-metric-views`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-metric-views); `wellview-setup` owns registration.

**Answering an ad-hoc question:** resolve in this order:

1. **Metric view** — if `wellview_daily_ops_metrics` is registered, query it with `MEASURE(...)`; it
   encodes the canonical definitions (master-unit normalization + per-job grain baked in).
2. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `wellview_cost_per_foot`, `wellview_npt_pct`,
   `wellview_afe_variance_pct`, `wellview_rop`, `wellview_ft_to_m` — when the metric takes parameters.
3. **Parameterized example query** — check [examples.sql](examples.sql) for a matching pattern; use it
   with the user's parameters (`:param` syntax).
4. **Pre-joined view** — compose using `v_daily_report_enriched` / `v_time_log_enriched` /
   `v_job_cost_rollup` from [views.sql](views.sql).
5. **Raw tables** — only when the view layer doesn't cover the join shape, and only after units / job
   selection / `LV` decodes are confirmed. Explain why you're skipping the views.

## What's in this skill

- [schema.md](schema.md) — load when joining or selecting columns. The daily-report / time-log / cost / AFE spine (canonical → resolve to physical via glossary).
- [gotchas.md](gotchas.md) — load before writing non-trivial joins. The record-tree, master-unit, one-well-many-jobs, calc-vs-stored, `LV`-decode, AFE-allocation, and 24-hour-reconciliation traps in depth.
- [examples.sql](examples.sql) — load when the user's question matches a pattern (daily report readout, NPT %, cost per foot, AFE variance, days-vs-depth, cumulative cost).
- [views.sql](views.sql) — DDL for `v_daily_report_enriched`, `v_time_log_enriched`, `v_job_cost_rollup`. Register once via `wellview-setup`.
- [metric_udfs.sql](metric_udfs.sql) — Trusted Asset UC SQL functions Genie calls as governed metrics instead of regenerating ad-hoc SQL. Register once via `wellview-setup`.
- [metric_view.yaml](metric_view.yaml) — **load when** building/extending the daily-ops/cost semantic layer, a Genie Agent, or a dashboard. Canonical measures + agent metadata over `v_daily_report_enriched`, with master-unit normalization and per-job grain baked in. Register once via `wellview-setup`; mechanics live in the platform skill `databricks-metric-views`.

## What NOT to do

- Don't join the record tree on `IDWELL` — use `IDRECPARENT = parent.IDREC`.
- Don't roll cost/footage/days to the well without grouping by job — multiple jobs double-count.
- Don't compute cost/ft, days/1000ft, or ROP before confirming the master unit of depth/footage and the cost currency.
- Don't hard-code NPT / operation / cost code literals — decode via the `LV` tables / glossary.
- Don't assume `CostCum` / `DaysFromSpud` / `ROP` are stored columns — recompute via the UDFs/views if absent.
- Don't declare a job "on budget" or "ahead of plan" without surfacing the AFE-baseline and NPT-definition assumptions you used.
- Don't write or alter UC comments / table metadata from this skill — that's `wellview-setup`'s job (preview-then-apply, gated on approval).

## Composes with

- **`wellview-overview`** for the record tree, `WV`/`LV`/`SYS` grammar, and universal gotchas (master units, calc-vs-stored). This skill assumes that literacy.
- **`wellview-setup`** to register the views, Trusted UDFs, and metric view, and to supply the glossary (physical names + **units** + `LV` decodes). Never run those scripts from this skill — defer to setup's preview-then-apply flow.
- **`wellview-drilling-npt`** for bit-by-bit ROP/MSE and deep NPT root-cause by phase/operation code. This skill reports NPT % and section ROP; that one owns drilling-performance methodology.
- **`wellview-data-engineering`** for the conformed per-job Silver/Gold spine the views build on (master-unit normalization at Silver→Gold).
- **`databricks-metric-views`** (platform) — the *mechanics* of creating/registering/refreshing the metric view. This skill supplies the source-specific YAML + agent metadata; that skill supplies the how.
- **`databricks-genie`** (platform) — Genie Agent creation mechanics, when standing up a daily-ops/cost agent.
