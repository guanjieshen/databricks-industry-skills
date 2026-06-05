# Reliability — Gotchas

> **Forward-looking PM analytics** (forecasting, planning, JOBPLAN management,
> workload-by-craft) lives in [`../maximo-pm-planning/`](../maximo-pm-planning/).
> This skill covers **backward-looking** PM performance metrics (compliance,
> time-since-last, MTBF, MTTR). Several gotchas below (EXTDATE coalesce,
> USETARGETDATE, ACTIVE filter, PMANCESTOR) apply to both skills — they're
> cross-referenced from `maximo-pm-planning/gotchas.md`.

## Contents

- 1. MTBF and MTTR have specific Maximo O&G definitions
- 2. PM compliance has at least three valid definitions
- 2a. The effective due date is `COALESCE(EXTDATE, NEXTDATE)` — not just `NEXTDATE`
- 2b. Fixed vs floating PMs anchor on different dates
- 2c. Only `ACTIVE`-state PMs forecast
- 2d. PM hierarchy traversal — use `PMANCESTOR`, not naive `PARENT` self-join
- 2e. Meter-based PMs forecast using `ASSETMETER.AVERAGE`
- 2f. The column is `FREQUNIT`, not `FREQUENCYUNITS`
- 3. FAILURECODE hierarchy must be flattened before aggregation
- 4. Failure event timestamp ≠ WO close timestamp
- 5. PM Compliance and "skipped" PMs
- 6. Meter-reading-driven analytics
- 7. "Bad actor" definitions
- 8. Asset class hierarchy uses CLASSSTRUCTUREID, not strings
- 9. SMRP reactive-vs-proactive is a LABOR-HOUR ratio, and corrective ≠ reactive
- 10. Resolve "completed/closed" status via SYNONYMDOMAIN, and watch HISTORYFLAG

These are the definitional traps that cause reliability metrics to be wrong or to drift from what Maximo's own UI shows.

> **Universal mechanics live in `maximo-overview`.** SITEID composite-key joins,
> `WOCLASS = 'WORKORDER'` filtering, `ISTASK` dedup, status-is-a-synonym-domain
> (`SYNONYMDOMAIN`), `HISTORYFLAG`, and app-server-timezone datetimes are taught
> once there. This file APPLIES them in reliability SQL (gotcha 10 below) and
> only authors reliability-specific depth.

## 1. MTBF and MTTR have specific Maximo O&G definitions

There are multiple valid definitions of MTBF in industry:
- **Operational MTBF**: (total operating time) / (number of failures)
- **Inherent MTBF**: design value from manufacturer
- **SMRP MTBF**: number of operating hours divided by number of failures

IBM's Maximo O&G application has its own specific formula displayed in the UI, documented at:
`https://www.ibm.com/support/pages/mttr-and-mtbf-fields-explained-maximo-oil-gas-asset-oil-application`

**The UDFs in `metric_udfs.sql` match the IBM formula.** If you compute MTBF a different way in SQL, the number won't reconcile to Maximo screens, and the reliability engineer will reject the result. Use the UDFs.

## 2. PM compliance has at least three valid definitions

| Definition | Numerator | Denominator |
|---|---|---|
| **SMRP** | PMs completed within 10% tolerance window | PMs scheduled |
| **Strict on-time** | PMs completed by effective due date | PMs with due date in period |
| **Customer-specific** | (varies) | (varies) |

The default in `metric_udfs.sql` is SMRP. If the customer uses a different definition, register a customer-specific UDF alongside (with a customer-prefixed name).

## 2a. The effective due date is `COALESCE(EXTDATE, NEXTDATE)` — not just `NEXTDATE`

This is the single biggest correctness fix for PM compliance queries.

Maximo's `PM.EXTDATE` is a one-time override (the "PM Extended Date") that supersedes `NEXTDATE` and auto-clears after the WO is generated. Maintenance planners use it to legitimately defer a PM. If your compliance query uses only `NEXTDATE`, you'll mis-classify legitimate extensions as overdue.

```sql
-- WRONG (overcounts overdue)
WHERE pm.nextdate < current_date()

-- RIGHT
WHERE COALESCE(pm.extdate, pm.nextdate) < current_date()
```

The shipped `pm_compliance` UDF uses the coalesce. Apply the same pattern to ad-hoc queries.

References:
- IBM PM forecast logic: https://www.ibm.com/docs/en/mas-cd/maximo-manage/continuous-delivery?topic=forecasting-preventive-maintenance-forecast-logic
- IBM Support: PM Extended Date

## 2b. Fixed vs floating PMs anchor on different dates

`PM.USETARGETDATE` is a boolean controlling the schedule type:

| `USETARGETDATE` | Type | Anchor for next-cycle generation |
|---|---|---|
| `TRUE` | **Fixed** schedule | `PM.LASTSTARTDATE` (target date, regardless of when the prior WO actually completed) |
| `FALSE` | **Floating** schedule | `PM.LASTCOMPDATE` (last actual completion) |

For *compliance* analytics, both still compare against `COALESCE(EXTDATE, NEXTDATE)` as the target — the difference matters for *next-cycle forecasting* and for explaining variance when a PM drifts.

If a customer's PM compliance suddenly looks bad on a class of assets, check whether those PMs are floating: a late completion shifts every subsequent target.

## 2c. Only `ACTIVE`-state PMs forecast

`PM.STATUS = 'ACTIVE'` is required for the PM to actually generate WOs. Inactive / draft PMs sit in the table and look schedulable but never produce WOs. The shipped UDF filters to `STATUS = 'ACTIVE'`; ad-hoc queries should too.

## 2d. PM hierarchy traversal — use `PMANCESTOR`, not naive `PARENT` self-join

PMs can be hierarchical (a master PM with child PMs for sub-assets). A naive `WORKORDER.PMNUM = PM.PMNUM` join misses any WO generated against a descendant PM. Use the IBM-canonical **`PMANCESTOR` closure table** — one row per (ancestor, descendant) pair across all depths.

```sql
-- All WOs generated by PM 'PUMP-MASTER-001' or any descendant PM
SELECT w.*
FROM :catalog.:silver_schema.workorder w
JOIN :catalog.:silver_schema.pmancestor pa
    ON pa.pmnum = w.pmnum AND pa.siteid = w.siteid
WHERE pa.ancestor = 'PUMP-MASTER-001'
  AND pa.ancestor_siteid = w.siteid;
```

If the customer's Bronze ingestion didn't materialize `PMANCESTOR`, fall back to a recursive CTE on `PM.PARENT`.

> **Closure-table mechanics in general** (probe-before-use, recursive-CTE fallback, depth caps, self-row conventions) are documented in detail in [`../maximo-asset-hierarchy/gotchas.md`](../maximo-asset-hierarchy/gotchas.md). That skill covers `LOCANCESTOR` and `ASSETANCESTOR` with the same patterns — `PMANCESTOR` is the PM-specific application. Load `maximo-asset-hierarchy` when working with multi-level hierarchies in general.

## 2e. Meter-based PMs forecast using `ASSETMETER.AVERAGE`

Meter-based PMs (e.g. "every 500 operating hours") use the meter's per-day-average to forecast next due date:

```
first_forecast_date ≈ LASTREADINGDATE + (METER_FREQUENCY - LASTREADING) / ASSETMETER.AVERAGE
```

Columns to know:
- `ASSETMETER.AVERAGE` — average meter-units per day (Maximo-computed rolling average)
- `ASSETMETER.LASTREADING` — most recent reading value
- `ASSETMETER.LASTREADINGDATE` — when it was read

`AVERAGE` can be zero or NULL for new meters — return NULL or treat as not-forecastable.

## 2f. The column is `FREQUNIT`, not `FREQUENCYUNITS`

Minor but a real gotcha — some older Maximo docs use `FREQUENCYUNITS` informally. The physical column is `FREQUNIT`. Valid values: `DAYS`, `HOURS`, `MILES`, `READINGS`, etc.

## 3. FAILURECODE hierarchy must be flattened before aggregation

`FAILURECODE` is a tree:
```
PROBLEM: "Bearing failure"
  └─ CAUSE: "Lubrication failure"
       └─ REMEDY: "Replace bearing, audit oil change frequency"
  └─ CAUSE: "Misalignment"
       └─ REMEDY: "Realign, recheck after 30 days"
```

If you `GROUP BY FAILURECODE`, you aggregate at the leaf level — usually too granular. To aggregate by problem category, flatten the tree to the `TYPE = 'PROBLEM'` level first:

```sql
WITH problems AS (
    SELECT failurecode, description AS problem_desc
    FROM failurecode WHERE type = 'PROBLEM'
)
SELECT p.problem_desc, COUNT(*)
FROM failurereport fr
JOIN failurecode fc ON fc.failurecode = fr.failurecode
JOIN problems p ON (
    fc.failurecode = p.failurecode
    OR fc.parent = p.failurecode
    OR fc.parent IN (SELECT failurecode FROM failurecode WHERE parent = p.failurecode)
)
GROUP BY p.problem_desc;
```

For deeper hierarchies, use a recursive CTE.

## 4. Failure event timestamp ≠ WO close timestamp

Reliability metrics anchor on **when the failure occurred**, not when the WO was closed. These differ by hours-to-days. Use the best-available approximation in order of preference:
1. `WORKORDER.ACTSTART` (if recorded) — closest to failure
2. `WORKORDER.REPORTDATE` — when reported (often within minutes of failure)
3. `WORKORDER.ACTFINISH` — last resort; significantly biased toward repair completion

The shipped UDFs use a defensible default (`ACTSTART` if non-null, else `REPORTDATE`).

Two more correctness notes that bite reliability specifically:
- **Datetimes are app-server-timezone, not per-row UTC** (universal — see `maximo-overview`). When bucketing failures by day/week/month across sites, a naive UTC assumption shifts events across day boundaries. Bucket on the same convention everywhere.
- **Edit History can append failure reports / `LABTRANS` to a CLOSED WO.** Those rows can postdate `ACTFINISH`/the close date, so a failure or labor row may legitimately appear "after" the WO closed. Don't drop late-arriving failure rows as errors, and don't assume `MAX(actfinish)` bounds all failure activity.

## 5. PM Compliance and "skipped" PMs

When a PM is skipped (manually disabled, deferred, retired, decommissioned), should it count against compliance? Different organizations answer differently. The shipped UDF includes a `PM.STATUS = 'ACTIVE'` filter to exclude obviously-disabled PMs but does NOT exclude deferrals (`PM.DEFERREDDATE IS NOT NULL`) since deferrals are often legitimate exceptions.

If the customer wants stricter accounting, register a custom variant.

## 6. Meter-reading-driven analytics

`METERREADING` is high-volume — joining it to `WORKORDER` without windowing produces millions of rows. Common pattern: aggregate readings first (daily / weekly), then join to events.

Threshold-exceedance is also customer-specific — `WARNLIMITHI` / `ACTIONLIMITHI` are configurable per meter and may be unset.

## 7. "Bad actor" definitions

Bad-actor analysis has multiple valid definitions:
- Top N by failure count in period
- Top N by total downtime
- Top N by repair cost
- Top N by criticality-weighted failure count

Confirm with the user which they mean. The shipped `bad_actor_assets` example uses failure count, with criticality-weighted variant available.

## 8. Asset class hierarchy uses CLASSSTRUCTUREID, not strings

When the user says "centrifugal pumps", they're using a business-friendly name. The actual filter is `ASSET.CLASSSTRUCTUREID IN (4521, 4522, ...)` — IDs from `CLASSSTRUCTURE`.

Resolve via the workspace glossary skill (`<customer>-maximo-glossary`) if available. Otherwise ASK — don't `WHERE DESCRIPTION LIKE '%pump%'` (catches non-pumps and misses pumps with different naming conventions).

## 9. SMRP reactive-vs-proactive is a LABOR-HOUR ratio, and corrective ≠ reactive

This is the reliability-specific metric trap that the `WORKTYPE`-based shortcut gets wrong.

Per SMRP Best Practices, reactive-vs-proactive and planned-vs-unplanned ratios must be computed on **labor hours** (`LABTRANS.REGULARHRS` + premium hours), **not WO counts**. A single emergency WO can consume more labor than ten routine PMs; counting WOs distorts the ratio.

And **"corrective" is ORTHOGONAL to "reactive":**
- *Corrective* work identified pre-failure from PM/PdM inspection (e.g. "PM found a worn bearing, scheduled a replacement") is **PROACTIVE**.
- Only work done in response to an actual functional failure is **reactive**.
- So `WORKTYPE = 'CM'` (corrective maintenance) is **not** a reactive proxy. Many corrective WOs are proactive. (`maximo-work-orders` gotcha 14 makes the same point from the WO side.)

**Schedule compliance** is measured over the schedule week and **excludes break-in work** (unplanned work that displaced scheduled work). It is often **not derivable from raw MBO** without a planned-flag the customer maintains — surface this to the user (see SKILL.md *Questions to surface first*) rather than fabricating a ratio.

Practical pattern: join `WORKORDER` failure events to `LABTRANS` and sum hours, classifying each WO as reactive/proactive by a customer-confirmed rule (often a `WORKTYPE` set *plus* a failure-report presence test), never by `WORKTYPE` alone.

## 10. Resolve "completed/closed" status via SYNONYMDOMAIN, and watch HISTORYFLAG

Reliability metrics key almost entirely on completed/closed work, so two universal mechanics (owned by `maximo-overview`) matter here more than anywhere:

- **Status is a synonym domain.** `WORKORDER.STATUS` stores the customer-renamable synonym (`VALUE`), not the internal `MAXVALUE` Maximo logic uses. A literal `status IN ('COMP','CLOSE')` silently misses any custom synonyms. Resolve the completed set from `SYNONYMDOMAIN`:

```sql
WHERE w.status IN (
    SELECT value FROM :catalog.:silver_schema.synonymdomain
    WHERE domainid = 'WOSTATUS' AND maxvalue IN ('COMP','CLOSE')
)
```

In stock Maximo internal == external, so literals work until a customer adds synonyms — but the resolved form is always safe. The shipped UDFs/views use literals for readability; harden them with the `SYNONYMDOMAIN` lookup if this deployment has custom WO-status synonyms.

- **`HISTORYFLAG` hides the records reliability needs.** A WO at a final status (`CLOSE`/`CAN`) gets `HISTORYFLAG = 1` and drops out of standard List views (IBM-shipped views filter `HISTORYFLAG = 0`). Since MTBF/MTTR/compliance are computed on closed work, **confirm closed records are even present** in the silver layer before trusting any reliability number — some pipelines mirror the `HISTORYFLAG = 0` filter and silently drop history.

Both are universal — see `maximo-overview`; this section only flags why they bite reliability hardest.
