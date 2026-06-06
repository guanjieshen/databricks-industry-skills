---
name: maximo-inventory
description: |
  Use for IBM Maximo / Maximo / EAM / CMMS inventory, storeroom, and
  parts-availability analytics on INVENTORY + INVBALANCES + MATUSETRANS data:
  items below reorder point, multi-storeroom on-hand positions, top consumed
  parts, dead stock, ABC classification, stockout-risk-for-WO checks, parts kit
  explosions, reservation backlogs, inventory carrying value, inventory turns.
  Triggers on: "items below reorder", "stockout", "on hand", "parts inventory",
  "storeroom", "INVENTORY", "INVBALANCES", "MATUSETRANS", "MATRECTRANS",
  "INVRESERVE", "ITEM", "ITEMSTRUCT", "ABC analysis", "dead stock", "inventory
  turns", "parts availability for WO", "kit explosion", "reservation backlog",
  "carrying cost". Compose with maximo-overview for baseline data-model literacy,
  maximo-work-orders for planned material demand (WPMATERIAL), and
  maximo-maintenance-cost for cost methodology.
metadata:
  version: "0.2.0"
parent: maximo-overview
---

# Maximo Inventory

Help materials specialists and maintenance planners query inventory positions, usage, and parts availability across Maximo storerooms. This skill adds the inventory-specific schema, gold-standard queries, reusable views, and Trusted UDFs on top of `maximo-overview`'s baseline data-model literacy and universal gotchas.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas (composite `SITEID` keys, status-is-a-synonym-domain / `SYNONYMDOMAIN` resolution, `HISTORYFLAG`, app-server-timezone datetimes). This skill builds on that foundation and applies those patterns to the inventory tables.

## When to use

Triggered by inventory / storeroom / parts-availability questions:
- "Items below reorder point at site X"
- "What's our on-hand quantity for ITEM-12345?"
- "Top consumed parts last quarter"
- "Dead stock — items with no movement in N months"
- "Will WO-12345 have all its parts available?"
- "ABC classification of our inventory"
- "Inventory carrying value by storeroom"
- "Reservation backlog — committed parts waiting for issue"
- "Parts kit explosion — what's in ITEM-KIT-3?"
- "Inventory turns for ITEM-X"

**Defer to siblings when:**
- Inventory **cost methodology** beyond a single carrying-value readout — multi-currency normalization, GL impact, PM-vs-CM material spend → `maximo-maintenance-cost`
- Upcoming material demand forecast from PMs (`JPMATERIAL` aggregated to a window) → `maximo-pm-planning`
- Planned material on a WO (`WPMATERIAL`) join shape and WO semantics → `maximo-work-orders`

## Top gotchas

These traps silently produce wrong numbers. Read before writing any non-trivial query (full set in [gotchas.md](gotchas.md); `maximo-overview` carries the universal ones — `SITEID` joins, status-synonym resolution, `HISTORYFLAG`, app-server datetimes):

1. **`INVENTORY` is the master; `INVBALANCES` holds the quantity.** `INVENTORY` is one row per (`ITEMNUM`, `LOCATION`, `SITEID`) carrying reorder rules and ABC class. Actual on-hand lives in `INVBALANCES` (N rows per `INVENTORY`, one per bin/lot). Querying `INVENTORY` for a quantity returns the master, not the stock.
2. **`AVAILABLE = CURBAL - RESERVEDQTY`.** `INVBALANCES.CURBAL` includes reserved stock. Any "is it available" / stockout-risk question must subtract `RESERVEDQTY`, or you overstate availability. The shipped `item_on_hand` UDF does this for you.
3. **Filter `MATUSETRANS` by `ISSUETYPE` for "consumption."** The table logs `ISSUE`, `RETURN`, `TRANSFER`, `ADJUSTMENT`. Use `ISSUETYPE IN ('ISSUE','RETURN')` and net via `SUM(QUANTITY)` — `QUANTITY` is signed (issues positive, returns negative), so one `SUM` nets returns out (never `SUM(issue) - SUM(return)`, which double-flips the sign; gotcha 5). Including `TRANSFER` double-counts (a transfer moves stock between storerooms, it doesn't consume it).
4. **Only `STOREROOM` locations hold inventory.** `LOCATIONS` mixes `OPERATING`, `STOREROOM`, `LABOR`, `COURIER`, `REPAIR`, etc. Joining `INVENTORY`/`INVBALANCES` to `LOCATIONS` without `TYPE = 'STOREROOM'` pulls in non-stocking locations.
5. **Status columns are synonym domains; don't hard-code literals.** `ITEM.STATUS`, `INVENTORY.STATUS`, and the `WORKORDER.STATUS` you join to all store the customer-renamable synonym (`VALUE`), not the internal `MAXVALUE`. In a stock deployment literals like `'ACTIVE'`/`'COMP'` work, but once a customer adds synonyms they silently miss rows — resolve the set via `SYNONYMDOMAIN` (domains `ITEMSTATUS`, `INVSTATUS`, `WOSTATUS`). See `maximo-overview` and [gotchas.md](gotchas.md).

## Questions to surface first

Surface these to the user *before* answering — there is no defensible default:

1. **Storeroom scope.** "Which storerooms should this cover?" Storerooms are customer-defined `LOCATIONS` rows with `TYPE = 'STOREROOM'`; an item commonly stocks in several, and "on-hand" can mean one storeroom or a sum across all. Confirm the set (the workspace glossary may map business names to location codes). For multi-site customers also confirm whether to sum across `SITEID`.
2. **Available vs on-hand.** "Available" nets out reservations (`CURBAL - RESERVEDQTY`); "on-hand" is gross `CURBAL`. Reorder/stockout questions almost always want *available* — confirm which the user means, since they diverge whenever stock is reserved against open WOs.
3. **Costing method for any value question.** Inventory value depends on `INVENTORY.COSTMETHOD`, which is set per item (`AVERAGE` / `FIFO` / `LIFO` / `STANDARD`) and selects a different `INVCOST` column. Confirm the method(s) in play before computing carrying value, and defer multi-currency normalization to `maximo-maintenance-cost`.
4. **"Dead stock" / "no movement" threshold.** The cutoff (e.g. 6, 12, 24 months) and whether "movement" means any `MATUSETRANS` issue vs any transaction at all are customer conventions with no default. Confirm both before reporting dead stock.

## Pre-flight (per session)

One-time session config — cache, don't re-ask:

1. **Catalog/schema** — confirm via the customer's workspace glossary skill if installed, or ask.
2. **Glossary skill** — is a `<customer>-maximo-glossary` workspace skill installed? Prefer it for business-term resolution (storeroom names, item groups).

If a business term is ambiguous and no glossary covers it, **ask before guessing**.

## Workflow

For any new question, resolve in this order:

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `item_on_hand`, `item_total_on_hand`, `reorder_alert_count`, `inventory_turns`, `dead_stock_count`. If a UDF matches the question, call it.
2. **Parameterized example query** — check [examples.sql](examples.sql) for an existing pattern; use it with the user's parameters.
3. **Pre-joined view** — compose using `v_inventory_position` / `v_stock_movement` / `v_reorder_alerts` from [views.sql](views.sql).
4. **Raw tables** — only when the view layer doesn't cover the join shape. Explain why you're skipping the views.

## What's in this skill

- [schema.md](schema.md) — load when joining or selecting columns. Reference for `ITEM`, `INVENTORY`, `INVBALANCES`, `INVCOST`, `MATUSETRANS`, `MATRECTRANS`, `INVRESERVE`, `ITEMSTRUCT`, and the storeroom slice of `LOCATIONS`.
- [gotchas.md](gotchas.md) — load before writing non-trivial joins. INVENTORY-vs-INVBALANCES, available-vs-on-hand, multi-storeroom, costing methods, issue types, UoM conversions, kits, storeroom filter, status synonyms, obsolete items, rotating items.
- [examples.sql](examples.sql) — load when the user's question matches a pattern (reorder, multi-storeroom position, top consumed, dead stock, ABC, reservation backlog, WO parts check, kit explosion, usage trend, carrying value).
- [views.sql](views.sql) — DDL for `v_inventory_position`, `v_stock_movement`, `v_reorder_alerts`. Register once via `maximo-setup`.
- [metric_udfs.sql](metric_udfs.sql) — Trusted Asset UC SQL functions Genie Code calls as governed metrics instead of regenerating ad-hoc SQL. Register once via `maximo-setup`.

## What NOT to do

- **Don't confuse `INVENTORY` with `INVBALANCES`** — `INVENTORY` is the master row per (item, storeroom); the quantity lives in `INVBALANCES` (gotcha 1).
- **Don't sum `INVBALANCES.CURBAL` as "available"** — subtract reservations: `AVAILABLE = CURBAL - RESERVEDQTY` (gotcha 2).
- **Don't join `INVENTORY` to all `LOCATIONS`** — filter `TYPE = 'STOREROOM'` first (gotcha 4).
- **Don't hard-code status literals** — `ITEM.STATUS` / `INVENTORY.STATUS` / `WORKORDER.STATUS` are synonym domains; resolve via `SYNONYMDOMAIN` (gotcha 5, owned by `maximo-overview`).
- **Don't include `MATUSETRANS` rows with `ISSUETYPE = 'TRANSFER'`** in consumption totals (gotcha 3).
- **Don't compute inventory *cost* methodology here** — multi-currency normalization, GL impact, and PM-vs-CM material spend belong to `maximo-maintenance-cost`. This skill owns the *physical* inventory layer.
- **Don't write or alter UC comments / table metadata from this skill** — UC comments are owned by `maximo-setup` (preview-then-apply, gated on explicit user approval). Defer to it.

## Composes with

- **`maximo-work-orders`** — `WPMATERIAL` (planned materials on WOs) and the `WORKORDER` semantics behind a `MATUSETRANS.WONUM` / `INVRESERVE.WONUM` join. This skill reads `WORKORDER.STATUS` to scope open reservations but defers WO status sets and `HISTORYFLAG` handling to work-orders / overview.
- **`maximo-maintenance-cost`** — material cost methodology: multi-currency (`INVCOST.CURRENCYCODE`) normalization, GL impact, and PM-vs-CM material spend. Costing-method *context* (`COSTMETHOD`) lives here; cost rollup and currency normalization live there.
- **`maximo-pm-planning`** — `JPMATERIAL` aggregated for forecast PMs feeds future material demand. This skill reports current/historical inventory; pm-planning owns the forward demand forecast.
- **`maximo-procurement`** — the buy side of `MATRECTRANS`: PO/PR/invoice headers, vendor master, and PO receipts. This skill reads `MATRECTRANS` as stock movement into `INVBALANCES`; procurement reads the same rows as PO receipts. Reorder/availability live here; PO backlog, vendor spend, and three-way match live there.
- **`maximo-asset-hierarchy`** — for queries spanning storerooms across regions ("total on-hand under region X"). Compose with `v_location_rollup_keys` to roll up `INVBALANCES` by storeroom parent location.
- **`maximo-setup`** to register the views in [views.sql](views.sql) and the Trusted UDFs in [metric_udfs.sql](metric_udfs.sql). Never run those scripts from this skill — defer to setup's preview-then-apply workflow.
