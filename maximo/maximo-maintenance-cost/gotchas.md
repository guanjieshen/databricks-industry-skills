# Maximo Maintenance Cost — Gotchas

These are the cost-SPECIFIC gotchas. Universal mechanics (SITEID composite keys,
status-as-synonym-domain / `SYNONYMDOMAIN` resolution, HISTORYFLAG, app-server-
timezone datetimes, WOCLASS, ISTASK tasks-vs-child-WOs) are owned by
`maximo-overview` — this file APPLIES them in its SQL and points there, it does
not re-teach them.

## Contents
1. `WORKORDER.ACTLABCOST` vs `SUM(LABTRANS.LINECOST)` — reconcile both
2. Parent / child WO cost rollup is NOT automatic
3. Multi-currency aggregation = wrong number
4. WOs without an asset
5. Labor cost components — decompose for productivity analytics
6. Contractor labor — identification varies by customer
7. Material cost timing vs invoice cost
8. PM-generated vs preventive worktype — NOT the same
9. Closed vs active WO costs — period attribution
10. Estimate vs actual variance — flag NULL estimates
11. Follow-up WO costs do NOT roll up to the originator

## 1. `WORKORDER.ACTLABCOST` vs `SUM(LABTRANS.LINECOST)` — reconcile both

These should match but often don't:

| Source | Behavior |
|---|---|
| `WORKORDER.ACTLABCOST` | Header column; per-record actual. Post-close Edit-History appends may not re-settle the header (ledger F13). |
| `SUM(LABTRANS.LINECOST)` | Granular; always reflects underlying transactions, including any appended after close. |

For **trend / time-series analytics**, prefer `SUM(LABTRANS.LINECOST)` aggregated by `STARTDATE` — gives true period attribution.

For **historical reports against closed WOs**, `WORKORDER.ACTLABCOST` is the customer's audit-of-record number.

If a customer asks "show me the cost of WO-12345" and the two disagree, mention the discrepancy — it's a real data quality signal.

## 2. Parent / child WO cost rollup is NOT automatic

Cost columns post to the record where the work was incurred and do NOT roll up to
the parent automatically (ledger F6). A parent WO does **not** see child-task /
child-WO costs in its `ACTLABCOST` by default, and `ACTTOTALCOST` is non-persistent
(may be missing in silver). If you want "total cost for the WO tree":

```sql
-- Recursive roll-up of cost across parent + all descendants.
-- :siteid scopes the join (PARENT is unique only within SITEID — overview F1).
-- :parent_wonum is the root WO. PARENT is MUTABLE (work packages regroup WOs).
WITH RECURSIVE wo_tree AS (
    SELECT wonum, siteid, parent, actlabcost, actmatcost
    FROM :catalog.:silver_schema.workorder
    WHERE wonum = :parent_wonum AND siteid = :siteid

    UNION ALL

    SELECT w.wonum, w.siteid, w.parent, w.actlabcost, w.actmatcost
    FROM :catalog.:silver_schema.workorder w
    JOIN wo_tree t ON w.parent = t.wonum AND w.siteid = t.siteid
)
SELECT SUM(COALESCE(actlabcost,0) + COALESCE(actmatcost,0)) FROM wo_tree;
```

Or sum `LABTRANS` / `MATUSETRANS` directly across all WONUMs in the tree (more
reliable than header columns). Note: this traverses the `PARENT` hierarchy only —
**follow-up** WOs are in a separate hierarchy and are NOT included (see #11).
`ISTASK` semantics (tasks-within-a-WO vs independently-tracked child WOs) are an
overview/work-orders concept — see overview F5 if you need to separate them.

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

Always check the asset-attribution rate before reporting "cost per asset". Note
the universal filters applied here: `WOCLASS='WORKORDER'` (overview F9), and
`status` resolved via `SYNONYMDOMAIN` rather than literals because status is a
renamable synonym domain (overview F2). Closed WOs carry `HISTORYFLAG=1` and drop
out of IBM-shipped List views — completed cost mostly lives in history, so do NOT
add a `HISTORYFLAG=0` filter here (overview F3):
```sql
SELECT
    COUNT(*) AS total_wos,
    SUM(CASE WHEN assetnum IS NULL THEN 1 ELSE 0 END) AS no_asset_wos,
    SUM(CASE WHEN assetnum IS NULL THEN COALESCE(actlabcost,0) + COALESCE(actmatcost,0) ELSE 0 END) AS no_asset_cost
FROM :catalog.:silver_schema.workorder
WHERE woclass = 'WORKORDER'
  AND status IN (
      SELECT value FROM :catalog.:silver_schema.synonymdomain
      WHERE domainid = 'WOSTATUS' AND maxvalue IN ('COMP','CLOSE')
  );
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

For "what we paid" analytics, use `maximo-procurement` (PO/invoice/vendor). For "what we consumed at standard/avg cost", use this skill.

## 8. PM-generated vs preventive worktype — NOT the same

Two distinct concepts often confused:

| Filter | What it means |
|---|---|
| `WORKORDER.PMNUM IS NOT NULL` | This WO was generated by a PM (source) |
| `WORKORDER.WORKTYPE = 'PM'` | Business categorization of the work (intent) |

A user can manually create a WO with `WORKTYPE = 'PM'` (preventive work, but not auto-generated). Conversely, a WO can be PM-generated but have `WORKTYPE = 'CM'` if the PM produces follow-up corrective work.

The `pm_vs_cm_cost_ratio` UDF uses `PMNUM IS NOT NULL` (source-based). If the customer prefers worktype-based categorization, register a customer-specific UDF.

## 9. Closed vs active WO costs — period attribution

Costs accumulate as transactions are entered. `COMP` (physical work done) ≠ `CLOSE`
(finalization → becomes history); many shops never `CLOSE`, so a `CLOSE`-only filter
undercounts completed cost — key on `COMP`-or-later (overview F8). Also, actual
labor can be appended to a CLOSED WO via Edit History, so `LABTRANS` rows can
postdate `ACTFINISH` (overview F13) — close-date attribution misses them. For
"Q3 spend":
- **Transaction-date attribution** (most common): sum `LABTRANS.LINECOST` (by
  `STARTDATE`) and `MATUSETRANS.LINECOST` (by `TRANSDATE`) where the transaction
  date falls in Q3. Captures Edit-History appends correctly.
- **Close-date attribution**: sum `WORKORDER.ACTLABCOST + ACTMATCOST` where
  `ACTFINISH` falls in Q3.

These produce different numbers, especially for long-running WOs. The shipped views
use transaction-date attribution (defensible default for analytics). Dates are in
the app-server timezone (overview F4) — confirm it before bucketing across sites.

## 10. Estimate vs actual variance — flag NULL estimates

`ESTLABCOST` and `ESTMATCOST` may be NULL or zero when:
- The WO wasn't planned before execution (common for emergency work)
- Planning happened via JOBPLAN reference instead of explicit WPLABOR/WPMATERIAL

A "variance" calculation against NULL/0 estimate produces infinite or NULL — flag and exclude these WOs from variance reports.

## 11. Follow-up WO costs do NOT roll up to the originator

Creating a WO/ticket from an existing record sets the new one to `Follow-up` and
the original to `Originator` (ledger F7). Follow-ups live in SEPARATE hierarchies —
their cost/labor do NOT roll up to the originator, and they are NOT reachable via
`PARENT` (so the gotcha #2 recursion will miss them). This silently undercounts the
true cost of addressing an originating problem.

Trace the relationship via `ORIGRECORDID`/`ORIGRECORDCLASS` on the follow-up, or
the `RELATEDRECORD` table (relationship types `FOLLOWUP` / `ORIGINATOR` / `RELATED`):

```sql
-- Total cost of an originating WO plus all its follow-ups
WITH followups AS (
    SELECT rr.recordkey AS fu_wonum, rr.siteid AS fu_siteid
    FROM :catalog.:silver_schema.relatedrecord rr
    WHERE rr.relatedreckey = :origin_wonum
      AND rr.relatedrecclass = 'WORKORDER'
      AND rr.relatetype = 'FOLLOWUP'
)
SELECT
    SUM(COALESCE(w.actlabcost,0) + COALESCE(w.actmatcost,0)) AS total_incl_followups
FROM :catalog.:silver_schema.workorder w
WHERE (w.wonum = :origin_wonum AND w.siteid = :siteid)
   OR (w.wonum, w.siteid) IN (SELECT fu_wonum, fu_siteid FROM followups);
```

`RELATEDRECORD` column names vary slightly across Maximo versions (`RECORDKEY`/
`RELATEDRECKEY` vs `RECKEY`) — confirm in this deployment before relying on them.
