---
name: oracle-fusion-data-quality
description: |
  Use to diagnose Oracle Fusion Cloud ERP (Fusion ERP / Financials / SCM /
  Oracle Cloud ERP) data-quality problems when a financial number "looks wrong"
  before trusting an analytical result. Covers: trial balance doesn't tie /
  debits != credits (unbalanced journal), GL-to-subledger (XLA) reconciliation
  drift, posted-vs-unposted leakage (unposted journals counted as actuals),
  multi-currency summing without conversion (ENTERED summed across currencies),
  _ALL multi-org duplicate / double-counting, BICC extract gaps (hard deletes
  not captured, late-arriving rows, Bronze drift), period open/close status
  mismatches, and orphan code combinations (CCID not in GL_CODE_COMBINATIONS).
  Provides an ordered symptom-to-probe playbook of ready-to-run parameterized
  SQL diagnostics plus a symptom -> cause -> fix catalogue. Triggers on: "this
  number looks wrong", "trial balance doesn't tie", "GL doesn't match the
  subledger", "totals don't add up", "reconcile Fusion", "deletes not captured",
  "currency totals off", "duplicate POs", "orphan CCID", "data quality".
metadata:
  version: "0.1.0"
parent: oracle-fusion-overview
---

# Oracle Fusion Data Quality

When something looks off in Fusion analytics, this skill helps Genie diagnose. Common shapes: the trial balance doesn't tie; GL doesn't reconcile to the subledger; totals are inflated by `_ALL` multi-org rows; currency sums are wrong; numbers drift from Fusion because the BICC extract missed deletes.

**Why this skill matters**: the first time a user gets a wrong financial number, they distrust the entire library. This skill makes "investigate why this looks wrong" a competent, fast workflow.

> **FIRST:** load the `oracle-fusion-overview` skill — it is the canonical home for the universal Fusion mechanics this skill leans on: `_ALL` multi-org scoping, CCID segments, accounting-vs-transaction date, period open/close, entered-vs-accounted currency, the GL↔XLA bridge, and BICC deletes-not-captured. This skill applies those patterns inside its probes and adds the diagnostic-specific depth. The accounting mechanics (segments, currency, periods, XLA) are owned by the keystone `oracle-fusion-ledger-coa`.

## When to use

- "This number looks wrong" / "doesn't match Fusion / OTBI / a prior report"
- "The trial balance doesn't tie" / "debits don't equal credits"
- "GL doesn't reconcile to the subledger (AP/AR/PO)"
- "Our actuals look too high — are unposted journals leaking in?"
- "Multi-currency totals are off"
- "We have the same PO twice / totals are double-counted"
- "Numbers drifted from Fusion — did the extract miss deletes?"
- Before trusting numbers from a new analytical query, especially in a new workspace

Boundary with siblings: this skill **finds and explains** the data defect. The owning module skill defines the *correct metric* once the data is trusted (trial balance / actuals → `oracle-fusion-general-ledger`; spend → `oracle-fusion-procurement`; segment/currency/period/XLA mechanics → `oracle-fusion-ledger-coa`; the Silver pipeline where ingestion-side fixes land → `oracle-fusion-data-engineering`).

## Questions to surface first

Ask these before running diagnostics — the answers change which probe and which remediation apply:

1. **What is the source of truth for the comparison?** The Fusion UI / OTBI, a prior report, or another system? UI differences are often currency-basis (entered vs accounted) or period-status display, not data defects.
2. **Which ledger / currency basis and period scope does the user mean?** "Revenue" in entered vs accounted vs analytics currency, posted-only vs all, a single ledger vs consolidated — confirm before deciding a number is wrong.
3. **What is the landing pattern + extract fidelity?** BICC incremental (deletes NOT captured by default), FDI, or base mirror? Drift from Fusion is often a missing Deleted-Record extract, not corruption.
4. **Is a source-side fix even permitted?** At regulated customers, changes to source Fusion config follow change management. If source fixes are off the table, scope to ingestion or analytics remediation only.

## Pre-flight (per session)

Cache these once; don't re-ask each probe:
- **Catalog + schema** of the Fusion Silver layer (`:catalog`, `:silver_schema`).
- **In-scope ledgers / business units and the currency basis** (from `oracle-fusion-setup` glossary) — needed to scope Probes correctly.
- **Landing pattern + whether deletes are captured** (from the glossary) — needed to interpret Probe 6.

## Workflow

Don't run all diagnostics at once. Start with what the user is observing, pick the matching probe from [diagnostics.sql](diagnostics.sql), run it, and triage from there.

### Step 1 — Frame the symptom

- Expected number vs observed number.
- Source-of-truth comparison (Fusion UI / OTBI / prior report / other system).
- Affected ledger / business unit / period / currency.

### Step 2 — Pick the right diagnostic probe (ordered)

Run in roughly this order when the symptom is vague — earlier probes rule out the most common, cheapest-to-confirm causes first.

| Symptom | Probe in `diagnostics.sql` |
|---|---|
| Trial balance doesn't tie / debits != credits | `Probe 1 — Unbalanced journals` |
| Actuals look too high / unposted leaking in | `Probe 2 — Posted vs unposted leakage` |
| Multi-currency totals look wrong | `Probe 3 — Multi-currency summing without conversion` |
| `_ALL` totals double-counted / same PO twice | `Probe 4 — _ALL multi-org duplicate counting` |
| Period numbers change / not final | `Probe 5 — Period status mismatch` |
| Numbers drifted from Fusion | `Probe 6 — BICC extract gaps (deletes / late-arriving)` |
| GL doesn't match the subledger | `Probe 7 — GL-to-subledger (XLA) reconciliation drift` |
| Account decode fails / NULL account name | `Probe 8 — Orphan code combinations (CCID)` |

### Step 3 — Interpret findings using [common-issues.md](common-issues.md)

Each probe maps to a known root cause. See `common-issues.md` for symptom → cause → fix and the quick triage tree.

### Step 4 — Recommend remediation

Three buckets:
- **Ingestion-side fixes** — usually right when the gap is uniform/recent (e.g. BICC incremental not capturing deletes → add a Deleted-Record extract or full-reload reconcile, in `oracle-fusion-data-engineering`).
- **Source-system / config fixes** — when Fusion itself has the gap (a period left open, a feeder not transferred to GL).
- **Analytics-side workaround** — when neither can be fixed near-term and the query must compensate (e.g. scope by `LEDGER_ID`/`PRC_BU_ID`, use accounted amounts).

Never recommend a workaround without documenting WHY the underlying issue exists and who owns the fix.

## What NOT to do

- Don't run every diagnostic at once — overwhelming and most aren't relevant.
- Don't assume a defect without ruling out a **user-side definition mismatch** first (entered-vs-accounted currency, posted-only, ledger/BU scope) — the most common "wrong number".
- Don't sum `ENTERED` amounts across currencies to "check" a total — that reproduces the bug; use accounted/ledger amounts (Probe 3).
- Don't add GL journal amounts to XLA subledger detail when reconciling — XLA rolls *up into* GL; comparing levels is the point, summing them double-counts (Probe 7).
- Don't call drift from Fusion "corruption" before checking the **BICC deletes-not-captured** case (Probe 6) — it's the most common cause and is an ingestion gap, not bad data.
- Don't flag a changing period number as a defect before checking **period open/close** status — open periods legitimately change (Probe 5).
- Don't define the *correct* downstream metric here — defer trial balance/actuals to `oracle-fusion-general-ledger`, spend to `oracle-fusion-procurement`, and segment/currency/period/XLA mechanics to `oracle-fusion-ledger-coa`.

## What's in this skill

- [diagnostics.sql](diagnostics.sql) — **load when** you have a symptom and need the ready-to-run probe (8 probes, ordered). Has a `## Contents` index.
- [common-issues.md](common-issues.md) — **load when** a probe returns rows and you need the symptom → cause → fix catalogue + quick triage tree. Has a `## Contents` index.

## Composes with

- `oracle-fusion-overview` — canonical home for the universal mechanics applied throughout (`_ALL` scoping, CCID segments, period open/close, entered-vs-accounted currency, GL↔XLA, BICC deletes-not-captured).
- `oracle-fusion-ledger-coa` — owns the accounting model (segment resolution, currency conversion, period mapping, XLA bridge) the probes lean on; defines the *correct* reconciled metric.
- `oracle-fusion-setup` — owns the landing pattern, deletes-captured flag, ledger/BU scope, and the workspace glossary recording intentional exceptions.
- `oracle-fusion-data-engineering` — owns the Bronze→Silver pipeline where most ingestion-side fixes land (deletes-not-captured reconcile, dedup); references the platform skill `databricks-spark-declarative-pipelines`.

## References

- Oracle Fusion Financials data model (OEDMF): `https://docs.oracle.com/en/cloud/saas/financials/25c/oedmf/`
- BICC (BI Cloud Connector) — incremental extract + Deleted-Record extract behavior: `https://docs.oracle.com/en/cloud/saas/applications-common/bicc/`
