---
name: maximo-data-engineering
description: |
  Use to design, build, or extend Lakeflow Spark Declarative Pipelines (SDP /
  DLT) that model Maximo Bronze data into a clean Silver/Gold layer. Covers
  WORKORDER (apply changes — current state), WOSTATUS (append — history),
  ASSET (SCD2), LOCATIONS (hierarchy flatten), gold metric views, and data
  expectations. Triggers on: "build a pipeline for Maximo Silver", "model
  Maximo Bronze", "what's the right SDP pattern for WORKORDER", "Maximo
  CDC", "Maximo Silver / Gold layer".
tags:
  - data-source:ibm-maximo
  - tier:foundation
  - persona:da-platform
---

# Maximo Data Engineering

Design the Silver/Gold layer for Maximo data using Lakeflow Spark Declarative Pipelines. This is the platform foundation every downstream Maximo skill stands on.

Assumes Maximo data is already landed in Bronze (partner connector, custom Spark JDBC, MAS Kafka — ingestion is out of scope for this skill family). Bridges from whatever Bronze shape exists to a clean Silver/Gold layer.

## When to use

- "Build me an SDP / Lakeflow pipeline for Maximo Silver"
- "What's the right CDC pattern for WORKORDER?"
- "How should I model WOSTATUS?"
- "Set up the Maximo Silver/Gold layer"
- "Extend the pipeline to add a new Maximo table"

## Pre-flight

1. **Bronze shape**: "What does your Maximo Bronze look like?"
   - **Partner-connector mirrors** (Fivetran / Qlik / Informatica) — flat tables that roughly preserve MBO names and columns. Often already snapshot-like with a `_fivetran_synced` audit column.
   - **Custom Spark JDBC dumps** — raw periodic full or delta snapshots against DB2/Oracle. Needs more CDC work in Silver.
   - **MAS Kafka events** — streaming JSON/XML payloads with hierarchical MBO structure. Needs flattening before becoming usable Silver tables.

2. **Target catalog/schema**: "Where should the Silver and Gold layers live?"
3. **Lakeflow target**: "Are you building this as a Lakeflow Pipeline (SDP/DLT) or as plain Spark jobs?" SDP is recommended — incrementality + expectations are first-class.

## The Maximo Silver-layer table-modeling decision matrix

This is the most important content of the skill. For each Maximo table, the correct Silver modeling is opinionated:

| Maximo table | Silver type | Why |
|---|---|---|
| `WORKORDER` | **Streaming Table + APPLY CHANGES INTO** | Captures current state; idempotent on `(WONUM, SITEID)` |
| `WOSTATUS` | **Streaming Table, append-only** | Each row is a state transition. **NEVER apply-changes — that loses history** |
| `LABTRANS` | **Streaming Table, append-only** | Append; transactions don't update |
| `ASSET` | **SCD Type 2** | Long-lived; need history of attribute changes for time-travel queries |
| `LOCATIONS` | **SCD Type 2** | Hierarchies change; need temporal queries |
| `LOCHIERARCHY` | **Materialized View** rebuilt from LOCATIONS each run | Derived hierarchy — easier as MV than streaming |
| `PM` | **SCD Type 2** | Schedule rules change; track history |
| `JOBPLAN` / `JPLABOR` / `JPMATERIAL` | **SCD Type 2** | Templates evolve |
| `FAILURECODE` | **Materialized View** | Slow-changing taxonomy; full refresh is fine |
| `FAILUREREPORT` | **Streaming Table, append-only** | Per-WO record, written once |
| `ASSET METER` | **SCD Type 2** | Meter definitions can change limits |
| `METERREADING` | **Streaming Table, append-only** | High-volume time series |
| `COMPANIES`, `LABOR`, `PERSON`, `CRAFT` | **SCD Type 1 or 2** | Master data; SCD2 if history matters |
| `plusgpermitwork`, `plusgincperson` (O&G) | **Streaming Table + APPLY CHANGES INTO** | Stateful records; idempotent updates |
| `plusgshftlogentry` (O&G shift logs) | **Streaming Table, append-only** | Append; logs are immutable |
| `SYNONYMDOMAIN` | **Materialized View** | Slow-changing reference |

## Gotchas at the Silver layer

See [gotchas.md](gotchas.md). The three to internalize:

1. **WOSTATUS is APPEND, not APPLY CHANGES.** Apply-changes on WOSTATUS will collapse the history table to one row per WO. Verify by checking that `WOSTATUS` row counts continue to grow over time.
2. **`WOCLASS` filter belongs at the SILVER LAYER, not in every consuming query.** Create `silver.workorder` filtered to `WOCLASS = 'WORKORDER'` and a separate `silver.workorder_all_classes` for the rare query that needs PM/CHANGE/RELEASE/ACTIVITY records. Downstream skills assume the filtered Silver.
3. **`ISTASK = 1` tasks are valid data, not noise.** Keep them in Silver. Filter at consumption time per the use case (backlog → headers only; cost roll-up → roll up by PARENT).

## Workflow

1. **Run pre-flight**: confirm Bronze shape, target catalog/schema, Lakeflow target.
2. **Generate the pipeline source** using [pipeline.py](pipeline.py) as the canonical template. It handles all three Bronze shapes via parameterized input sources.
3. **Configure expectations** using [expectations.md](expectations.md) — recommended data-quality rules per table.
4. **Define Gold views** for downstream consumption using [gold_views.sql](gold_views.sql).
5. **Document the resulting Silver/Gold layout** so analyst-tier skills know where to find tables. Update the customer's workspace glossary (`maximo-setup` skill) if catalog/schema differs from defaults.

## What this skill does NOT cover

- **Ingestion to Bronze** (Kafka readers, JDBC connectors, partner-connector setup). Assumed done.
- **Customer-specific extension tables** beyond standard Maximo MBOs. Add them by adapting `pipeline.py` patterns to the new table — but they're not in the canonical template.
- **AI/BI dashboards or Genie Spaces over Gold**. Those are downstream skills (currently v3 plans).

## What NOT to do

- Don't `APPLY CHANGES INTO` WOSTATUS — collapses history. Append only.
- Don't omit the `WOCLASS = 'WORKORDER'` filter from the Silver `workorder` table — it forces every consumer to remember the filter.
- Don't materialize Gold metric views as managed Delta tables if they can be views — views are cheaper, recompute on demand, and stay fresh.
- Don't merge multiple modules' tables into one Silver table just because columns overlap. The MBO boundaries are real and helpful.

## References

- [pipeline.py](pipeline.py) — canonical SDP pipeline template (parameterized for Bronze shape)
- [gold_views.sql](gold_views.sql) — DDL for reusable Gold views
- [gotchas.md](gotchas.md) — Silver-layer modeling traps
- [expectations.md](expectations.md) — recommended data-quality expectations per table
- Lakeflow SDP docs: https://docs.databricks.com/aws/en/dlt/
