# Maximo Maintenance Cost — Schema Reference

For the universal Maximo schema (WORKORDER, ASSET, LOCATIONS) and all universal mechanics (SITEID composite keys, status-as-synonym-domain, HISTORYFLAG, app-server-timezone datetimes, WOCLASS, ISTASK), see `maximo-overview`. This skill focuses on the columns and tables that contribute to maintenance cost analytics.

## Contents
- `WORKORDER` cost columns (header-level)
- `LABTRANS` — labor transactions
- `MATUSETRANS` — material transactions (cost side)
- `WPLABOR` / `WPMATERIAL` — planned (estimate) lines
- Per-WO cost-transaction history (LABTRANS / MATUSETRANS / SERVRECTRANS / TOOLTRANS)
- `COMPANIES` — vendor / contractor master
- `LABOR` — labor master (referenced only)
- Cardinality summary

## `WORKORDER` cost columns (header-level)

| Column | Type | Notes |
|---|---|---|
| `ESTLABCOST` | DECIMAL | Estimated labor cost (from WPLABOR rollup at plan time) |
| `ESTMATCOST` | DECIMAL | Estimated material cost (from WPMATERIAL rollup) |
| `ESTSERVCOST` | DECIMAL | Estimated contracted-service cost |
| `ESTTOOLCOST` | DECIMAL | Estimated tool cost |
| `ACTLABCOST` | DECIMAL | Actual labor cost posted to THIS record as LABTRANS rows are entered. Per-record — does NOT auto-roll-up to the parent WO (ledger F6). Can be re-settled by post-close Edit-History appends; reconcile against `SUM(LABTRANS.LINECOST)`. |
| `ACTMATCOST` | DECIMAL | Actual material cost posted to THIS record as MATUSETRANS rows are entered. Per-record — no auto-rollup to parent. |
| `ACTSERVCOST` | DECIMAL | Actual contracted-service cost |
| `ACTTOOLCOST` | DECIMAL | Actual tool cost |
| `ACTTOTALCOST` | DECIMAL | **NON-PERSISTENT (computed)** — sum of the actual cost fields. May be ABSENT in silver (it is not a stored column in stock Maximo). Never depend on it; compute the total from the persisted fields instead (ledger F6, IBM APAR IV13319). |
| `WOCURRENCY` | STRING | Currency code — may vary across sites (ledger F12). Pair with `EXCHANGERATE`. |
| `EXCHANGERATE` | DECIMAL | Exchange rate to base currency at the time costs were captured. |
| `CHARGEACCT` | STRING | GL charge account (customer-specific format; GL integration is out of scope here) |
| `WORKTYPE` | STRING | Customer-configured business categorization (`CM`, `PM`, `EM`, `PROJ`, etc.) — business intent, NOT the PM-generated source flag |
| `PMNUM` | STRING | NULL for non-PM WOs; populated for PM-generated WOs (the source flag) |

**Best practice for "total cost on a WO"** — compute from persisted fields; do NOT
read `ACTTOTALCOST` (non-persistent, may be missing):
```sql
COALESCE(actlabcost, 0) + COALESCE(actmatcost, 0)
  + COALESCE(actservcost, 0) + COALESCE(acttoolcost, 0) AS total_actual_cost
```
This is HEADER cost for THIS WO only. For a WO tree, recurse the hierarchy or
aggregate the transaction tables — header costs do not roll up (see gotchas #2).

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

For granular cost analytics, sum `LABTRANS.LINECOST` rather than relying on `WORKORDER.ACTLABCOST`. Actual labor can be appended to a CLOSED WO via Edit History (ledger F13), so `LABTRANS` rows can postdate `ACTFINISH`/close — `LABTRANS` reflects this, the header may not re-settle. Attribute spend by `LABTRANS.STARTDATE` (app-server timezone — see overview F4), not by close date, for true period consumption.

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

## Per-WO cost-transaction history

There is no stock per-WO cost-history rollup table. The actual WO cost transactions live in the stock transaction tables — `LABTRANS` (labor), `MATUSETRANS` (material), `SERVRECTRANS` (services), and `TOOLTRANS` (tools) — each carrying `LINECOST`. For in-flight cost trending, aggregate these by their transaction dates (`LABTRANS.STARTDATE`, `MATUSETRANS.TRANSDATE`, etc.) rather than assuming a dedicated history table.

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
- Find `LABTRANS` rows where `LABORCODE` references a contractor — identification is customer-specific (`LABOR.VENDOR IS NOT NULL`, or a `LABOR.LABORTYPE` value); confirm via the workspace glossary (see gotchas #6)
- Sum `LABTRANS.LINECOST`
- Or join via `WORKORDER.VENDOR` for service-contract work booked as `ACTSERVCOST`

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
| `LABOR` → `LABTRANS` | 1 : N |
| `LABOR` → `COMPANIES` (via VENDOR) | N : 1 (when contractor labor) |
| `WORKORDER` → `ASSET` | N : 1 (cost attribution to asset) |
| `WORKORDER` → `WORKORDER` (parent/child) | self via `PARENT` (cost does NOT auto-rollup) |
