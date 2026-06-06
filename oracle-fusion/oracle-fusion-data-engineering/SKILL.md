---
name: oracle-fusion-data-engineering
description: |
  Use to design, build, or extend the Silver layer that models Oracle Fusion
  Cloud ERP (Fusion ERP / Financials / SCM / Oracle Cloud ERP) Bronze extracts
  into clean, query-ready canonical tables. Covers the Fusion-specific modeling
  decisions: ingesting BICC Public View Object (PVO) incremental extracts and
  Fusion Data Intelligence (FDI/FAW) star schemas, the apply-changes vs append
  vs SCD2 choice per Fusion table (GL_JE_HEADERS, GL_JE_LINES, GL_BALANCES,
  GL_CODE_COMBINATIONS, PO_HEADERS_ALL / _LINES_ALL / _DISTRIBUTIONS_ALL,
  XLA_AE_LINES), dedup on PVO/extract keys, _ALL multi-org handling,
  deletes-not-captured reconciliation (BICC incremental misses hard deletes),
  and currency/period conformance. Triggers on: "build a pipeline for Fusion
  Silver", "model BICC PVO extracts", "ingest Fusion Data Intelligence", "right
  CDC pattern for GL_JE_HEADERS", "dedup Fusion PVO", "Fusion deletes not
  captured", "Fusion medallion / Silver layer". Defers Lakeflow SDP mechanics to
  databricks-spark-declarative-pipelines.
metadata:
  version: "0.1.0"
parent: oracle-fusion-overview
---

# Oracle Fusion Data Engineering

Design the Silver layer for Oracle Fusion data. Fusion Cloud is SaaS — there is no direct JDBC to the transaction tables — so Bronze is whatever the customer's **landing pattern** produced (BICC PVO file extracts, an FDI star schema, or BI Publisher/OTBI reporting extracts). This skill bridges from that Bronze to a clean, canonical Silver layer the module skills query.

> **FIRST:** load the `oracle-fusion-overview` skill — it carries the org model (Ledger / LE / BU), the **landing-pattern-agnostic rule**, the canonical EBS-style table names, and the universal gotchas (`_ALL` multi-org scoping, CCID segments, accounting-vs-transaction date, period open/close, entered-vs-accounted currency, GL↔XLA, BICC deletes-not-captured). This skill builds on it. For Lakeflow SDP build/debug mechanics (AutoCDC, Auto Loader, expectations API), load the platform skill [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines) — this skill provides only the Fusion-specific modeling decisions.

## When to use

- "Build me an SDP / Lakeflow pipeline for Fusion Silver"
- "How do I ingest BICC PVO extracts (or an FDI star schema)?"
- "What's the right CDC pattern for GL_JE_HEADERS / PO_HEADERS_ALL?"
- "How should I dedup the PVO extract / handle late-arriving rows?"
- "Our BICC extract doesn't capture deletes — how do I reconcile?"
- "Set up / extend the Fusion Silver layer"

**Defer to siblings when:**
- Per-customer physical→canonical mapping, segment meanings, UC comments, the workspace glossary → `oracle-fusion-setup` (it owns UC comment registration; never write comments from this skill).
- "This Silver number looks wrong" diagnostics (unbalanced journals, XLA↔GL drift, extract gaps) → `oracle-fusion-data-quality`.
- Segment-resolution / currency-conversion / period-mapping UDFs and views → `oracle-fusion-ledger-coa` (the keystone). This skill lands the tables those build on.

## Pre-flight (per session)

One-time session config — cache, don't re-ask:

1. **Landing pattern + physical names.** BICC PVO, FDI, or base mirror? Confirm the physical→canonical mapping via the `<customer>-oracle-fusion-glossary` (`oracle-fusion-setup`) if installed, or ask. This decides the `bronze()` source and every column projection.
2. **Target catalog/schema** — "Where should Silver live?" Placeholders: `:catalog`, `:silver_schema`, `:gold_schema`.
3. **Lakeflow target** — Lakeflow Pipeline (SDP) or plain Spark jobs? SDP recommended: incrementality + expectations are first-class.
4. **Extract fidelity** — incremental (last-update-date) only, or is there a Deleted-Record extract / periodic full reload? Decides the deletes-not-captured handling below.

## The Fusion Silver-layer modeling decision matrix

The most important content. For each canonical Fusion table, the correct Silver modeling depends on whether it's a **transaction log** (append), a **stateful record** (apply-changes / SCD), or **reference data** (MV). See [silver-tables.md](silver-tables.md) for grain + dedup key + incremental column per v1 table.

| Canonical table | Silver type | Dedup / merge key | Why |
|---|---|---|---|
| `GL_JE_HEADERS` | **Streaming Table + APPLY CHANGES** | `JE_HEADER_ID` | Header state evolves (unposted → posted); idempotent on the PK |
| `GL_JE_LINES` | **Streaming Table + APPLY CHANGES** | `JE_HEADER_ID, JE_LINE_NUM` | Lines mutate until posting; key is header+line |
| `GL_BALANCES` | **Streaming Table + APPLY CHANGES** | `LEDGER_ID, CODE_COMBINATION_ID, CURRENCY_CODE, PERIOD_NAME, ACTUAL_FLAG` | One balance row per slice; re-extracted as it changes within an open period |
| `GL_CODE_COMBINATIONS` | **SCD Type 2** (or MV) | `CODE_COMBINATION_ID` | COA combos are slowly-changing reference; SCD2 if "what was the account enabled-flag on date X" matters |
| `GL_PERIODS` / `GL_PERIOD_STATUSES` | **Materialized View** | — | Slow-changing calendar; full refresh fine |
| `GL_DAILY_RATES` | **Streaming Table, append-only** | `FROM_CURRENCY, TO_CURRENCY, CONVERSION_DATE, CONVERSION_TYPE` | Rate rows are written once per (pair, date, type) |
| `XLA_AE_HEADERS` / `XLA_AE_LINES` | **Streaming Table, append-only** | natural extract key | Subledger accounting entries are immutable once created |
| `PO_HEADERS_ALL` | **Streaming Table + APPLY CHANGES** | `PO_HEADER_ID` | Header state evolves (approved, canceled, closed); `_ALL` = keep all BUs |
| `PO_LINES_ALL` | **Streaming Table + APPLY CHANGES** | `PO_HEADER_ID, PO_LINE_ID` | |
| `PO_DISTRIBUTIONS_ALL` | **Streaming Table + APPLY CHANGES** | `PO_DISTRIBUTION_ID` | Carries the charged CCID |
| `POZ_SUPPLIERS` (+ sites) | **SCD Type 2** | `VENDOR_ID` (`VENDOR_SITE_ID`) | Supplier master; track attribute history |

Keep `_ALL` tables holding **all** business units in Silver — never pre-filter a BU out (consumers scope by `PRC_BU_ID` / `LEDGER_ID`). Don't merge multiple modules' tables into one Silver table just because columns overlap; the canonical boundaries are real.

## Gotchas at the Silver layer

The traps that silently corrupt every downstream financial metric (the overview owns the universal mechanics — apply them in the pipeline, don't re-teach them):

1. **BICC incremental extracts don't capture hard deletes.** Standard last-update-date PVO extracts catch INSERT/UPDATE only. A row deleted in Fusion simply stops appearing — it is NOT removed from Bronze, so Silver drifts (e.g. a canceled-then-purged PO lingers). If there's no Deleted-Record extract, do a **periodic full reload** of affected tables (snapshot-reconcile: anti-join the latest full snapshot against Silver and tombstone the missing keys). Record the gap; it's a `oracle-fusion-data-quality` reconciliation probe.
2. **Dedup on the extract/PVO key, with a reliable sequence column.** PVO extracts can re-deliver the same logical row across runs (overlapping incremental windows, re-extracts). `apply_changes` needs a monotonic `sequence_by` — use `LAST_UPDATE_DATE` (Fusion's audit column) where present, else the extract/ingest timestamp. Confirm it's trustworthy per table.
3. **`_ALL` multi-org: keep all BUs, never sum at Silver.** `_ALL` tables hold every BU's rows. Silver mirrors them in full; the BU scope (`PRC_BU_ID`, `LEDGER_ID`) is a *consumer* concern. Pre-filtering or summing across BUs at Silver is wrong.
4. **Currency and period are conformance points, not transforms.** Pass `ENTERED_DR/CR`, `ACCOUNTED_DR/CR`, `CURRENCY_CODE`, and `PERIOD_NAME` through unmodified. Never sum `ENTERED` across currencies and never normalize to a single currency at Silver — conversion (via `GL_DAILY_RATES`) and period ordering are owned by the keystone `oracle-fusion-ledger-coa`. This layer just lands the columns intact.
5. **Posted-vs-unposted and cancel/close flags are data, not filters.** Keep unposted journals (`STATUS='U'`) and canceled POs (`CANCEL_FLAG='Y'`) in Silver — downstream leakage/exception diagnostics need them. Filter at consumption, not at Silver.
6. **FDI star schema is pre-modeled — don't re-dimensionalize.** If the landing pattern is FDI, Bronze is already facts/dims with prebuilt metrics. Map FDI subject-area objects to the canonical names via the glossary and pass through; don't rebuild a star that Oracle already built.

## Workflow

1. **Run pre-flight + confirm the landing pattern** and physical→canonical mapping (from the glossary). Confirm the sequence column and extract fidelity (deletes captured?).
2. **Generate the pipeline source** using [pipeline.py](pipeline.py) as the canonical template — it parameterizes the `bronze()` source over the landing pattern and shows the apply-changes/append patterns for representative GL + PO tables. Defer SDP build/debug mechanics to [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines).
3. **Decide the materialization** per table from the matrix + [silver-tables.md](silver-tables.md).
4. **Handle deletes** per extract fidelity (Gotcha 1): rely on the Deleted-Record extract if present, else schedule a periodic full-reload reconcile.
5. **Document the Silver layout** so the keystone and module skills know where the canonical tables live. Update the workspace glossary via `oracle-fusion-setup` if catalog/schema differs from defaults.

## What this skill does NOT cover

- **Lakeflow SDP mechanics** (AutoCDC syntax, Auto Loader options, expectations API, pipeline config/scheduling/debugging) → platform skill [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines). This skill provides Fusion-specific modeling decisions only; `pipeline.py` is an illustrative sketch, not a tutorial.
- **Ingestion to Bronze** (BICC extract scheduling in Oracle, OCI Object Storage → Delta landing, FDI provisioning). Assumed done; out of scope. This skill starts from Bronze.
- **Segment resolution / currency conversion / period mapping** — owned by the keystone `oracle-fusion-ledger-coa` (its views + Trusted UDFs). This layer lands the raw columns those build on.
- **UC comments / table metadata** — owned by `oracle-fusion-setup` (preview-then-apply).

## What NOT to do

- Don't `APPLY CHANGES INTO` the append-only logs (`XLA_AE_LINES`, `GL_DAILY_RATES`) — collapses or misorders immutable history. Append only.
- Don't pre-filter or sum across business units in `_ALL` tables at Silver — keep all BUs; scope is a consumer concern.
- Don't normalize currency or sum `ENTERED` across currencies at Silver — pass `ENTERED`/`ACCOUNTED`/`CURRENCY_CODE` through; conversion is owned by `oracle-fusion-ledger-coa`.
- Don't drop unposted journals or canceled/closed POs at Silver — downstream diagnostics need them.
- Don't assume BICC incremental captures deletes — it doesn't by default (Gotcha 1); plan a Deleted-Record extract or full-reload reconcile.
- Don't hard-code a physical table name — resolve it via the glossary's physical→canonical mapping (landing-agnostic rule).
- Don't write or alter UC comments from this skill — owned by `oracle-fusion-setup`.

## References

- [pipeline.py](pipeline.py) — load when generating/extending the pipeline. Illustrative SDP sketch for BICC PVO → Bronze → Silver covering representative GL + PO tables.
- [silver-tables.md](silver-tables.md) — load when deciding what to materialize. The v1 canonical tables (GL + procurement + keystone) with grain, dedup key, and incremental column.
- Composes with: `oracle-fusion-overview` (universal mechanics), `oracle-fusion-ledger-coa` (segment/currency/period — builds on this layer), `oracle-fusion-setup` (physical→canonical mapping, UC comments), `oracle-fusion-data-quality` (reconciliation probes).
- Lakeflow SDP docs: `https://docs.databricks.com/aws/en/dlt/`
