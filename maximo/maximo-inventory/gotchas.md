# Maximo Inventory — Gotchas

Domain-specific inventory traps. The universal Maximo mechanics — composite
`SITEID` keys, status-is-a-synonym-domain / `SYNONYMDOMAIN` resolution,
`HISTORYFLAG` hiding closed records, and app-server-timezone datetimes — are
owned by `maximo-overview`; this file applies them to the inventory tables
rather than re-teaching them.

## Contents
1. `INVENTORY` vs `INVBALANCES` — master vs current quantity
2. `AVAILABLE = CURBAL - RESERVEDQTY`
3. Multi-storeroom inventory — sum across, or filter to one
4. Costing methods vary per item — don't naively average costs
5. Issue types — `ISSUETYPE` discriminates `MATUSETRANS` rows
6. Unit-of-measure conversions are silent
7. Kit issues (`ITEMSTRUCT`) — don't double-count
8. Only storeroom locations hold inventory
9. Status columns are synonym domains (`ITEMSTATUS`, `INVSTATUS`)
10. Obsolete items still appear in `INVBALANCES`
11. Rotating items have their own quirks
12. Reservations & open WOs — apply WO status/HISTORYFLAG correctly
13. Movement bucketing uses app-server-timezone datetimes

## 1. `INVENTORY` vs `INVBALANCES` — master vs current quantity

The single most common confusion in inventory analytics.

| Table | What it holds | Grain |
|---|---|---|
| `INVENTORY` | Master record per (item, storeroom). Reorder rules, ABC class, costing method | 1 row per (`ITEMNUM`, `LOCATION`, `SITEID`) |
| `INVBALANCES` | Current quantity (on-hand, reserved) | N rows per `INVENTORY` row — one per bin/lot |

```sql
-- "How much of ITEM-X is in MAIN-STORE?"
-- WRONG (returns the master row, not the quantity):
SELECT * FROM INVENTORY WHERE itemnum = 'ITEM-X' AND location = 'MAIN-STORE';

-- RIGHT:
SELECT SUM(curbal) FROM INVBALANCES
WHERE itemnum = 'ITEM-X' AND location = 'MAIN-STORE' AND siteid = 'BEDFORD';
```

(`LOCATION` is unique only within `SITEID` — always carry `SITEID` in the
join/filter. Universal gotcha, see `maximo-overview`.)

## 2. `AVAILABLE = CURBAL - RESERVEDQTY`

`INVBALANCES.CURBAL` includes reserved stock. If you ask "is item X available", you must subtract reservations:

```sql
SELECT itemnum, location, SUM(curbal) AS on_hand, SUM(reservedqty) AS reserved,
       SUM(curbal) - SUM(reservedqty) AS available
FROM INVBALANCES
WHERE itemnum = 'ITEM-X'
GROUP BY itemnum, location;
```

The shipped `item_on_hand` UDF subtracts reservations by default. Use it.

## 3. Multi-storeroom inventory — sum across, or filter to one

Same item exists in multiple `INVENTORY` rows (one per storeroom). Decide intent:

```sql
-- "Total on-hand across all storerooms"
SELECT SUM(curbal) FROM INVBALANCES WHERE itemnum = 'ITEM-X';

-- "On-hand at the West storeroom"
SELECT SUM(curbal) FROM INVBALANCES
WHERE itemnum = 'ITEM-X' AND location = 'ZONE-W';
```

Watch for `SITEID` too in multi-site customers — the same `LOCATION` code can
recur at different sites.

## 4. Costing methods vary per item — don't naively average costs

`INVENTORY.COSTMETHOD` is set per item per storeroom. Different items use different methods:

| Method | Meaning |
|---|---|
| `AVERAGE` | Rolling average cost based on receipts. Default in many setups. |
| `FIFO` / `LIFO` | First-in-first-out / Last-in-first-out — cost of issue depends on receipt order |
| `STANDARD` | Pre-set standard cost; variances accumulated separately |

For "total inventory value", use the cost method's relevant `INVCOST` column:

```sql
-- Approximate inventory carrying value
SELECT b.itemnum, b.location, SUM(b.curbal) AS qty,
       CASE i.costmethod
            WHEN 'STANDARD' THEN c.stdcost
            WHEN 'LIFO'     THEN c.lastcost
            ELSE                 c.avgcost
       END AS unit_cost,
       SUM(b.curbal) * (CASE i.costmethod
            WHEN 'STANDARD' THEN c.stdcost
            WHEN 'LIFO'     THEN c.lastcost
            ELSE                 c.avgcost
       END) AS approx_value
FROM INVBALANCES b
JOIN INVENTORY i USING (itemnum, location, siteid)
JOIN INVCOST   c USING (itemnum, location, siteid)
GROUP BY b.itemnum, b.location, i.costmethod, c.stdcost, c.avgcost, c.lastcost;
```

This is an *approximate physical-carrying* value. Anything beyond it — summing
across currencies (`INVCOST.CURRENCYCODE` varies by org/site), GL impact, or
PM-vs-CM material spend — belongs to `maximo-maintenance-cost`; don't sum
`LINECOST`/cost across currencies here.

## 5. Issue types — `ISSUETYPE` discriminates `MATUSETRANS` rows

| `ISSUETYPE` | Effect on on-hand |
|---|---|
| `ISSUE` | Decreases on-hand at source storeroom |
| `RETURN` | Increases on-hand at source storeroom (issued part returned unused) |
| `TRANSFER` | Decreases at source, increases at destination (`TOSTOREROOM`) |
| `ADJUSTMENT` | Manual correction — could be either direction |

**For "consumption" or "usage" analytics, filter `ISSUETYPE IN ('ISSUE', 'RETURN')`** and net them out. Including `TRANSFER` double-counts movements (the destination already has its own `MATRECTRANS` or balance change).

## 6. Unit-of-measure conversions are silent

An item can be:
- Stocked in `ISSUEUNIT = 'EACH'`
- Purchased in `ORDERUNIT = 'CASE'` (where 1 case = 12 each)
- Issued in either depending on the transaction

`MATUSETRANS.QUANTITY` may be in different UoMs across rows. The Maximo UI auto-converts, but raw SQL doesn't. Check `UOMCONVERSION` for the multipliers when an item has multiple UoMs in play.

Symptom: usage numbers are unexpectedly 12× off → check UoMs.

## 7. Kit issues (`ITEMSTRUCT`) — don't double-count

A kit item (e.g. `PUMP-OVERHAUL-KIT`) has child components in `ITEMSTRUCT`. When the kit is issued to a WO:
- Some setups record only the kit issue in `MATUSETRANS`
- Other setups also record each component issue in `MATUSETRANS` (denormalized)

If you `JOIN MATUSETRANS m TO ITEMSTRUCT s ON s.parent = m.itemnum` and the customer is already denormalizing, you'll count each component twice.

Check by looking at a known kit issue: if `MATUSETRANS` already has rows for the children, don't join `ITEMSTRUCT`.

## 8. Only storeroom locations hold inventory

`LOCATIONS` has many types: `OPERATING`, `STOREROOM`, `LABOR`, `COURIER`, `REPAIR`, `SALVAGE`, `VENDOR`. Only `STOREROOM` is real inventory.

```sql
-- Naively joining INVENTORY to LOCATIONS without filtering type pulls in operating locations as if they have inventory.
JOIN LOCATIONS l ON l.location = i.location  -- might match too many
                AND l.siteid   = i.siteid
                AND l.type     = 'STOREROOM' -- always include this
```

## 9. Status columns are synonym domains (`ITEMSTATUS`, `INVSTATUS`)

`ITEM.STATUS` (domain `ITEMSTATUS`) and `INVENTORY.STATUS` (domain `INVSTATUS`)
store the customer-renamable **synonym** `VALUE`, not the internal `MAXVALUE`
that Maximo logic keys on. In a stock deployment internal == external so a
literal `STATUS = 'ACTIVE'` works — but once a customer adds synonyms, literals
silently drop rows. Resolve the set via `SYNONYMDOMAIN`:

```sql
-- "Active" inventory, synonym-safe
WHERE inv.status IN (
    SELECT value FROM SYNONYMDOMAIN
    WHERE domainid = 'INVSTATUS' AND maxvalue = 'ACTIVE'
)
```

This is the universal status mechanic owned by `maximo-overview` — applied here
to the inventory domains. The example/view literals (`'ACTIVE'`) are correct for
stock deployments; switch to the `SYNONYMDOMAIN` form when synonyms exist.

## 10. Obsolete items still appear in `INVBALANCES`

Obsolete items (`ITEM.STATUS` at the `OBSOLETE` synonym) aren't issued (Maximo
blocks new transactions) but historical balances and consumption history remain.
For "active inventory" reports, filter to the `ACTIVE` synonym (see gotcha 9).
For historical movement reports, don't filter — include obsolete items so trends
aren't truncated.

## 11. Rotating items have their own quirks

Items with `ROTATING = 1` (pumps, motors, etc.) are tracked individually by serial number. `INVBALANCES` has rows per condition (`NEW`, `REPAIRED`, `IN-SERVICE`). For "spares available", filter `CONDITIONCODE IN ('NEW', 'REPAIRED')` and exclude `IN-SERVICE` (already on an asset, not in the storeroom).

## 12. Reservations & open WOs — apply WO status/HISTORYFLAG correctly

`INVRESERVE` (and the `RESERVEDQTY` it aggregates into `INVBALANCES`) commits
stock to future WOs. When you join `INVRESERVE.WONUM` / `MATUSETRANS.WONUM` back
to `WORKORDER` to scope "open" reservations:

- `WORKORDER.STATUS` is the `WOSTATUS` synonym domain — resolve "still open"
  (i.e. not `COMP`/`CLOSE`/`CAN`) via `SYNONYMDOMAIN`, not literals (gotcha 9
  pattern; status set owned by `maximo-work-orders` / `maximo-overview`).
- Closed/cancelled WOs carry `HISTORYFLAG = 1` and drop out of standard Maximo
  views — if the silver pipeline mirrors that filter, a reservation against a
  just-closed WO may look orphaned. Confirm closed WOs are present before
  treating an old reservation as a live backlog. (Universal `HISTORYFLAG`
  mechanic, see `maximo-overview`.)

Reservations are normally released when the WO reaches `CLOSE` (not merely
`COMP`), so a `COMP`-but-not-`CLOSE` WO can still hold reservations — relevant
when a shop defers closing.

## 13. Movement bucketing uses app-server-timezone datetimes

`MATUSETRANS.TRANSDATE` / `MATRECTRANS.TRANSDATE` are stored in the app server's
local timezone (often UTC, but that is a config choice — not guaranteed), not
per-row UTC. When bucketing usage by day/week/month across sites, don't assume
UTC. This is the universal datetime mechanic owned by `maximo-overview`; confirm
the deployment's app-server timezone via `maximo-setup`.
