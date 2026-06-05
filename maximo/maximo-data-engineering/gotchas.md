# Silver-Layer Modeling Gotchas

The traps that cause Maximo Silver/Gold layers to be subtly wrong.

> Universal Maximo mechanics — SITEID composite keys, `WOCLASS` filtering,
> `ISTASK` tasks-vs-child-WOs, status-is-a-synonym-domain (`SYNONYMDOMAIN`
> resolution), `HISTORYFLAG`, and app-server-timezone datetimes — are owned by
> `maximo-overview`. This file APPLIES them to the Silver/Gold layer; it does not
> re-teach them. The one rule worth restating for pipeline authors:
> **mirror Bronze in full — never copy Maximo's `HISTORYFLAG = 0` List-view
> filter into Silver.** Closed/cancelled records carry `HISTORYFLAG = 1`; drop
> them and every downstream completion/trend/MTBF metric goes blank. Let
> consumers filter `HISTORYFLAG` per query, not the pipeline.

## Contents

1. WOSTATUS must be APPEND-ONLY, never APPLY CHANGES
2. `WOCLASS` filter belongs at the Silver layer
3. ASSET hierarchy and SCD2
4. METERREADING volume
5. plusg* tables — extension solution joins
6. SCD2 vs SCD1 for master data
7. Multi-currency and units of measure (defer methodology to maximo-maintenance-cost)
8. Don't materialize Gold metric views as Delta tables
9. Test the pipeline on a known-volume Bronze before going live

## 1. WOSTATUS must be APPEND-ONLY, never APPLY CHANGES

`WOSTATUS` is a **transition log** — one row per status change per WO. If you `APPLY CHANGES INTO` keyed by `(WONUM, SITEID)`, you collapse the entire history to one row per WO. This is the single most common modeling error.

```python
# WRONG
dlt.apply_changes(
    target="wostatus",
    source="wostatus_bronze",
    keys=["WONUM", "SITEID"],   # collapses history!
    ...
)

# RIGHT
@dlt.table(name="wostatus")
def wostatus():
    return dlt.read_stream("bronze.wostatus")   # append only
```

If you must dedup at Silver (Bronze has at-least-once duplicates), key on the full row (`WONUM`, `SITEID`, `CHANGEDATE`, `STATUS`), not just `(WONUM, SITEID)`.

## 2. `WOCLASS` filter belongs at the Silver layer

`WORKORDER` holds five different record classes (`WORKORDER`, `PM`, `CHANGE`, `RELEASE`, `ACTIVITY`). Putting the `WHERE WOCLASS = 'WORKORDER'` filter in every consuming query is leaky — eventually someone forgets and gets wrong counts.

Build two Silver tables:
- `silver.workorder` — pre-filtered to `WOCLASS = 'WORKORDER'`. This is what 95% of queries use.
- `silver.workorder_all_classes` — full table for the rare query that needs PM/CHANGE/RELEASE/ACTIVITY.

## 3. ASSET hierarchy and SCD2

`ASSET` is naturally SCD2 — assets change attributes (criticality, manufacturer, parent) over their decades-long lifetime, and reliability/integrity analytics care about WHAT the asset was at the time of a failure event.

When joining a Gold view to ASSET, the example views in `gold_views.sql` (e.g. `v_failure_events`) filter to `a.__END_AT IS NULL` for current state. For time-travel queries (what was the criticality on the day of the failure?), use a range join against `__START_AT` / `__END_AT`.

## 4. METERREADING volume

`METERREADING` is high-volume in any non-trivial deployment (every meter reading on every asset, often sub-hourly). Append-only streaming is correct, but:

- Partition by `READINGDATE` at Silver for downstream pruning
- Consider a Gold rollup table (`v_meter_daily`) for any dashboard that aggregates by day — recomputing from raw at query time is expensive

## 5. plusg* tables — extension solution joins

The PLUSG O&G tables join to standard Maximo tables via the standard keys (`WONUM`, `SITEID`; `ASSETNUM`, `SITEID`; etc.). Don't forget to include them in Silver if customer uses the O&G industry solution — the HSE skill depends on them.

If the customer is on classic Maximo without PLUSG, simply omit these tables — no harm.

## 6. SCD2 vs SCD1 for master data

Convention I recommend:
- **SCD2**: ASSET, LOCATIONS, PM, JOBPLAN, ASSETMETER (anything that's referenced historically in analytics)
- **SCD1 with history retained at Bronze**: COMPANIES, LABOR, PERSON, CRAFT (master data that changes rarely and where historical analytics is rarely needed)

If you're not sure, SCD2 is the safer default. Costs more storage but preserves time-travel.

## 7. Multi-currency and units of measure

In multi-site or multi-country deployments, `WORKORDER.WOCURRENCY` / `EXCHANGERATE`
vary across orgs/sites, material costs may be in different units of measure, and
meter readings may use different unit conventions across regions. Summing
`LINECOST` across currencies is meaningless.

**At the Silver/Gold layer, pass cost columns through unmodified** —
`LINECOST`, `WOCURRENCY`, `EXCHANGERATE`, `ACTLABCOST`, `ACTMATCOST`. Do NOT
build currency normalization into this layer. The multi-currency normalization
methodology (and cost rollup, estimate-vs-actual variance, contractor spend) is
owned by **`maximo-maintenance-cost`** — defer to it rather than re-implementing
a conversion here, so the normalization is consistent across all consumers.

If you must surface a unit/currency-aware default, expose `WOCURRENCY` alongside
the raw cost so downstream skills can group correctly.

## 8. Don't materialize Gold metric views as Delta tables

`v_failure_events`, `v_pm_schedule`, and the module-owned Gold views should be views, not materialized tables. Why:
- They're recomputed cheaply at query time over the (already-incremental) Silver streaming tables
- Materializing them creates staleness windows
- AI/BI dashboards and Genie Spaces hit them millions of times — the cost of materializing isn't worth the staleness risk

If a specific view becomes expensive (millions of rows × heavy joins), promote that one to a materialized view with refresh cadence — but not by default.

## 9. Test the pipeline on a known-volume Bronze before going live

Before exposing Silver to downstream consumers:
1. Run the pipeline on a Bronze snapshot of known row counts.
2. Validate every Silver table row count against expectations:
   - `WORKORDER` Silver = Bronze `WORKORDER` rows filtered to `WOCLASS='WORKORDER'`
   - `WOSTATUS` Silver = Bronze `WOSTATUS` rows (append, should match)
   - ASSET Silver count = current-state ASSET rows in Bronze
3. Spot-check 5–10 WOs end-to-end across the join chain.

This catches the "WOSTATUS got collapsed via apply-changes" bug before it ships.
