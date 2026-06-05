---
name: example-data-engineering
description: |
  REPLACE THIS. Use to build, debug, or extend Bronze→Silver→Gold pipelines on
  <source> data — source-specific table list, CDC keys, MBO mapping,
  REST-API ingestion quirks, refresh strategy. NOT a generic Lakeflow tutorial;
  this skill defers SDP / Auto Loader / AutoCDC mechanics to the platform
  skill databricks-spark-declarative-pipelines and adds only the source-
  specific knowledge that platform skill can't infer. Triggers on: "build a
  pipeline for <source>", "ingest <source> data", "CDC for <source>",
  "<source> bronze to silver", "<source> refresh strategy",
  "which <source> tables should I materialize".
metadata:
  version: "0.1.0"
parent: example-overview
---

# <Source> Data Engineering

Source-specific Bronze→Silver/Gold modeling for `<source>`. The platform-layer [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines) skill handles SDP / Auto Loader / AutoCDC mechanics; this skill adds the source-specific table list, CDC keys, and ingestion quirks the platform skill can't infer.

> **FIRST:** load `<source>-overview` for baseline data-model literacy.

## When to use

- "Build a Bronze→Silver pipeline for `<source>`"
- "Which `<source>` tables should I materialize in Silver?"
- "What are the CDC keys for `WORKORDER` / `<other>`?"
- "How do I handle `<source>`'s REST-API ingestion gaps?"
- "Refresh strategy for `<source>` data — incremental or full?"

## Top gotchas

1. **MBO ↔ table mapping is 1:1 for standard tables, but customer extensions may not be.** Custom MBOs sometimes map to `<MBO>_EXT` or live in entirely different schemas. Discover via `<source>-setup`'s introspect step before assuming.
2. **REST-API ingestion has known gaps.** When customers PATCH records directly via REST, status-history tables (e.g. `WOSTATUS`) don't receive new rows. Document this in any pipeline that reads history tables.
3. **Composite primary keys.** CDC keys for `<source>` are usually `(BUSINESS_KEY, SITEID)`, not just `BUSINESS_KEY`. Single-column CDC produces duplicate rows in multi-site customers.

## Questions to surface first

1. **Ingestion source format.** Cloud Files (Auto Loader)? Federated query? Native connector? REST scrape? Different ingestion shapes need different Bronze patterns.
2. **Refresh cadence.** Hourly micro-batch? Nightly full? Real-time streaming? Affects Silver materialization strategy.
3. **Which tables to materialize in Silver vs leave in Bronze.** The full `<source>` schema has 100+ tables — only ~20–30 are typically used. Confirm scope with the user.

## Pre-flight (per session)

1. **Bronze catalog/schema** holding the raw `<source>` data.
2. **Target Silver catalog/schema** for the modeled tables.
3. **SDP entry point** — where the existing pipeline lives, or "greenfield".

## Workflow

For any pipeline task, resolve in this order:

1. **Platform mechanics** — load [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines) for SDP / Auto Loader / AutoCDC / DQ expectation patterns. **This skill does NOT re-teach those.**
2. **Source-specific table list** — see [silver-tables.md](silver-tables.md). Customer-extended tables live in the workspace glossary.
3. **Source-specific CDC + DQ expectations** — see [pipeline.py](pipeline.py) skeleton.

## What's in this skill

- [silver-tables.md](silver-tables.md) — **load when** scoping which tables to materialize. Curated subset of `<source>`'s MBOs that downstream module skills depend on.
- [pipeline.py](pipeline.py) — skeleton SDP definitions for the curated tables. CDC keys, expectations, SCD2 patterns are filled in source-specifically.

## What NOT to do

- **Don't re-teach Lakeflow / SDP / Auto Loader / AutoCDC mechanics.** Reference [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines).
- Don't materialize all `<source>` tables — only those downstream skills depend on. Over-materialization is a silent cost.
- Don't assume single-column CDC keys — `<source>` business keys are `SITEID`-scoped composites.

## Composes with

- **`<source>-overview`** — data-model anchor.
- **`<source>-setup`** — UC comments are registered on the Silver tables this pipeline produces.
- **[`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines)** — pipeline mechanics.
- **`<source>-data-quality`** — diagnostic playbook for "this number looks wrong" after the pipeline runs.
