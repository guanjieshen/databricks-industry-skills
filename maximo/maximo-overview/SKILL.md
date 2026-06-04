---
name: maximo-overview
description: |
  Use whenever the user mentions IBM Maximo, MAS (Maximo Application Suite),
  or any Maximo concept — work orders, WO, WONUM, WORKORDER, assets, ASSETNUM,
  PMs, JOBPLAN, MBO, plusg* tables, "EAM data". Orients Genie on Maximo's data
  model, the module map, and universal gotchas that apply across any Maximo
  query (SITEID composite keys, WOCLASS filtering, ISTASK deduplication,
  WOSTATUS vs WORKORDER history split). This is the foundation skill loaded
  for any Maximo question — other Maximo skills layer on top.
metadata:
  version: "0.1.0"
---

# Maximo Overview

This skill gives you the baseline literacy needed to work with IBM Maximo data in Databricks. Load it whenever a user mentions Maximo, MAS, or any Maximo concept.

You are not a Maximo specialist out of the box. With this skill loaded, you behave like one — you know the module map, the canonical tables, the joins that always go wrong, and how the Oil & Gas industry extensions layer in.

## Genie Code tips (apply to every Maximo question)

- **Auth is ambient in the workspace** — Genie Code is already authenticated to the current workspace, so do **not** pass `--profile` (there's usually no named profile and it would fail). Use `--profile <name>` only when running these skills from a local machine against a `~/.databrickscfg` profile.
- **Reference tables explicitly** with `@catalog.schema.table` and use **`/findTables`** to locate them — don't guess names.
- Skills load **only in Agent mode**, and Genie selects them **only by matching their `description`**. If you edit a skill, start a **new chat** for the change to take effect.
- If `maximo-setup` has not been run in this workspace, business terms and Unity Catalog comments may be missing and answers degrade. Offer to run it.

## When to use

- Any user mention of: Maximo, MAS, EAM, CMMS, work order, WO, WONUM, WORKORDER, ASSET, ASSETNUM, LOCATIONS, PM, JOBPLAN, LABTRANS, FAILURECODE, MBO, plusg*
- Any request to query, analyze, or build pipelines/dashboards/ML on Maximo data
- Before activating any other Maximo skill — this one provides the shared baseline

If the user's question is module-specific (work orders, reliability metrics, integrity inspections, HSE permits), the matching module skill (`maximo-work-orders`, `maximo-reliability`, etc.) will also load. Compose them.

## Pre-flight (ask once per session, then cache)

1. **Catalog/schema location**: "Which Unity Catalog catalog/schema holds your Maximo Silver layer?" (e.g. `eam.maximo_silver`)
2. **Workspace glossary**: Check whether a `<customer>-maximo-glossary` workspace skill is installed. If yes, defer business-jargon resolution to it. If no, suggest running `maximo-setup` for the workspace once — it generates that glossary.

## The five universal gotchas (apply to almost every Maximo query)

Read these every time. They are the cause of ~80% of wrong answers Genie gives on Maximo data without this skill loaded.

1. **`WORKORDER.STATUS` is *current*; history is in `WOSTATUS`.** A WO has one row in `WORKORDER` (current state) and N rows in `WOSTATUS` (one per status transition). Asking "what's the status of WO X" → `WORKORDER`. Asking "how long was WO X in INPRG" → `WOSTATUS`.

2. **`WORKORDER` is a multi-purpose table — filter by `WOCLASS`.** It also holds PM records (`'PM'`), Changes (`'CHANGE'`), Releases (`'RELEASE'`), Activities (`'ACTIVITY'`). For normal work-order analysis, always `WHERE WOCLASS = 'WORKORDER'`. Without this filter, backlog counts and labor totals are inflated.

3. **`ISTASK = 1` rows are child tasks — dedupe to parent for backlog counts.** A WO has a header (`ISTASK = 0`) and may have N child tasks (`ISTASK = 1`, each with a `PARENT` pointer). Counting all rows double-counts.

4. **`SITEID` is part of every business key.** `WONUM`, `ASSETNUM`, `LOCATION`, `JPNUM` are unique only within a site. Joining without `SITEID` produces a cross product. Always include `SITEID` in joins between Maximo tables.

5. **Open-status set is customer-configurable.** Maximo defaults are `WAPPR / APPR / WSCH / WMATL / INPRG`, but every customer extends. "Open" typically means everything except `COMP / CLOSE / CAN`. Confirm with the user OR consult the workspace glossary skill.

## The Maximo module map (which tables live where)

Tables Genie should know exist, organized by Maximo module:

### Work Management
- `WORKORDER` — WO header (current state)
- `WOSTATUS` — WO status history (per-transition log)
- `LABTRANS` — labor transactions booked to WOs (one row per craft-hour)
- `WPLABOR` / `WPMATERIAL` — planned labor / material on a WO
- `JOBPLAN` / `JPLABOR` / `JPMATERIAL` — task templates referenced by `WORKORDER.JPNUM`

### Asset Management
- `ASSET` — asset master + `ASSETSTATUS`
- `ASSETMETER` — meter definitions per asset (corrosion gauges, vibration channels, etc.)
- `METERREADING` — time-series readings against meters
- `LOCATIONS` — location master
- `LOCHIERARCHY` — full parent-child hierarchy if needed

### Preventive Maintenance
- `PM` — PM master (schedule definitions)
- `PMSEQUENCE` — PM step sequences

### Failure Reporting
- `FAILUREREPORT` — coded failure data on completed WOs
- `FAILURECODE` — failure taxonomy (tree: PROBLEM → CAUSE → REMEDY)

### Inventory / Purchasing (`maximo-inventory` skill in v3)
- `INVENTORY`, `INVBALANCES`, `INVUSE`
- `PO`, `POLINE`, `INVOICE`, `INVOICELINE`
- `COMPANIES`

### Resources (Labor)
- `LABOR` — labor master (`LABORCODE` → person + craft + default rate)
- `PERSON` — person master
- `CRAFT` — craft codes

### Oil & Gas extensions (PLUSG industry solution)
- `plusgpermitwork` — permit to work
- `plusgpertype` — permit types
- `plusgshftlogentry` / `plusgshiftlog` — operator shift logs
- `plusgincperson` — incident persons
- `plusgrelatedrec` — related-record links (e.g., incident → MOC → integrity finding)
- `plusgoperaction` — operator actions

Other industry-solution prefixes you may see: `PLUSC` (Calibration), `PLUST` (Transportation), `PLUSU` (Utilities).

### Operational / system
- `SYNONYMDOMAIN` — value-domain lookups (e.g. status synonyms per `DOMAINID`)
- `MAXVARS` — system-wide config values

## Cardinality cheat-sheet

| Relationship | Cardinality |
|---|---|
| `WORKORDER` → `WOSTATUS` | 1 : N |
| `WORKORDER` → `LABTRANS` | 1 : N |
| `WORKORDER` → `FAILUREREPORT` | 1 : 0..N |
| `WORKORDER` → `ASSET` | N : 1 (via `ASSETNUM + SITEID`) |
| `WORKORDER` → `LOCATIONS` | N : 1 (via `LOCATION + SITEID`) |
| `WORKORDER` → `JOBPLAN` | N : 1 (via `JPNUM + ORGID`) |
| `WORKORDER` → `WORKORDER` (parent/child) | self-join via `PARENT` |
| `ASSET` → `ASSETMETER` | 1 : N |
| `ASSETMETER` → `METERREADING` | 1 : N |
| `PM` → `PMSEQUENCE` | 1 : N |
| `FAILUREREPORT` → `FAILURECODE` | N : 1 |
| `plusgpermitwork` → `WORKORDER` | 1 : N (a permit covers WOs) |

## Date semantics — which `*_DATE` column means what

| Column | Meaning |
|---|---|
| `REPORTDATE` | WO created |
| `STATUSDATE` | When the *current* `STATUS` was set (not the original create) |
| `TARGCOMPDATE` | Target completion |
| `SCHEDSTART` / `SCHEDFINISH` | Scheduled window |
| `ACTSTART` / `ACTFINISH` | Actual execution window |
| `CHANGEDATE` (on `WOSTATUS`) | When this status transition was logged |

"Backlog age" usually = `current_date() - REPORTDATE` for open WOs. Some customers prefer days-in-current-status (`current_date() - STATUSDATE`). Confirm.

## What NOT to do

- Don't run a Maximo query without filtering `WHERE WOCLASS = 'WORKORDER'` if working with work-order data — unless explicitly asked otherwise.
- Don't ignore `SITEID` in joins between Maximo tables. Multi-site customers get silently wrong results.
- Don't assume the customer's open-status set matches Maximo defaults. Ask or consult the workspace glossary.
- Don't fabricate column names that aren't in this document. If a customer mentions a custom field, ask if it's a standard extension column or something they added.
- Don't conflate `WORKORDER.STATUS` (current) with `WOSTATUS.STATUS` (history). The #1 source of wrong answers.

## Module pointers (depth lives in module skills)

- For **labor / craft / crew / qualification / capacity** queries → load [`maximo-labor-resources`](../maximo-labor-resources/). The `LABOR`, `PERSON`, `CRAFT`, `LABORCRAFTRATE`, `QUALIFICATION`, `QUALPERSON`, `CREW`, `CALENDAR`, `WORKPERIOD`, `AVAILREFLY`, `ASSIGNMENT` tables and their gotchas live there.
- For **hierarchical rollups** (by region / station / area / system / asset class) → load [`maximo-asset-hierarchy`](../maximo-asset-hierarchy/). The `LOCHIERARCHY`, `LOCANCESTOR`, `ASSETANCESTOR`, `SYSTEM`, `CLASSSTRUCTURE` content and closure-table mechanics live there.

## References

- IBM Maximo Manage docs: `https://www.ibm.com/docs/en/masv-and-l/maximo-manage/`
- IBM Maximo Oil & Gas docs: `https://www.ibm.com/docs/en/mfo-and-g/`
- Class-name prefixes (PLUSG, PLUSC, PLUST, PLUSU): `https://www.ibm.com/support/pages/classname-prefixes-info-industry-solutions-classes-maximo`
