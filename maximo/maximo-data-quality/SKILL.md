---
name: maximo-data-quality
description: |
  Use to diagnose Maximo data quality issues — "this number looks wrong",
  "WOSTATUS seems sparse", "labor totals don't match Maximo UI", "orphaned
  records", "the same WO appears twice", "site totals don't reconcile",
  "PM compliance dropped suddenly". Provides a diagnostic playbook with
  ready-to-run SQL probes for the most common Maximo data quality problems.
metadata:
  version: "0.1.0"
parent: maximo-overview
---

# Maximo Data Quality

When something looks off in Maximo analytics, this skill helps Genie diagnose. Common shapes: numbers don't match what's on the Maximo UI; status history looks sparse; labor totals double-count; assets have orphaned records; site reconciliation breaks.

**Why this skill matters**: the first time a user gets a wrong number, they distrust the entire library. This skill makes "investigate why this looks wrong" a competent, fast workflow.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas (SITEID composite keys, `WOCLASS` filtering, `ISTASK` dedup, WOSTATUS-vs-WORKORDER history). This skill builds on that foundation.

## When to use

- "This number looks wrong" / "doesn't match Maximo UI"
- "Why is WOSTATUS empty for so many WOs?"
- "We have the same WONUM twice — is that possible?"
- "Labor totals don't reconcile to the WO's actual cost"
- "Site totals don't add up"
- "PM compliance suddenly dropped — what happened?"
- Before trusting numbers from a new analytical query, especially in a new workspace

## Workflow

Don't run all diagnostics at once. Start with what the user is observing, pick the matching probe from [diagnostics.sql](diagnostics.sql), run it, and triage from there.

### Step 1 — Frame the symptom

Ask the user:
- What's the number they expected vs what they're getting?
- Is the source-of-truth comparison the Maximo UI, a previous report, or a different system (PCMS, GIS, etc.)?
- Which site / time range / asset class is affected?

### Step 2 — Pick the right diagnostic probe

| Symptom | Probe in `diagnostics.sql` |
|---|---|
| WOSTATUS sparse / current status doesn't match latest WOSTATUS row | `Probe 1 — WOSTATUS coverage` |
| Same WONUM appearing twice | `Probe 2 — WONUM uniqueness within SITEID` |
| Labor totals double-counted | `Probe 3 — ISTASK / PARENT roll-up integrity` |
| Status counts inflated | `Probe 4 — WOCLASS filter sanity` |
| Orphaned LABTRANS / WPLABOR | `Probe 5 — Orphan check` |
| ASSET / LOCATION rows with no parent | `Probe 6 — Hierarchy orphans` |
| Master-data drift (same name, different SITEID) | `Probe 7 — Cross-site duplicates` |
| Date inconsistencies | `Probe 8 — Date sanity` |
| PM compliance dropped suddenly | `Probe 9 — PM generation health` |
| Custom column unexpectedly NULL | `Probe 10 — Custom column population` |

### Step 3 — Interpret findings using [common_issues.md](common_issues.md)

Each probe maps to a known root cause. See `common_issues.md` for diagnosis + remediation patterns.

### Step 4 — Recommend remediation

Three buckets:
- **Ingestion-side fixes** — usually the right answer if the gap is uniform across recent data (e.g. REST ingestion not writing WOSTATUS history)
- **Source-system fixes** — when Maximo itself has the gap (custom statuses not in standard domain, broken PM regen)
- **Analytics-side workaround** — when neither can be fixed near-term and the query needs to compensate

Never recommend a workaround without documenting WHY the underlying issue exists and who owns fixing it.

## What NOT to do

- Don't run every diagnostic at once — overwhelming and most aren't relevant
- Don't assume an issue is data quality without ruling out user-side misunderstanding first (e.g. "open" status set mismatch)
- Don't propose a fix that requires changing source Maximo without flagging the change-management implications (every Maximo change can trigger MOC requirements at O&G customers)

## References

- [diagnostics.sql](diagnostics.sql) — 10 ready-to-run diagnostic probes
- [common_issues.md](common_issues.md) — root-cause taxonomy for each probe
- IBM APAR IJ17261 — "STATUS CHANGE IS NOT REGISTERED IN WOSTATUS TABLE": https://www.ibm.com/support/pages/apar/IJ17261
