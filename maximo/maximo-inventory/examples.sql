-- =============================================================================
-- Maximo Inventory — Gold-Standard Query Examples
-- =============================================================================
-- Each block is a parameterized template that maps to a single analytical
-- question. Bind these Databricks SQL parameters at execution time:
--   :catalog          → the customer's UC catalog (e.g. eam)
--   :silver_schema    → Silver schema with the MBO tables (e.g. maximo_silver)
--   :gold_schema      → Gold schema with the registered views
--   :metrics_schema   → schema with the Trusted UDFs (only for UDF examples)
--   :itemnum, :siteid, :location, :wonum, :kit_itemnum, :dead_stock_months
--                     → per-query value parameters
-- These examples assume views.sql and metric_udfs.sql have been registered.
-- Workflow priority: if a Trusted UDF matches the question, prefer it over the
-- view-based query (see SKILL.md §Workflow).
--
-- STATUS FILTERING: examples below use literal status sets (e.g. 'ACTIVE') for
-- readability. That is correct in a STOCK deployment, but ITEM.STATUS /
-- INVENTORY.STATUS / WORKORDER.STATUS store the synonym VALUE — so when a
-- customer has added status synonyms, resolve the set from the internal MAXVALUE
-- via SYNONYMDOMAIN (see example 6 for the canonical WO pattern; gotcha 9).
-- TIMEZONE: TRANSDATE is app-server-timezone, not per-row UTC — don't assume UTC
-- when bucketing usage across sites (gotcha 13, owned by maximo-overview).
-- =============================================================================
--
-- Contents (load the block that matches the question):
--   1.  Items below reorder point at a site
--   2.  Multi-storeroom inventory position for an item
--   3.  Top consumed parts last quarter
--   4.  Dead stock — items with no movement in N months
--   5.  ABC analysis — items ranked by annual usage cost
--   6.  Reservation backlog — committed parts not yet issued (synonym/HISTORYFLAG-aware)
--   7.  Parts availability check for a specific WO
--   8.  Kit explosion — components of a parent item
--   9.  Weekly usage trend for a specific item
--   10. Inventory carrying value by storeroom
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Items below reorder point at a site
-- -----------------------------------------------------------------------------
-- Trigger: "items below reorder", "what's low on stock at site X"
SELECT
    p.itemnum, p.location, p.item_description,
    p.on_hand, p.available,
    p.reorder_point,
    p.reorder_point - p.available AS shortfall,
    p.order_quantity
FROM :catalog.:gold_schema.v_inventory_position p
WHERE p.available < p.reorder_point
  AND p.siteid = :siteid
  AND p.item_status = 'ACTIVE'
ORDER BY shortfall DESC
LIMIT 100;


-- -----------------------------------------------------------------------------
-- 2. Multi-storeroom inventory position for an item
-- -----------------------------------------------------------------------------
-- Trigger: "where is item X", "stock of item X across storerooms"
SELECT
    location, siteid, binnum,
    SUM(curbal)                              AS on_hand,
    SUM(reservedqty)                         AS reserved,
    SUM(curbal) - SUM(reservedqty)           AS available
FROM :catalog.:silver_schema.invbalances
WHERE itemnum = :itemnum
GROUP BY location, siteid, binnum
ORDER BY on_hand DESC;


-- -----------------------------------------------------------------------------
-- 3. Top consumed parts last quarter
-- -----------------------------------------------------------------------------
-- Trigger: "most-used parts", "top consumed items"
-- QUANTITY/LINECOST are SIGNED (issues positive, returns negative; schema.md), so
-- net consumption = SUM(quantity) over the filtered ISSUE+RETURN set. Returns
-- already carry a negative sign and net themselves out — do NOT subtract RETURN.
SELECT
    t.itemnum,
    i.description,
    SUM(t.quantity)                          AS total_consumed,
    SUM(t.linecost)                          AS total_cost,
    COUNT(DISTINCT t.wonum)                  AS distinct_wos
FROM :catalog.:silver_schema.matusetrans t
JOIN :catalog.:silver_schema.item i ON i.itemnum = t.itemnum
WHERE t.issuetype IN ('ISSUE', 'RETURN')
  AND t.transdate >= add_months(current_date(), -3)
GROUP BY t.itemnum, i.description
HAVING SUM(t.quantity) > 0
ORDER BY total_consumed DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- 4. Dead stock — items with no movement in N months
-- -----------------------------------------------------------------------------
-- Trigger: "dead stock", "items with no movement"
-- Confirm the threshold and what "movement" means before reporting (see
-- SKILL.md §Questions to surface first).
SELECT
    p.itemnum, p.location, p.item_description,
    p.on_hand,
    p.last_movement_date,
    datediff(DAY, p.last_movement_date, current_date()) AS days_since_movement
FROM :catalog.:gold_schema.v_inventory_position p
WHERE p.on_hand > 0
  AND (p.last_movement_date IS NULL OR p.last_movement_date < add_months(current_date(), - :dead_stock_months))
ORDER BY p.on_hand DESC
LIMIT 100;


-- -----------------------------------------------------------------------------
-- 5. ABC analysis — items ranked by annual usage cost
-- -----------------------------------------------------------------------------
-- Trigger: "ABC classification", "high-value items"
WITH annual_usage AS (
    SELECT
        itemnum,
        SUM(linecost) AS annual_cost
    FROM :catalog.:silver_schema.matusetrans
    WHERE issuetype = 'ISSUE'
      AND transdate >= add_months(current_date(), -12)
    GROUP BY itemnum
),
ranked AS (
    SELECT
        itemnum, annual_cost,
        annual_cost / SUM(annual_cost) OVER ()         AS pct_of_total,
        SUM(annual_cost) OVER (ORDER BY annual_cost DESC) / SUM(annual_cost) OVER () AS cumulative_pct
    FROM annual_usage
)
SELECT
    r.itemnum,
    i.description,
    ROUND(r.annual_cost, 2)                AS annual_usage_cost,
    ROUND(r.pct_of_total * 100, 2)         AS pct_of_total,
    ROUND(r.cumulative_pct * 100, 2)       AS cumulative_pct,
    CASE
        WHEN r.cumulative_pct <= 0.80 THEN 'A'
        WHEN r.cumulative_pct <= 0.95 THEN 'B'
        ELSE 'C'
    END                                    AS suggested_abc
FROM ranked r
JOIN :catalog.:silver_schema.item i ON i.itemnum = r.itemnum
ORDER BY annual_usage_cost DESC
LIMIT 200;


-- -----------------------------------------------------------------------------
-- 6. Reservation backlog — committed parts not yet issued
-- -----------------------------------------------------------------------------
-- Trigger: "reservation backlog", "parts reserved but not issued"
-- "Still open" WO statuses are a synonym domain — resolve the not-final set via
-- SYNONYMDOMAIN rather than literals (gotcha 9; WOSTATUS set owned by
-- maximo-work-orders / maximo-overview). Reservations are released at CLOSE, so
-- a COMP-but-not-CLOSE WO can still hold them. Closed WOs may carry
-- HISTORYFLAG = 1 and be filtered upstream — confirm they are present before
-- treating an old reservation as live (gotcha 12).
SELECT
    r.wonum, w.description AS wo_description, w.status,
    r.itemnum,  i.description AS item_description,
    r.reservedqty,
    r.requireddate,
    datediff(DAY, r.requireddate, current_date()) AS days_overdue
FROM :catalog.:silver_schema.invreserve r
JOIN :catalog.:silver_schema.item i ON i.itemnum = r.itemnum
JOIN :catalog.:silver_schema.workorder w
    ON w.wonum = r.wonum AND w.siteid = r.siteid
WHERE w.status NOT IN (
        SELECT value
        FROM :catalog.:silver_schema.synonymdomain
        WHERE domainid = 'WOSTATUS'
          AND maxvalue IN ('COMP', 'CLOSE', 'CAN')   -- final/closed statuses
      )
  AND r.requireddate < current_date()
ORDER BY days_overdue DESC
LIMIT 50;


-- -----------------------------------------------------------------------------
-- 7. Parts availability check for a specific WO
-- -----------------------------------------------------------------------------
-- Trigger: "will WO-X have all parts available", "is WO ready to schedule"
-- WPMATERIAL is the planned-material list owned by maximo-work-orders; this
-- example reads it to net required vs available. AVAILABLE nets reservations.
SELECT
    wp.wonum, wp.itemnum, i.description AS item_description,
    wp.itemqty                                                AS required_qty,
    COALESCE(SUM(b.curbal - b.reservedqty), 0)                AS available_now,
    CASE
        WHEN COALESCE(SUM(b.curbal - b.reservedqty), 0) >= wp.itemqty THEN 'OK'
        WHEN COALESCE(SUM(b.curbal - b.reservedqty), 0) > 0 THEN 'PARTIAL'
        ELSE 'STOCKOUT'
    END                                                        AS availability_status
FROM :catalog.:silver_schema.wpmaterial wp
JOIN :catalog.:silver_schema.item i ON i.itemnum = wp.itemnum
LEFT JOIN :catalog.:silver_schema.invbalances b
    ON b.itemnum = wp.itemnum AND b.siteid = wp.siteid
WHERE wp.wonum = :wonum AND wp.siteid = :siteid
GROUP BY wp.wonum, wp.itemnum, i.description, wp.itemqty
ORDER BY availability_status;


-- -----------------------------------------------------------------------------
-- 8. Kit explosion — components of a parent item
-- -----------------------------------------------------------------------------
-- Trigger: "what's in kit X", "components of ITEM-KIT-3"
SELECT
    s.parent                                AS kit_itemnum,
    s.itemnum                               AS component_itemnum,
    i.description                           AS component_description,
    s.qty                                   AS qty_per_kit,
    s.unitcost                              AS component_unit_cost,
    s.qty * s.unitcost                      AS component_cost_contribution
FROM :catalog.:silver_schema.itemstruct s
JOIN :catalog.:silver_schema.item i ON i.itemnum = s.itemnum
WHERE s.parent = :kit_itemnum
ORDER BY component_cost_contribution DESC;


-- -----------------------------------------------------------------------------
-- 9. Weekly usage trend for a specific item
-- -----------------------------------------------------------------------------
-- Trigger: "usage trend for item X", "weekly consumption"
-- TRANSDATE is app-server-timezone; week buckets follow that TZ, not UTC.
-- QUANTITY/LINECOST are SIGNED (issues positive, returns negative; schema.md), so
-- net consumption = SUM(quantity) over the filtered ISSUE+RETURN set — returns
-- net themselves out. Do NOT subtract RETURN.
SELECT
    date_trunc('WEEK', transdate)            AS week_starting,
    SUM(quantity)                            AS quantity_consumed,
    SUM(linecost)                            AS cost_consumed,
    COUNT(DISTINCT wonum)                    AS distinct_wos
FROM :catalog.:silver_schema.matusetrans
WHERE itemnum = :itemnum
  AND issuetype IN ('ISSUE', 'RETURN')
  AND transdate >= add_months(current_date(), -12)
GROUP BY date_trunc('WEEK', transdate)
ORDER BY week_starting;


-- -----------------------------------------------------------------------------
-- 10. Inventory carrying value by storeroom
-- -----------------------------------------------------------------------------
-- Trigger: "inventory carrying cost", "how much inventory do we hold"
-- Approximate PHYSICAL carrying value. Multi-currency normalization and GL
-- impact belong to maximo-maintenance-cost — don't sum across differing
-- INVCOST.CURRENCYCODE here.
SELECT
    b.location                               AS storeroom,
    b.siteid,
    COUNT(DISTINCT b.itemnum)                AS distinct_items,
    SUM(b.curbal)                            AS total_units,
    ROUND(SUM(
        b.curbal * (
            CASE i.costmethod
                WHEN 'STANDARD' THEN c.stdcost
                WHEN 'LIFO'     THEN c.lastcost
                ELSE                 c.avgcost
            END
        )
    ), 2)                                    AS approx_carrying_value
FROM :catalog.:silver_schema.invbalances b
JOIN :catalog.:silver_schema.inventory i
    ON i.itemnum = b.itemnum AND i.location = b.location AND i.siteid = b.siteid
LEFT JOIN :catalog.:silver_schema.invcost c
    ON c.itemnum = b.itemnum AND c.location = b.location AND c.siteid = b.siteid
WHERE b.curbal > 0
GROUP BY b.location, b.siteid
ORDER BY approx_carrying_value DESC;
