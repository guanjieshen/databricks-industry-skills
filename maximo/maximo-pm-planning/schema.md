# Maximo PM Planning — Schema Reference

For the **detailed `PM` table reference**, see [`../maximo-reliability/schema.md`](../maximo-reliability/schema.md). PM is the central table for both skills — documenting it once there and cross-referencing here avoids drift. Universal column semantics (SITEID composite keys, `STATUS` as a synonym domain, `HISTORYFLAG`, app-server-timezone datetimes) are owned by `maximo-overview`.

This file focuses on the **planning-specific** tables and forward-looking columns.

## Contents
- Key columns on `PM` for forecasting
- `PMSEQUENCE` — multi-frequency PMs
- `JOBPLAN` — task template (org-scoped)
- `JPLABOR` — planned labor on a template
- `JPMATERIAL` — planned material on a template
- `JPSERVICE` — planned contracted services
- `JPSEGMENT` — job-plan steps / operations
- `ASSETMETER` — meter-based PM forecasting
- `LABOR` — craft availability (cross-ref)
- `CALENDAR` / `WORKPERIOD` — shift schedules (deferred to labor-resources)
- Cardinality summary

## Key columns on `PM` for forecasting

(See `../maximo-reliability/schema.md` for the full reference.)

| Column | Why it matters for planning |
|---|---|
| `NEXTDATE` | Calculated next due date |
| `EXTDATE` | One-time override — always use `COALESCE(EXTDATE, NEXTDATE)` as effective due date |
| `USETARGETDATE` | Fixed (TRUE) vs floating (FALSE) — affects next-cycle anchor |
| `STATUS` | Only active PMs forecast. Synonym domain `PMSTATUS` — stores the renamable `VALUE`, not internal `MAXVALUE`; resolve via `SYNONYMDOMAIN` if renamed (see `maximo-overview`) |
| `ORGID` | Carried on `PM`; required to join the org-scoped `JOBPLAN`/`JP*` tables |
| `METERNAME` | Runtime meter for meter-based PMs — FK to `ASSETMETER.METERNAME` |
| `ALERTLEAD` | Days before NEXTDATE that the WO is generated |
| `FREQUENCY` + `FREQUNIT` | Cadence (e.g. 30 DAYS, 500 HOURS) |
| `LASTSTARTDATE` / `LASTCOMPDATE` | Last execution anchor — fixed uses LASTSTARTDATE, floating uses LASTCOMPDATE |

## `PMSEQUENCE` — multi-frequency PMs

The same PM can have **multiple action cadences**: e.g. a pump PM might do 30-day lubrication, 90-day inspection, and 365-day rebuild — all from one PM with three sequences.

| Column | Notes |
|---|---|
| `PMNUM` / `SITEID` | FK to PM |
| `SEQUENCE` | Sequence number within the PM |
| `JPNUM` | FK to JOBPLAN — different actions = different job plans |
| `FREQUENCY` | Frequency for this specific sequence |
| `FREQUNIT` | Unit |

For accurate workload forecasting, expand each `PM` into its sequences before counting WOs or summing labor.

```sql
SELECT pm.pmnum, pm.siteid, seq.sequence, seq.jpnum, seq.frequency, seq.frequnit
FROM pm
LEFT JOIN pmsequence seq ON seq.pmnum = pm.pmnum AND seq.siteid = pm.siteid
WHERE pm.__END_AT IS NULL
  AND pm.status = 'ACTIVE';
```

## `JOBPLAN` — task template (org-scoped)

Job-plan templates and all their child tables (`JPLABOR`, `JPMATERIAL`, `JPSERVICE`, `JPSEGMENT`) key on `(JPNUM, ORGID)` — **org-scoped, not site-scoped**. Always join PM → JOBPLAN on `(JPNUM, ORGID)`. See gotcha 9.

| Column | Notes |
|---|---|
| `JPNUM` | Job plan identifier |
| `ORGID` | Composite with JPNUM (templates are org-scoped, not site-scoped) |
| `DESCRIPTION` | Template description |
| `WORKTYPE` | Default work type when applied |
| `DURATION` | Estimated total duration in hours |
| `INTERRUPTIBLE` | Can the work be interrupted? Affects scheduling |
| `STATUS` | `ACTIVE`, `DRAFT`, `INACTIVE` |
| `PRIORITY` | Default priority for generated WOs |

## `JPLABOR` — planned labor on a template

| Column | Notes |
|---|---|
| `JPNUM` / `ORGID` | FK to JOBPLAN |
| `CRAFT` | Craft required (ELEC, MECH, INST, etc.) |
| `SKILLLEVEL` | Required skill level |
| `LABORHRS` | Planned labor hours |
| `QUANTITY` | Number of resources needed (e.g. 2 mechanics) |
| `LINECOST` | Planned labor cost |

For **forecast workload by craft**: sum `JPLABOR.LABORHRS` across PMs whose effective due date falls in the forecast window, grouped by `CRAFT`.

## `JPMATERIAL` — planned material on a template

| Column | Notes |
|---|---|
| `JPNUM` / `ORGID` | FK to JOBPLAN |
| `ITEMNUM` | Material required |
| `ITEMQTY` | Quantity planned |
| `LINECOST` | Planned material cost |
| `STOREROOM` / `STORELOC` | Where to draw from |

For **forecast material demand**: sum `JPMATERIAL.ITEMQTY` across forecast PMs, grouped by `ITEMNUM` — feeds into `maximo-inventory` for stockout-risk checks.

## `JPSERVICE` — planned contracted services

| Column | Notes |
|---|---|
| `JPNUM` / `ORGID` | FK to JOBPLAN |
| `SERVICECODE` | Service classification |
| `QUANTITY`, `UNITCOST`, `LINECOST` | Planned service cost |
| `VENDOR` | Default vendor (FK to COMPANIES) |

## `JPSEGMENT` — job-plan steps / operations

For very granular planning. Most analytics don't need to descend below `JOBPLAN`.

| Column | Notes |
|---|---|
| `JPNUM` / `ORGID` / `SEGMENT` | Composite key |
| `DESCRIPTION` | Step description |
| `DURATION` | Step duration |
| `JPLABORID` / `JPMATERIALID` | Optional FKs to specific labor / material lines |

## `ASSETMETER` — meter-based PM forecasting

Drives forecasts for meter-based PMs (`PM.FREQUNIT` in `HOURS`/`MILES`/`READINGS`). Keyed on `(ASSETNUM, SITEID, METERNAME)`.

| Column | Notes |
|---|---|
| `ASSETNUM` / `SITEID` | FK to ASSET |
| `METERNAME` | Meter identifier — match to `PM.METERNAME` for the runtime meter |
| `LASTREADING` | Most recent meter value |
| `LASTREADINGDATE` | When the last reading was taken |
| `AVERAGE` | Maximo-computed rolling per-day consumption rate. NULL/0 on a new meter → forecast is unknowable (return NULL). See gotcha 8 |

## `LABOR` — for craft availability

(Cross-referenced from `maximo-overview`.) Used to estimate available craft hours when balancing workload-vs-capacity.

## `CALENDAR` / `WORKPERIOD` — shift schedules (deferred to labor-resources)

| Table | Notes |
|---|---|
| `CALENDAR` | Customer-defined working calendars |
| `WORKPERIOD` | Specific work periods per calendar (shifts, days off, holidays) |

These are **often half-populated** at real customers — `CALENDAR` may exist but `WORKPERIOD` rows may only cover a subset of weeks. Always check coverage before claiming workload-vs-capacity analysis is meaningful. The capacity/availability master (including `AVAILREFLY`) is **owned by `maximo-labor-resources`** — for capacity tables and the half-populated-coverage probe, compose with that skill rather than re-deriving them here.

## Cardinality summary

| Relationship | Cardinality |
|---|---|
| `PM` → `PMSEQUENCE` | 1 : 0..N (PM with no sequences is single-cadence) |
| `PM` → `JOBPLAN` | N : 1 (many PMs can reference the same template) |
| `JOBPLAN` → `JPLABOR` | 1 : N |
| `JOBPLAN` → `JPMATERIAL` | 1 : N |
| `JOBPLAN` → `JPSEGMENT` | 1 : N |
| `WORKORDER` → `PM` | N : 1 (PM-generated WOs via `WORKORDER.PMNUM`) |
| `WORKORDER` → `JOBPLAN` | N : 1 (via `WORKORDER.JPNUM` + `ORGID`) |
| `ASSET` → `ASSETMETER` | 1 : N (one row per meter on the asset) |
| `PM` → `ASSETMETER` | N : 1 (via `PM.METERNAME` for meter-based PMs) |
| `CALENDAR` → `WORKPERIOD` | 1 : N |
