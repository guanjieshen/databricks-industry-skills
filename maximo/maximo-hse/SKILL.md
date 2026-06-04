---
name: maximo-hse
description: |
  Use for Health, Safety & Environment workflows on Maximo data — Permit to
  Work (plusgpermitwork), incidents (INCIDENT + plusgincperson), investigations,
  Management of Change (MOC) records, safety observations, and regulatory HSE
  reporting (TRIR / LTIR / near-miss tracking). Triggers on: "HSE", "permit to
  work", "PTW", "incident", "near miss", "investigation", "TRIR", "LTIR",
  "MoC", "Management of Change", "safety observation", "OSHA recordable",
  "PSM", "process safety".
metadata:
  version: "0.1.0"
parent: maximo-overview
---

# Maximo HSE

Help HSE managers, safety officers, and regulatory reporting teams query, analyze, or build pipelines on Maximo's HSE-related data. Heavily relies on the PLUSG industry-solution extension (O&G).

This skill is **O&G-heavy**. If the customer is not on the Maximo Oil & Gas industry solution, the `plusg*` tables won't exist and most of this skill won't apply.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas (SITEID composite keys, `WOCLASS` filtering, `ISTASK` dedup, WOSTATUS-vs-WORKORDER history). This skill builds on that foundation.

## When to use

- "How many permits to work are open right now?"
- "TRIR for last quarter"
- "Open corrective actions from incidents older than 30 days"
- "Near-miss trend last year"
- "Permits expiring in the next 7 days"
- "Incidents by category by site"
- "OSHA recordable incidents this year"
- "Outstanding MoC actions"
- "Incidents tied to a specific asset / location"

For integrity-specific incident analysis (did a missed inspection cause this incident?), defer to `maximo-integrity` — it has the inspection→incident join via `plusgrelatedrec`.

## Pre-flight (per session)

1. **Confirm O&G industry solution**: ask if `plusg*` tables are populated in the Silver layer. If not, most of this skill won't work — flag to the user.
2. **Recordable definition**: "Are you using OSHA recordable, MSHA, or a customer-specific definition?" The reporting category drives the filter on incidents.
3. **TRIR / LTIR formula**: standard is `(recordable incidents × 200,000) / hours-worked`. Confirm the hours-worked source — often a corporate HR system, not Maximo.

## Workflow priority

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `trir`, `ltir`, `open_permit_count`, `incident_count_by_class`
2. **Pre-joined views** in [views.sql](views.sql) — `v_open_permits`, `v_incidents_enriched`, `v_moc_actions`
3. **Parameterized examples** in [examples.sql](examples.sql)
4. **Raw tables** — last resort

## What's in this skill

- [schema.md](schema.md) — plusgpermitwork, plusgpertype, INCIDENT, plusgincperson, plusgrelatedrec, MOC tables
- [gotchas.md](gotchas.md) — sparse plusg* data, TRIR hours-worked source, near-miss vs incident vs recordable
- [examples.sql](examples.sql) — parameterized HSE queries
- [views.sql](views.sql) — DDL for `v_open_permits`, `v_incidents_enriched`, `v_moc_actions`
- [metric_udfs.sql](metric_udfs.sql) — **Trusted Asset functions**: UC SQL functions you register once so Genie Spaces call them as *certified, governed metrics* instead of regenerating ad-hoc SQL. Register via `maximo-setup` or by running the file, then reference the functions by name.

## What NOT to do

- **Don't compute TRIR without confirming the hours-worked source.** Hours-worked typically comes from HR / payroll, not Maximo. Asking for it is part of the workflow.
- **Don't conflate "incident" classifications.** OSHA-recordable, near-miss, first-aid, lost-time — different categories drive different metrics. Verify which the user wants.
- **Don't assume `plusg*` tables exist** without checking. Many Maximo deployments are classic Maximo without the O&G industry solution.
- **Don't expose PII** (incident person names, medical details) in any generated artifact. Aggregate or de-identify.
- **Don't bypass the privacy / regulatory review** for incident data — every customer has rules about who can see what.

## Composes with

- **`maximo-asset-hierarchy`** — for incident/permit rollups by location parent ("incidents at station 4 last quarter", "open permits under region X"). Use `v_location_rollup_keys`.
- **`maximo-labor-resources`** — for PTW (permit-to-work) competency checks: "who's qualified for hot work" via QUALPERSON + QUALIFICATION. Composing labor-resources + HSE answers "is this permit's worker qualified for this task type?"

## References

- [schema.md](schema.md)
- [gotchas.md](gotchas.md)
- [examples.sql](examples.sql)
- [views.sql](views.sql)
- [metric_udfs.sql](metric_udfs.sql)
- IBM Maximo for Oil & Gas docs (HSE): https://www.ibm.com/docs/en/mfo-and-g/
- OSHA Recordkeeping (TRIR): https://www.osha.gov/recordkeeping
- API RP 754 (Process Safety Performance Indicators)
