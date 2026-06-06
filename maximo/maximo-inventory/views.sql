-- =============================================================================
-- Maximo Inventory — Gold Views
-- =============================================================================
-- Bind :catalog, :silver_schema, :gold_schema (Databricks SQL parameters) to the
-- customer's UC catalog and schemas at registration time. Register once via
-- maximo-setup (preview-then-apply); do not run from the skill.
-- STATUS literals (e.g. 'ACTIVE') are correct for stock deployments; switch to
-- the SYNONYMDOMAIN form (gotcha 9) when the customer has added status synonyms.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_inventory_position
-- The workhorse view. One row per (item, storeroom). Aggregates INVBALANCES,
-- joins INVENTORY for reorder rules and ABC class, joins ITEM for description,
-- joins INVCOST for unit cost, computes available + days-since-last-movement.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_inventory_position
COMMENT 'Per-(item, storeroom) inventory position. One row per INVENTORY master. Reorder status, available qty (net of reservations), days-since-last-movement.'
AS
WITH balances AS (
    SELECT
        itemnum, location, siteid,
        SUM(curbal)                                       AS on_hand,
        SUM(reservedqty)                                  AS reserved,
        SUM(curbal) - SUM(reservedqty)                    AS available
    FROM :catalog.:silver_schema.invbalances
    GROUP BY itemnum, location, siteid
)
SELECT
    inv.itemnum,
    inv.location,
    inv.siteid,
    inv.itemsetid,
    i.description                                         AS item_description,
    i.status                                              AS item_status,
    i.commodity, i.commoditygroup,
    i.itemtype, i.rotating,
    i.stockeditem,
    inv.reorderpoint                                      AS reorder_point,
    inv.maxlevel                                          AS max_level,
    inv.minlevel                                          AS min_level,
    inv.orderqty                                          AS order_quantity,
    inv.leadtime                                          AS lead_time_days,
    inv.abctype                                           AS abc_class,
    inv.costmethod                                        AS cost_method,
    inv.status                                            AS inventory_status,
    inv.vendor                                            AS default_vendor,
    COALESCE(b.on_hand, 0)                                AS on_hand,
    COALESCE(b.reserved, 0)                               AS reserved,
    COALESCE(b.available, 0)                              AS available,
    inv.lastissuedate                                     AS last_movement_date,
    c.avgcost                                             AS avg_unit_cost,
    c.stdcost                                             AS std_unit_cost,
    c.lastcost                                            AS last_unit_cost,
    c.currencycode                                        AS currency,
    CASE
        WHEN COALESCE(b.available, 0) <  inv.reorderpoint THEN 'BELOW_REORDER'
        WHEN COALESCE(b.available, 0) <= inv.minlevel     THEN 'AT_MIN'
        WHEN COALESCE(b.available, 0) >= inv.maxlevel     THEN 'AT_MAX'
        ELSE 'OK'
    END                                                    AS stock_status
FROM :catalog.:silver_schema.inventory inv
JOIN :catalog.:silver_schema.item i
    ON i.itemnum = inv.itemnum AND i.itemsetid = inv.itemsetid
LEFT JOIN balances b
    ON b.itemnum = inv.itemnum
   AND b.location = inv.location
   AND b.siteid   = inv.siteid
LEFT JOIN :catalog.:silver_schema.invcost c
    ON c.itemnum = inv.itemnum
   AND c.location = inv.location
   AND c.siteid   = inv.siteid;


-- -----------------------------------------------------------------------------
-- v_stock_movement
-- MATUSETRANS aggregated to (item, storeroom, week) grain for trending analytics.
-- Nets ISSUE + RETURN; excludes TRANSFER and ADJUSTMENT.
-- QUANTITY (and LINECOST) are SIGNED in MATUSETRANS: issues positive, returns
-- negative (schema.md). So net consumption = SUM(quantity) over the filtered
-- ISSUE+RETURN set — returns already carry a negative sign and net themselves
-- out. Do NOT subtract RETURN explicitly: that would double-flip the sign and
-- make a return INCREASE net consumption.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_stock_movement
COMMENT 'Net consumption per (item, storeroom, week). QUANTITY/LINECOST are signed (issues positive, returns negative); net consumption = SUM(quantity). Filters to ISSUE+RETURN; excludes TRANSFER and ADJUSTMENT.'
AS
SELECT
    itemnum,
    location,
    siteid,
    date_trunc('WEEK', transdate)                         AS week_starting,
    SUM(quantity)                                         AS net_consumed,
    SUM(linecost)                                         AS net_cost,
    COUNT(DISTINCT wonum)                                 AS distinct_wos
FROM :catalog.:silver_schema.matusetrans
WHERE issuetype IN ('ISSUE', 'RETURN')
GROUP BY itemnum, location, siteid, date_trunc('WEEK', transdate);


-- -----------------------------------------------------------------------------
-- v_reorder_alerts
-- Items currently below reorder point with suggested order quantity.
-- One row per (item, storeroom) needing replenishment.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_reorder_alerts
COMMENT 'Items currently below reorder point. One row per (item, storeroom) needing replenishment.'
AS
SELECT
    p.itemnum, p.location, p.siteid,
    p.item_description,
    p.available,
    p.reorder_point,
    p.reorder_point - p.available                         AS shortfall,
    p.order_quantity                                      AS suggested_order_qty,
    p.lead_time_days,
    p.default_vendor,
    p.abc_class,
    p.stock_status
FROM :catalog.:gold_schema.v_inventory_position p
WHERE p.stock_status IN ('BELOW_REORDER', 'AT_MIN')
  AND p.item_status = 'ACTIVE'
  AND p.inventory_status = 'ACTIVE';
