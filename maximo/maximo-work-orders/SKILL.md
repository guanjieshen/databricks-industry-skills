---
name: maximo-work-orders
description: |
  Use when querying, analyzing, or building pipelines on IBM Maximo work-order
  data — backlog, aging, status, completion, labor by craft, planned vs actual,
  asset/location/job-plan joins. Triggers on: "open work orders", "WO backlog",
  "WORKORDER", "WOSTATUS", "work order status history", "labor hours by craft",
  "completed WOs", "preventive vs corrective maintenance", "WO aging", and any
  question about WO operations. Compose with maximo-overview for baseline data
  model literacy.
metadata:
  version: "0.1.0"
parent: maximo-overview
---

# Maximo Work Orders

Help the user query, analyze, or build pipelines on Maximo work-order data. Composes with `maximo-overview` (baseline data model + universal gotchas) — this skill adds the work-order-specific schema, gold-standard queries, and reusable views/UDFs.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas (SITEID composite keys, `WOCLASS` filtering, `ISTASK` dedup, WOSTATUS-vs-WORKORDER history). This skill builds on that foundation.

## When to use

Triggered by work-order operational questions:
- "What's our open WO backlog?"
- "Show me WOs aging over 90 days"
- "Labor hours by craft last month"
- "How many corrective vs preventive WOs did we complete?"
- "Status history for WO X"
- "Top assets by WO volume"
- "Actual vs planned labor on completed WOs"

For reliability metrics (MTBF, MTTR, PM compliance), defer to `maximo-reliability` — it has the registered Trusted UDFs.

For integrity / inspection workflows, defer to `maximo-integrity`.

## Pre-flight (per session)

1. **Silver catalog/schema**: confirm via the customer's workspace glossary skill if installed, or ask.
2. **Open-status set**: customer-configurable. Default `('WAPPR', 'APPR', 'INPRG', 'WSCH', 'WMATL')` unless glossary says otherwise.
3. **Business-jargon resolution**: any term you don't recognize (Mainline, Region, etc.) → consult the workspace glossary skill, or ASK before guessing.

## Workflow priority (per Databricks Genie best practice)

For any new question, resolve in this order:

1. **Parameterized example query** — check [examples.sql](examples.sql) for an existing pattern that matches the user's question. If found, use it directly with the user's parameters.
2. **Pre-joined view** — compose using `v_workorder_enriched` / `v_workorder_status_history` / `v_labor_actuals` from [views.sql](views.sql). These are the Gold views built by `maximo-data-engineering`.
3. **Raw tables** — only when the view layer doesn't cover the join shape. Explain why you're skipping the view.

## What's in this skill

- [schema.md](schema.md) — full reference for WORKORDER, WOSTATUS, ASSET, LOCATIONS, LABTRANS, WPLABOR/WPMATERIAL, JOBPLAN, FAILUREREPORT
- [gotchas.md](gotchas.md) — error-prone joins (WOSTATUS history, WOCLASS, ISTASK dedup, SITEID composite, etc.)
- [examples.sql](examples.sql) — parameterized gold-standard queries
- [views.sql](views.sql) — DDL for `v_workorder_enriched`, `v_workorder_status_history`, `v_labor_actuals`
- [metric_udfs.sql](metric_udfs.sql) — **Trusted Asset functions**: UC SQL functions you register once so Genie Spaces call them as *certified, governed metrics* instead of regenerating ad-hoc SQL. Register via `maximo-setup` or by running the file, then reference the functions by name.

## What NOT to do

- Don't write reliability metrics (MTBF/MTTR/PM compliance) — that's `maximo-reliability`'s job.
- Don't ignore the universal gotchas from `maximo-overview`: `WOCLASS = 'WORKORDER'`, `ISTASK = 0` for backlog, `SITEID` in joins, `WORKORDER.STATUS` vs `WOSTATUS`.
- Don't hard-code the open-status set — read from workspace glossary or ask.
- Don't fabricate columns not in [schema.md](schema.md). If user mentions a custom column, check workspace glossary or ask.

## Setup helpers

If the user hasn't registered the views/UDFs from this skill yet:
1. Offer to read [views.sql](views.sql) and [metric_udfs.sql](metric_udfs.sql) and write them as runnable scripts.
2. Substitute the customer's catalog/schema from the workspace glossary.
3. Show the SQL before suggesting execution — never run silently.
