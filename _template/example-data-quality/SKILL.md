---
name: example-data-quality
description: |
  REPLACE THIS. Use to diagnose data-quality issues with <source> data
  — orphan records, missing status history, REST-API ingestion gaps,
  schema mismatches, count discrepancies vs the source UI, broken
  closure tables. The "this number looks wrong" playbook for <source>.
  Triggers on: "this <source> number looks wrong", "audit <source>
  data quality", "why is my <source> backlog count off", "missing
  status history in WOSTATUS", "find orphans in <source>",
  "reconcile <source> to source UI".
metadata:
  version: "0.1.0"
parent: example-overview
---

# <Source> Data Quality

The diagnostic playbook for "this number looks wrong" investigations on `<source>` data. Ordered probes that start broad and narrow to the cause. When the cause is identified, hand off to the relevant module skill for the fix.

> **FIRST:** load `<source>-overview` for the data-model anchor.

## When to use

- "The backlog count in my dashboard doesn't match what Maximo's UI shows"
- "WOSTATUS history seems incomplete"
- "Why is asset hierarchy depth >50 — that can't be right"
- "Orphan LABTRANS rows referencing missing WONUM"
- "Reconcile this Genie answer to what the SME expects"

## Diagnostic playbook

Ordered. Start at probe 1; only descend when you've ruled out the prior cause.

1. **Ingestion completeness** — are Bronze row counts within expected ranges? Compare against the source system's UI export if available.
2. **REST-API ingestion gap** — for any *history* discrepancy, check whether the customer ingests via REST PATCH (which doesn't write to `*STATUS` tables). See [diagnostics.sql](diagnostics.sql) probe 2.
3. **Composite-key joins** — is the report's SQL missing `SITEID` in joins? Multi-site customers produce cross-product inflation.
4. **`WOCLASS` filter** — is the report counting `PM` / `CHANGE` / `RELEASE` records as "work orders"?
5. **`ISTASK` filter** — is the report double-counting parent + child task rows?
6. **Closure-table staleness** — for hierarchy reports, is the closure table rebuilt on the same cadence as the base?
7. **UC comments out of date** — last-resort check. If Genie keeps writing the wrong SQL despite correct schema, run `<source>-setup`'s preview to see what comments are registered.

## Questions to surface first

1. **Which symptoms** does the user observe? Wrong number vs missing rows vs extra rows vs broken history?
2. **Reference value** — what does the user EXPECT the number to be, and where does that expectation come from (source UI, prior dashboard, SME estimate)?
3. **Time window** — last 30 days, last quarter, all-time? Narrows the search space.

## Pre-flight (per session)

1. **UC catalog/schema** for `<source>` Silver data.
2. **Access** to read source-system UI exports for reconciliation (if available).

## Workflow

For any "this number looks wrong" report:
1. Surface the three questions above before running anything.
2. Walk the playbook in order — load [diagnostics.sql](diagnostics.sql) probes as needed.
3. When the cause is isolated, hand off to the relevant module skill (`<source>-work-orders` for WO-count issues, `<source>-asset-hierarchy` for rollup issues, etc.) for the corrective query.

## What's in this skill

- [diagnostics.sql](diagnostics.sql) — **load probe-by-probe** as you walk the playbook. Don't load all at once.
- [common-issues.md](common-issues.md) — **load when** the symptom doesn't match an obvious probe. Catalogue of past issues + their causes.

## What NOT to do

- Don't fix the user's query without first identifying *why* it was wrong. The diagnostic value of this skill is the cause, not just the cure.
- Don't suggest re-ingestion as the first remedy — most issues are query/filter issues, not data issues.

## Composes with

- **`<source>-overview`** — data-model anchor.
- All module skills — once the cause is identified, defer the correct query to the module skill.
- **`<source>-setup`** — for UC-comments reconciliation (probe 7).
