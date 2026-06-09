# Maximo Integrity — Gotchas

## Contents

- 1. Corrosion rate is TWO rates (ST and LT), not one regression slope
- 2. `t_required` (t-min) is a per-component input, not derived from the trend
- 3. Next-inspection-due is a code rule, not a flat PM `NEXTDATE`
- 4. `PLUSGRELATEDREC` is NOT base `RELATEDRECORD`
- 5. Inspection results may live in `MEASUREMENT`/`MEASUREPOINT`
- 6. Regulatory vs SMRP PM compliance are different metrics
- 7. Inspection-work isolation is customer-specific
- 8. Corrosion rate requires at least 2 readings
- 9. UT thickness gauging gotchas (minimum vs average, calibration drift)
- 10. The customer probably has a parallel PCMS / integrity system
- 11. RBI scoring is customer-specific
- 12. Inspection findings ≠ WO failure codes
- 13. Audit prep requires reproducibility
- 14. Pipe segments are LOCATIONS, not assets

These traps silently produce wrong numbers in safety-critical reporting. Read before writing any query. `maximo-overview` carries the universal Maximo gotchas (SITEID, `WOCLASS`, `ISTASK`, status-via-`SYNONYMDOMAIN`, `HISTORYFLAG`, app-server-timezone datetimes) — this file does not repeat them.

## 1. Corrosion rate is TWO rates (ST and LT), not one regression slope

API 510 (vessels) and API 570 (piping) define **two** corrosion rates, and engineers compute **both**:

| Rate | Formula | Readings used | Purpose |
|---|---|---|---|
| **Long-term (LT)** | `(t_initial − t_actual) / years(t_initial→t_actual)` | full history | trend stability |
| **Short-term (ST)** | `(t_previous − t_actual) / years(t_previous→t_actual)` | the two most recent readings | catches a recent / accelerated damage mechanism |

**Remaining life (years) = `(t_actual − t_required) / corrosion_rate`.** Engineers use the rate that gives the **more conservative (shorter) remaining life**.

A single naive linear-regression slope (best-fit line over all points) **masks recent acceleration** — exactly the signal ST is designed to catch. So `v_corrosion_trends` should expose ST and LT **separately** and a `remaining_life` that picks the worse case, rather than one regression slope. Where the shipped `corrosion_rate` UDF returns a regression slope, treat it as an LT-style trend estimate and complement it with an ST calculation from the two most recent readings before quoting remaining life.

## 2. `t_required` (t-min) is a per-component input, not derived from the trend

`t_required` (a.k.a. **t-min**) is the minimum thickness for safe operation — the larger of the pressure-design minimum and the structural minimum for the component. It is a **known per-component INPUT** supplied by the integrity engineer / design data, **not** something you infer from the thickness readings.

Implication: if t-min is unknown for the component, **remaining life cannot be computed — return NULL and ASK** where it comes from (custom column, `ASSETMETER` limit, or the parallel integrity system). Do not substitute a warning/retirement limit unless the customer confirms it equals t-min.

## 3. Next-inspection-due is a code rule, not a flat PM `NEXTDATE`

Per API 510/570 the next inspection due date is the **stricter (shorter)** of:
1. a **code-mandated maximum interval**, and
2. **half the calculated remaining life**.

So `next_inspection_due = last_inspection_date + min(statutory_max_interval, 0.5 × remaining_life)`.

Code maxima (the absolute ceiling):
- **API 570 piping:** Class 1 thickness/external every **5 years** or half remaining life, whichever is less; Class 2/3 up to **10 years** or half remaining life.
- **API 510 vessels:** internal/on-stream inspection **half remaining life or 10 years**, whichever is less.

Two accepted conservative approaches the customer may use: the **half-life principle** (next interval = half remaining life) and the **double-corrosion-rate principle** (compute remaining life using twice the measured rate, then schedule). Both tighten the cadence as corrosion progresses; the code maximum is the ceiling.

A flat recurring PM frequency (a fixed `PM.NEXTDATE` cadence) **will be wrong as assets age and remaining life shrinks**. `inspection_on_time_compliance` and `next_inspection_due` should reflect this condition-based cadence — confirm the customer's interval policy (see Questions to surface first).

## 4. `PLUSGRELATEDREC` is NOT base `RELATEDRECORD`

The Oil & Gas add-on ships its own related-records object **`PLUSGRELATEDREC`** (class prefix `PLUSG`), **distinct** from the base **`RELATEDRECORD`** object:

- IBM industry add-ons use a documented classname-prefix convention: `PLUSG` = Oil and Gas, `PLUSC` = Calibration, `PLUSP` = Service Provider, `PLUSS` = Spatial, `PLUST` = Transportation, `PLUSD` = Utilities, `PLUSA` = Asset Configuration Manager, `PLUS` = Nuclear, `PLUSH` = Health Care, `PLUSF` = Facilities. O&G-specific entities/columns carry a `PLUSG*` prefix.
- IBM APAR IJ41024 documents `PLUSGRELATEDREC` carrying its own `RELATEDRECWONUM` attribute and that a change to `WORKORDER.WONUM` does not propagate into it — confirming it is its own link table, not base `RELATEDRECORD`.
- **Base `RELATEDRECORD`** carries `FOLLOWUP` / `ORIGINATOR` (directional creation chain) and `RELATED` (bidirectional peer) types, plus `ORIGRECORDID` / `ORIGRECORDCLASS` follow-up trace. **That generic mechanism is owned by `maximo-work-orders` (ledger F7) — defer there.** Author only `PLUSGRELATEDREC`-specific depth here.

**Don't conflate them, and confirm `PLUSG*` objects actually exist in the deployment** before querying — not every Maximo instance has the O&G add-on.

## 5. Inspection results may live in `MEASUREMENT`/`MEASUREPOINT`, not only custom columns or PCMS

Base Maximo Manage **Condition Monitoring** models observation points as `MEASUREPOINT` records (one per asset/location + `GAUGE`/`CHARACTERISTIC` meter, defining upper/lower **action limits**), with readings stored as `MEASUREMENT` records. When a reading falls outside action limits, a work order (commonly at status `WAPPR`) is created manually or automatically via the **`MeasurePointWoGenCronTask`** cron task, optionally from a referenced PM/Job Plan.

So structured inspection-result data (readings + limits) often lives in `MEASUREMENT`/`MEASUREPOINT` — **not only** in custom columns or an external PCMS. Check this base mechanism before assuming findings are off-platform.

## 6. Regulatory vs SMRP PM compliance are different metrics

These are NOT interchangeable:

| Metric | Used by | Definition | Acceptance |
|---|---|---|---|
| **SMRP PM compliance** | Operational maintenance | % completed within 10% tolerance / scheduled | Trending KPI (>90% is "good") |
| **Regulatory compliance** | Integrity / regulators | Binary per-asset — were they inspected by the statutory deadline? | 100% expected; deviations trigger reporting |

The `pm_compliance` UDF in `maximo-reliability` computes SMRP — **do not use it for regulatory compliance reporting**. This skill ships `inspection_on_time_compliance` with statutory-deadline semantics.

## 7. Inspection-work isolation is customer-specific

There's no Maximo-universal way to say "this WO is an inspection vs operational maintenance." Customers use one of:
- `WORKORDER.WORKTYPE` value (codes like `REG`, `INSP`, `API510`)
- `WORKORDER.JPNUM` linked to inspection-specific job plans
- A custom regulatory-flag column on `WORKORDER` (name varies per customer — read from the workspace glossary)

Always check the workspace glossary first. If no convention is defined, ASK before guessing.

## 8. Corrosion rate requires at least 2 readings

You can't compute a rate from one point. If `MEASUREMENT`/`METERREADING` has fewer than 2 readings for a given asset+meter+window, return NULL and tell the user. Don't fudge it.

For sparse data (one reading per year), expand the window before computing — the formula assumes a roughly linear corrosion mechanism in the window. Note the LT/ST distinction (gotcha 1): even with many points, the ST rate needs the two most recent readings.

## 9. UT thickness gauging gotchas

- **Minimum vs average wall thickness**: a single UT reading is at one point on the vessel; the actual minimum could be elsewhere. For regulatory work, the metric is usually MINIMUM thickness, not average.
- **Calibration drift**: readings before/after calibration events can have step changes that aren't real corrosion. Look for sudden jumps and flag.
- **Retirement thickness vs t-min**: each asset has a retirement/warning thickness (often a custom column or `ASSETMETER` limit). Do not assume it equals `t_required` (t-min) for remaining-life math (gotcha 2) — confirm.

## 10. The customer probably has a parallel PCMS / integrity system

For pressure vessels and piping, many O&G customers maintain a separate system (PCMS, Bentley AssetWise APM, or similar) that is a source of truth for integrity data. But **before assuming findings are off-platform, check the base `MEASUREPOINT`/`MEASUREMENT` mechanism (gotcha 5) and any `PLUSG*` O&G objects (gotcha 4)** — structured results may already be in Maximo.

When the user asks an integrity question:
1. Check `MEASUREPOINT`/`MEASUREMENT` and `PLUSG*` objects in the deployment.
2. Check the workspace glossary for `custom_tables` referencing PCMS-like data.
3. If a PCMS table is present, the canonical answer may come from joining Maximo to it.

Don't assume — ask.

## 11. RBI scoring is customer-specific

API RP 580/581 defines the framework (risk = likelihood × consequence) but every customer implements differently. The shipped `rbi_score` UDF is a defensible default (criticality × time-since-last-inspection × corrosion-rate severity). Customers often have richer formulas using consequence-of-failure modeling, probability-of-failure modeling, and asset-specific damage factors.

If the customer has a dedicated RBI tool, that's the canonical source. The Maximo-side score is approximate.

## 12. Inspection findings ≠ WO failure codes

When an integrity inspection finds a defect, the recording happens via one of:
- A `MEASUREMENT` against a `MEASUREPOINT` (structured, base mechanism — gotcha 5)
- A custom column on `WORKORDER` (e.g. `WO_INSPECTION_FINDING_CLASS`)
- A linked record via `PLUSGRELATEDREC` to a finding/integrity record
- A free-text memo (least useful for analytics)

`FAILUREREPORT` / `FAILURECODE` is for maintenance failures (something broke and required a fix). Don't conflate the two — inspection findings often precede failures by months/years.

## 13. Audit prep requires reproducibility

When the user says "audit prep, pull all inspections for site X" — what they need is a **reproducible, dated dump** they can hand to a regulator. Specifically:
- Filter to a closed time window.
- Include the status-transition trail from `WOSTATUS` (`CHANGEDATE`, `CHANGEBY`) so the audit trail is visible. (Resolve status synonyms via `SYNONYMDOMAIN` per `maximo-overview` rather than hard-coding literals.)
- Don't filter on current state only (auditors want all historical changes), and be aware `HISTORYFLAG = 1` work may be filtered out of standard views — confirm closed records are present (see `maximo-overview`).
- Output should be reproducible — the same query on the same date produces identical results. Use `__START_AT` / `__END_AT` on SCD2 tables to time-travel to the audit-date version of ASSET / LOCATIONS / PM.

## 14. Pipe segments are LOCATIONS, not assets

For pipeline integrity, the "asset" being inspected is often a **pipeline segment**, which lives in `LOCATIONS` (or a custom segment table), not `ASSET`. The hierarchy is:
- Region (LOCATIONS) → Segment (LOCATIONS) → Inspection point (custom location / `MEASUREPOINT`)

This differs from rotating equipment where ASSET is the unit. Confirm with the user whether they're asking about asset-style or pipeline-style integrity.
