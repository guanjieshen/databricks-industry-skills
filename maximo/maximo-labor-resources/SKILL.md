---
name: maximo-labor-resources
description: |
  Use for IBM Maximo / Maximo / EAM / CMMS labor-resource analytics — the labor
  master and capacity layer. Covers labor masters (LABOR), persons (PERSON),
  crafts (CRAFT, LABORCRAFTRATE), qualifications (QUALIFICATION, QUALPERSON),
  crews (AMCREW, AMCREWLABOR), person groups (PERSONGROUP), shift calendars
  (CALENDAR, WORKPERIOD), availability incl. planned absences (MODAVAIL), and
  WO assignments (ASSIGNMENT). Answers
  "who can do this work", "crew utilization", "expiring certifications",
  "available craft-hours next week", "contractor vs employee mix",
  "qualifications for asset class X", "assignment backlog". Triggers on:
  "labor", "crew", "craft", "qualifications", "certifications", "shift
  schedule", "assignment", "capacity", "utilization", "contractor mix",
  "workforce". Compose with maximo-pm-planning for
  workload-vs-capacity gaps. For actual labor cost/hours on completed WOs
  (LABTRANS), use maximo-work-orders or maximo-maintenance-cost.
metadata:
  version: "0.2.0"
parent: maximo-overview
---

# Maximo Labor & Resources

The **who** layer underneath every Maximo "can we do this work" question. Covers labor masters, qualifications, crews, calendars, and assignments — the resource-availability data that pm-planning's forecast workload needs to balance against.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, module map, and the universal gotchas this skill builds on: `SITEID` composite keys (gotcha 4), status-is-a-synonym-domain / `SYNONYMDOMAIN` resolution (gotcha 5), `HISTORYFLAG` closed-record filtering (gotcha 6), and app-server-timezone datetimes (gotcha 7). This skill APPLIES those patterns in its own SQL and adds only the labor-domain depth.

## When to use

- "Who's qualified to work on centrifugal pumps?"
- "Crew utilization this week / month"
- "Available craft-hours by week (capacity)"
- "Workload vs capacity gap" (composes with `maximo-pm-planning`)
- "Certifications expiring in the next 90 days"
- "Vacation impact on next quarter's PM compliance"
- "Contractor vs employee labor mix"
- "Top crafts by total hours booked"
- "Assignment backlog — labor with open assigned WOs"

This skill owns the **labor master** + **capacity** layer. For *actual* labor cost/hours on completed WOs (`LABTRANS` aggregation), use `maximo-work-orders` or `maximo-maintenance-cost` — cost is the consumption side.

## Top gotchas (inline — Genie may not load `gotchas.md` at decision time)

1. **`LABOR` ≠ `PERSON`** — `LABOR` is the maintainable resource record (craft + rate + status); `PERSON` is the human. Not every person is labor (admin staff aren't); some labor records are contractor resources with `PERSONID = NULL` and no `PERSON` link. An `INNER JOIN` silently drops contractor labor — use `LEFT JOIN labor → person`.

2. **Contractor identification varies by customer** — most common is `LABOR.VENDOR IS NOT NULL` (links to `COMPANIES`); others key off whether the labor's `CRAFT` (via `LABORCRAFTRATE`) carries a `VENDOR`, or a custom `LABOR.LABORTYPE` value. There is **no** `LABOR.OUTSIDELABOR` column — don't use it. Always check the workspace glossary before classifying labor as contractor vs employee. The `contractor_spend` UDF in `maximo-maintenance-cost` uses the vendor-link pattern by default.

3. **`CALENDAR` / `WORKPERIOD` are often sparsely populated** — about half of customers don't maintain forward-year `WORKPERIOD` rows. A query that claims "we have X hours of capacity next month" silently returns zero if `WORKPERIOD` doesn't cover that window. Probe coverage first (see `gotchas.md` §3). Note: scheduled hours are DERIVED from `WORKPERIOD.SHIFTSTART/SHIFTEND` (there is no `WORKPERIOD.HOURS` or `PERIODTYPE` column), and `WORKPERIOD.WORKDATE` / `SHIFTSTART` / `SHIFTEND` are app-server-TZ — see overview gotcha 7 before bucketing capacity by week across sites.

4. **`QUALPERSON.EXPIRYDATE`** — expired certifications mean the person can no longer be assigned to qualified work. Filter `(EXPIRYDATE IS NULL OR EXPIRYDATE > current_date()) AND STATUS = 'ACTIVE'` when checking "who's qualified." Filtering only on `QUALPERSON` existence inflates the qualified pool.

5. **Labor reporting / actuals = `LABTRANS` — there is no Maximo labor-reporting-history table.** The Labor Reporting application writes to `LABTRANS` (the cost-bearing per-WO transaction, owned by `maximo-work-orders`, consumed by `maximo-maintenance-cost`). Payroll/timekeeping reconciliation typically happens in an **external timekeeping system**, not a Maximo table — don't expect a `LABREPHIST`-style object.

6. **`MODAVAIL` holds availability modifications (incl. planned absences) — it is NOT an absence-only table.** Person/labor (and crew) availability is defined per resource via the "Modify Availability" object `MODAVAIL`, separate from the shared `CALENDAR`/`SHIFT`/`WORKPERIOD`. `MODAVAIL` carries BOTH working-time and non-working-time rows; **planned absences (vacation/sick/personal) are the NON-WORK rows**, identified by a reason code (`RSNCODE` synonym domain, e.g. `VAC`/`SICK`/`PERSONAL`). Filter to the non-work reason codes to get absences — don't treat every `MODAVAIL` row as an absence. **MODAVAIL's exact column names are not publicly documented; confirm columns against `MAXATTRIBUTE` in this deployment** before relying on the absence-aware UDFs/views (they are templates).

7. **Status columns are synonym domains — don't hard-code literals.** `LABOR.STATUS`, `ASSIGNMENT.STATUS`, `QUALPERSON.STATUS`, and the `WORKORDER.STATUS` you join to all store the customer-renamable synonym, not the internal value. Resolve sets via `SYNONYMDOMAIN` (domains here include `LABORSTATUS`, `ASSIGNSTATUS`/`AMCREWSTATUS` per deployment) exactly as overview gotcha 5 prescribes — the examples in this skill use literals only because stock Maximo has internal==external; switch to `SYNONYMDOMAIN` resolution if the deployment added synonyms.

## Questions to surface first

Ask these before answering — each has multiple defensible interpretations and no safe default:

1. **"How do you identify contractor vs employee labor?"** — `LABOR.VENDOR IS NOT NULL`, a craft-rate `VENDOR` (via `LABORCRAFTRATE`), and custom `LABORTYPE` values are all in use across deployments and give different counts (there is no `LABOR.OUTSIDELABOR` column). Confirm the convention (workspace glossary) before any contractor-mix or outside-labor metric.
2. **"What does 'available capacity' mean here — scheduled hours, or scheduled net of planned absences?"** — `WORKPERIOD` alone gives gross scheduled hours; subtracting overlapping `MODAVAIL` non-work (absence) rows gives net-of-vacation. And `WORKPERIOD` may not cover the forecast window at all (gotcha 3). Confirm the definition and the coverage before quoting a capacity number.
3. **"What counts as 'qualified' — any holding, or a current non-expired ACTIVE certification?"** — including lapsed certs inflates the pool; some customers also require `QUALIFICATION.REQUIREDFORWORK = 1` matching. Confirm which.
4. **"Utilization against what denominator?"** — booked `LABTRANS` hours over scheduled `WORKPERIOD` hours, over calendar hours, or over net-of-absence hours all yield different percentages. Confirm the denominator (and whether overtime/premium hours count) before reporting utilization.

## Pre-flight (per session)

Cache these once; don't re-ask each turn:

1. **Silver catalog/schema** — confirm via workspace glossary.
2. **Calendar coverage** — `CALENDAR` / `WORKPERIOD` are often half-populated. Verify rows exist for the forecast window (gotchas.md §3 probe) before claiming "we have capacity for X."
3. **Contractor convention** — whether contractors are `LABOR.VENDOR IS NOT NULL`, identified via a craft-rate `VENDOR` (`LABORCRAFTRATE`), or a custom `LABORTYPE` (per the workspace glossary).
4. **App-server timezone** — a `maximo-setup` deployment fact; needed before bucketing `WORKPERIOD` / `MODAVAIL` datetimes by week across sites (overview gotcha 7).

## Workflow

Resolution priority — prefer the highest available rung:

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `crew_capacity_hours`, `qualified_labor_count`, `labor_utilization_pct`, `expired_qualifications_count`, `vacation_impact_hours`
2. **Pre-joined views** in [views.sql](views.sql) — `v_labor_position`, `v_crew_capacity`, `v_qualification_expiry`
3. **Parameterized examples** in [examples.sql](examples.sql)
4. **Raw tables** — last resort; apply overview gotchas 4–7 (SITEID joins, SYNONYMDOMAIN status, HISTORYFLAG, app-server TZ) yourself

## What's in this skill (load when…)

- [schema.md](schema.md) — full table reference (LABOR, PERSON, CRAFT, LABORCRAFTRATE, QUALIFICATION + CERTIFICATION + QUALPERSON, AMCREW family, CALENDAR / WORKPERIOD / MODAVAIL, ASSIGNMENT). **Load when** writing non-trivial joins or when you need column-level detail.
- [gotchas.md](gotchas.md) — extended versions of the inline gotchas plus more (currency on rates, crew rollup, qualification hierarchy, person-group nesting, employee-vs-contractor blends, MODAVAIL/WORKPERIOD sync). **Load when** the query touches a table the inline gotchas don't cover.
- [examples.sql](examples.sql) — 10 parameterized gold-standard queries. **Load when** the user's question maps to a common pattern (crew utilization, expiring certs, etc.).
- [views.sql](views.sql) — DDL for the gold views. **Load when** registering the views in a new customer environment.
- [metric_udfs.sql](metric_udfs.sql) — UC SQL function DDL for Trusted UDFs. **Load when** registering metrics in UC.

## What NOT to do

- Don't `INNER JOIN` `LABOR` to `PERSON` unless you specifically need only labor-with-person — you'll miss contractor labor records (`PERSONID IS NULL`).
- Don't compute "available capacity" without first probing `WORKPERIOD` coverage — the answer may be silently zero.
- Don't count expired or inactive certifications as qualified. Filter `EXPIRYDATE` and `STATUS`.
- Don't invent a `LABREPHIST`-style labor-reporting-history table — labor actuals are `LABTRANS` (owned by `maximo-work-orders`); payroll/timekeeping reconciliation lives in an external timekeeping system, not Maximo.
- Don't treat every `MODAVAIL` row as an absence — it holds both work and non-work rows; absences are the non-work `RSNCODE` rows. And don't assert specific `MODAVAIL` columns as canonical (they're undocumented — confirm against `MAXATTRIBUTE`).
- Don't aggregate rates across currencies (`LABORCRAFTRATE.CURRENCYCODE` may vary). For total labor cost / multi-currency normalization, DEFER to `maximo-maintenance-cost` — don't re-derive cost rollups here.
- Don't hard-code status literals when the deployment has custom synonyms — resolve via `SYNONYMDOMAIN` (overview gotcha 5).
- Don't assume closed WOs are present when joining `ASSIGNMENT` → `WORKORDER` — IBM-shipped views filter `HISTORYFLAG = 0` (overview gotcha 6).
- Don't compute reactive-vs-proactive or schedule-compliance ratios from labor hours here — those SMRP semantics are owned by `maximo-reliability`.
- Don't propose creating new labor records — that's transactional, not analytical.

## Composes with

- **`maximo-pm-planning`** — provides forecast workload via `v_pm_workload_by_craft`. This skill provides matching capacity (`v_crew_capacity`, `crew_capacity_hours` UDF). The joined query — workload vs capacity gap by craft × week — is the single highest-value cross-skill query in the family.
- **`maximo-work-orders`** — owns `LABTRANS` aggregation and `ASSIGNMENT`→`WORKORDER` work-management semantics; this skill provides the LABOR master those reference.
- **`maximo-maintenance-cost`** — owns cost rollup, contractor spend, and multi-currency normalization (`contractor_spend` UDF relies on `LABOR.VENDOR`). This skill is the authoritative source for LABOR column semantics; DEFER cost math to it.
- **`maximo-reliability`** — owns reactive/proactive, PM-compliance, and schedule-compliance metrics on labor hours. Provide the labor master; DEFER the SMRP ratios.
- **`maximo-asset-hierarchy`** — for "qualified labor by region" rollups via the location/asset closure tables.

## References

- IBM Maximo Manage — Resources module: https://www.ibm.com/docs/en/masv-and-l/maximo-manage/cd
- Authoring standard: see `_authoring/authoring-industry-skills/SKILL.md`
