---
name: maximo-hse
description: |
  Use for IBM Maximo (Maximo, EAM, CMMS) Health, Safety & Environment workflows —
  Permit to Work (plusgpermitwork, PERMITWORKNUM), permit/certificate types
  (plusgpertype), incidents (TICKET with CLASS='INCIDENT', plusgincperson),
  investigations, Management of Change (MOC), safety observations, Lock Out Tag
  Out (LOTO) plans, and regulatory HSE reporting (TRIR / LTIR / near-miss). Most
  HSE tables come from the PLUSG Oil & Gas industry solution. Triggers on: "HSE",
  "permit to work", "PTW", "incident", "near miss", "investigation", "TRIR",
  "LTIR", "MoC", "Management of Change", "safety observation", "LOTO", "lock out
  tag out", "OSHA recordable", "API RP 754", "PSM", "process safety", "permits
  expiring", "incidents by site".
metadata:
  version: "0.2.0"
parent: maximo-overview
---

# Maximo HSE

Help HSE managers, safety officers, and regulatory reporting teams query, analyze, or build pipelines on Maximo's HSE-related data. Most HSE objects live in the **PLUSG industry-solution extension (Oil & Gas)**; incidents themselves are core Maximo TICKET records.

This skill is **O&G-heavy**. If the customer is not on the Maximo Oil & Gas industry solution, the `plusg*` tables won't exist and most of this skill won't apply.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas (SITEID composite keys, status-is-a-synonym-domain / `SYNONYMDOMAIN` resolution, `HISTORYFLAG` hiding closed records, app-server-timezone datetimes, current-`STATUS`-vs-status-history). This skill applies those and adds HSE-specific depth.

> **PHYSICAL COLUMN NAMES:** IBM does not publish a per-column data dictionary for `PLUSG*` tables; the names below come from the MAS Performance Wiki's recommended-index DDL. Confirm every `PLUSG*` column against `MAXATTRIBUTE` (`WHERE objectname LIKE 'PLUSG%'`) in THIS deployment before shipping.

## When to use

- "How many permits to work are open right now?"
- "TRIR / LTIR for last quarter"
- "Open corrective actions from incidents older than 30 days"
- "Near-miss trend last year"
- "Permits expiring in the next 7 days"
- "Incidents by category by site"
- "OSHA recordable incidents this year"
- "Outstanding MoC actions"
- "Incidents tied to a specific asset / location"

For integrity-specific incident analysis (did a missed inspection cause this incident?), defer to `maximo-integrity` — it owns the inspection→incident join via `plusgrelatedrec`.

## Top gotchas

These silently produce wrong results. Read before any non-trivial query (full set in [gotchas.md](gotchas.md); `maximo-overview` carries the universal ones).

1. **Incidents are TICKET records, not their own table.** SR, INCIDENT, and PROBLEM all share the core `TICKET` table, distinguished by `TICKET.CLASS` (`SR` / `INCIDENT` / `PROBLEM`). The surrogate key is `TICKETID` (this is why `plusgincperson` keys on `TICKETID`). Filter `CLASS='INCIDENT'`. Incident status resolves via `SYNONYMDOMAIN WHERE domainid='INCIDENTSTATUS'` — the stock value set is `NEW/QUEUED/PENDING/INPROG/RESOLVED/CLOSED`. Tickets get `HISTORYFLAG=1` at CLOSED/CANCELLED/REJECTED and drop off the List tab (apply overview gotchas F2/F3).
2. **Permit physical names: `PERMITWORKNUM` + `PLUSGPERTYPEID`, not `permitnum` / `permittype`.** `plusgpermitwork`'s identifier is `PERMITWORKNUM`; its FK to the type catalog is `PLUSGPERTYPEID` (the `plusgpertype` surrogate PK), NOT a column named `PERMITTYPE`. Join `plusgpertype.plusgpertypeid = plusgpermitwork.plusgpertypeid`.
3. **Permit-to-Work is NOT a work order — it has its own STATUS + HISTORYFLAG.** PTW status comes from a PTW-specific value list (NOT `WOSTATUS`), and its status HISTORY lives in the PTW object's own status-history mechanism (analogous to TKSTATUS for tickets / WOSTATUS for work orders), NOT in `WOSTATUS`. Never join permits to `WOSTATUS ON wonum = permitworknum` — permits are not work orders, so they have no `WOSTATUS` rows.
4. **LOTO plans have NO STATUS field — use the `ACTIVE` flag.** Lock Out Tag Out Plan records use an `ACTIVE` field, not a status domain (per IBM docs). There is no LOTO status-history table; fall back to the audit log if you need activation history.
5. **No stock OSHA-recordable / API RP 754 Tier column exists.** IBM ships no fixed column or domain mapping for OSHA-recordable or API RP 754 Tier 1-4 classification. These are implemented per-deployment via incident `CLASSIFICATION` (`CLASSSTRUCTUREID`), a severity/category value list, or customer attributes. Do NOT hardcode a recordable/Tier column — parameterize recordable categories and confirm the mapping in the workspace glossary.

## Questions to surface first

Ask these before computing — each has no defensible default:

1. **Is the O&G (PLUSG) industry solution installed?** If `plusg*` tables aren't populated in Silver, Permit-to-Work / Operator-Log / incident-person analytics won't work — flag it rather than returning empty results.
2. **Which incident classification = "recordable"?** OSHA-recordable / lost-time / near-miss / first-aid are deployment-configured (via `CLASSSTRUCTUREID` or a category value list), not a stock column. Confirm the codes before TRIR/LTIR.
3. **What is the hours-worked source for TRIR/LTIR?** The denominator (`(recordables × 200,000) / hours-worked`) almost always comes from HR / payroll, not Maximo. Do NOT derive it from `LABTRANS` (that's only labor booked to WOs).
4. **What does "MoC compliance %" mean here?** % at-stage-by-stage-deadline vs % fully-closed-by-close-deadline vs % with completed actions — three valid framings.
5. **How are corrective actions tracked?** Dedicated ACTION module vs `WOCLASS='ACTION'` WOs vs incident sub-tasks vs a custom table — varies by customer.

## Pre-flight (per session)

1. **Confirm catalog / schema** and bind `:catalog`, `:silver_schema`, `:gold_schema`, `:metrics_schema`.
2. **Confirm O&G industry solution** (`plusg*` populated). Cache the answer.
3. **Resolve the workspace glossary** for incident classification codes (recordable / near-miss / Tier mapping) and PTW status set — these are deployment-specific.

## Workflow priority

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `trir`, `ltir`, `open_permit_count`, `permit_compliance`, `incident_count_by_class`
2. **Pre-joined views** in [views.sql](views.sql) — `v_open_permits`, `v_incidents_enriched`, `v_moc_actions`
3. **Parameterized examples** in [examples.sql](examples.sql)
4. **Raw tables** — last resort

## What's in this skill

- [schema.md](schema.md) — load when you need physical columns: plusgpermitwork, plusgpertype, TICKET/INCIDENT, plusgincperson, plusgrelatedrec, LOTO, MOC.
- [gotchas.md](gotchas.md) — load before any non-trivial query: PTW-status-history, LOTO ACTIVE flag, recordable-classification, near-miss lag, PII handling.
- [examples.sql](examples.sql) — load for parameterized HSE queries.
- [views.sql](views.sql) — load to build gold views `v_open_permits`, `v_incidents_enriched`, `v_moc_actions`.
- [metric_udfs.sql](metric_udfs.sql) — **Trusted Asset functions**: UC SQL functions registered once so Genie calls them as certified, governed metrics. Register via `maximo-setup` or by running the file.

## What NOT to do

- **Don't join permits to `WOSTATUS`** — PTW is not a work order. Use the PTW object's own status-history (confirm the object name in this deployment).
- **Don't use `permitnum` / `permittype` / `incidentid` as column names** — the verified physical names are `PERMITWORKNUM`, `PLUSGPERTYPEID`, and `TICKETID`. Confirm against `MAXATTRIBUTE`.
- **Don't hardcode OSHA-recordable or API RP 754 Tier columns** — they don't exist in stock Maximo; drive them from the deployment's classification/domain.
- **Don't compute TRIR without confirming the hours-worked source** (HR/payroll, not Maximo).
- **Don't expose PII** (incident person names, medical details) — `plusgincperson` is PII-sensitive; aggregate or de-identify in every artifact.
- **Don't assume `plusg*` tables exist** without checking — many deployments are classic Maximo without the O&G solution.
- **Don't re-teach universal mechanics** (SITEID joins, SYNONYMDOMAIN, HISTORYFLAG, timezones) — apply them and defer to `maximo-overview`.

## Composes with

- **`maximo-overview`** — universal gotchas (SITEID, SYNONYMDOMAIN status resolution, HISTORYFLAG, datetimes, current-status-vs-history). Apply, don't duplicate.
- **`maximo-integrity`** — owns the inspection→incident causal join via `plusgrelatedrec`. Defer integrity-driven incident root-cause to it.
- **`maximo-asset-hierarchy`** — incident/permit rollups by location/asset parent ("incidents at station 4", "open permits under region X") via `v_location_rollup_keys`.
- **`maximo-labor-resources`** — PTW competency checks ("who's qualified for hot work") via `QUALPERSON` + `QUALIFICATION`. Owns labor master; defer qualification logic to it.
- **`maximo-workflow-and-approvals`** — owns approval routing / time-in-approval (`WFINSTANCE`/`WFASSIGNMENT`); defer permit/MoC approval-cycle metrics to it.

## References

- IBM Maximo for Oil & Gas docs (HSE): https://www.ibm.com/docs/en/mfo-and-g/
- IBM MAS Performance Wiki (PLUSG recommended indexes — source for physical column names): https://ibm-mas.github.io/mas-performance/mas/manage-industry-solutions/ong-hse/bestpractice/
- OSHA Recordkeeping (TRIR): https://www.osha.gov/recordkeeping
- API RP 754 (Process Safety Performance Indicators, Tier 1-4)
