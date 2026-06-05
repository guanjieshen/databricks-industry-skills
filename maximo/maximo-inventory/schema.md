# Maximo Inventory — Schema Reference

For the universal Maximo schema and mechanics (composite `SITEID` keys,
status-is-a-synonym-domain / `SYNONYMDOMAIN`, `HISTORYFLAG`, app-server-timezone
datetimes), see `maximo-overview`. This file focuses on the inventory module's
tables and joins.

## Contents
- `ITEM` — global item master
- `INVENTORY` — per-(item, storeroom) master record
- `INVBALANCES` — current quantities per bin/lot
- `INVCOST` — cost data per (item, storeroom)
- `MATUSETRANS` — material usage transactions
- `MATRECTRANS` — material receipt transactions
- `INVRESERVE` — current reservations
- `ITEMSTRUCT` — item assembly structure
- `LOCATIONS` (filtered to storerooms)
- Cardinality summary

## `ITEM` — global item master

One row per distinct item code, regardless of where stocked. The catalog.

| Column | Notes |
|---|---|
| `ITEMNUM` | Business key (the part number) |
| `ITEMSETID` | Item-set identifier — items belong to item sets that span sites |
| `DESCRIPTION` | Item description |
| `COMMODITY` / `COMMODITYGROUP` | Item categorization (often used for ABC analysis) |
| `STATUS` | Synonym domain `ITEMSTATUS` (`ACTIVE`, `PENDING`, `OBSOLETE`) — stores the renamable synonym `VALUE`; resolve via `SYNONYMDOMAIN`. Only `ACTIVE` items can be issued |
| `ITEMTYPE` | `ITEM`, `SERVICE`, `TOOL`, `STDSERVICE` |
| `ROTATING` | `1` if the item is rotating (tracked by serial number with maintenance history) |
| `STOCKEDITEM` | `1` if stocked in inventory; `0` for direct-buy items |
| `ORDERUNIT` / `ISSUEUNIT` | Default UoMs (purchase vs issue) |

## `INVENTORY` — per-(item, storeroom) master record

One row per (`ITEMNUM`, `LOCATION`, `SITEID`). Holds reorder rules and ABC class per storeroom — same item in two storerooms is two `INVENTORY` rows.

| Column | Notes |
|---|---|
| `ITEMNUM` | FK to ITEM |
| `LOCATION` | FK to LOCATIONS (must be `TYPE = 'STOREROOM'`) |
| `SITEID` | Composite key |
| `ITEMSETID` | Composite with ITEMNUM |
| `BINNUM` | Default bin location within the storeroom |
| `REORDERPOINT` | Stock level that triggers a reorder alert |
| `MAXLEVEL` | Maximum stocking level |
| `MINLEVEL` | Minimum level (often = reorder point) |
| `ORDERQTY` | Default order quantity when reordering |
| `LEADTIME` | Days to receive after order |
| `ABCTYPE` | ABC classification (`A`, `B`, `C`) — customer-defined; usually cost × velocity ranking |
| `COSTMETHOD` | `AVERAGE`, `FIFO`, `LIFO`, `STANDARD` — customer-configured per item |
| `STATUS` | Synonym domain `INVSTATUS` (`ACTIVE`, `INACTIVE`, `OBSOLETE`, `PLANNING`) — stores the renamable synonym `VALUE`; resolve via `SYNONYMDOMAIN` |
| `VENDOR` | Default supplier (FK to COMPANIES) |
| `LASTISSUEDATE` | Most recent issue (denormalized for dead-stock queries) |

## `INVBALANCES` — current quantities per bin/lot

One row per (item, storeroom, bin, lot). Current state.

| Column | Notes |
|---|---|
| `ITEMNUM` | FK to ITEM |
| `LOCATION` | FK to LOCATIONS / INVENTORY |
| `SITEID` | Composite |
| `BINNUM` | Bin location |
| `LOTNUM` | Lot number (NULL if not lot-tracked) |
| `CURBAL` | Current quantity on hand |
| `RESERVEDQTY` | Quantity reserved against future WOs |
| `STAGINGBIN` | `1` if this is a staging bin (in-transit) |
| `CONDITIONCODE` | Condition (NEW, REPAIRED, etc.) — for rotating items |

Derived: **`AVAILABLE = CURBAL - RESERVEDQTY`**. Always subtract reservations for "really available".

## `INVCOST` — cost data per (item, storeroom)

| Column | Notes |
|---|---|
| `ITEMNUM` | FK to ITEM |
| `LOCATION` | FK to LOCATIONS |
| `SITEID` | Composite |
| `AVGCOST` | Maximo-computed rolling average cost |
| `LASTCOST` | Cost of most recent receipt |
| `STDCOST` | Standard cost (if using STANDARD costing method) |
| `CURRENCYCODE` | Currency — summing value across differing currencies is meaningless; defer multi-currency normalization to `maximo-maintenance-cost` |

## `MATUSETRANS` — material usage transactions

Append-only log of every material movement (issue, transfer, return, adjustment).

| Column | Notes |
|---|---|
| `MATUSETRANSID` | Surrogate key |
| `ITEMNUM` | The item moved |
| `LOCATION` | Source storeroom |
| `SITEID` | Composite |
| `WONUM` | FK to WORKORDER (if issued to a WO) |
| `QUANTITY` | Quantity moved (negative for adjustments-down or returns) |
| `LINECOST` | Cost of this transaction at the time it happened |
| `ISSUETYPE` | `ISSUE`, `TRANSFER`, `RETURN`, `ADJUSTMENT` |
| `TRANSDATE` | When the transaction happened — app-server-timezone, not per-row UTC (see `maximo-overview`); don't assume UTC when bucketing across sites |
| `CONDITIONCODE` | For rotating items |
| `TOSTOREROOM` / `TOSITEID` | For `TRANSFER` — destination storeroom |

For "consumption" analytics, filter `ISSUETYPE IN ('ISSUE', 'RETURN')` and net them out. Exclude `TRANSFER` (moves between storerooms, doesn't consume).

## `MATRECTRANS` — material receipt transactions

Append-only log of receipts (against POs or transfers in).

| Column | Notes |
|---|---|
| `MATRECTRANSID` | Surrogate key |
| `ITEMNUM` | The item received |
| `TOSTOREROOM` / `TOSITEID` | Destination |
| `QUANTITY` | Quantity received |
| `LINECOST` | Cost of this receipt |
| `RECEIPTREF` | FK to receipt header (RECEIPT or PO line) |
| `TRANSDATE` | When received |

## `INVRESERVE` — current reservations

Items committed to future WOs. The `RESERVEDQTY` on `INVBALANCES` aggregates these.

| Column | Notes |
|---|---|
| `INVRESERVEID` | Surrogate |
| `ITEMNUM` / `LOCATION` / `SITEID` | What's reserved |
| `WONUM` | Which WO it's reserved for |
| `RESERVEDQTY` | Quantity reserved |
| `REQUIREDDATE` | When the WO needs it |

## `ITEMSTRUCT` — item assembly structure

Parent/child relationship — a kit (`PARENT` item) is composed of multiple component items. When you issue the kit, you implicitly consume the components.

| Column | Notes |
|---|---|
| `PARENT` | Parent ITEMNUM (the kit) |
| `ITEMNUM` | Child component |
| `QTY` | How many of the child are in one parent |
| `UNITCOST` | Component cost contribution |

If the customer's `MATUSETRANS` denormalizes kit issues (records the components, not the kit), you'd double-count by joining `ITEMSTRUCT`. Verify the ingestion convention.

## `LOCATIONS` (filtered to storerooms)

Inventory only lives in `LOCATIONS` rows where `TYPE = 'STOREROOM'`. Other location types (`OPERATING`, `LABOR`, `COURIER`, etc.) never hold inventory.

## Cardinality summary

| Relationship | Cardinality |
|---|---|
| `ITEM` → `INVENTORY` | 1 : N (one per storeroom that stocks it) |
| `INVENTORY` → `INVBALANCES` | 1 : N (one per bin/lot) |
| `INVENTORY` → `INVCOST` | 1 : 1 (or 1 : 0 if cost not populated) |
| `INVENTORY` → `MATUSETRANS` | 1 : N (append-only log) |
| `INVENTORY` → `INVRESERVE` | 1 : N (one per WO reservation) |
| `ITEM` → `ITEMSTRUCT` (as PARENT) | 1 : N (kit components) |
| `WORKORDER` → `MATUSETRANS` | 1 : N (via WONUM) |
| `WORKORDER` → `WPMATERIAL` | 1 : N (planned materials — lives in `maximo-work-orders` schema) |
