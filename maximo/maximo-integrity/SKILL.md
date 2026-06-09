---
name: maximo-integrity
description: |
  Use for IBM Maximo / Maximo / EAM / CMMS asset-integrity analytics:
  pressure-vessel and pipeline inspections, corrosion trending (UT thickness
  gauging via MEASUREPOINT/MEASUREMENT and ASSETMETER/METERREADING),
  remaining-life and corrosion-rate calculation (API 510 / 570 short-term vs
  long-term), condition-based inspection-interval / next-due cadence, regulatory
  PM compliance (API 510 / 570 / B31.4 / CSA Z662 / DOT 49 CFR), risk-based
  inspection (RBI) scoring, and Oil & Gas inspection links via PLUSGRELATEDREC.
  Triggers on: "corrosion rate", "remaining life", "t-min", "thickness reading",
  "UT gauging", "MEASUREPOINT", "regulatory inspection", "inspection due",
  "next inspection interval", "API 510", "API 570", "B31.4", "CSA Z662", "RBI",
  "pressure vessel", "pipeline integrity", "PLUSG", "integrity engineer".
metadata:
  version: "0.2.0"
parent: maximo-overview
---

# Maximo Integrity

Help integrity engineers query, analyze, or build pipelines for **mechanical / pipeline / asset integrity** workflows on Maximo data. Composes with `maximo-overview` (universal data model literacy) and `maximo-reliability` (some metric UDFs overlap).

This skill is **O&G-heavy**. Integrity is a major discipline at pipeline operators, refineries, and midstream gas — distinct from operational maintenance and distinct from HSE. Failures here are regulatory/safety-critical, so the queries must match what's in the Maximo UI exactly.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas (SITEID composite keys, `WOCLASS` filtering, `ISTASK` tasks-vs-child-WOs, status-as-synonym-domain resolved via `SYNONYMDOMAIN`, `HISTORYFLAG`, app-server-timezone datetimes, `STATUS`-current-vs-`WOSTATUS`-history). This skill applies those where relevant and adds integrity-specific depth — it does not re-teach them.

## When to use

- "Show me all pressure vessels with inspections due in the next 6 months"
- "Corrosion rate on asset X from thickness readings"
- "Remaining life / t-min for vessel X"
- "Which assets are overdue on regulatory inspection?"
- "RBI risk score for our compressor fleet"
- "Inspection findings tied to last quarter's incidents"
- "Audit prep: pull all inspection records for site X"
- "Inspection on-time compliance %"
- "Did a missed inspection contribute to this incident?"

**Defer to siblings when:**
- Operational backlog / WO aging / labor analytics → `maximo-work-orders`
- SMRP-style PM compliance (operational maintenance) → `maximo-reliability`. **Regulatory** PM compliance lives here — different metric, different stakes.
- HSE incidents (safety, permits, near-misses unrelated to asset integrity) → `maximo-hse`
- Generic follow-up → originator creation chains in `RELATEDRECORD` → `maximo-work-orders` (ledger F7). This skill owns only the **O&G `PLUSGRELATEDREC`** overlay (see gotcha 3 and schema.md).

## Top gotchas

These traps silently produce wrong numbers in safety-critical reporting. Read before writing any query (full set in [gotchas.md](gotchas.md); `maximo-overview` carries the universal ones):

1. **Corrosion rate is two rates, not one regression slope.** API 510/570 define a **long-term (LT)** rate `(t_initial − t_actual) / years` over full history and a **short-term (ST)** rate `(t_previous − t_actual) / years` over the two most recent readings. Remaining life = `(t_actual − t_required) / rate`; engineers pick the **more conservative (shorter)** remaining life. A single best-fit line masks recent accelerated thinning — expose ST and LT separately (see gotcha 1 in gotchas.md and `v_corrosion_trends`).
2. **`t_required` (t-min) is a per-component INPUT, not derived from the trend.** It is the minimum safe thickness (pressure-design + structural minimum) supplied per component; never infer it from the readings. If it is unknown, remaining life cannot be computed — return NULL and ASK.
3. **`PLUSGRELATEDREC` ≠ base `RELATEDRECORD`.** The O&G add-on ships its own related-records object `PLUSGRELATEDREC` (class prefix `PLUSG`), distinct from base `RELATEDRECORD`. O&G inspection/integrity links may live in `PLUSGRELATEDREC`; generic follow-up/originator chains use `RELATEDRECORD` and are owned by `maximo-work-orders` (ledger F7). Do not conflate them, and confirm `PLUSG*` objects actually exist in the deployment before querying them.
4. **Next-inspection-due is a code rule, not a flat PM `NEXTDATE`.** Per API 510/570 the due date is the **stricter (shorter)** of a statutory maximum interval and **half the remaining life**: `min(statutory_max, 0.5 × remaining_life)` from the last inspection. A fixed recurring PM frequency goes wrong as the asset ages and remaining life shrinks (see gotcha 4).
5. **Structured inspection results may live in `MEASUREMENT`/`MEASUREPOINT`, not only custom columns or an external PCMS.** Base Manage Condition Monitoring stores observation points as `MEASUREPOINT` (with upper/lower action limits) and readings as `MEASUREMENT`; breaching an action limit can generate an inspection WO via the `MeasurePointWoGenCronTask` cron. Check for this base mechanism before assuming findings are only in custom columns or a parallel system.

## Questions to surface first

Surface these *before* answering — there is no defensible default:

1. **Inspection-work isolation.** There is no Maximo-universal "this WO is an inspection" flag. Common conventions: `WORKTYPE IN ('REG','INSP','API510','API570',…)`, a `JPNUM` subset of inspection job plans, or a custom regulatory-flag column (name varies per customer — read from the workspace glossary). Resolve via workspace glossary; if undefined, ASK.
2. **Corrosion-rate basis.** Should remaining life use the **short-term** rate (two most recent readings, catches recent acceleration), the **long-term** rate (full history, trend stability), or the **more conservative** of the two? Default to the more conservative; confirm.
3. **`t_required` / t-min source.** Where does the per-component minimum thickness come from — a custom column, `ASSETMETER` limit, or the parallel integrity system? Without it, no remaining life.
4. **Inspection-interval policy.** Half-life principle, double-corrosion-rate principle, or a flat code-maximum ceiling? And which **regulatory regime** governs — API 510 (vessels), API 570 piping Class 1/2/3, B31.4, CSA Z662, DOT 49 CFR? Each has different maxima.
5. **Asset class for the question.** "Pressure vessels", "above-ground piping" — map to `CLASSSTRUCTUREID` via workspace glossary. Also confirm whether the inspected object is an `ASSET` or a `LOCATIONS` pipe segment (gotcha 9 in gotchas.md).

## Pre-flight (per session)

Cache these once; don't re-ask each turn:
1. Catalog / silver-schema / gold-schema / metrics-schema names.
2. Workspace glossary for: inspection `WORKTYPE` set, `CLASSSTRUCTUREID` map, any parallel PCMS / `custom_tables` entries, and whether `PLUSG*` (O&G) objects are deployed.

## Workflow priority

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `corrosion_rate`, `next_inspection_due`, `inspection_on_time_compliance`, `rbi_score`.
2. **Pre-joined views** in [views.sql](views.sql) — `v_inspection_schedule`, `v_corrosion_trends`, `v_inspection_findings`.
3. **Parameterized examples** in [examples.sql](examples.sql).
4. **Raw tables** — last resort.

SQL parameters use Databricks-native `:param` syntax (e.g. `:catalog.:silver_schema.MEASUREMENT`, `WHERE assetnum = :assetnum`).

## RBI scoring (a special note)

Risk-Based Inspection is a methodology, not a single formula. API RP 580/581 defines the framework — risk = likelihood × consequence — but implementations vary by customer. The shipped `rbi_score` UDF uses a defensible default (criticality × time-since-last-inspection × corrosion-rate severity); every customer wants their own variant. Document the formula in the UDF comment so engineers can reconcile.

If the customer has a dedicated RBI tool (PCMS, RBMI, etc.), data is usually maintained THERE. The Maximo side just records the inspection findings and dates. Don't reinvent the customer's RBI methodology — point them at their canonical source if one exists.

## What's in this skill

- [schema.md](schema.md) — MEASUREPOINT/MEASUREMENT and ASSETMETER/METERREADING for corrosion, PM for inspections, PLUSGRELATEDREC for O&G incident/finding links. Load when picking tables/columns.
- [gotchas.md](gotchas.md) — ST/LT corrosion methodology, t-min as input, condition-based interval cadence, regulatory vs SMRP compliance, PLUSGRELATEDREC vs RELATEDRECORD, customer-specific RBI. Load before any non-trivial query.
- [examples.sql](examples.sql) — parameterized integrity queries (vessels due, corrosion trends, remaining life, audit prep).
- [views.sql](views.sql) — `v_inspection_schedule`, `v_corrosion_trends`, `v_inspection_findings`.
- [metric_udfs.sql](metric_udfs.sql) — **Trusted Asset functions**: UC SQL functions you register once so Genie Agents call them as *certified, governed metrics* instead of regenerating ad-hoc SQL. Register via `maximo-setup` or by running the file, then reference the functions by name.

## What NOT to do

- **Don't compute a single regression-slope corrosion rate.** Compute ST and LT separately and drive remaining life from the more conservative one (gotcha 1). A single best-fit line masks recent accelerated thinning.
- **Don't derive `t_required` (t-min) from the readings.** It is a per-component design input; missing t-min means no remaining life — return NULL and ASK (gotcha 2).
- **Don't schedule inspections on a flat PM `NEXTDATE`.** Next-due is `min(statutory_max, 0.5 × remaining_life)` and tightens as the asset ages (gotcha 4).
- **Don't conflate `PLUSGRELATEDREC` with base `RELATEDRECORD`.** They are distinct objects; generic follow-up/originator semantics are owned by `maximo-work-orders` (ledger F7) — defer there and author only `PLUSGRELATEDREC` depth here (gotcha 3).
- **Don't use SMRP PM compliance for regulatory compliance** — regulatory is binary (in/out of code) with statutory deadlines; SMRP is a tolerance-window percentage. (The `pm_compliance` UDF is owned by `maximo-reliability`.)
- **Don't conflate inspection findings with WO failure codes.** `FAILUREREPORT`/`FAILURECODE` captures maintenance failures; inspection findings may live in `MEASUREMENT` against `MEASUREPOINT`, custom columns, or `PLUSGRELATEDREC` links (gotcha 5).
- **Don't recommend an inspection schedule change without flagging that it's a regulatory matter** — cadence changes can require regulator notification.

## Composes with

- **`maximo-work-orders`** — generic follow-up → originator creation chains via base `RELATEDRECORD` / `ORIGRECORDID` (ledger F7). This skill defers that mechanism and owns only the O&G `PLUSGRELATEDREC` overlay.
- **`maximo-reliability`** — SMRP PM compliance (`pm_compliance`) and rework-rate KPIs. Regulatory compliance stays here.
- **`maximo-asset-hierarchy`** — inspection rollups by area / process system ("all vessels under unit X due for inspection"). Use `v_location_rollup_keys` or the `descendant_count` UDF.
- **`maximo-labor-resources`** — "who's qualified to perform this inspection" (joins inspection PMs to qualified labor via `QUALPERSON`).

## References

- [schema.md](schema.md)
- [gotchas.md](gotchas.md)
- [examples.sql](examples.sql)
- [views.sql](views.sql)
- [metric_udfs.sql](metric_udfs.sql)
- API 510 (Pressure Vessel Inspection Code) / API 570 (Piping Inspection Code): https://www.api.org/
- API RP 580 / 581 (Risk-Based Inspection): https://www.api.org/
- CSA Z662 (Canadian pipeline code): https://www.csagroup.org/
- Remaining-life / corrosion-rate methodology (ST vs LT): https://epcland.com/remaining-life-of-pressure-vessels/ · https://amarineblog.com/2020/01/15/corrosion-rate-calculation-api-510-570/
- Half-life vs double-corrosion-rate interval principles: https://www.falconinspec.com/api-510/
- IBM industry-solution classname prefixes (PLUSG = Oil & Gas): https://www.ibm.com/support/pages/classname-prefixes-info-industry-solutions-classes-maximo
- IBM APAR IJ41024 (PLUSGRELATEDREC is a distinct O&G object): https://www.ibm.com/support/pages/apar/IJ41024
- IBM Condition Monitoring (MEASUREPOINT / MEASUREMENT): https://www.ibm.com/docs/en/maximo-eam-saas?topic=application-condition-monitoring-overview
