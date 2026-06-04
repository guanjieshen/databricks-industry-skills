# Maximo Reliability — Schema Reference

For the universal Maximo schema (WORKORDER, ASSET, LOCATIONS), see `maximo-overview/SKILL.md`. This skill focuses on tables specific to reliability metrics.

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
| `FREQUENCY` | INT | Interval value |
| `FREQUNIT` | STRING | `DAYS`, `HOURS`, `MILES`, `READINGS` |
| `NEXTDATE` | TIMESTAMP | Next due date |
| `LASTSTARTDATE` | TIMESTAMP | Last generation date |
| `ALERTLEAD` | INT | Days before NEXTDATE to alert / generate WO |

### `PMSEQUENCE`

PM step sequences (rare for analytics — most queries hit `PM` directly).

### `ASSETMETER` and `METERREADING`

Condition-monitoring meters per asset.

`ASSETMETER` defines: meter name, type (continuous / gauge / characteristic), warn/action thresholds.

`METERREADING` is the time-series: append-only readings against meters.

For meter-driven failure prediction or threshold-exceedance analysis, join `METERREADING` to `ASSETMETER` to compare reading values against `WARNLIMITHI` / `ACTIONLIMITHI` / `WARNLIMITLO` / `ACTIONLIMITLO`.

## Cardinality summary (reliability-specific)

| Relationship | Cardinality |
|---|---|
| `WORKORDER` → `FAILUREREPORT` | 1 : 0..N |
| `FAILUREREPORT` → `FAILURECODE` | N : 1 |
| `FAILURECODE` → `FAILURECODE` (tree) | self via `PARENT` |
| `ASSET` → `PM` | 1 : N |
| `ASSET` → `ASSETMETER` | 1 : N |
| `ASSETMETER` → `METERREADING` | 1 : N |
