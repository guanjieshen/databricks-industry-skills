---
name: wellview-data-engineering
description: |
  Use to build, debug, or extend Bronze->Silver->Gold pipelines on Peloton
  WellView data — which WV/LV/SYS tables to materialize, the IDREC GUID CDC
  keys, SYSMODDATE incremental strategy, master-unit normalization at
  Silver->Gold, LV-code decode, and the per-job daily-ops/cost gold fact the
  module skills query. NOT a generic Lakeflow tutorial; defers SDP / Auto
  Loader / AutoCDC mechanics to the platform skill
  databricks-spark-declarative-pipelines and adds only WellView-specific
  knowledge. Triggers on: "build a pipeline for WellView", "ingest WellView
  data", "WellView bronze to silver", "model WellView", "which WellView tables
  to materialize", "normalize WellView units", "WellView CDC keys", "Peloton
  ETL to Databricks".
metadata:
  version: "0.1.0"
parent: wellview-overview
---

# WellView Data Engineering

WellView-specific Bronze→Silver/Gold modeling. The platform-layer [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines) skill handles SDP / Auto Loader / AutoCDC mechanics; this skill adds the WellView table list, GUID CDC keys, master-unit normalization, and the gold fact the module skills depend on.

> **FIRST:** load `wellview-overview` for the record tree, the `WV`/`LV`/`SYS` grammar, and the universal gotchas (master units, calc-vs-stored).

## When to use

- "Build a Bronze→Silver pipeline for WellView"
- "Which WellView tables should I materialize?"
- "What are the CDC keys for `WVJOB` / `WVJOBREPORT`?"
- "Normalize WellView depth/cost units in the lakehouse"
- "Build the daily-ops/cost gold fact for the metric view"

## Top gotchas

1. **CDC key is `IDREC` (a GUID), not a composite.** Unlike Maximo's `SITEID`-scoped keys, WellView rows are keyed by a globally-unique `IDREC`. Use `IDREC` as the merge key and `SYSMODDATE` as the incremental watermark.
2. **Normalize master units ONCE, at Silver→Gold.** WellView stores depth/footage in a configurable master unit and cost in a currency. Convert to one unit (metres; a base currency) at the Silver→Gold boundary so every downstream skill is unit-safe. Scattered conversions drift. The unit per column comes from `SYSUNIT` / the glossary.
3. **Calc-engine fields won't be in the extract.** `CostCum`, `DaysFromSpud`, `ROP` are computed in WellView's app, not stored. Recompute them in Gold (window sums, date diffs, footage/hours) — don't expect them in Bronze.
4. **Materialize the spine + needed LV/SYS, not all 200–300 tables.** Over-materialization is silent cost. Only the ~17-table daily-ops/cost spine plus the `LV*` decode tables and `SYSUNIT` are needed for this family.

## Questions to surface first

1. **Ingestion channel.** Peloton ETL powered by Snowflake (read-only replica) or the Peloton Platform API? Different Bronze patterns; the Snowflake replica is the common path.
2. **Master units + currency.** What unit is depth/footage stored in, and what currency is cost? This must be pinned (from `SYSUNIT` / `wellview-setup`) before the Silver→Gold normalization is written.
3. **Scope.** Which domains/modules are in use (drilling / completion / workover / integrity)? Don't model trees the customer doesn't populate.

## Pre-flight (per session)

1. **Bronze catalog/schema** holding the raw replicated WellView tables.
2. **Target Silver/Gold catalog/schema** (`:silver_schema` / `:gold_schema`).
3. **SDP entry point** — existing pipeline or greenfield.

## Workflow

1. **Platform mechanics** — load [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines) for SDP / Auto Loader / AutoCDC / expectations. **This skill does not re-teach those.**
2. **WellView table list** — see [silver-tables.md](silver-tables.md): the spine + LV + SYS subset to materialize, with CDC keys.
3. **Normalization + gold fact** — see [pipeline.py](pipeline.py): master-unit normalization at Silver→Gold, LV decode, and the report-grained `v_daily_ops_cost_fact` the `wellview-daily-ops-cost` metric view consumes.

## What's in this skill

- [silver-tables.md](silver-tables.md) — **load when** scoping which tables to materialize. The curated WV/LV/SYS subset + CDC keys + master-unit source.
- [pipeline.py](pipeline.py) — skeleton SDP definitions: Bronze passthrough, Silver typing/dedup by `IDREC`, Gold normalization + the daily-ops/cost fact.

## What NOT to do

- **Don't re-teach Lakeflow / SDP / Auto Loader / AutoCDC mechanics.** Reference the platform skill.
- Don't normalize units in the analytical skills — do it once here at Silver→Gold.
- Don't drop calc-engine recomputation (cumulative cost, days, ROP) — they won't arrive in the extract.
- Don't materialize all 200–300 tables — only the spine + needed LV/SYS.
- Don't use a composite CDC key — WellView's key is the `IDREC` GUID.

## Composes with

- **`wellview-overview`** — record-tree + grammar anchor.
- **`wellview-setup`** — pins the master units / currency / `LV` decodes this pipeline applies, and registers UC comments on the Silver tables this produces.
- **`wellview-daily-ops-cost`** — consumes the `v_daily_ops_cost_fact` and the enriched views this builds.
- **`wellview-data-quality`** — the "this number looks wrong" playbook after the pipeline runs.
- **[`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines)** (platform) — pipeline mechanics.
