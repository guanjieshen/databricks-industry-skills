# Maximo Reliability — Schema Reference

For the universal Maximo schema (WORKORDER, ASSET, LOCATIONS), see `maximo-overview/SKILL.md`. This skill focuses on tables specific to reliability metrics.

## Contents

- Tables used by reliability metrics
- Cardinality summary (reliability-specific)

## Tables used by reliability metrics

### `WORKORDER` (filtered to failure events)

Failure events are WOs where:
- `WOCLASS = 'WORKORDER'`
- A `FAILUREREPORT` row exists (or `FAILURECODE IS NOT NULL` on WORKORDER itself)
- `STATUS IN ('COMP', 'CLOSE')` (the failure has been worked and recorded)

For MTBF / MTTR / failure analytics, work from `v_failure_events` rather than raw WORKORDER.

### `FAILUREREPORT`

Per-WO coded failure record (one row per WO that recorded a failure).

| Column | Type | Notes |
|---|---|---|
| `WONUM` | STRING | FK to WORKORDER.WONUM |
| `SITEID` | STRING | Composite with WONUM |
| `FAILURECODE` | STRING | FK to FAILURECODE; this is the leaf-level code |
| `RECORDKEY` | STRING | The failure-report's own ID |

### `FAILURECODE`

The failure taxonomy — a tree of PROBLEM, CAUSE, and REMEDY nodes.

| Column | Type | Notes |
|---|---|---|
| `FAILURECODE` | STRING | Code identifier |
| `DESCRIPTION` | STRING | Free-text description |
| `PARENT` | STRING | Parent code (tree structure) |
| `TYPE` | STRING | `PROBLEM`, `CAUSE`, or `REMEDY` |

**Cardinality**: Failures form a tree. Aggregation requires flattening to a fixed depth or pinning to a `TYPE`.

### `PM`

Preventive maintenance master.

| Column | Type | Notes |
|---|---|---|
| `PMNUM` | STRING | PM identifier |
| `SITEID` | STRING | Composite with PMNUM |
| `ASSETNUM` | STRING | Target asset |
| `JPNUM` | STRING | Template (FK to JOBPLAN) |
| `STATUS` | STRING | Only `ACTIVE` PMs generate WOs. Other states (DRAFT, INACTIVE) sit in the table |
| `FREQUENCY` | INT | Interval value |
| `FREQUNIT` | STRING | `DAYS`, `HOURS`, `MILES`, `READINGS`. Note: physical column is `FREQUNIT` (not `FREQUENCYUNITS`) |
| `NEXTDATE` | TIMESTAMP | Calculated next due date |
| `EXTDATE` | TIMESTAMP | **One-time override** that supersedes `NEXTDATE`. Auto-clears after WO generation. Use `COALESCE(EXTDATE, NEXTDATE)` for the effective due date |
| `USETARGETDATE` | BOOLEAN | `TRUE` = fixed schedule (anchor on `LASTSTARTDATE`), `FALSE` = floating (anchor on `LASTCOMPDATE`) |
| `LASTSTARTDATE` | TIMESTAMP | Last generation start (anchor for fixed schedules) |
| `LASTCOMPDATE` | TIMESTAMP | Last completion (anchor for floating schedules) |
| `ALERTLEAD` | INT | Days before NEXTDATE to alert / generate WO |
| `PARENT` | STRING | Parent PM if this PM is in a hierarchy. Prefer `PMANCESTOR` over naive PARENT self-join for hierarchy traversal |

### `PMANCESTOR` — PM hierarchy closure table (IBM-canonical)

The PMANCESTOR table is a **closure table** for the PM hierarchy: one row per (ancestor, descendant) pair across all depths. Required for correct hierarchical roll-ups when WOs are generated against descendant PMs.

| Column | Notes |
|---|---|
| `PMNUM` | The descendant PM (part of the key) |
| `ANCESTOR` | An ancestor PMNUM at any depth (part of the key) |
| `HIERARCHYLEVELS` | Number of levels between the ancestor and descendant |
| `SITEID` | Site scope; ancestor and descendant share the same `SITEID` |

The ancestor is identified by `ANCESTOR` within the same `SITEID` (there is no separate ancestor-site column). A naive `PM.PARENT` self-join misses indirect ancestors. Always use `PMANCESTOR` for hierarchy queries.

### `PMSEQUENCE`

PM step sequences (rare for analytics — most queries hit `PM` directly).

### `ASSETMETER` and `METERREADING`

Condition-monitoring meters per asset.

`ASSETMETER` defines the meter contract:

| Column | Notes |
|---|---|
| `ASSETNUM` + `SITEID` + `METERNAME` | Composite key |
| `LASTREADING` | Most recent reading value |
| `LASTREADINGDATE` | When most recent reading was taken |
| `AVERAGE` | **Maximo-computed rolling average meter-units per day**. Used in meter-based PM forecasting (the PM interval lives on `PMMETER.FREQUENCY`, not here — see `maximo-pm-planning`). Can be NULL / zero for new meters |

Note: the meter *type* (`CONTINUOUS`/`GAUGE`/`CHARACTERISTIC`) is a property of the meter master `METER` (joined via `METERNAME`), **not** a column on `ASSETMETER`. And `ASSETMETER` has **no** warning/action-limit columns — Condition Monitoring limits live on `MEASUREPOINT` as `LOWERWARNING`/`UPPERWARNING`/`LOWERACTION`/`UPPERACTION`.

`METERREADING` is the time-series: append-only readings against meters.

For meter-driven failure prediction or threshold-exceedance analysis, compare `METERREADING` values against the Condition Monitoring limits on `MEASUREPOINT` (`LOWERWARNING`/`UPPERWARNING`/`LOWERACTION`/`UPPERACTION`) — for that analysis defer to `maximo-integrity`.

## Cardinality summary (reliability-specific)

| Relationship | Cardinality |
|---|---|
| `WORKORDER` → `FAILUREREPORT` | 1 : 0..N |
| `FAILUREREPORT` → `FAILURECODE` | N : 1 |
| `FAILURECODE` → `FAILURECODE` (tree) | self via `PARENT` |
| `ASSET` → `PM` | 1 : N |
| `PM` → `PM` (parent/child) | self-join via `PARENT` OR closure via `PMANCESTOR` |
| `PMANCESTOR` (ancestor) → `PM` | 1 : N (transitive closure) |
| `ASSET` → `ASSETMETER` | 1 : N |
| `ASSETMETER` → `METERREADING` | 1 : N |
