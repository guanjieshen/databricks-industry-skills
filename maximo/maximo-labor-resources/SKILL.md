---
name: maximo-labor-resources
description: |
  Use for IBM Maximo / EAM / CMMS labor-resource analytics — labor masters
  (LABOR), persons (PERSON), crafts (CRAFT, LABORCRAFTRATE), qualifications and
  certifications (QUALIFICATION, CERTIFICATION, QUALPERSON), crews (CREW,
  CREWLABOR, CREWWORKGROUP), person groups (PERSONGROUP), shift calendars
  (CALENDAR, WORKPERIOD), planned absences (AVAILREFLY), and WO assignments
  (ASSIGNMENT, LABREPHIST). Answers "who can do this work", "crew utilization",
  "expiring certifications", "available craft-hours next week", "vacation
  impact", "contractor vs employee mix", "qualifications for asset class X".
  Triggers on: "labor", "crew", "craft", "labor availability", "qualifications",
  "certifications", "shift schedule", "assignment", "capacity", "utilization",
  "vacation", "contractor mix", "craft mix", "workforce". Compose with
  maximo-pm-planning for workload-vs-capacity gap analytics.
metadata:
  version: "0.1.0"
parent: maximo-overview
---

# Maximo Labor & Resources

The **who** layer underneath every Maximo "can we do this work" question. Covers labor masters, qualifications, crews, calendars, and assignments — the resource-availability data that pm-planning's forecast workload needs to balance against.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, module map, and universal gotchas (SITEID composite keys, `WOCLASS` filtering, status semantics). This skill builds on that foundation.

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

For *actual* labor cost on completed WOs (`LABTRANS` aggregation), use `maximo-maintenance-cost` or `maximo-work-orders`. This skill owns the **labor master** + **capacity** layer; cost is the consumption side.

## Pre-flight (cache for the session)

1. **Silver catalog/schema** — confirm via workspace glossary.
2. **Calendar coverage** — `CALENDAR` / `WORKPERIOD` are often half-populated. Verify rows exist for the forecast window before claiming "we have capacity for X."
3. **Contractor convention** — workspace glossary should specify whether contractors are identified by `LABOR.VENDOR IS NOT NULL`, a custom `LABORTYPE`, or another flag.

## Top gotchas (inline — Genie may not load `gotchas.md` at decision time)

1. **`LABOR` ≠ `PERSON`** — `LABOR` is the maintainable resource record (with craft + rate); `PERSON` is the human. Not every person is labor (admin staff aren't); some labor records are contractor resources with no `PERSON` link. Joining naïvely produces wrong counts. Use `LEFT JOIN` if you need person details for labor records that have them.

2. **Contractor identification varies by customer** — the most common pattern is `LABOR.VENDOR IS NOT NULL` (links to `COMPANIES`). Other customers use a custom `LABOR.LABORTYPE` value or a flag column. Always check the workspace glossary before classifying labor as contractor vs employee.

3. **`CALENDAR` / `WORKPERIOD` are often sparsely populated** — about half of customers don't maintain forward-year `WORKPERIOD` rows. A query that claims "we have X hours of capacity next month" will silently return zero if `WORKPERIOD` doesn't cover that month. Always check coverage first. See `gotchas.md` for the coverage-probe pattern.

4. **`QUALPERSON.EXPIRYDATE`** — expired certifications mean the person can no longer be assigned to qualified work. Filter to `EXPIRYDATE IS NULL OR EXPIRYDATE > current_date()` when checking "who's qualified." Naively filtering only on `QUALPERSON` existence inflates the qualified pool.

5. **`LABREPHIST` ≠ `LABTRANS`** — `LABREPHIST` is the labor-reporting audit log (who reported what hours per pay period — used by payroll). `LABTRANS` is the cost-bearing transaction (what was booked to which WO). For analytics, **prefer `LABTRANS`** — already documented in `maximo-work-orders` and used by `maximo-maintenance-cost`. Use `LABREPHIST` only when reconciling against payroll.

## Workflow priority

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `crew_capacity_hours`, `qualified_labor_count`, `labor_utilization_pct`, `expired_qualifications_count`, `vacation_impact_hours`
2. **Pre-joined views** in [views.sql](views.sql) — `v_labor_position`, `v_crew_capacity`, `v_qualification_expiry`
3. **Parameterized examples** in [examples.sql](examples.sql)
4. **Raw tables** — last resort

## What's in this skill (load when…)

- [schema.md](schema.md) — full table reference (LABOR, PERSON, CRAFT, LABORCRAFTRATE, QUALIFICATION + CERTIFICATION + QUALPERSON, CREW family, CALENDAR / WORKPERIOD / AVAILREFLY, ASSIGNMENT, LABREPHIST). **Load when** writing non-trivial joins or when you need column-level detail.
- [gotchas.md](gotchas.md) — extended versions of the 5 inline gotchas plus 5 more (currency on rates, crew rollup, qualification hierarchy, person-group nesting, employee-vs-contractor blends). **Load when** the query touches a table the inline gotchas don't cover.
- [examples.sql](examples.sql) — 10 parameterized gold-standard queries. **Load when** the user's question maps to a common pattern (crew utilization, expiring certs, etc.).
- [views.sql](views.sql) — DDL for the gold views. **Load when** registering the views in a new customer environment.
- [metric_udfs.sql](metric_udfs.sql) — UC SQL function DDL for Trusted UDFs. **Load when** registering metrics in UC.

## Compose with

- **`maximo-pm-planning`** — provides forecast workload via `v_pm_workload_by_craft`. This skill provides matching capacity (`v_crew_capacity`, `crew_capacity_hours` UDF). The joined query — workload vs capacity gap by craft × week — is the single highest-value cross-skill query in the family.
- **`maximo-work-orders`** — `LABTRANS` aggregation lives there; this skill provides the LABOR master that LABTRANS references.
- **`maximo-maintenance-cost`** — `contractor_spend` UDF lives there and relies on `LABOR.VENDOR`. This skill is the authoritative source for LABOR column semantics.
- **`maximo-asset-hierarchy`** — for "qualified labor by region" rollups.

## What NOT to do

- Don't join `LABOR` to `PERSON` with `INNER JOIN` unless you specifically need the union of both (you'll miss contractor labor records).
- Don't compute "available capacity" without first probing `WORKPERIOD` coverage — the answer may be silently zero.
- Don't count expired certifications as qualified. Filter `EXPIRYDATE`.
- Don't use `LABREPHIST` for cost — that's `LABTRANS`'s job.
- Don't aggregate rates across currencies (`LABORCRAFTRATE.CURRENCYCODE` may vary).
- Don't propose creating new labor records — that's transactional, not analytical.

## References

- IBM Maximo Manage — Resources module: https://www.ibm.com/docs/en/masv-and-l/maximo-manage/cd
- Authoring standard: see `_authoring/authoring-industry-skills/SKILL.md`
