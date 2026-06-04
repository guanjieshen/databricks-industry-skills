# Maximo Integrity — Gotchas

## 1. Regulatory vs SMRP PM compliance are different metrics

These are NOT interchangeable:

| Metric | Used by | Definition | Acceptance |
|---|---|---|---|
| **SMRP PM compliance** | Operational maintenance | % completed within 10% tolerance / scheduled | Trending KPI (>90% is "good") |
| **Regulatory compliance** | Integrity / regulators | Binary per-asset — were they inspected by the statutory deadline? | 100% expected; deviations trigger reporting |

The `pm_compliance` UDF in `maximo-reliability` computes SMRP — **do not use it for regulatory compliance reporting**. This skill ships `inspection_on_time_compliance` which uses statutory-deadline semantics.

## 2. Inspection-work isolation is customer-specific

There's no Maximo-universal way to say "this WO is an inspection vs operational maintenance." Customers use one of:
- `WORKORDER.WORKTYPE` value (codes like `REG`, `INSP`, `API510`)
- `WORKORDER.JPNUM` linked to inspection-specific job plans
- A custom column (`WO_REG_FLAG = 'Y'`, etc.)

Always check the workspace glossary first. If no convention is defined, ASK before guessing.

## 3. Corrosion rate requires at least 2 readings

You can't compute a rate from one point. If `METERREADING` has fewer than 2 readings for a given asset+meter+window, return NULL and tell the user. Don't fudge it.

For sparse data (one reading per year), expand the window before computing — the formula assumes a roughly linear corrosion mechanism in the window.

## 4. UT thickness gauging gotchas

- **Minimum vs average wall thickness**: a single UT reading is at one point on the vessel; the actual minimum could be elsewhere. For regulatory work, the metric is usually MINIMUM thickness, not average.
- **Calibration drift**: readings before/after calibration events can have step changes that aren't real corrosion. Look for sudden jumps and flag.
- **Retirement thickness**: each asset has a `RETIREMENT_THICKNESS` value (often a custom column or a `WARNLIMITLO` on ASSETMETER) — when readings approach it, the asset must be retired or de-rated. Critical for integrity engineering.

## 5. The customer probably has a parallel PCMS / integrity system

For pressure vessels and piping, most O&G customers maintain a separate system (PCMS, Bentley AssetWise APM, or similar) that is the source of truth for integrity data. Maximo holds the *work* records (inspections, PMs, repairs), not always the *findings*.

When the user asks an integrity question:
1. Check the workspace glossary for `custom_tables` referencing PCMS-like data.
2. If present, the canonical answer comes from joining Maximo to the PCMS table.
3. If absent, the customer may be running integrity exclusively in Maximo (uncommon for vessels/piping but common for rotating equipment).

Don't assume — ask.

## 6. RBI scoring is customer-specific

API RP 580/581 defines the framework but every customer implements differently. The shipped `rbi_score` UDF is a defensible default (criticality × time-since-last-inspection × corrosion-rate severity). Customers often have richer formulas using:
- Consequence-of-failure modeling (population near asset, environmental sensitivity)
- Probability-of-failure modeling (degradation mechanism, inspection effectiveness)
- Asset-specific damage factors

If the customer has a dedicated RBI tool, that's the canonical source. The Maximo-side score is approximate.

## 7. Inspection findings ≠ WO failure codes

When an integrity inspection finds a defect, the recording happens via one of:
- A custom column on `WORKORDER` (e.g. `WO_INSPECTION_FINDING_CLASS`)
- A linked record via `plusgrelatedrec` to a finding record in PCMS
- A free-text memo (least useful for analytics)

`FAILUREREPORT` is for maintenance failures (something broke and required a fix). Don't conflate the two — inspection findings often precede failures by months/years.

## 8. Audit prep requires reproducibility

When the user says "audit prep, pull all inspections for site X" — what they need is a **reproducible, dated dump** they can hand to a regulator. Specifically:
- Filter to a closed time window
- Include `CHANGEDATE`, `CHANGEBY` from WOSTATUS so the audit trail is visible
- Don't filter on current state (auditors want all historical changes)
- Output should be reproducible — running the same query on the same date should produce identical results

Use `__START_AT` / `__END_AT` on SCD2 tables to time-travel back to the audit-date version of ASSET / LOCATIONS / PM.

## 9. Pipe segments are LOCATIONS, not assets

For pipeline integrity, the "asset" being inspected is often a **pipeline segment**, which lives in `LOCATIONS` (or a custom segment table), not `ASSET`. The hierarchy is:
- Region (LOCATIONS) → Segment (LOCATIONS) → Inspection point (custom location)

This is different from rotating equipment where ASSET is the unit. Confirm with the user whether they're asking about asset-style or pipeline-style integrity.
