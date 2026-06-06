# Maximo Integrity — Schema Reference

For the universal Maximo schema (WORKORDER, ASSET, LOCATIONS) and universal mechanics (SITEID composite keys, `WOCLASS`, `ISTASK`, status-via-`SYNONYMDOMAIN`, `HISTORYFLAG`, app-server-timezone datetimes), see `maximo-overview/SKILL.md`. This skill focuses on tables specific to integrity workflows and does not re-teach the universal ones.

## Contents

- `MEASUREPOINT` / `MEASUREMENT` — base Condition Monitoring observation points + readings
- `ASSETMETER` — meter definitions per asset
- `METERREADING` — time-series readings against meters
- Corrosion-rate & remaining-life inputs (ST/LT, t-min)
- `WORKORDER` (filtered to inspection work)
- `PM` (filtered to regulatory PMs)
- `PLUSGRELATEDREC` (O&G — distinct from base `RELATEDRECORD`)
- `PLUSGINCPERSON` (O&G)
- Custom tables (common patterns)
- Cardinality summary

## Tables used

### `MEASUREPOINT` / `MEASUREMENT` — base Condition Monitoring (exists regardless of O&G)

Base Maximo Manage Condition Monitoring models observation points as **`MEASUREPOINT`** records — one per asset/location + a `GAUGE` or `CHARACTERISTIC` meter — defining upper/lower **action limits**. Readings are stored as **`MEASUREMENT`** records. When a reading falls outside its action limits, an inspection WO is created manually or automatically via the **`MeasurePointWoGenCronTask`** cron task (optionally from a referenced PM / job plan; the generated WO typically starts at status `WAPPR`).

This means structured inspection-result data (readings + limits) often lives in `MEASUREMENT` / `MEASUREPOINT` — **not only** in custom columns or an external PCMS. Check for this base mechanism before assuming findings are off-platform.

Key `MEASUREPOINT` columns: `POINTNUM`, `ASSETNUM`/`LOCATION`, `SITEID`, `METERNAME`, and the limit fields `LOWERWARNING` / `UPPERWARNING` / `LOWERACTION` / `UPPERACTION` (warning + action thresholds; readings outside the action limits trigger a WO). Key `MEASUREMENT` columns: `MEASUREDATE`, `MEASUREMENTVALUE` (numeric) / `OBSERVATION` (characteristic), `POINTNUM`.

### `ASSETMETER` — meter definitions per asset

For integrity, the key meters are:
- **UT thickness** (e.g. `METERNAME = 'UT_THICKNESS'`, type `CHARACTERISTIC` or `GAUGE`) — corrosion gauging
- **Vibration** (e.g. `VIB_VEL_HORIZ`, `VIB_VEL_VERT`) — rotating equipment condition
- **Operating hours** — runtime accumulation
- **Pressure / temperature** — process variable monitoring

Key columns: `ASSETNUM` + `SITEID` + `METERNAME`, `LASTREADING`, `LASTREADINGDATE`, `AVERAGE`. **`ASSETMETER` has no warning/action-limit columns** — Condition Monitoring limits live on `MEASUREPOINT` (`LOWERWARNING`/`UPPERWARNING`/`LOWERACTION`/`UPPERACTION`); the meter *type* lives on the `METER` master, not here. Action-limit breaches typically trigger an inspection or repair WO.

### `METERREADING` — time-series readings against meters

Append-only. Key columns: `READINGDATE`, `READING`. **Datetimes are stored in the app-server timezone (see `maximo-overview`), not per-row UTC — keep that in mind when computing year-fractions for rates.**

For pressure-vessel UT readings, customers often have a separate **PCMS-like custom table** (corrosion management system) that holds the same data with more domain detail. Check the workspace glossary for `custom_tables` entries referencing `pcms_thickness_readings` or similar.

### Corrosion-rate & remaining-life inputs (ST / LT, t-min)

Per API 510/570, corrosion is characterized by **two** rates, not one regression slope:

| Rate | Formula | Source readings |
|---|---|---|
| **Long-term (LT)** | `(t_initial − t_actual) / years` | full history (trend stability) |
| **Short-term (ST)** | `(t_previous − t_actual) / years` | the two most recent readings (catches recent acceleration) |

**Remaining life (years) = `(t_actual − t_required) / corrosion_rate`.** Engineers compute both rates and use the one giving the **shorter (more conservative)** remaining life.

- `t_actual` = latest thickness reading (`MEASUREMENT` / `METERREADING`).
- `t_initial` = first/installed thickness; `t_previous` = prior reading.
- `t_required` (a.k.a. **t-min**) = minimum thickness for safe operation (pressure-design + structural minimum). It is a **known per-component INPUT** — never derived from the trend. Sourced from a custom column, an `ASSETMETER` limit, or the parallel integrity system; if unknown, remaining life is NULL.

### `WORKORDER` (filtered to inspection work)

Inspection WOs are isolated by one of:
- `WORKTYPE IN ('REG', 'INSP', 'API510', 'API570', ...)` — workspace-glossary-driven
- `JPNUM` in a customer-specific list of inspection job plans
- A custom column flag (`WO_REG_FLAG = 'Y'`, etc.)

### `PM` (filtered to regulatory PMs)

Regulatory PMs are usually marked by:
- A `WORKTYPE` value that propagates to generated WOs
- A `JPNUM` referencing a regulatory inspection job plan
- A custom column (`PM_REG_CODE = 'API510'`, etc.)

Use workspace glossary to determine the customer's convention.

### `PLUSGRELATEDREC` (O&G industry solution — DISTINCT from base `RELATEDRECORD`)

The Oil & Gas add-on ships its **own** related-records object `PLUSGRELATEDREC` (class prefix `PLUSG`), **separate** from the base `RELATEDRECORD` object. They are not the same table — do not conflate them:

- **`PLUSGRELATEDREC`** is the O&G overlay used for inspection/integrity links. IBM APAR IJ41024 documents it carrying its own `RELATEDRECWONUM` attribute (with blank/read-only "Same As Object"/"Same As Attribute"), and notes that a change to `WORKORDER.WONUM` does **not** propagate into `PLUSGRELATEDREC` — confirming it is its own link table.
- **Base `RELATEDRECORD`** carries the generic `FOLLOWUP` / `ORIGINATOR` (directional creation chain) and `RELATED` (bidirectional peer) relationship types, plus the `ORIGRECORDID` / `ORIGRECORDCLASS` follow-up trace. **That base mechanism is owned by `maximo-work-orders` (ledger F7) — defer the generic follow-up/originator semantics there.**

An O&G inspection record in `PLUSGRELATEDREC` might link to:
- An `INCIDENT` record (inspection triggered by an incident)
- An `MOC` record (Management of Change for a finding)
- Another `WORKORDER` (follow-up repair WO)

**Confirm `PLUSG*` objects are actually deployed before querying** — not every Maximo instance has the O&G add-on. Column names vary by version/customization; inspect the deployed object rather than assuming base `RELATEDRECORD` columns.

### `PLUSGINCPERSON` (O&G industry solution)

Persons involved in an incident — used for HSE rollups. For integrity, the link `PLUSGRELATEDREC` → `INCIDENT` → `PLUSGINCPERSON` lets you answer "was anyone hurt by an incident tied to this asset's missed inspection?" Detailed HSE incident analytics belong to `maximo-hse`.

### Custom tables (common patterns)

Most O&G customers maintain a parallel system to Maximo for integrity. Typical names:
- `pcms_*` — Plant Corrosion Management System
- `anomaly_*` — Inline inspection / pig run findings
- `gis_*` — GIS attributes for pipeline segments
- `cmpd_*` — Compliance / regulatory case-management

These join to Maximo via `ASSETNUM`, `LOCATION`, or custom keys. Check workspace glossary.

## Cardinality summary

| Relationship | Cardinality |
|---|---|
| `ASSET`/`LOCATIONS` → `MEASUREPOINT` | 1 : N |
| `MEASUREPOINT` → `MEASUREMENT` | 1 : N |
| `ASSET` → `ASSETMETER` | 1 : N |
| `ASSETMETER` → `METERREADING` | 1 : N |
| `PM` → `WORKORDER` (regulatory) | 1 : N |
| `WORKORDER` (inspection) → `PLUSGRELATEDREC` → `INCIDENT` | N : N via O&G link table |
| `ASSET` → custom PCMS table | 1 : N typically |
