---
name: maximo-data-quality
description: |
  Use to diagnose IBM Maximo (Maximo, EAM, CMMS) data-quality problems when a
  number "looks wrong" before trusting an analytical result. Covers: numbers
  don't match the Maximo UI, sparse WOSTATUS / status history, current
  WORKORDER.STATUS out of sync with the latest WOSTATUS row, duplicate
  (WONUM, SITEID), double-counted labor (ISTASK/PARENT), inflated counts
  (missing WOCLASS filter), orphaned LABTRANS / WPLABOR / WPMATERIAL,
  ASSET/LOCATIONS hierarchy orphans, cross-site master-data drift, implausible
  REPORTDATE/ACTFINISH/STATUSDATE dates, PM compliance dropping suddenly, custom
  columns unexpectedly NULL, stale LOCANCESTOR closure tables, expired
  QUALPERSON still ACTIVE. Provides a symptom-to-probe playbook of ready-to-run
  SQL diagnostics plus a root-cause taxonomy (ingestion vs source vs analytics).
  Triggers on: "this number looks wrong", "doesn't match Maximo", "reconcile",
  "orphaned records", "same WO twice", "totals don't add up", "data quality".
metadata:
  version: "0.2.0"
parent: maximo-overview
---

# Maximo Data Quality

When something looks off in Maximo analytics, this skill helps Genie diagnose. Common shapes: numbers don't match the Maximo UI; status history looks sparse; labor totals double-count; assets have orphaned records; site reconciliation breaks.

**Why this skill matters**: the first time a user gets a wrong number, they distrust the entire library. This skill makes "investigate why this looks wrong" a competent, fast workflow.

> **FIRST:** load the `maximo-overview` skill — it is the canonical home for the universal Maximo mechanics this skill leans on: SITEID composite keys, `WOCLASS` filtering, `ISTASK` tasks-vs-child-WOs, status-is-a-synonym-domain (`SYNONYMDOMAIN`) resolution, `HISTORYFLAG` hiding closed records, app-server-timezone datetimes, and STATUS-current-vs-WOSTATUS-history. This skill applies those patterns inside its probes and adds the diagnostic-specific depth.

## When to use

- "This number looks wrong" / "doesn't match Maximo UI"
- "Why is WOSTATUS empty for so many WOs?" / current status ≠ latest WOSTATUS row
- "We have the same WONUM twice — is that possible?"
- "Labor totals don't reconcile to the WO's actual cost"
- "Site totals don't add up"
- "PM compliance suddenly dropped — what happened?"
- Before trusting numbers from a new analytical query, especially in a new workspace

Boundary with siblings: this skill **finds and explains** the data defect. The owning module skill defines the *correct metric* once the data is trusted (e.g. cost rollup → `maximo-maintenance-cost`; PM compliance / reactive-vs-proactive → `maximo-reliability`; closure-table traversal → `maximo-asset-hierarchy`; labor master → `maximo-labor-resources`).

## Top gotchas

1. **Before declaring a "missing record" defect, check `HISTORYFLAG`.** A record at a FINAL status gets `HISTORYFLAG=1`, becomes a history record, and drops out of standard List views — so "the WO is gone" is often expected, not a bug. Run completeness counts with AND without the `HISTORYFLAG=0` filter. (Mechanic owned by `maximo-overview`; applied here in Probes 1, 8.)
2. **Status mismatches can be a synonym artifact, not a data bug.** Status columns store the customer-renamable synonym (`SYNONYMDOMAIN.VALUE`), not the internal `MAXVALUE`. A status that "looks wrong" vs the UI may simply be a renamed synonym; resolve via `SYNONYMDOMAIN` before calling it a defect. (Owned by `maximo-overview`; applied in Probes 1, 4.)
3. **Don't "standardize on UTC" as a date fix.** Maximo datetimes are stored in the app server's local timezone (often UTC, but that is a config choice — not guaranteed) and displayed in the user-profile TZ. A "wrong date" is frequently a TZ-display difference, not corruption. Confirm the deployment's app-server TZ (a `maximo-setup` interview fact) before flagging or rewriting dates. (Owned by `maximo-overview`.)
4. **Rule out a user-side definition mismatch before opening a data-quality investigation.** The most common "wrong number" is a differing "open" status set or a forgotten `WOCLASS`/`ISTASK` filter — not bad data. Reproduce the user's exact query first.
5. **A workaround without a root cause is a future bug.** Always classify the defect as ingestion-side, source-system, or analytics-side, and name who owns the fix, before recommending a compensating query.

## Questions to surface first

Ask these before running diagnostics — the answers change which probe and which remediation apply:

1. **What is the source of truth for the comparison?** Maximo UI, a prior report, or another system (PCMS, GIS, SAP)? UI differences are often synonym/TZ/HISTORYFLAG display behavior, not data defects.
2. **What "open" (or "completed") status set does the user mean?** "Open" has multiple valid definitions; confirm the exact `STATUS` values (and whether they're synonyms vs internal `MAXVALUE`) before deciding a count is wrong.
3. **Should closed/history records be in scope?** Completion and trend metrics need `HISTORYFLAG=1` records; live-backlog metrics exclude them. The right answer flips whether "missing" rows are a bug.
4. **Is a fix even permitted at the source?** At regulated (e.g. O&G) customers, any change to source Maximo can trigger MOC/change-management. If source fixes are off the table, scope to ingestion or analytics remediation only.

## Pre-flight (per session)

Cache these once; don't re-ask each probe:
- **Catalog + schema** of the Maximo Silver layer (`:catalog`, `:schema`). Probes assume a single Silver schema.
- **App-server timezone** of this deployment (from `maximo-setup`) — needed to interpret Probe 8 date findings.
- **Known custom statuses / synonyms** for this customer, if `maximo-setup` recorded them.

## Workflow

Don't run all diagnostics at once. Start with what the user is observing, pick the matching probe from [diagnostics.sql](diagnostics.sql), run it, and triage from there.

### Step 1 — Frame the symptom

- Expected number vs observed number.
- Source-of-truth comparison (UI / prior report / other system).
- Affected site / time range / asset class.

### Step 2 — Pick the right diagnostic probe

| Symptom | Probe in `diagnostics.sql` |
|---|---|
| WOSTATUS sparse / current status ≠ latest WOSTATUS row | `Probe 1 — WOSTATUS coverage` |
| Same WONUM appearing twice | `Probe 2 — WONUM uniqueness within SITEID` |
| Labor totals double-counted | `Probe 3 — ISTASK / PARENT roll-up integrity` |
| Status counts inflated | `Probe 4 — WOCLASS filter sanity` |
| Orphaned LABTRANS / WPLABOR / WPMATERIAL | `Probe 5 — Orphan check` |
| ASSET / LOCATION rows with no parent | `Probe 6 — Hierarchy orphans` |
| Master-data drift (same name, different SITEID) | `Probe 7 — Cross-site duplicates` |
| Date inconsistencies | `Probe 8 — Date sanity` |
| PM compliance dropped suddenly | `Probe 9 — PM generation health` |
| Custom column unexpectedly NULL | `Probe 10 — Custom column population` |
| LABTRANS references missing LABOR | `Probe 11 — Labor master integrity` |
| LOCANCESTOR stale vs LOCHIERARCHY | `Probe 12 — Closure-table integrity` |
| Expired QUALPERSON still ACTIVE | `Probe 13 — Qualification expiry gaps` |

### Step 3 — Interpret findings using [common_issues.md](common_issues.md)

Each probe maps to a known root cause. See `common_issues.md` for diagnosis + remediation patterns and the quick triage tree.

### Step 4 — Recommend remediation

Three buckets:
- **Ingestion-side fixes** — usually the right answer if the gap is uniform across recent data (e.g. REST ingestion not writing WOSTATUS history).
- **Source-system fixes** — when Maximo itself has the gap (custom statuses not in the standard domain, broken PM regen).
- **Analytics-side workaround** — when neither can be fixed near-term and the query must compensate.

Never recommend a workaround without documenting WHY the underlying issue exists and who owns fixing it.

## What's in this skill

- [diagnostics.sql](diagnostics.sql) — **load when** you have a symptom and need the ready-to-run probe (13 probes). Has a `## Contents` index.
- [common_issues.md](common_issues.md) — **load when** a probe returns rows and you need the root-cause taxonomy + remediation. Has a `## Contents` index and a quick triage tree.

## What NOT to do

- Don't run every diagnostic at once — overwhelming and most aren't relevant.
- Don't assume a defect without ruling out a user-side definition mismatch first (open-status set, missing `WOCLASS`/`ISTASK` filter).
- Don't "standardize on UTC" to fix dates — app-server TZ is a config choice (see Top gotcha 3); confirm it first.
- Don't call a closed/history record "missing" without checking `HISTORYFLAG` (Top gotcha 1).
- Don't propose a source-Maximo change without flagging change-management implications (every Maximo change can trigger MOC at O&G customers).
- Don't define the *correct* downstream metric here — defer cost rollup to `maximo-maintenance-cost`, PM compliance / reliability metrics to `maximo-reliability`, hierarchy traversal to `maximo-asset-hierarchy`, labor master to `maximo-labor-resources`.

## Composes with

- `maximo-overview` — canonical home for the universal mechanics applied throughout (SITEID, WOCLASS, ISTASK, SYNONYMDOMAIN status resolution, HISTORYFLAG, app-server-timezone, STATUS-vs-WOSTATUS history).
- `maximo-setup` — owns the deployment's app-server TZ, custom-status/synonym list, and the workspace glossary that records intentional exceptions (e.g. "same asset name across SITEIDs is expected for asset class X").
- `maximo-labor-resources` — owns the labor master; Probes 11 and 13 detect defects that its metrics depend on.
- `maximo-asset-hierarchy` — owns closure-table traversal; Probe 12 detects LOCANCESTOR staleness it must fall back from.
- `maximo-data-engineering` — owns the Bronze→Silver pipeline where most ingestion-side fixes land (references the platform skill `databricks-spark-declarative-pipelines`).

## References

- IBM APAR IJ17261 — "STATUS CHANGE IS NOT REGISTERED IN WOSTATUS TABLE": https://www.ibm.com/support/pages/apar/IJ17261
