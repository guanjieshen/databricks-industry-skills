---
name: maximo-reliability
description: |
  Use for asset reliability metrics on Maximo data — MTBF, MTTR, PM compliance,
  failure-mode analysis, bad-actor assets, time-between-failures. Ships UC SQL
  function definitions for the canonical formulas (matching IBM's published
  O&G MTBF/MTTR definitions) so reliability engineers can reconcile to the
  Maximo UI. Triggers on: "MTBF", "MTTR", "PM compliance", "failure analysis",
  "bad actor", "reliability scorecard", "mean time between failures", "mean
  time to repair", "RCM", "SMRP metric".
tags:
  - data-source:ibm-maximo
  - tier:module
  - module:asset-reliability
  - industry:oil-and-gas
  - industry:utilities
  - industry:mining
  - persona:reliability-engineer
  - persona:analyst
  - persona:da-platform
---

# Maximo Reliability

Help the user compute reliability metrics on Maximo data — MTBF, MTTR, PM compliance, failure-mode analysis. Composes with `maximo-overview` and `maximo-work-orders`.

The defining quality of this skill: **registered Trusted UDFs whose output matches what's displayed in the Maximo UI**, so reliability engineers can reconcile dashboard numbers against Maximo screens.

## When to use

- "What's the MTBF for centrifugal pumps?"
- "MTTR by asset class last year"
- "PM compliance for Q3"
- "Top failure modes on our rotating equipment"
- "Which assets are bad actors?"
- "Reliability scorecard"
- "Time-since-last-failure for asset X"

For raw WO analytics (backlog, status, labor), defer to `maximo-work-orders`. This skill is metric-specific.

For integrity / regulatory inspection compliance (different from SMRP-style PM compliance), defer to `maximo-integrity`.

## Pre-flight (per session)

1. **Silver catalog/schema** — confirm via workspace glossary or ask
2. **PM-compliance definition** — Maximo has multiple valid definitions:
   - SMRP standard: completed within tolerance window / scheduled
   - Customer-specific: may use a different tolerance or denominator
   - Read from workspace glossary if available; otherwise ask
3. **Failure-classification depth** — `FAILURECODE` is a tree (PROBLEM → CAUSE → REMEDY). Confirm which level the user wants aggregations at.

## Workflow priority

For any new question, resolve in this order:

1. **Trusted UDF** — if a registered UC SQL function in [metric_udfs.sql](metric_udfs.sql) computes what's asked (mtbf, mttr, pm_compliance, time_since_last_failure, time_since_last_pm), call it directly. These earn the Trusted-asset badge in Genie.
2. **Parameterized example** — check [examples.sql](examples.sql).
3. **Pre-joined view** — compose against `v_failure_events`, `v_pm_schedule`, `v_meter_excursions` from [views.sql](views.sql).
4. **Raw tables** — last resort; explain why.

## Critical: MTBF and MTTR formulas

IBM publishes O&G-specific MTBF/MTTR definitions used by the Maximo UI. The UDFs in [metric_udfs.sql](metric_udfs.sql) match those formulas. **Do not reinvent the formula**, or the number you produce won't match what the reliability engineer sees on their Maximo screen.

Citation in the UDF comments references IBM Support page: `https://www.ibm.com/support/pages/mttr-and-mtbf-fields-explained-maximo-oil-gas-asset-oil-application`

## What's in this skill

- [schema.md](schema.md) — ASSET, WORKORDER (failures), FAILUREREPORT, FAILURECODE, PM, PMSEQUENCE, ASSETMETER
- [gotchas.md](gotchas.md) — MTBF/MTTR definitional traps, PM-compliance ambiguity, FAILURECODE hierarchy
- [examples.sql](examples.sql) — parameterized reliability queries
- [views.sql](views.sql) — DDL for `v_failure_events`, `v_pm_schedule`
- [metric_udfs.sql](metric_udfs.sql) — UC SQL functions: `mtbf`, `mttr`, `pm_compliance`, `time_since_last_failure`, `time_since_last_pm`

## What NOT to do

- **Don't invent MTBF/MTTR formulas.** Use the registered UDFs. If the user's customer has a non-standard definition, register a customer-specific UDF alongside (don't replace the canonical one).
- **Don't aggregate `FAILURECODE` without flattening the hierarchy** to the level the user asked for.
- **Don't conflate PM compliance (operational) with regulatory inspection compliance** — those are different metrics with different stakes. Regulatory compliance lives in `maximo-integrity`.
- **Don't run a reliability query without filtering `WOCLASS = 'WORKORDER'`** — the base table holds non-failure record classes.

## References

- [schema.md](schema.md)
- [gotchas.md](gotchas.md)
- [examples.sql](examples.sql)
- [views.sql](views.sql)
- [metric_udfs.sql](metric_udfs.sql)
- IBM MTBF/MTTR fields explained (O&G): https://www.ibm.com/support/pages/mttr-and-mtbf-fields-explained-maximo-oil-gas-asset-oil-application
- SMRP best practices: https://smrp.org/
