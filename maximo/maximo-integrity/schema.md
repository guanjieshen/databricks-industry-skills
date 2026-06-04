# Maximo Integrity — Schema Reference

For the universal Maximo schema (WORKORDER, ASSET, LOCATIONS), see `maximo-overview/SKILL.md`. This skill focuses on tables specific to integrity workflows.

## Tables used

### `ASSETMETER` — meter definitions per asset

For integrity, the key meters are:
- **UT thickness** (e.g. `METERNAME = 'UT_THICKNESS'`, type `CHARACTERISTIC` or `GAUGE`) — corrosion gauging
- **Vibration** (e.g. `VIB_VEL_HORIZ`, `VIB_VEL_VERT`) — rotating equipment condition
- **Operating hours** — runtime accumulation
- **Pressure / temperature** — process variable monitoring

Key columns: `METERNAME`, `WARNLIMITLO`, `WARNLIMITHI`, `ACTIONLIMITLO`, `ACTIONLIMITHI`. The `ACTIONLIMIT*` thresholds typically trigger an inspection or repair WO when breached.

### `METERREADING` — time-series readings against meters

Append-only. Key columns: `READINGDATE`, `READING`. Corrosion rate is computed as the linear regression slope of `READING` against `READINGDATE` for a thickness meter on a given asset.

For pressure-vessel UT readings, customers often have a separate **PCMS-like custom table** (corrosion management system) that holds the same data with more domain detail. Check the workspace glossary for `custom_tables` entries referencing `pcms_thickness_readings` or similar.

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

### `plusgrelatedrec` (O&G industry solution)

Link table for relating records: an inspection WO might be linked to:
- An `INCIDENT` record (the inspection was triggered by an incident)
- An `MOC` record (Management of Change request for a finding)
- Another `WORKORDER` (follow-up repair WO)

Schema: `RECORDKEY`, `RECORDCLASS`, `RELATEDRECKEY`, `RELATEDRECCLASS`, `RELATIONSHIP` — bidirectional links.

### `plusgincperson` (O&G industry solution)

Persons involved in an incident — used for HSE rollups. For integrity, the link from `plusgrelatedrec` → `INCIDENT` → `plusgincperson` lets you answer "was anyone hurt by an incident tied to this asset's missed inspection?"

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
| `ASSET` → `ASSETMETER` | 1 : N |
| `ASSETMETER` → `METERREADING` | 1 : N |
| `PM` → `WORKORDER` (regulatory) | 1 : N |
| `WORKORDER` (inspection) → `plusgrelatedrec` → `INCIDENT` | N : N via link table |
| `ASSET` → custom PCMS table | 1 : N typically |
