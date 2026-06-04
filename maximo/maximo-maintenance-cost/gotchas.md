# Maximo Maintenance Cost — Gotchas

## 1. `WORKORDER.ACTLABCOST` vs `SUM(LABTRANS.LINECOST)` — reconcile both

These should match but often don't:

| Source | Behavior |
|---|---|
| `WORKORDER.ACTLABCOST` | Header column; settles at WO close. Post-close adjustments may not propagate. |
| `SUM(LABTRANS.LINECOST)` | Granular; always reflects underlying transactions. |

For **trend / time-series analytics**, prefer `SUM(LABTRANS.LINECOST)` aggregated by `STARTDATE` — gives true period attribution.

For **historical reports against closed WOs**, `WORKORDER.ACTLABCOST` is the customer's audit-of-record number.

If a customer asks "show me the cost of WO-12345" and the two disagree, mention the discrepancy — it's a real data quality signal.

## 2. Parent / child WO cost rollup is NOT automatic

A parent WO does **not** see child-task costs in its `ACTLABCOST` by default. If you want "total cost for the WO tree":

```sql
-- Recursive roll-up of cost across parent + all descendants
WITH RECURSIVE wo_tree AS (
    SELECT wonum, siteid, parent, actlabcost, actmatcost
    FROM workorder
    WHERE wonum = '{{parent_wonum}}' AND siteid = '{{siteid}}'

    UNION ALL

    SELECT w.wonum, w.siteid, w.parent, w.actlabcost, w.actmatcost
    FROM workorder w
    JOIN wo_tree t ON w.parent = t.wonum AND w.siteid = t.siteid
)
SELECT SUM(actlabcost + actmatcost) FROM wo_tree;
```

Or sum `LABTRANS` / `MATUSETRANS` directly across all WOs in the tree.

## 3. Multi-currency aggregation = wrong number

`WORKORDER.WOCURRENCY` can vary across sites. Summing `LINECOST` across rows in different currencies produces a meaningless number.

Solutions in order of preference:
1. **Normalize at Silver layer** to a single reporting currency (best)
2. **Group by currency** in reports — show `USD: $X, CAD: $Y` separately
3. **Filter to single-currency scope** before summing

The shipped UDFs assume single-currency. Multi-currency customers should register a customer-prefixed UDF that normalizes.

## 4. WOs without an asset (~10-30% at typical customers)

WOs may have `ASSETNUM IS NULL` when:
- Work is location-only (e.g. groundskeeping, building cleaning)
- Cost-center work (e.g. crew shift overhead)
- Generic shop work (e.g. "build a new spare")

For **asset-attributed cost reports**, these WOs are silently excluded. Decide:
- Exclude them and disclose (default behavior of `asset_maintenance_cost` UDF)
- Bucket as "non-asset" and report separately
- Allocate to a parent asset / location based on customer rules

Always check the asset-attribution rate before reporting "cost per asset":
```sql
SELECT
    COUNT(*) AS total_wos,
    SUM(CASE WHEN assetnum IS NULL THEN 1 ELSE 0 END) AS no_asset_wos,
    SUM(CASE WHEN assetnum IS NULL THEN actlabcost + actmatcost ELSE 0 END) AS no_asset_cost
FROM workorder
WHERE woclass = 'WORKORDER' AND status IN ('COMP','CLOSE');
```

## 5. Labor cost components — decompose for productivity analytics

`LABTRANS.LINECOST` is total — includes regular pay + premium pay + travel time. For "labor productivity" or "overtime rate" analytics, decompose:

```sql
SELECT
    laborcode, craft,
    SUM(regularhrs)                                 AS regular_hours,
    SUM(premiumpayhours)                            AS premium_hours,
    SUM(regularhrs * payrate)                       AS regular_cost,
    SUM(premiumpayhours * COALESCE(premiumpayrate, payrate * 1.5)) AS premium_cost,
    SUM(linecost)                                   AS total_cost
FROM labtrans
WHERE transtype = 'WORK'
  AND startdate >= add_months(current_date(), -12)
GROUP BY laborcode, craft;
```

Travel time (`TRANSTYPE = 'TRAVEL'`) is often analyzed separately.

## 6. Contractor labor — identification varies by customer

Maximo doesn't have a single "contractor" flag. Common patterns:
- `LABOR.VENDOR IS NOT NULL` (vendor-supplied labor)
- `LABOR.LABORTYPE` value (`CONTRACTOR`, `VENDOR`, etc. — customer-configured)
- `LABTRANS.LABORCODE` references a synthetic contractor code

Confirm with the workspace glossary. The shipped `contractor_spend` UDF takes the vendor `COMPANY` as input and joins via `LABOR.VENDOR` — adjust if your customer's convention differs.

## 7. Material cost timing vs invoice cost

`MATUSETRANS.LINECOST` is at **issue time**, using `INVCOST.AVGCOST` (or LIFO/FIFO/STANDARD per `INVENTORY.COSTMETHOD`). The actual cost paid to the vendor is on the **invoice side** (procurement module — out of scope here).

These can differ materially when:
- Material price rises between receipt and issue (FIFO/LIFO methods will show this)
- Standard cost is significantly out-of-date
- Returns are valued at a different cost than the original issue

For "what we paid" analytics, use the procurement skill (planned v5). For "what we consumed at standard/avg cost", use this skill.

## 8. PM-generated vs preventive worktype — NOT the same

Two distinct concepts often confused:

| Filter | What it means |
|---|---|
| `WORKORDER.PMNUM IS NOT NULL` | This WO was generated by a PM (source) |
| `WORKORDER.WORKTYPE = 'PM'` | Business categorization of the work (intent) |

A user can manually create a WO with `WORKTYPE = 'PM'` (preventive work, but not auto-generated). Conversely, a WO can be PM-generated but have `WORKTYPE = 'CM'` if the PM produces follow-up corrective work.

The `pm_vs_cm_cost_ratio` UDF uses `PMNUM IS NOT NULL` (source-based). If the customer prefers worktype-based categorization, register a customer-specific UDF.

## 9. Closed vs active WO costs — period attribution

Cost columns continue accumulating until WO is closed. For "Q3 spend":
- **Transaction-date attribution** (most common): sum `LABTRANS.LINECOST` and `MATUSETRANS.LINECOST` where the transaction date falls in Q3
- **Close-date attribution**: sum `WORKORDER.ACTLABCOST + ACTMATCOST` where `ACTFINISH` falls in Q3

These produce different numbers, especially for long-running WOs. The shipped views use transaction-date attribution (defensible default for analytics).

## 10. Estimate vs actual variance — flag NULL estimates

`ESTLABCOST` and `ESTMATCOST` may be NULL or zero when:
- The WO wasn't planned before execution (common for emergency work)
- Planning happened via JOBPLAN reference instead of explicit WPLABOR/WPMATERIAL

A "variance" calculation against NULL/0 estimate produces infinite or NULL — flag and exclude these WOs from variance reports.
