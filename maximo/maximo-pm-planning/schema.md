# Maximo PM Planning — Schema Reference

For the **detailed `PM` table reference**, see [`../maximo-reliability/schema.md`](../maximo-reliability/schema.md). PM is the central table for both skills — documenting it once there and cross-referencing here avoids drift.

This file focuses on the **planning-specific** tables and forward-looking columns.

## Key columns on `PM` for forecasting

(See `../maximo-reliability/schema.md` for the full reference.)

| Column | Why it matters for planning |
|---|---|
| `NEXTDATE` | Calculated next due date |
| `EXTDATE` | One-time override — always use `COALESCE(EXTDATE, NEXTDATE)` as effective due date |
| `USETARGETDATE` | Fixed (TRUE) vs floating (FALSE) — affects next-cycle anchor |
| `STATUS` | Only `ACTIVE` PMs forecast |
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

## `JOBPLAN` — task template

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

## `LABOR` — for craft availability

(Cross-referenced from `maximo-overview`.) Used to estimate available craft hours when balancing workload-vs-capacity.

## `CALENDAR` / `WORKPERIOD` — shift schedules (where populated)

| Table | Notes |
|---|---|
| `CALENDAR` | Customer-defined working calendars |
| `WORKPERIOD` | Specific work periods per calendar (shifts, days off, holidays) |

These are **often half-populated** at real customers — `CALENDAR` may exist but `WORKPERIOD` rows may only cover a subset of weeks. Always check coverage before claiming workload-vs-capacity analysis is meaningful.

## Cardinality summary

| Relationship | Cardinality |
|---|---|
| `PM` → `PMSEQUENCE` | 1 : 0..N (PM with no sequences is single-cadence) |
| `PM` → `JOBPLAN` | N : 1 (many PMs can reference the same template) |
| `JOBPLAN` → `JPLABOR` | 1 : N |
| `JOBPLAN` → `JPMATERIAL` | 1 : N |
| `JOBPLAN` → `JPSEGMENT` | 1 : N |
| `WORKORDER` → `PM` | N : 1 (PM-generated WOs via `WORKORDER.PMNUM`) |
| `WORKORDER` → `JOBPLAN` | N : 1 (via `WORKORDER.JPNUM`) |
| `CALENDAR` → `WORKPERIOD` | 1 : N |
