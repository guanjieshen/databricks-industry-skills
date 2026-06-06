---
name: wellview-data-quality
description: |
  Use to diagnose data-quality issues with Peloton WellView data — orphan
  IDRECPARENT records, well/job double-counting, unit inconsistency (feet mixed
  with metres, multi-currency cost), calc-vs-stored mismatches (CostCum / ROP /
  DaysFromSpud missing), undecoded LV codes, time-log days that don't sum to
  24 h, and AFE over-allocation. The "this number looks wrong" playbook for
  WellView. Triggers on: "this WellView number looks wrong", "my cost per foot
  is off", "NPT seems too high", "audit WellView data quality", "why is my well
  cost double", "missing days from spud", "reconcile WellView to the daily
  report", "orphan records in WellView".
metadata:
  version: "0.1.0"
parent: wellview-overview
---

# WellView Data Quality

The diagnostic playbook for "this number looks wrong" on WellView data. Most wrong answers
trace to the record-tree, units, or grain — and because those errors are *invisible* in the
result, this skill surfaces them deliberately. Ordered probes; hand off the fix to the module.

> **FIRST:** load `wellview-overview` for the record tree, grammar, and universal gotchas.

## When to use

- "Cost per foot looks 3× too high / too low"
- "Well cost looks doubled"
- "NPT % seems wrong"
- "Days-from-spud / cumulative cost is blank"
- "Reconcile this Genie answer to the WellView daily report"

## Diagnostic playbook

Ordered. Start at probe 1; descend only when you've ruled out the prior cause. Load
[diagnostics.sql](diagnostics.sql) probe-by-probe.

1. **Unit inconsistency (#1 cause).** Is depth/footage being compared/divided across mixed
   units (feet vs metres), or cost summed across currencies? Profile value ranges and confirm
   the master unit against `SYSUNIT` / the glossary. A 3.28× cost-per-foot error is this.
2. **Well/job double-count.** Is the query grouping by `WVJOB.IDREC` before rolling to the
   well? A well with multiple jobs double-counts cost/footage/days without it.
3. **Record-tree join on `IDWELL`.** Is the tree joined on `IDWELL` instead of
   `IDRECPARENT = parent.IDREC`? That fans out every child against every job.
4. **Orphan `IDRECPARENT`.** Child rows whose parent `IDREC` is missing vanish from inner
   joins (or, with `IDWELL`, attach to the wrong parent). Count them.
5. **Calc-vs-stored.** Is the metric (`CostCum`, `DaysFromSpud`, `ROP`) a calc-engine output
   absent from the extract → returning NULL? Recompute it (see `wellview-data-engineering`).
6. **Undecoded LV codes.** Are coded columns (NPT, phase, cost) showing raw codes / NULL
   labels because the `LV` join missed? Confirm the `LV` table + code→label columns.
7. **24-hour reconciliation.** Do a report-day's time-log hours sum to ~24? Sums of 19 or 26
   signal missing/overlapping activities (or midnight-crossing math).
8. **AFE over-allocation.** Do `WVAFEDETAIL` allocations for an AFE exceed 100%, or is a
   shared AFE attributed to multiple jobs without de-dup? Inflates AFE variance.

## Questions to surface first

1. **Symptom shape.** Wrong number, missing rows, extra rows, or blank metric?
2. **Reference value.** What does the user expect, and from where (the WellView daily report
   UI, a prior dashboard, an SME estimate)?
3. **Scope.** Which well/job and time window? Narrows the search.

## Pre-flight (per session)

1. **Catalog/schema** for WellView Silver data.
2. **Glossary / `SYSUNIT` access** to confirm master units and `LV` decodes during diagnosis.

## Workflow

1. Surface the three questions above before running anything.
2. Walk the playbook in order; load [diagnostics.sql](diagnostics.sql) probes as needed.
3. When the cause is isolated, hand off: cost/AFE/NPT → `wellview-daily-ops-cost`; unit/grain
   modeling → `wellview-data-engineering`.

## What's in this skill

- [diagnostics.sql](diagnostics.sql) — **load probe-by-probe** as you walk the playbook. Don't load all at once.
- [common-issues.md](common-issues.md) — **load when** the symptom doesn't match an obvious probe. Symptom → cause → fix catalogue.

## What NOT to do

- Don't fix the query before identifying *why* it was wrong — the cause is the value here.
- Don't assume a unit from a single value — profile the range and confirm against `SYSUNIT` / glossary.
- Don't silently drop orphan/duplicate rows — report the count so coverage is honest.
- Don't patch a data issue in a one-off query — fix it at the conformed layer (`wellview-data-engineering`).

## Composes with

- **`wellview-overview`** — record-tree + unit anchor.
- **`wellview-daily-ops-cost`** — the corrected cost/NPT/AFE query once the cause is found.
- **`wellview-data-engineering`** — most fixes belong at Silver→Gold (units, grain), not in query patches.
