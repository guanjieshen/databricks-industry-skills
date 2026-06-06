---
name: maximo-data-engineering
description: |
  Use to design, build, or extend Lakeflow Spark Declarative Pipelines (SDP /
  DLT) that model IBM Maximo / Maximo / EAM / CMMS Bronze data into a clean
  Silver/Gold layer. Covers the per-MBO Silver modeling decision (apply-changes
  vs append vs SCD2 vs materialized view) for WORKORDER, WOSTATUS, LABTRANS,
  ASSET, LOCATIONS, PM, FAILURECODE/FAILUREREPORT, METERREADING, labor and
  hierarchy tables; cross-domain gold consumption views (v_failure_events,
  v_pm_schedule — single-domain WO views are owned by maximo-work-orders); and per-table data-quality
  expectations. Triggers on: "build a pipeline for Maximo Silver", "model
  Maximo Bronze", "right SDP / DLT pattern for WORKORDER", "Maximo CDC",
  "apply changes vs append for WOSTATUS", "SCD2 for ASSET", "Maximo Silver /
  Gold / medallion layer", "Maximo data expectations", "what's the correct
  CDC pattern for this Maximo table".
metadata:
  version: "0.2.0"
parent: maximo-overview
---

# Maximo Data Engineering

Design the Silver/Gold layer for Maximo data using Lakeflow Spark Declarative Pipelines. This is the platform foundation every downstream Maximo skill stands on.

Assumes Maximo data is already landed in Bronze (partner connector, custom Spark JDBC, MAS Kafka — ingestion is out of scope for this skill family). Bridges from whatever Bronze shape exists to a clean Silver/Gold layer.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas (SITEID composite keys, `WOCLASS` filtering, `ISTASK` tasks-vs-child-WOs, `STATUS`-current-vs-`WOSTATUS`-history, status-is-a-synonym-domain, `HISTORYFLAG`, app-server-timezone datetimes). This skill builds on that foundation. For Lakeflow SDP build/debug mechanics (AutoCDC, Auto Loader, expectations API), load the platform skill [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines) — this skill provides only the Maximo-specific modeling decisions.

## When to use

- "Build me an SDP / Lakeflow pipeline for Maximo Silver"
- "What's the right CDC pattern for WORKORDER?"
- "How should I model WOSTATUS — apply-changes or append?"
- "Set up the Maximo Silver/Gold layer"
- "Extend the pipeline to add a new Maximo table"

**Defer to siblings when:**
- Per-column/per-table customer-deployment facts, UC comments, the workspace glossary, and the deployment's app-server timezone → `maximo-setup` (it owns UC comment registration; never write comments from this skill).
- "This Silver number looks wrong" diagnostics (completeness, reconciliation) → `maximo-data-quality`.
- Cost rollup / multi-currency normalization methodology → `maximo-maintenance-cost`.

## Top gotchas

The Silver-layer modeling traps that silently corrupt every downstream metric (full set in [gotchas.md](gotchas.md); `maximo-overview` carries the universal mechanics — apply them in the pipeline, don't re-teach them):

1. **`WOSTATUS` is APPEND-ONLY, never APPLY CHANGES.** `WOSTATUS` is a status-transition log — one row per change. `apply_changes` keyed on `(WONUM, SITEID)` collapses the entire history to one row per WO. This is the single most common Maximo modeling error. Same rule for `LABTRANS`, `METERREADING`, `FAILUREREPORT` and other transaction logs.
2. **NEVER filter `HISTORYFLAG` out at Silver.** Closed/cancelled records get `HISTORYFLAG = 1` and drop out of stock Maximo List views — but Silver must keep them, or every completion/trend/MTBF metric downstream goes blank (see `maximo-overview`). Mirror Bronze in full; let consumers filter. Do not copy Maximo's `HISTORYFLAG = 0` view filter into Silver.
3. **`WOCLASS` filter belongs at the Silver layer.** `WORKORDER` also holds `PM`/`CHANGE`/`RELEASE`/`ACTIVITY`. Build `silver.workorder` pre-filtered to `WOCLASS = 'WORKORDER'` plus a separate `silver.workorder_all_classes`, so consumers don't each re-remember the filter.
4. **Resolve status sets via `SYNONYMDOMAIN`, never literals — even in Gold views.** Status columns store the customer-renamable synonym (`VALUE`), not the internal `MAXVALUE` Maximo logic uses (see `maximo-overview`). A Gold view hard-coding `status IN ('COMP','CLOSE')` silently misses custom synonyms; resolve via `SYNONYMDOMAIN` (`DOMAINID`, `MAXVALUE`, `VALUE`). And `COMP` ≠ `CLOSE` — key "completed" on COMP-or-later, not CLOSE.
5. **Don't materialize Gold metric views as managed Delta tables.** Keep `v_*` as views over the (already-incremental) Silver streaming tables — cheaper, always fresh, no staleness window. Promote a single view to a materialized view only if it becomes provably expensive.

## Questions to surface first

Surface these to the user *before* building — there is no defensible default:

1. **Bronze shape and CDC fidelity.** Is Bronze a partner-connector mirror (Fivetran/Qlik/Informatica — often snapshot-like with a `_fivetran_synced` audit column), a custom Spark JDBC dump (periodic full/delta snapshots — needs CDC reconstruction in Silver), or MAS Kafka events (hierarchical JSON/XML — needs flattening first)? The whole `apply_changes` vs append decision and the `sequence_by` column depend on this. If JDBC snapshots, confirm whether deletes are captured at all — soft-deleted-in-Maximo rows may simply stop appearing.
2. **Which audit/sequence column orders changes?** `apply_changes` and SCD2 need a reliable monotonic sequencing column (e.g. `_fivetran_synced`, `CHANGEDATE`, an ingestion timestamp). Confirm it exists and is trustworthy per table — Maximo `CHANGEDATE` is app-server-local time, not per-row UTC (see `maximo-overview`), so cross-site ordering can be subtly off.
3. **Which tables need SCD Type 2 vs SCD Type 1?** SCD2 preserves attribute history (needed when reliability/integrity analytics ask "what was the asset's criticality on the failure date?"); SCD1 is cheaper for master data where history is rarely queried. Confirm per table — the default below is opinionated but storage-vs-history is a real tradeoff.
4. **Is the customer on the O&G / other industry solution (PLUSG* tables)?** If yes, include those extension tables in Silver (HSE/integrity skills depend on them); if classic Maximo, omit them — no harm.

## Pre-flight (per session)

One-time session config — cache, don't re-ask:

1. **Target catalog/schema** — "Where should the Silver and Gold layers live?" Confirm via the customer's workspace glossary skill (`maximo-setup`) if installed, or ask.
2. **Lakeflow target** — "Lakeflow Pipeline (SDP/DLT) or plain Spark jobs?" SDP is recommended: incrementality + expectations are first-class.

## The Maximo Silver-layer table-modeling decision matrix

This is the most important content of the skill. For each Maximo table, the correct Silver modeling is opinionated:

| Maximo table | Silver type | Why |
|---|---|---|
| `WORKORDER` | **Streaming Table + APPLY CHANGES INTO** | Captures current state; idempotent on `(WONUM, SITEID)` |
| `WOSTATUS` | **Streaming Table, append-only** | Each row is a state transition. **NEVER apply-changes — that loses history** |
| `LABTRANS` | **Streaming Table, append-only** | Append; transactions don't update |
| `ASSET` | **SCD Type 2** | Long-lived; need history of attribute changes for time-travel queries |
| `LOCATIONS` | **SCD Type 2** | Hierarchies change; need temporal queries |
| `LOCHIERARCHY` | **Materialized View** (Bronze pass-through) | Real Maximo table; small, slow-changing — full-refresh MV |
| `PM` | **SCD Type 2** | Schedule rules change; track history |
| `JOBPLAN` / `JPLABOR` / `JPMATERIAL` | **SCD Type 2** | Templates evolve |
| `FAILURECODE` | **Materialized View** | Slow-changing taxonomy; full refresh is fine |
| `FAILUREREPORT` | **Streaming Table, append-only** | Per-WO record, written once |
| `ASSETMETER` | **SCD Type 2** | Meter definitions can change limits |
| `METERREADING` | **Streaming Table, append-only** | High-volume time series |
| `COMPANIES`, `LABOR`, `PERSON`, `CRAFT` | **SCD Type 1 or 2** | Master data; SCD2 if history matters |
| `plusgpermitwork`, `plusgincperson` (O&G) | **Streaming Table + APPLY CHANGES INTO** | Stateful records; idempotent updates |
| `plusgshftlogentry` (O&G shift logs) | **Streaming Table, append-only** | Append; logs are immutable |
| `SYNONYMDOMAIN` | **Materialized View** | Slow-changing reference |

Keep `ISTASK = 1` tasks in Silver (they are valid data, not noise — filter at consumption time per use case). Keep `HISTORYFLAG = 1` closed records in Silver. The MBO boundaries are real — don't merge multiple modules' tables into one Silver table just because columns overlap.

## Workflow

1. **Run pre-flight + surface the questions above**: confirm Bronze shape/CDC fidelity, sequencing column, SCD2-vs-1 choices, target catalog/schema, Lakeflow target.
2. **Generate the pipeline source** using [pipeline.py](pipeline.py) as the canonical template. It handles all three Bronze shapes via a parameterized `bronze()` input source. Defer SDP build/debug mechanics to [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines).
3. **Configure expectations** using [expectations.md](expectations.md) — recommended data-quality rules per table.
4. **Define Gold views** for downstream consumption using [gold_views.sql](gold_views.sql). Resolve status sets via `SYNONYMDOMAIN`, not literals, and keep them as views (not materialized tables).
5. **Document the resulting Silver/Gold layout** so analyst-tier skills know where to find tables. Update the customer's workspace glossary via `maximo-setup` if catalog/schema differs from defaults.

## What's in this skill

- [pipeline.py](pipeline.py) — load when generating or extending the pipeline. Canonical SDP template, parameterized for Bronze shape; covers WORKORDER, WOSTATUS, LABTRANS, ASSET, LOCATIONS, PM, FAILURE*, METERREADING, plus labor and hierarchy tables.
- [gold_views.sql](gold_views.sql) — load when defining the consumption layer. DDL for the cross-domain views `v_failure_events`, `v_pm_schedule`. Single-domain WO views (`v_workorder_enriched`, `v_workorder_status_history`, `v_labor_actuals`) are owned by `maximo-work-orders` — compose against those, don't redefine them here.
- [gotchas.md](gotchas.md) — load before modeling any table. Silver-layer modeling traps (apply-changes vs append, SCD2 conventions, METERREADING volume, PLUSG* joins).
- [expectations.md](expectations.md) — load when attaching data-quality rules. Recommended `@dlt.expect*` per Silver table.

## What NOT to do

- Don't `APPLY CHANGES INTO` `WOSTATUS`/`LABTRANS`/`METERREADING`/`FAILUREREPORT` — collapses history. Append only.
- Don't filter `HISTORYFLAG = 1` rows out at Silver — downstream completion/trend metrics need closed records.
- Don't hard-code status literals (`'COMP'`, `'CLOSE'`, …) in Gold views — resolve via `SYNONYMDOMAIN` (see `maximo-overview`); customer synonyms break literals.
- Don't materialize Gold metric views as managed Delta tables if they can be views — views are cheaper, recompute on demand, and stay fresh.
- Don't normalize or sum costs across currencies in this layer — multi-currency normalization methodology is owned by `maximo-maintenance-cost`. Pass `LINECOST`/`WOCURRENCY`/`EXCHANGERATE` through unmodified.
- Don't write or alter UC comments / table metadata from this skill — UC comments are owned by `maximo-setup` (preview-then-apply, gated on explicit user approval).
- Don't try to model **ingestion to Bronze** (Kafka readers, JDBC connectors, partner-connector setup) here — assumed done, out of scope for this family.

## Composes with

- **`maximo-overview`** for the universal mechanics this pipeline applies (SITEID keys, WOCLASS, ISTASK, status-synonym resolution, HISTORYFLAG, app-server-timezone datetimes). Apply them in the pipeline/views; don't re-teach them.
- **`maximo-setup`** to register the Gold views and any UC comments — never run those writes from this skill; defer to setup's preview-then-apply workflow. Setup also carries the deployment's actual app-server timezone.
- **`maximo-data-quality`** for "this Silver number looks wrong" diagnostics; this skill ships preventive expectations, not reconciliation playbooks.
- **`maximo-maintenance-cost`** for cost rollup and multi-currency normalization; this layer passes cost columns through.
- Downstream module skills compose against Gold views. This skill owns the **cross-domain** views (`v_failure_events`, `v_pm_schedule`); **single-domain** views are owned by the module — e.g. `maximo-work-orders` owns `v_workorder_enriched` / `v_workorder_status_history` / `v_labor_actuals`. This skill provides the shared modeling pattern they all follow.
- For SDP build/debug mechanics: platform skill [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines). Lakeflow SDP docs: https://docs.databricks.com/aws/en/dlt/
