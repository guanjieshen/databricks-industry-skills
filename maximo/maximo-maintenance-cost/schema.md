# Maximo Maintenance Cost — Schema Reference

For the universal Maximo schema (WORKORDER, ASSET, LOCATIONS), see `maximo-overview`. This skill focuses on the columns and tables that contribute to maintenance cost analytics.

## `WORKORDER` cost columns (header-level)

| Column | Type | Notes |
|---|---|---|
| `ESTLABCOST` | DECIMAL | Estimated labor cost (from WPLABOR rollup at plan time) |
| `ESTMATCOST` | DECIMAL | Estimated material cost (from WPMATERIAL rollup) |
| `ESTSERVCOST` | DECIMAL | Estimated contracted-service cost |
| `ESTTOOLCOST` | DECIMAL | Estimated tool cost |
| `ACTLABCOST` | DECIMAL | Actual labor cost (rolls up LABTRANS at WO close) |
| `ACTMATCOST` | DECIMAL | Actual material cost (rolls up MATUSETRANS at WO close) |
| `ACTSERVCOST` | DECIMAL | Actual contracted-service cost |
| `ACTTOOLCOST` | DECIMAL | Actual tool cost |
| `WOCURRENCY` | STRING | Currency code — may vary across sites |
| `CHARGEACCT` | STRING | GL charge account (customer-specific format) |
| `WORKTYPE` | STRING | Customer-configured business categorization (`CM`, `PM`, `EM`, `PROJ`, etc.) |
| `PMNUM` | STRING | NULL for non-PM WOs; populated for PM-generated WOs |

**Best practice for "total cost on a WO"**:
```sql
COALESCE(actlabcost, 0) + COALESCE(actmatcost, 0)
  + COALESCE(actservcost, 0) + COALESCE(acttoolcost, 0) AS total_actual_cost
```

## `LABTRANS` — labor transactions

Granular labor cost source. Each row is one craft-hour booked.

| Column | Notes |
|---|---|
| `WONUM` / `SITEID` | FK to WORKORDER |
| `LABORCODE` | The person who logged this labor (FK to LABOR) |
| `CRAFT` | Craft code (e.g. `ELEC`, `MECH`, `INST`) |
| `REGULARHRS` | Hours at regular rate |
| `PREMIUMPAYHOURS` | Overtime / premium hours |
| `PAYRATE` | Pay rate at time of transaction |
| `PREMIUMPAYRATE` | Premium rate at time of transaction |
| `LINECOST` | Total cost of this transaction (`regularhrs × payrate + premiumpayhours × premiumpayrate`) |
| `TRANSTYPE` | `WORK`, `TRAVEL` |

For granular cost analytics, sum `LABTRANS.LINECOST` rather than relying on `WORKORDER.ACTLABCOST`. The header value can settle post-close-adjustments.

## `MATUSETRANS` — material transactions (cost side)

Same table as referenced in `maximo-inventory`. For cost, the relevant columns:

| Column | Notes |
|---|---|
| `WONUM` / `SITEID` | FK to WORKORDER |
| `ITEMNUM` | Item issued |
| `QUANTITY` | Quantity issued |
| `LINECOST` | Cost at issue time (uses `INVCOST.AVGCOST` / standard cost / FIFO/LIFO per `INVENTORY.COSTMETHOD`) |
| `ISSUETYPE` | `ISSUE`, `TRANSFER`, `RETURN`, `ADJUSTMENT` |
| `TRANSDATE` | When |

For cost analytics, filter `ISSUETYPE IN ('ISSUE', 'RETURN')` and net them (return is a credit).

## `WPLABOR` / `WPMATERIAL` — planned (estimate) lines

For variance analysis (estimate vs actual):

| Table | Key columns |
|---|---|
| `WPLABOR` | `WONUM`, `SITEID`, `CRAFT`, `LABORHRS`, `LINECOST` (planned labor cost) |
| `WPMATERIAL` | `WONUM`, `SITEID`, `ITEMNUM`, `ITEMQTY`, `LINECOST` (planned material cost) |

These exist when the WO has been planned. Compare `SUM(WPLABOR.LINECOST)` vs `SUM(LABTRANS.LINECOST)` for variance.

## `COSTHIST` — per-WO cost history (where enabled)

Not all customers populate `COSTHIST`. When present, it logs cost transactions per WO over time (useful for in-flight cost trending). Usually:
- One row per (WO, transaction type, transdate)
- `LINECOST`, `LINECOSTOTHERS`, `LINECOSTHRS`

If absent, use `LABTRANS` + `MATUSETRANS` aggregated.

## `COMPANIES` — vendor / contractor master

Used for "contractor spend" analytics.

| Column | Notes |
|---|---|
| `COMPANY` | Vendor identifier |
| `NAME` | Vendor name |
| `TYPE` | `V` (vendor), `M` (manufacturer), `C` (courier), `I` (internal). Filter `TYPE = 'V'` for external vendors |
| `DISABLED` | `1` if disqualified — disqualified vendors can't have new POs/invoices |
| `LIMIT` | Spending limit per-PO |

To compute contractor spend:
- Find `LABTRANS` rows where `LABORCODE` references a contractor (typically `LABOR.TYPE = 'C'` or similar customer convention)
- Sum `LABTRANS.LINECOST`
- Or join via `WORKORDER.VENDOR` for service-contract work

## `LABOR` — labor master (referenced only)

For full LABOR table documentation (columns, joins, contractor identification patterns), see **[`../maximo-labor-resources/schema.md`](../maximo-labor-resources/schema.md)**. The labor master is the domain of `maximo-labor-resources`; this skill consumes it only for cost attribution.

Quick reference of the columns this skill touches:

| Column | Used for |
|---|---|
| `LABORCODE` | Joining `LABTRANS` to identify the resource that booked hours |
| `VENDOR` | Contractor identification (default `contractor_spend` UDF semantics) |
| `LABORTYPE` | Alternate contractor flag (customer-configurable) |

For analytics that go beyond cost (capacity, qualifications, crew composition), compose with `maximo-labor-resources`.

## Cardinality summary

| Relationship | Cardinality |
|---|---|
| `WORKORDER` → `LABTRANS` | 1 : N |
| `WORKORDER` → `MATUSETRANS` | 1 : N |
| `WORKORDER` → `WPLABOR` | 1 : N |
| `WORKORDER` → `WPMATERIAL` | 1 : N |
| `WORKORDER` → `COSTHIST` | 1 : N (where populated) |
| `LABOR` → `LABTRANS` | 1 : N |
| `LABOR` → `COMPANIES` (via VENDOR) | N : 1 (when contractor labor) |
| `WORKORDER` → `ASSET` | N : 1 (cost attribution to asset) |
| `WORKORDER` → `WORKORDER` (parent/child) | self via `PARENT` (cost does NOT auto-rollup) |
