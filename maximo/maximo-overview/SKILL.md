---
name: maximo-overview
description: |
  Use whenever the user mentions IBM Maximo, Maximo, EAM, CMMS, MAS (Maximo
  Application Suite), asset management, or maintenance management — work
  orders (WO, WONUM, WORKORDER), assets (ASSETNUM, asset hierarchy), locations
  (LOCATIONS), labor (LABTRANS, craft), PMs (preventive maintenance, JOBPLAN),
  failure analysis, MBO data model, plusg* / plusc* / plust* industry-solution
  tables. Orients Genie on Maximo's data model, the module map, and the five
  universal gotchas that apply across any Maximo query (SITEID composite keys,
  WOCLASS filtering, ISTASK dedup, WOSTATUS-vs-WORKORDER history split,
  customer-configurable open-status set). This is the foundation skill loaded
  for any Maximo question — other Maximo skills layer on top.
metadata:
  version: "0.2.0"
---

# Maximo Overview

The foundation skill for working with IBM Maximo data in Databricks. Load it whenever the user mentions Maximo, MAS, EAM, CMMS, or any Maximo concept. Other Maximo skills (`maximo-work-orders`, `maximo-reliability`, etc.) layer on top — they set `parent: maximo-overview` so this stays loaded.

You are not a Maximo specialist out of the box. With this skill loaded, you behave like one — you know the module map, the canonical tables, the joins that always go wrong, and how the Oil & Gas industry extensions layer in.

## When to use

- Any user mention of: Maximo, MAS, EAM, CMMS, work order, WO, WONUM, WORKORDER, ASSET, ASSETNUM, LOCATIONS, PM, JOBPLAN, LABTRANS, FAILURECODE, MBO, plusg*
- Any request to query, analyze, or build pipelines/dashboards/ML on Maximo data
- Before activating any other Maximo skill — this one provides the shared baseline

If the user's question is module-specific (work orders, reliability metrics, integrity inspections, HSE permits), the matching module skill (`maximo-work-orders`, `maximo-reliability`, etc.) will also load. Compose them.

## Pre-flight (ask once per session, then cache)

1. **Catalog/schema location**: "Which Unity Catalog catalog/schema holds your Maximo Silver layer?" (e.g. `eam.maximo_silver`). SQL placeholders use Databricks-native syntax: `:catalog`, `:silver_schema`, `:gold_schema`.
2. **Workspace glossary**: check whether a `<customer>-maximo-glossary` workspace skill is installed. If yes, defer business-jargon resolution to it.
3. **`maximo-setup` status**: if not yet run, UC table/column comments and customer-specific conventions (open-status set, MTBF formula, custom worktypes) are missing — Genie quality degrades. Offer to run it. Setup is split-responsibility by design: facts that fit cleanly in a UC column comment live there (Genie reads them directly); the rest live in skill content as a staging ground that can graduate to comments over time.

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

### Inventory / Purchasing
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

## Composes with

Depth lives in the sibling skills. The overview's job is to route — when the user's question is module-specific, Genie loads the matching skill on top of this one.

### Foundation tier (one-time or cross-cutting)

- [`maximo-setup`](../maximo-setup/) — one-time customer-deployment bootstrap. Profiles the customer's Maximo data, interviews on conventions, generates a workspace-tier `<customer>-maximo-glossary` skill, registers UC comments via a preview-then-apply workflow. Run once per workspace.
- [`maximo-data-engineering`](../maximo-data-engineering/) — Bronze→Silver/Gold modeling for Maximo. Defers Lakeflow SDP mechanics to the canonical platform skill [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines).
- [`maximo-data-quality`](../maximo-data-quality/) — "this number looks wrong" diagnostic playbook.
- [`maximo-workflow-and-approvals`](../maximo-workflow-and-approvals/) — Maximo's workflow engine (WFINSTANCE, WFASSIGNMENT). Cross-cuts every business object that goes through approval (WO, PR, PO, invoice, MoC, incident, ticket).

### Module tier (analytical domains)

- [`maximo-work-orders`](../maximo-work-orders/) — WO operations: backlog, status history, labor analytics, completion, planned vs actual.
- [`maximo-reliability`](../maximo-reliability/) — reliability metrics (backward-looking): MTBF, MTTR, PM compliance, failure-mode analysis. Ships Trusted UDFs matching IBM's published O&G formulas.
- [`maximo-pm-planning`](../maximo-pm-planning/) — PM planning (forward-looking): PM forecasting, craft workload, JOBPLAN content, route grouping. Companion to `maximo-reliability`.
- [`maximo-inventory`](../maximo-inventory/) — INVENTORY, INVBALANCES, ITEM, storeroom analytics: reorder, stockout, ABC, parts availability for WOs.
- [`maximo-maintenance-cost`](../maximo-maintenance-cost/) — cost rollups by asset / location / period: ACTLABCOST + ACTMATCOST, budget vs actual, PM-vs-CM cost, contractor spend.
- [`maximo-labor-resources`](../maximo-labor-resources/) — labor masters (LABOR, PERSON, CRAFT, LABORCRAFTRATE), qualifications (QUALIFICATION, QUALPERSON), crews (CREW, CREWLABOR), calendars (CALENDAR, WORKPERIOD), assignments (ASSIGNMENT). Composes with `maximo-pm-planning` for workload-vs-capacity gap analytics.
- [`maximo-asset-hierarchy`](../maximo-asset-hierarchy/) — closure tables (LOCHIERARCHY, LOCANCESTOR, ASSETANCESTOR), classification trees (CLASSSTRUCTURE), virtual hierarchies (SYSTEM), and rollups by region / station / area / system / asset class. Composes with most module skills for hierarchical analytics.
- [`maximo-integrity`](../maximo-integrity/) — O&G-heavy: corrosion trending, regulatory inspections (API 510 / 570, B31.4, CSA Z662), RBI scoring, inspection-tied incidents. Requires PLUSG industry-solution tables.
- [`maximo-hse`](../maximo-hse/) — O&G-heavy: permit-to-work, incidents, investigations, MoC, TRIR/LTIR. Requires PLUSG.

### Genie Agent scaffolder

**Be precise about the Genie products:** *Genie Code* is the agent harness that loads these skills and authors artifacts. *Genie Agents* (formerly *Genie Spaces*) are a curated text-to-SQL data product Genie Code can create on top of UC data. The scaffolder skill below curates the **content**; creation mechanics defer to the platform skill.

- [`maximo-genie-space`](../maximo-genie-space/) — *to be renamed `maximo-genie-agent` post-rebrand.* Curates a Genie Agent on Maximo data: which UC objects to include, semantic descriptions, Trusted UDFs to register, sample questions. Defers Agent creation mechanics to [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md).

### Platform skills (reference, never duplicate)

When a Maximo module touches platform mechanics, reference the canonical platform skill from [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills) rather than re-teaching:

| Need | Platform skill |
|---|---|
| Genie Agent creation / management | [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md) |
| Lakeflow pipelines (SDP / Auto Loader / AutoCDC) | [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines) |
| UC mechanics (comments, grants, lineage, tags) | [`databricks-unity-catalog`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-unity-catalog) |
| AI/BI Dashboards on Maximo data | [`databricks-aibi-dashboards`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-aibi-dashboards) |
| Job scheduling for pipelines / refreshes | [`databricks-jobs`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-jobs) |

## References

- IBM Maximo Manage docs: `https://www.ibm.com/docs/en/masv-and-l/maximo-manage/`
- IBM Maximo Oil & Gas docs: `https://www.ibm.com/docs/en/mfo-and-g/`
- Class-name prefixes (PLUSG, PLUSC, PLUST, PLUSU): `https://www.ibm.com/support/pages/classname-prefixes-info-industry-solutions-classes-maximo`
