# Maximo PM Planning — Gotchas

## 1. PMs vs the WOs they generate

The single most important distinction in this skill:

| Concept | Maximo object | Time orientation |
|---|---|---|
| The **schedule** | `PM` (and `PMSEQUENCE` for multi-cadence) | Forward — `NEXTDATE` is the next instance |
| The **instance** | `WORKORDER` where `PMNUM IS NOT NULL` | Backward — when the schedule fired |

For **forecasting**: query `PM` against `COALESCE(EXTDATE, NEXTDATE)`.

For **historical execution / compliance**: query `WORKORDER` filtered by `PMNUM IS NOT NULL` (lives in `maximo-reliability`).

Never use a single query to do both — it gets confusing fast.

## 2. Multi-frequency PMs use `PMSEQUENCE` — expand before counting

The same PM can produce multiple work cadences. A pump PM might do 30-day lube + 90-day inspection + 365-day rebuild, all from one PM row with three `PMSEQUENCE` rows.

A naive `COUNT(*) FROM PM` undercounts the actual workload produced. Always expand:

```sql
-- Each sequence is a separate forecast row
SELECT pm.pmnum, pm.siteid,
       COALESCE(seq.jpnum, pm.jpnum) AS effective_jpnum,
       COALESCE(seq.frequency, pm.frequency) AS effective_frequency,
       COALESCE(seq.frequnit, pm.frequnit)   AS effective_frequnit
FROM pm
LEFT JOIN pmsequence seq ON seq.pmnum = pm.pmnum AND seq.siteid = pm.siteid
WHERE pm.__END_AT IS NULL AND pm.status = 'ACTIVE';
```

For PMs without sequences, the `pm` row itself is the single cadence (LEFT JOIN preserves it).

## 3. `COALESCE(EXTDATE, NEXTDATE)` — same gotcha as reliability

The PM Extended Date overrides Next Due Date. See [`../maximo-reliability/gotchas.md`](../maximo-reliability/gotchas.md) gotcha 2a for the full explanation. For forecasting, **always** use `COALESCE(EXTDATE, NEXTDATE)` as the effective due date.

## 4. Only `STATUS = 'ACTIVE'` PMs generate work

`DRAFT`, `INACTIVE`, and `PENDING` PMs sit in the table but don't fire. Filter `WHERE pm.status = 'ACTIVE'` for forecast queries.

## 5. Fixed vs floating affects forecast accuracy

`PM.USETARGETDATE`:
- **TRUE (fixed)**: anchor on `LASTSTARTDATE` — next due = anchor + frequency
- **FALSE (floating)**: anchor on `LASTCOMPDATE` — next due = anchor + frequency

For forecast queries, the `NEXTDATE` is already calculated by Maximo using the right anchor — you just consume it. But when **predicting** the next-next due date, the anchor matters. See [`../maximo-reliability/gotchas.md`](../maximo-reliability/gotchas.md) gotcha 2b.

## 6. `ALERTLEAD` generates WOs ahead of `NEXTDATE`

`PM.ALERTLEAD` specifies how many days before `NEXTDATE` the WO is auto-generated. A PM with `ALERTLEAD = 14` will produce its WO 14 days before its `NEXTDATE`.

For "due soon" buckets:
- "Due in next 30 days" includes PMs with `ALERTLEAD >= effective_due - current_date + (30 - alertlead)` — complicated. Easier: report against `NEXTDATE` directly, and separately surface WOs in `WAPPR` status that the planner needs to action.

```sql
-- Forecast PMs effectively due in next 30 days, accounting for ALERTLEAD
SELECT *
FROM pm
WHERE status = 'ACTIVE'
  AND COALESCE(extdate, nextdate)
        BETWEEN current_date()
            AND current_date() + INTERVAL 30 DAY
            + INTERVAL '1' DAY * COALESCE(alertlead, 0);
```

## 7. Customer-specific tolerance windows

Customers use different tolerances for "on-time" classification:
- SMRP standard: 10% of frequency
- Strict: 0 days (must be on or before NEXTDATE)
- Custom: fixed days regardless of frequency

The shipped views use **due-bucket** classification (OVERDUE / DUE_30D / DUE_90D / FUTURE) which is tolerance-independent. If the customer wants on-time compliance bucketing, register a customer-specific view.

## 8. Meter-based PM forecasts depend on `ASSETMETER.AVERAGE`

For meter-based PMs (frequency in HOURS, MILES, READINGS), forecasting uses:

```
forecast_next_due ≈ LASTREADINGDATE + (FREQUENCY - LASTREADING) / AVERAGE
```

`ASSETMETER.AVERAGE` is a Maximo-computed rolling per-day rate. If it's NULL or 0 (new meter, no usage history), the forecast is unknowable — return NULL.

The shipped `meter_based_pm_forecast` UDF handles this. Don't bake assumptions about non-zero averages into custom queries.

## 9. Resource capacity tables are often half-populated

`CALENDAR` / `WORKPERIOD` define crew availability. In real customer data, they're often:
- Populated for the current year but not future years
- Populated at a generic site level but missing per-crew calendars
- Out-of-date (last year's holidays, not this year's)

Always check coverage before claiming workload-vs-capacity:

```sql
-- Does the customer have populated capacity for the forecast window?
SELECT calnum, MIN(startdate), MAX(startdate)
FROM workperiod
GROUP BY calnum;
```

If coverage is sparse, present forecast workload alone (without capacity comparison) and tell the user why.

## 10. JOBPLAN can be shared across many PMs

The same JOBPLAN can be referenced by many PMs. When summing planned labor for "all PMs in the next 30 days":

```sql
-- Per-PM × JOBPLAN labor expansion
SELECT
    pm.pmnum,
    jpl.craft,
    jpl.laborhrs                  AS labor_hours_per_instance
FROM pm
JOIN jplabor jpl ON jpl.jpnum = pm.jpnum AND jpl.orgid = pm.orgid
WHERE pm.status = 'ACTIVE'
  AND COALESCE(pm.extdate, pm.nextdate) BETWEEN current_date() AND current_date() + INTERVAL 30 DAY;
```

For "JOBPLAN edit impact" analysis ("if I change `JP-PUMP-3MO` labor hours, what PMs are affected?"), GROUP BY `JPNUM`:

```sql
SELECT pm.jpnum, COUNT(*) AS pm_count, COUNT(DISTINCT pm.assetnum) AS distinct_assets
FROM pm
WHERE pm.__END_AT IS NULL AND pm.status = 'ACTIVE'
GROUP BY pm.jpnum
ORDER BY pm_count DESC;
```
