---
name: maximo-integrity
description: |
  Use for asset integrity workflows on Maximo data — pressure-vessel and
  pipeline inspections, corrosion trending (UT thickness gauging from
  ASSETMETER/METERREADING), regulatory PM compliance (API 510 / 570 / B31.4 /
  CSA Z662 / DOT 49 CFR), risk-based inspection (RBI) scoring, and
  inspection-tied incidents. Triggers on: "corrosion rate", "thickness reading",
  "regulatory inspection", "inspection due", "API 510", "API 570", "B31.4",
  "RBI", "pressure vessel", "pipeline integrity", "integrity engineer".
tags:
  - data-source:ibm-maximo
  - tier:module
  - module:asset-integrity
  - industry:oil-and-gas
  - persona:integrity-engineer
  - persona:da-platform
---

# Maximo Integrity

Help integrity engineers query, analyze, or build pipelines for **mechanical / pipeline / asset integrity** workflows on Maximo data. Composes with `maximo-overview` (universal data model literacy) and `maximo-reliability` (some metric UDFs overlap).

This skill is **O&G-heavy**. Integrity is a major discipline at pipeline operators, refineries, and midstream gas — distinct from operational maintenance and distinct from HSE. Failures here are regulatory/safety-critical, so the queries must match what's in the Maximo UI exactly.

## When to use

- "Show me all pressure vessels with inspections due in the next 6 months"
- "Corrosion rate on asset X from thickness readings"
- "Which assets are overdue on regulatory inspection?"
- "RBI risk score for our compressor fleet"
- "Inspection findings tied to last quarter's incidents"
- "Audit prep: pull all inspection records for site X"
- "Inspection on-time compliance %"
- "Did a missed inspection contribute to this incident?"

For operational backlog / WO analytics, use `maximo-work-orders`. For SMRP-style PM compliance (operational maintenance), use `maximo-reliability`. **Regulatory** PM compliance lives here — different metric, different stakes.

For HSE incidents (safety, permits, near-misses unrelated to asset integrity), use `maximo-hse`.

## Pre-flight (per session)

1. **Inspection work isolation**: "How do you distinguish inspection work from operational work?" Common patterns:
   - `WORKTYPE IN ('REG', 'INSP', 'API510', 'API570', ...)` — most common
   - Custom column like `WO_REG_FLAG = 'Y'`
   - Subset of `JPNUM` (job plans dedicated to inspection)
   Resolve via workspace glossary if available.
2. **Asset class for the question**: integrity engineers ask about specific classes ("pressure vessels", "above-ground piping"). Map to `CLASSSTRUCTUREID` via workspace glossary.
3. **Regulatory regime**: API 510 (vessels), API 570 (piping), B31.4 (liquid pipelines), CSA Z662 (Canadian pipelines), DOT 49 CFR — different inspection cadences and tolerances.

## Workflow priority

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `corrosion_rate`, `next_inspection_due`, `inspection_on_time_compliance`, `rbi_score`.
2. **Pre-joined views** in [views.sql](views.sql) — `v_inspection_schedule`, `v_corrosion_trends`, `v_inspection_findings`.
3. **Parameterized examples** in [examples.sql](examples.sql).
4. **Raw tables** — last resort.

## RBI scoring (a special note)

Risk-Based Inspection is a methodology, not a single formula. API RP 580/581 defines the conceptual framework — risk = likelihood × consequence — but implementations vary by customer. The shipped `rbi_score` UDF uses a defensible default (criticality × time-since-last-inspection × corrosion-rate severity) but every customer wants their own variant. Document the formula in the UDF comment so engineers can reconcile.

If the customer has a dedicated RBI tool (PCMS, RBMI, etc.), data is usually maintained THERE. The Maximo side just records the inspection findings and dates. Don't reinvent the customer's RBI methodology — point them at their canonical source if one exists.

## What's in this skill

- [schema.md](schema.md) — ASSETMETER/METERREADING for corrosion, PM for inspections, plusgrelatedrec for incident links
- [gotchas.md](gotchas.md) — regulatory vs SMRP compliance, inspection-work isolation, customer-specific RBI formulas
- [examples.sql](examples.sql) — parameterized integrity queries (vessels due, corrosion trends, audit prep)
- [views.sql](views.sql) — `v_inspection_schedule`, `v_corrosion_trends`, `v_inspection_findings`
- [metric_udfs.sql](metric_udfs.sql) — `corrosion_rate`, `next_inspection_due`, `inspection_on_time_compliance`, `rbi_score`

## What NOT to do

- **Don't use SMRP PM compliance for regulatory compliance** — they're different metrics with different acceptance criteria. Regulatory is binary (in or out of code) with statutory deadlines; SMRP is a tolerance-window percentage.
- **Don't fabricate corrosion rates from a single reading.** Need at least 2 readings to compute a rate. If only one reading exists, return NULL and ASK.
- **Don't conflate inspection findings with WO closure events.** A WO closing with `FAILURECODE` is not necessarily an inspection finding — it's a maintenance failure. Inspection findings are typically captured in custom columns or `plusgrelatedrec` links to integrity records.
- **Don't recommend an inspection schedule change without flagging that it's a regulatory matter** — changes to inspection cadence can require regulator notification.

## References

- [schema.md](schema.md)
- [gotchas.md](gotchas.md)
- [examples.sql](examples.sql)
- [views.sql](views.sql)
- [metric_udfs.sql](metric_udfs.sql)
- API 510 (Pressure Vessel Inspection Code): https://www.api.org/
- API RP 580 (Risk-Based Inspection): https://www.api.org/
- CSA Z662 (Canadian pipeline code): https://www.csagroup.org/
