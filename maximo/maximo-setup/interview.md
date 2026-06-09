# Maximo Setup — Interview (adaptive, profile-first)

Run **after** `scripts/introspect_schema.py` has produced `draft_profile.json`. Conduct
this like a Maximo implementation consultant **who can already see the data**: the
profile answers "what" (the distinct values, the custom columns, which modules are
populated, the activity heatmap). Your job is to capture what data **can't** prove —
**intent, exceptions, process reality, and KPI definitions** — and to confirm/correct
the profiler's proposals.

**Ground every question in the profile.** Don't ask *"what are your statuses?"* — say
*"your data has these statuses; walk me through what they mean."* Ask in **batches of
2–3**, not all at once.

## Up-front explainer (tell the customer this)

> *"~30 questions are catalogued; we'll only ask the ones your data signals as relevant
> for your deployment. You can skip any — we'll flag it for follow-up and proceed. Stop
> whenever you want; we'll generate a glossary with what you've confirmed. The skill
> supports two paths: a **SME-led** path (~30 minutes) that captures everything; a
> **Solo path** (~10 minutes) for a non-Maximo DE working without a maintenance SME
> — Tier 1 questions only, the rest deferred to follow-up."*

### Six design principles (apply universally)

1. **Data tells us what it can.** Never ask what the profiler can answer.
2. **Tier by correctness blast radius.** Tier 1 always asked; Tier 2 quality; Tier 3 edge.
3. **Default to skip, not interrogate.** Questions fire only when their trigger evaluates true.
4. **Skip-defer is always a valid answer.** Customer is **never blocked**. Skipped → `answers.followups` with `owner: <role>`; glossary renders `_unknown_ — confirm with <role>`.
5. **Re-runs close gaps over time.** Delta-refresh revisits unconfirmed items.
6. **One accessible voice; explain Maximo concepts once per batch** (sidebars suppressed for Expert/Familiar via Q0).

## Two paths

| Path | Audience | Scope | Time |
|---|---|---|---|
| **SME-led** (default) | A maintenance / reliability / data-platform SME is on the session | All triggered questions (Tier 1 + 2 + 3) | ~30 min |
| **Solo path** | A non-Maximo DE working without a Maximo SME | **Tier 1 only**; everything else deferred to `_unknown_` with an owner | ~10 min |

**The Solo path is the right default for a non-Maximo DE evaluating the framework or building a first dashboard.** It produces a usable glossary that resolves the customer's sites, open-status set, modules-in-scope, and app-server timezone — enough for the metric views, joins, and status filters in every other `maximo-*` skill to work correctly *for this customer's data*. Business-term mappings, KPI nuance, customizations, and tribal knowledge stay flagged for the SME to confirm in a later re-run.

Solo-path Tier 1 questions (the only ones asked):
- Q1 (industry & PLUSG add-ons)
- Q2 (modules in Maximo vs another system)
- Q4 (open-status set — accept stock Maximo defaults if no obvious customizations)
- Q5 (status synonym renamings — easy to read from the profiler dump)
- Q10 (sites — list them; mapping to business regions deferred)
- Q11 (LOCATIONS vs ASSET parent authoritative — pick a default)
- Q22 (multi-currency — only if profiler shows distinct currencies > 1)
- Q24 (app-server timezone — if MAXVARS or default-instructions reveal it, otherwise default UTC)

## Question header pattern

Every question carries the same header so Genie Code can evaluate triggers against
`draft_profile.json` + `answers.json`-so-far and ask / skip / defer deterministically.

```markdown
### Q{N}: {Title}
**Tier**: 1 | 2 | 3
**Trigger**: <boolean condition over draft_profile + answers-so-far>
**Skip behavior**: defer to `_unknown_` with `owner: <role>`
**Records to**: answers.<key>

{Question prose — plain language, no dual phrasing}
```

## Q0 — Maximo familiarity check (FIRST question)

**Tier**: 1 (always asked, first)
**Trigger**: always
**Skip behavior**: default to `Limited` (eager defer affordance)
**Records to**: `customer.maximo_familiarity`

> *"How familiar are you with Maximo's data model and configuration?"*
>
> - **Expert** — you administer it, configure modules, know the MBO model
> - **Familiar** — you use it regularly but don't configure it
> - **Limited** — you've worked with the data but don't know how it's set up
> - **None** — you're a data engineer / analyst who hasn't used Maximo

**Adaptive behavior driven by Q0:**

| Familiarity | Concepts sidebars at batch start | Defer affordance | SME suggestion |
|---|---|---|---|
| `Expert` / `Familiar` | **Suppressed** | Offered as normal | Only when user asks |
| `Limited` / `None` | **Shown** — defines Maximo terms used in the batch | Offered **eagerly** ("if you're not sure we'll flag for a maintenance planner to confirm") | **Proactively suggested** for Batches 6 (data integrity), 7 (KPIs), 8 (regulatory) |

For `Limited` / `None`, also surface the **Solo path** as an explicit option: *"Want to take the Solo path? Tier 1 only — we capture the basics that let the rest of the Maximo skills work for your data, defer everything else to a maintenance SME later."*

---

## Contents

- Q0 — Maximo familiarity check (FIRST)
- Batch 0 — Industry & how you use Maximo
- Batch 1 — Work-order lifecycle & statuses (open set, SYNONYMDOMAIN renamings)
- Batch 2 — Work types & the PM-vs-CM truth
- Batch 3 — Sites, orgs & hierarchy
- Batch 4 — Asset classes & criticality
- Batch 5 — Custom columns & tables
- Batch 6 — Data integrity & process reality (workflow, failure codes, migration, TZ)
- Batch 7 — KPIs, multi-currency, & reconciliation
- Batch 8 — Regulatory & HSE (PLUSG / O&G only)
- Closing — tribal knowledge
- How to record answers (`answers.json` shape + profiler mapping)

---

## Batch 0 — Industry & how you actually use Maximo

> **Concepts in this batch** (shown for `Limited` / `None` familiarity only)
> - **Industry solution / add-on**: a Maximo add-on for a specific industry. Common ones: **PLUSG** (Oil & Gas — permits, integrity), **PLUSC** (Calibration), **PLUST** (Transportation), **PLUSU** (Utilities). Indicated by tables prefixed `plusg*` / `plusc*` etc.
> - **System of record**: which app *owns* the data for a given process. A customer may run work orders in Maximo but inventory in SAP — "modules in use" means modules where Maximo is authoritative.
> - **MAS** = Maximo Application Suite (the v8+ container product). **Manage** is the work-management app inside it.

Confirm `draft_profile.json → usage_profile` + Module Activity Heatmap (`activity_report.md`).

### Q1: Industry & PLUSG add-ons
**Tier**: 1
**Trigger**: always
**Skip behavior**: defer to `_unknown_` with `owner: Maximo administrator`
**Records to**: `industry_usage.industry`, `industry_usage.industry_solutions`

> *"The profile {found / did not find} `plusg*` tables. Are you on the Maximo Oil & Gas (PLUSG) industry solution? What industry and sub-segment are you?"* Other add-ons to ask about: PLUSC (Calibration), PLUST (Transportation), PLUSU (Utilities), Nuclear, Aviation, Spatial.

### Q2: Modules in Maximo vs. another system of record
**Tier**: 1
**Trigger**: always (uses Module Activity Heatmap as starting point)
**Skip behavior**: accept the heatmap verdicts as-is; flag DORMANT/INSUFFICIENT_DATA as `_unknown_`
**Records to**: `industry_usage.modules_in_use`, `industry_usage.modules_elsewhere`

> *"Heatmap shows: {ACTIVE: work-management, PM, labor}; {DORMANT: inventory}; {NOT_INGESTED: procurement}. For DORMANT/NOT_INGESTED modules: do you run that process in Maximo at all, or is it in SAP / Oracle / GIS / etc.? Confirm any ACTIVE module you DON'T actually use as authoritative."* Empty/sparse indicator tables usually mean the process lives elsewhere.

### Q3: Maintenance maturity
**Tier**: 2
**Trigger**: `customer.maximo_familiarity IN ('Expert', 'Familiar')` OR an SME is in the session
**Skip behavior**: defer to `_unknown_` with `owner: Reliability lead`
**Records to**: `industry_usage.maintenance_maturity`

> *"What's your maintenance maturity — run-to-failure, time-based PM, condition-based, RCM/PdM? Who uses this data and what decisions do they make from it?"*

### Q4: MAS / Manage version + patch level
**Tier**: 3
**Trigger**: customer mentions REST API ingestion, or asks about a feature that's version-gated (Trusted Assets routing, mobile changes, integration patterns)
**Skip behavior**: defer to `_unknown_` with `owner: Maximo administrator`
**Records to**: `mas_version`

> *"Which MAS version + patch level are you on (e.g. MAS 8.11.x / Manage 8.7.x)?"* Gates the REST-PATCH gotcha + feature availability + workflow engine version differences.

---

## Batch 1 — Work-order lifecycle & statuses

> **Concepts in this batch** (shown for `Limited` / `None`)
> - **WO status**: a work order's lifecycle marker. Maximo defaults: `WAPPR` (waiting on approval), `APPR` (approved), `INPRG` (in progress), `WSCH` (waiting on schedule), `WMATL` (waiting on materials), `COMP` (work physically complete), `CLOSE` (financially closed), `CAN` (cancelled). Customers can rename via SYNONYMDOMAIN and add custom statuses.
> - **`SYNONYMDOMAIN`**: Maximo's status-renaming table. `STATUS` columns store the customer-renamable synonym (`VALUE`), not the internal `MAXVALUE` that Maximo logic uses.
> - **`HISTORYFLAG`**: when a record reaches a final status (often `CLOSE`/`CAN`), Maximo sets `HISTORYFLAG=1` and the row drops out of standard List views. Means closed work may not be in the dataset.

Ground in `work_order.status_values` + `proposed_open_statuses`.

### Q5: Open-status set & lifecycle walk-through
**Tier**: 1
**Trigger**: always
**Skip behavior** (Solo path): accept stock Maximo defaults (`WAPPR, APPR, INPRG, WSCH, WMATL`); defer custom statuses to `_unknown_` with `owner: Maintenance planner`
**Records to**: `open_statuses`

> *"Your data has these statuses: {list}. Walk me through the lifecycle — which count as 'open'/backlog? Which is 'work done but not financially closed' (`COMP` vs `CLOSE`)? What are the non-standard ones (anything outside the stock Maximo defaults) in your shop?"*

### Q6: Status synonym renamings
**Tier**: 1
**Trigger**: profiler `synonymdomain` dump shows `WOSTATUS` domain rows where `VALUE != MAXVALUE`
**Skip behavior**: record the renamings as they appear in `SYNONYMDOMAIN` (data-provable; no SME needed)
**Records to**: `synonymdomain_renamings` (status domain → `{MAXVALUE: VALUE}` map)

> *"Have you renamed any status values?"* Status columns store the customer-renamable synonym (`SYNONYMDOMAIN.VALUE`), not the internal `MAXVALUE` (see maximo-overview). If the profiler's `SYNONYMDOMAIN` dump shows renamings, record the actual stored `VALUE` strings so generated SQL matches the data.

### Q7: How status changes are made
**Tier**: 2
**Trigger**: always (SME-led path); skip in Solo
**Skip behavior**: defer to `_unknown_` with `owner: Maximo administrator`
**Records to**: `process_reality.status_change_mode`

> *"How are statuses changed — UI, MIF/integration, or a mobile/REST app?"* Integration-driven status changes can skip `WOSTATUS` history rows — flag if so, since it breaks time-in-status.

### Q8: Cancellation rate + parking statuses + HISTORYFLAG presence
**Tier**: 2
**Trigger**: profiler shows `>5% CAN` OR `historyflag_distribution` shows uneven HISTORYFLAG=1 presence
**Skip behavior**: defer to `_unknown_` with `owner: Maintenance planner`
**Records to**: `process_reality.cancellation_pattern`, `process_reality.history_flag_present`

> *"The profile shows {N%} `CAN` — what drives cancellations? Any 'parking' statuses that inflate backlog age?"* Also confirm closed/history records are present: at a final status a record gets `HISTORYFLAG=1` and drops out of standard List views — completion/trend metrics must include them.

---

## Batch 2 — Work types & the PM-vs-CM truth

> **Concepts in this batch** (shown for `Limited` / `None`)
> - **WORKTYPE**: the WO category. Maximo defaults: `PM` (preventive), `CM` (corrective), `EM` (emergency), `PROJ` (project), `CAP` (capital). Customers often add 10+ codes.
> - **PMNUM**: a foreign key from WORKORDER to the PM master, indicating "this WO was generated from a PM schedule." Some customers set WORKTYPE='PM' by hand instead of relying on PMNUM — distorts PM-vs-CM ratios.

Ground in `work_order.worktype_values`.

### Q9: Worktype categorization
**Tier**: 1
**Trigger**: always
**Skip behavior** (Solo path): accept stock Maximo defaults (PM=preventive, CM/BD=corrective, EM=emergency, CAP/PROJ=capital); defer custom worktypes to `_unknown_` with `owner: Maintenance planner`
**Records to**: `worktypes`

> *"Your `WORKTYPE` values are {list}. Which are corrective / preventive / emergency / project? Is capital or project work mixed into maintenance WOs?"* (it inflates maintenance cost)

### Q10: PM-flag derivation truth
**Tier**: 2
**Trigger**: profiler shows `>20%` of `WORKTYPE='PM'` rows with `PMNUM IS NULL`
**Skip behavior**: defer to `_unknown_` with `owner: Maintenance planner`
**Records to**: `process_reality.pm_derivation`

> *"Does `WORKTYPE='PM'` actually equal PM-generated (`PMNUM IS NOT NULL`), or do planners set it by hand?"* Affects `maximo-maintenance-cost` and `maximo-pm-planning`.

---

## Batch 3 — Sites, orgs & hierarchy

> **Concepts in this batch** (shown for `Limited` / `None`)
> - **SITEID**: Maximo's strongest scoping key. Most business keys (`WONUM`, `ASSETNUM`, `LOCATION`) are unique only within a SITEID — joins between Maximo tables must always include SITEID.
> - **ORG (`ORGID`)**: a level above SITE; usually corresponds to a business unit or country.
> - **LOCATIONS hierarchy vs ASSET parent-child**: two different ways to model "where the work is." Customers pick one as authoritative.

Ground in `work_order.siteid_values`.

### Q11: Sites & rollup to business regions
**Tier**: 1
**Trigger**: always
**Skip behavior** (Solo path): record the raw SITEID list; defer business-region rollup to `_unknown_` with `owner: Maintenance planner`
**Records to**: `sites`, `location_hierarchy`

> *"Your `SITEID`s are {list} across {N} orgs. How do these roll up to business regions? Any test or decommissioned sites to exclude? Do you compare across orgs (watch for different calendars/currencies)?"*

### Q12: LOCATIONS vs ASSET parent — which is authoritative?
**Tier**: 1
**Trigger**: always
**Skip behavior** (Solo path): default to LOCATIONS hierarchy (more common)
**Records to**: `location_hierarchy.authoritative_source`

> *"Is `LOCATIONS` hierarchy, `ASSET` parent-child, or both authoritative for 'where the work is'?"*

---

## Batch 4 — Asset classes & criticality

> **Concepts in this batch** (shown for `Limited` / `None`)
> - **CLASSSTRUCTUREID**: Maximo's asset classification key — references `CLASSSTRUCTURE` (the class tree). Asset classes group equipment by type ("centrifugal pump", "pressure vessel").
> - **ASSET.CRITICALITY**: a numeric field (usually 1-5 or 1-10) indicating how critical the asset is. Convention varies: some customers use 10=most critical, others use 1=most critical, others use a custom column entirely.

Ground in `asset.classstructureid_values`.

### Q13: Asset classes that matter
**Tier**: 2
**Trigger**: profiler detects more than the customer's reasonable class count, OR SME path
**Skip behavior**: defer to `_unknown_` with `owner: Reliability engineer`
**Records to**: `asset_classes`

> *"There are {N} `CLASSSTRUCTUREID`s. Which classes matter for reliability/integrity, and what do you call them ('centrifugal pump')? Is the taxonomy maintained, or is most equipment in a few generic classes?"*

### Q14: Criticality scheme — primary column + direction + buckets
**Tier**: 2
**Trigger**: profiler shows `ASSET.CRITICALITY` populated OR detects a custom criticality column (column name LIKE '%criticality%' that isn't `ASSET.CRITICALITY`)
**Skip behavior**: defer to `_unknown_` with `owner: Reliability engineer`
**Records to**: `criticality.primary_column`, `criticality.direction`, `criticality.buckets`

> *"How do you flag 'critical' assets — `ASSET.CRITICALITY`, a tag, or a custom criticality column? What's the range (1–5 vs 1–10), which end is most critical (10 vs 1), and where are the bucket boundaries (Critical / High / Medium / Low)?"*

---

## Batch 5 — Custom columns & tables

> **Concepts in this batch** (shown for `Limited` / `None`)
> - **Custom column / table**: Maximo lets customers add columns and tables to extend the standard model. They show up alongside MBO-standard columns and need glossary entries so Genie knows what they mean.

Ground in `custom_columns` (detected) + `stats.high_null_columns`.

### Q15: What each custom column drives
**Tier**: 2
**Trigger**: profiler detected ≥1 custom column
**Skip behavior**: defer to `_unknown_` with `owner: Maximo administrator`
**Records to**: `custom_columns`

> *"I detected these custom columns: {list}. What does each drive? Which are mandatory in your process? Do any *replace* a standard field (e.g. a custom priority instead of `WOPRIORITY`)?"*

### Q16: High-null columns — deprecated or partial?
**Tier**: 3
**Trigger**: profiler shows ≥1 column with >80% null
**Skip behavior**: defer to `_unknown_` with `owner: Maximo administrator`
**Records to**: `custom_columns.<name>.notes`

> *"Column {X} is {high_null}% null — deprecated, or only used for a subset of work?"*

### Q17: Custom tables that join to standard Maximo
**Tier**: 2
**Trigger**: profiler detected ≥1 non-Maximo table in the silver schema (e.g. integrity systems, GIS, custom corrosion-monitoring tables)
**Skip behavior**: defer to `_unknown_` with `owner: Data platform team`
**Records to**: `custom_tables`

> *"Any custom tables that join to standard Maximo (corrosion-monitoring, GIS, integrity records)? What's the join key + meaning?"*

---

## Batch 6 — Data integrity & process reality

> **Concepts in this batch** (shown for `Limited` / `None`)
> - **`FAILUREREPORT`**: where engineers code root-cause data on completed WOs. If sparsely populated, MTBF / failure-mode analysis isn't trustworthy.
> - **`LABTRANS`**: actual labor hours booked to a WO. Distinguish from `WPLABOR` (planned/estimated).
> - **Workflow engine** (`WFINSTANCE` / `WFASSIGNMENT` / `WFPROCESS`): Maximo's approval routing. Used for WO approval, PR/PO approval, MOC, incidents.
> - **App-server timezone**: Maximo stores datetimes in the application-server's local TZ (often UTC, but that's a deployment config choice — not guaranteed). Day/week/month bucketing is wrong if you assume UTC and the server is on a regional TZ.

These decide whether analytics are trustworthy at all. Ground in `stats` + null density + `workflow_engine_signals`.

### Q18: Failure-report population & reliability data quality
**Tier**: 2
**Trigger**: profiler shows `FAILUREREPORT` exists AND `failurereport_population_pct < 60%`
**Skip behavior**: defer to `_unknown_` with `owner: Reliability engineer`
**Records to**: `data_quality.failure_report_pct`, `process_reality.failure_coding_practice`

> *"`FAILUREREPORT` is {N%} populated — if low, MTBF/failure-mode analysis isn't reliable. Do engineers actually code failures?"*

### Q19: Failure-code scheme depth
**Tier**: 2
**Trigger**: profiler shows `FAILUREREPORT` populated AND `FAILURECODE` table has rows
**Skip behavior**: defer to `_unknown_` with `owner: Reliability engineer`
**Records to**: `failure_code_scheme`

> *"Which level of the failure-code tree do you actually use — `PROBLEM` only, `PROBLEM` + `CAUSE`, or the full `PROBLEM` → `CAUSE` → `REMEDY`? Is the taxonomy maintained or mostly generic?"* Determines what `maximo-reliability` can aggregate.

### Q20: Labor-booking mode
**Tier**: 2
**Trigger**: profiler shows `LABTRANS` populated
**Skip behavior**: defer to `_unknown_` with `owner: Maintenance superintendent`
**Records to**: `process_reality.labor_booking_mode`, `assignment_model`

> *"Are labor hours *booked* in `LABTRANS` or estimated? Mobile (real-time) vs back-office (next-day) entry? What's the assignment model — `LEAD` / `SUPERVISOR` / `CREWID` / `ASSIGNMENT` table?"*

### Q21: Workflow scope & approval depth
**Tier**: 2
**Trigger**: profiler shows `WFPROCESS` has ≥1 active row OR `WFINSTANCE` has recent rows
**Skip behavior**: defer to `_unknown_` with `owner: Maximo administrator`
**Records to**: `workflows`

> *"What business objects route through your Maximo workflow engine — WO approval, PR/PO approval, MoC, incidents? How many approval levels for each (1 vs 3 vs 5+)? Any conditional / role-based routing rules `maximo-workflow-and-approvals` needs to know about?"*

### Q22: Signature options / approval-role configuration
**Tier**: 3
**Trigger**: Q21 returned a non-empty workflows list
**Skip behavior**: defer to `_unknown_` with `owner: Maximo administrator`
**Records to**: `signature_options`

> *"Are there mandatory signature options / role gates beyond the default approver (e.g. safety reviewer, environmental, MOC committee)?"*

### Q23: Migration cutover date
**Tier**: 2
**Trigger**: profiler shows pre-2018 WOs with sparse `WOSTATUS` history, OR ratio of historical-to-active is anomalous
**Skip behavior**: defer to `_unknown_` with `owner: Maximo administrator`
**Records to**: `migration_cutover`

> *"Did you migrate from an older Maximo or another CMMS? Pre-cutover WOs often have null history / placeholder statuses — what's the cutover date?"*

### Q24: App-server timezone
**Tier**: 1
**Trigger**: always (not data-provable)
**Skip behavior** (Solo path): default to UTC; flag in `_unknown_` with `owner: Maximo administrator` if no MAXVARS or default-instructions reveal it
**Records to**: `app_server_timezone`

> *"What timezone is your Maximo app server configured to?"* Maximo stores datetimes in the app server's local TZ (often UTC, but a config choice — not a guarantee — see maximo-overview), converted to the user-profile TZ for display. NOT data-provable; capture it so day/week/month bucketing across sites is correct.

---

## Batch 7 — KPIs, multi-currency, & reconciliation

> **Concepts in this batch** (shown for `Limited` / `None`)
> - **PM compliance**: the % of due PMs completed within their tolerance. Three+ valid definitions vary by customer (within frequency × X%, within ±N days, by week vs month bucket).
> - **`CURRENCYCODE`** on cost-bearing tables: Maximo supports multi-currency; if more than one currency exists, every aggregate needs a conversion-to-base step.

### Q25: KPI definitions in customer's own words
**Tier**: 2
**Trigger**: SME-led path
**Skip behavior**: defer to `_unknown_` with `owner: Maintenance leadership`
**Records to**: `kpis`

> *"How do you define PM compliance (numerator/denominator + tolerance), schedule compliance window, and 'backlog' today?"* Record the stated definition; the certified formulas live with `maximo-reliability` / `maximo-maintenance-cost`.

### Q26: Multi-currency base + conversion
**Tier**: 1
**Trigger**: profiler `currency_distinct_count > 1` across `PO` / `INVOICE` / `COMPANIES` / `WOCURRENCY`
**Skip behavior**: defer to `_unknown_` with `owner: Finance controller`
**Records to**: `currency_handling`

> *"Distinct currencies detected: {list}. What's your reporting base currency, and what's the conversion source (Maximo `MAXVARS`, an external rate table, manual)? Are historical WO/PO amounts at the rate of the event date or current rate?"* Decides every cost rollup in `maximo-maintenance-cost`.

### Q27: Existing dashboards to reconcile against
**Tier**: 2
**Trigger**: SME-led path OR customer mentions an existing report
**Skip behavior**: defer to `_unknown_` with `owner: Analytics team`
**Records to**: `existing_dashboards`

> *"What existing dashboards / reports do you trust today (Power BI, Cognos, AI/BI, Maximo's KPI portlets)? Which is the single 'one number we trust' we should reconcile our queries against — the fastest way to earn trust."*

---

## Batch 8 — Regulatory & HSE (only if PLUSG present / O&G / utilities / mining)

> **Concepts in this batch** (shown for `Limited` / `None`)
> - **PLUSG**: the Oil & Gas industry solution add-on. Adds `plusgpermitwork`, `plusgincperson`, `plusgshiftlog`, etc.
> - **API 510 / 570 / B31.4 / CSA Z662 / DOT 49 CFR**: publicly-published regulatory standards governing pressure-vessel / piping / pipeline integrity. Each has different inspection-interval ceilings.
> - **TRIR**: Total Recordable Incident Rate — the standard safety KPI. The "hours worked" denominator usually comes from corporate HR, not Maximo.

### Q28: Regulatory codes driving inspection PMs
**Tier**: 3
**Trigger**: PLUSG present OR customer mentions regulatory inspection
**Skip behavior**: defer to `_unknown_` with `owner: Integrity / compliance team`
**Records to**: `regulatory_codes`

> *"Which regulatory codes drive inspection PMs (API 510/570, B31.4, CSA Z662, DOT 49 CFR Part 192/195)? How is inspection work isolated — `WORKTYPE`, a custom flag column, or a `JPNUM` set?"*

### Q29: Permit-to-Work source & TRIR hours-worked source
**Tier**: 3
**Trigger**: PLUSG present
**Skip behavior**: defer to `_unknown_` with `owner: HSE manager`
**Records to**: `hse_sources.ptw`, `hse_sources.trir_hours_worked`

> *"Is Permit-to-Work in `plusgpermitwork`, or a custom/other system? What's your TRIR hours-worked source (usually a corporate HR system, not Maximo)?"*

---

## Closing — tribal knowledge

### Q30: Anything that's burned you
**Tier**: 2
**Trigger**: SME-led path
**Skip behavior**: skip silently
**Records to**: `tribal_knowledge`

> *"Any business term or quirk that's caused confusion in past data work? Anything that's burned you?"*

---

## How to record answers

The profiler seeds most of this; you confirm. Save as `answers.json` (consumed by
`generate_glossary.py`). The shape includes the `industry_usage` block plus the v0.3.0
keys (`customer.maximo_familiarity`, `workflows`, `signature_options`,
`failure_code_scheme`, `criticality.{direction,buckets}`, `assignment_model`,
`currency_handling`, `existing_dashboards`, `mas_version`).

Example for a fictional `Northstar Energy` deployment (shape only — substitute the customer's actual values):

```json
{
  "customer": "northstar",
  "customer_meta": { "maximo_familiarity": "Familiar" },
  "mas_version": "MAS 8.11.3 / Manage 8.7.2",
  "industry_usage": {
    "industry": "Midstream oil & gas (liquids + gas transmission)",
    "industry_solutions": ["Oil & Gas (PLUSG)"],
    "modules_in_use": ["work_management", "preventive_maintenance", "asset_integrity", "hse"],
    "modules_elsewhere": {"inventory": "SAP", "procurement": "SAP"},
    "maintenance_maturity": "time-based PM moving to condition-based on rotating equipment",
    "kpis": ["PM compliance (completed within 10% of frequency)", "schedule compliance (weekly)"],
    "app_server_timezone": "UTC",
    "migration_cutover": "2021-04-01 (pre-cutover WOs have null WOSTATUS history)",
    "notes": ["Capital work is WORKTYPE=CAP — exclude from maintenance cost"]
  },
  "sites": { "Region North": ["ZONE-N1", "ZONE-N2", "ZONE-N3"], "Region South": ["ZONE-S1", "ZONE-S2"] },
  "location_hierarchy": { "Region": "LOCHIERARCHY level 1", "Station": "LOCHIERARCHY level 2", "authoritative_source": "LOCATIONS" },
  "asset_classes": { "centrifugal pump": [4521, 4522], "pressure vessel": [7100, 7101] },
  "criticality": {
    "primary_column": "ASSET.CRITICALITY",
    "direction": "10 = most critical",
    "buckets": { "critical": "= 10", "high": "7–9", "medium": "4–6", "low": "≤ 3" }
  },
  "open_statuses": ["WAPPR", "APPR", "INPRG", "WSCH", "WMATL", "<CUSTOM_OPEN_STATUS>"],
  "synonymdomain_renamings": { "WOSTATUS": { } },
  "worktypes": { "corrective": ["CM", "EM"], "preventive": ["PM"], "capital": ["CAP"] },
  "workflows": {
    "wo_approval": { "active": true, "levels": 2 },
    "pr_po_approval": { "active": true, "levels": 3 },
    "moc": { "active": false }
  },
  "signature_options": ["SAFETY_REVIEW (mandatory for WORKTYPE='EM')"],
  "failure_code_scheme": "PROBLEM + CAUSE (REMEDY rarely populated)",
  "assignment_model": "ASSIGNMENT table; LEAD column rarely used",
  "currency_handling": {
    "base": "USD",
    "source": "MAXVARS exchange rates",
    "historical_basis": "event-date rate"
  },
  "existing_dashboards": ["Power BI: 'Maintenance Backlog Weekly'", "Cognos: 'PM Compliance by Site'"],
  "custom_columns": {
    "WORKORDER.WO_ROUTE_KM": "Route kilometer of the work site (example custom column)",
    "WORKORDER.WO_REGULATORY_FLAG": "Y/N — does this WO satisfy a regulatory requirement (example)"
  },
  "custom_tables": { "eam.maximo_silver.inspection_readings_custom": "Joined to ASSET on assetnum; UT thickness gauging (example custom table)" },
  "regulatory_codes": ["API 510", "API 570", "CSA Z662"],
  "hse_sources": { "ptw": "plusgpermitwork", "trir_hours_worked": "Workday HR (external)" },
  "process_reality": {
    "status_change_mode": "UI + mobile (no MIF integration)",
    "cancellation_pattern": "<5% — driven by scheduling errors",
    "history_flag_present": true,
    "pm_derivation": "PMNUM-driven (>95% of WORKTYPE='PM' have PMNUM)",
    "labor_booking_mode": "Mobile, real-time"
  },
  "data_quality": { "failure_report_pct": 42 },
  "tribal_knowledge": ["'In service' colloquially means STATUS='INPRG', not the asset status"],
  "followups": [
    {"question": "Meaning of the custom open-status / is it 'open'?", "owner": "Maintenance planners"},
    {"question": "Official CLASSSTRUCTUREID → asset-class names", "owner": "Reliability"}
  ]
}
```

> Build `followups` from every item flagged `_unknown_ — confirm with <role>`: each becomes a
> `{question, owner}` row. It renders as the glossary's follow-up-contacts table and is the
> worklist a **re-run** walks through. Use the **physical column casing** from the data in all
> mappings so generated SQL matches.

### `draft_profile.json` → `answers.json` mapping (what the profiler pre-fills)

| Profiler field | Interview confirms → answers.json key |
|---|---|
| `usage_profile` (plusg_present, modules_in_use, heatmap) | Batch 0 → `industry_usage` |
| `synonymdomain` dump (status renamings) | Batch 1 → `open_statuses` + `synonymdomain_renamings` |
| `historyflag_distribution` | Batch 1 → `process_reality.history_flag_present` |
| (not data-provable — MAS version) | Batch 0 → `mas_version` |
| (not data-provable — app server config) | Batch 6 → `app_server_timezone` |
| (not data-provable — migration history) | Batch 6 → `migration_cutover` |
| `work_order.proposed_open_statuses` | Batch 1 → `open_statuses` |
| `work_order.worktype_values` | Batch 2 → `worktypes` |
| `work_order.siteid_values` | Batch 3 → `sites` / `location_hierarchy` |
| `asset.classstructureid_values` + `criticality_distribution` | Batch 4 → `asset_classes` / `criticality` |
| `custom_columns` (detected) | Batch 5 → `custom_columns` |
| `failurereport_population_pct`, `failurecode_depth` | Batch 6 → `data_quality.failure_report_pct`, `failure_code_scheme` |
| `workflow_engine_signals` (WFPROCESS/WFINSTANCE active) | Batch 6 → `workflows` |
| `assignment_population_pct` | Batch 6 → `assignment_model` |
| `currency_distinct_count` across PO/INVOICE/COMPANIES | Batch 7 → `currency_handling` (trigger Q26 if > 1) |
