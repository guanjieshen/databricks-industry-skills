---
name: maximo-inventory
description: |
  Use for Maximo inventory / storeroom / parts-availability analytics — items
  below reorder point, multi-storeroom on-hand positions, top consumed parts,
  dead stock, ABC classification, stockout-risk-for-WO checks, parts kit
  explosions, reservation backlogs, inventory carrying cost, inventory turns.
  Triggers on: "items below reorder", "stockout", "on hand", "parts inventory",
  "storeroom", "INVENTORY", "INVBALANCES", "MATUSETRANS", "ITEM", "ABC
  analysis", "dead stock", "inventory turns", "parts availability for WO",
  "kit explosion", "reservation backlog", "carrying cost".
tags:
  - data-source:ibm-maximo
  - tier:module
  - module:inventory
  - industry:oil-and-gas
  - industry:utilities
  - industry:mining
  - industry:manufacturing
  - persona:materials-specialist
  - persona:analyst
  - persona:da-platform
---

# Maximo Inventory

Help materials specialists and maintenance planners query inventory positions, usage, and parts availability across Maximo storerooms. Composes with `maximo-overview` (universal gotchas) and `maximo-work-orders` (planned material demand via `WPMATERIAL`).

## When to use

- "Items below reorder point at site X"
- "What's our on-hand quantity for ITEM-12345?"
- "Top consumed parts last quarter"
- "Dead stock — items with no movement in N months"
- "Will WO-12345 have all its parts available?"
- "ABC classification of our inventory"
- "Inventory carrying cost by storeroom"
- "Reservation backlog — committed parts waiting for issue"
- "Parts kit explosion — what's in ITEM-KIT-3?"
- "Inventory turns for ITEM-X"

If the question is about **cost** of inventory (purchase price, GL impact), check `maximo-maintenance-cost` for the cost-attribution side. This skill handles the *physical* inventory layer.

If the question is about **upcoming material demand from PMs**, use `maximo-pm-planning` — it forecasts `JPMATERIAL` aggregated to a window.

## Pre-flight (per session)

1. **Silver catalog/schema**: confirm via workspace glossary or ask.
2. **Storeroom set**: "Which storerooms should this query cover?" Customer-defined; usually filter `LOCATIONS.TYPE = 'STOREROOM'`. Workspace glossary may map business names to storeroom location codes.
3. **Costing-method awareness**: if the question involves $$, confirm whether the customer uses `AVERAGE`, `FIFO`, `LIFO`, or `STANDARD` cost methods (varies by item) — affects how you compare costs across items.

## Workflow priority

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `item_on_hand`, `item_total_on_hand`, `reorder_alert_count`, `inventory_turns`, `dead_stock_count`
2. **Pre-joined views** in [views.sql](views.sql) — `v_inventory_position`, `v_stock_movement`, `v_reorder_alerts`
3. **Parameterized examples** in [examples.sql](examples.sql)
4. **Raw tables** — last resort

## What's in this skill

- [schema.md](schema.md) — ITEM, INVENTORY, INVBALANCES, INVCOST, MATUSETRANS, MATRECTRANS, INVRESERVE, ITEMSTRUCT
- [gotchas.md](gotchas.md) — INVENTORY vs INVBALANCES, multi-storeroom, costing methods, issue types, UoM, kits, reservations, storeroom filter
- [examples.sql](examples.sql) — parameterized inventory queries
- [views.sql](views.sql) — DDL for `v_inventory_position`, `v_stock_movement`, `v_reorder_alerts`
- [metric_udfs.sql](metric_udfs.sql) — Trusted UC SQL functions

## What NOT to do

- **Don't confuse `INVENTORY` with `INVBALANCES`** — `INVENTORY` is the master row per (item, storeroom); `INVBALANCES` is current quantity per bin. See gotcha 1.
- **Don't join `INVENTORY` to all `LOCATIONS`** — filter `LOCATIONS.TYPE = 'STOREROOM'` first.
- **Don't sum `INVBALANCES.CURBAL` as "available"** — subtract reservations: `AVAILABLE = CURBAL - RESERVED`.
- **Don't average costs across items with different `COSTMETHOD`** values — normalize first.
- **Don't include `MATUSETRANS` rows with `ISSUETYPE = 'TRANSFER'`** in "consumption" totals — transfers move stock between storerooms, they don't consume it.

## Composes with

- `maximo-work-orders` — `WPMATERIAL` (planned materials on WOs); `MATUSETRANS` joins back to WORKORDER
- `maximo-maintenance-cost` — material cost via `INVCOST` (costing-method context lives here, cost rollup lives there)
- `maximo-pm-planning` — `JPMATERIAL` aggregated for forecast PMs feeds future material demand
- **`maximo-asset-hierarchy`** — for queries spanning storerooms across regions ("total on-hand under region X"). Compose with `v_location_rollup_keys` to roll up `INVBALANCES` by storeroom parent.

## References

- [schema.md](schema.md)
- [gotchas.md](gotchas.md)
- [examples.sql](examples.sql)
- [views.sql](views.sql)
- [metric_udfs.sql](metric_udfs.sql)
- IBM Maximo Manage — Inventory module: https://www.ibm.com/docs/en/masv-and-l/maximo-manage/cd?topic=manage-inventory-module
