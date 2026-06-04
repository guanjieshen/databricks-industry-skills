-- =============================================================================
-- Maximo Inventory — UC SQL Function (Metric UDF) DDL
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} and {{catalog}}.{{metrics_schema}}.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS {{catalog}}.{{metrics_schema}}
COMMENT 'Trusted-asset SQL functions for Maximo inventory metrics';


-- -----------------------------------------------------------------------------
-- item_on_hand — available quantity at a specific storeroom (net of reservations)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.item_on_hand(
    itemnum_param STRING,
    location_param STRING COMMENT 'Storeroom location',
    siteid_param STRING
)
RETURNS DOUBLE
COMMENT 'Trusted metric: available quantity (CURBAL - RESERVEDQTY) for an item at a specific storeroom.'
RETURN (
    SELECT COALESCE(SUM(curbal - reservedqty), 0)
    FROM {{catalog}}.{{silver_schema}}.invbalances
    WHERE itemnum = itemnum_param
      AND location = location_param
      AND siteid = siteid_param
);


-- -----------------------------------------------------------------------------
-- item_total_on_hand — available quantity across ALL storerooms in a site
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.item_total_on_hand(
    itemnum_param STRING,
    siteid_param STRING COMMENT 'SITEID. Pass NULL for all sites.'
)
RETURNS DOUBLE
COMMENT 'Trusted metric: total available quantity for an item across all storerooms (optionally filtered by site).'
RETURN (
    SELECT COALESCE(SUM(curbal - reservedqty), 0)
    FROM {{catalog}}.{{silver_schema}}.invbalances
    WHERE itemnum = itemnum_param
      AND (siteid_param IS NULL OR siteid = siteid_param)
);


-- -----------------------------------------------------------------------------
-- reorder_alert_count — count of items currently below reorder point
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.reorder_alert_count(
    siteid_param STRING COMMENT 'SITEID. Pass NULL for all sites.'
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of (item, storeroom) combinations currently below reorder point. ACTIVE inventory only.'
RETURN (
    WITH balances AS (
        SELECT itemnum, location, siteid,
               SUM(curbal - reservedqty) AS available
        FROM {{catalog}}.{{silver_schema}}.invbalances
        GROUP BY itemnum, location, siteid
    )
    SELECT COUNT(*)
    FROM {{catalog}}.{{silver_schema}}.inventory inv
    LEFT JOIN balances b
        ON b.itemnum = inv.itemnum
       AND b.location = inv.location
       AND b.siteid = inv.siteid
    WHERE inv.status = 'ACTIVE'
      AND (siteid_param IS NULL OR inv.siteid = siteid_param)
      AND COALESCE(b.available, 0) < inv.reorderpoint
);


-- -----------------------------------------------------------------------------
-- inventory_turns — annualized usage / average on-hand for an item
-- -----------------------------------------------------------------------------
-- Higher turns = more rapid stock rotation. Industry benchmark varies (4-12 is
-- typical for spares; lower for slow-moving critical items).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.inventory_turns(
    itemnum_param STRING,
    siteid_param STRING COMMENT 'SITEID. Pass NULL for all sites.',
    window_days INT COMMENT 'Look-back window for usage (e.g. 365)'
)
RETURNS DOUBLE
COMMENT 'Trusted metric: annualized inventory turns = (usage in window, annualized) / (current available qty).'
RETURN (
    WITH usage AS (
        SELECT SUM(quantity) AS qty_used
        FROM {{catalog}}.{{silver_schema}}.matusetrans
        WHERE itemnum = itemnum_param
          AND issuetype = 'ISSUE'
          AND (siteid_param IS NULL OR siteid = siteid_param)
          AND transdate >= current_date() - make_interval(0, 0, 0, window_days, 0, 0, 0)
    ),
    on_hand AS (
        SELECT SUM(curbal - reservedqty) AS available
        FROM {{catalog}}.{{silver_schema}}.invbalances
        WHERE itemnum = itemnum_param
          AND (siteid_param IS NULL OR siteid = siteid_param)
    )
    SELECT
        CASE WHEN o.available > 0 AND window_days > 0
             THEN (u.qty_used * 365.0 / window_days) / o.available
             ELSE NULL
        END
    FROM usage u, on_hand o
);


-- -----------------------------------------------------------------------------
-- dead_stock_count — items with on-hand > 0 but no movement in N days
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.dead_stock_count(
    siteid_param STRING COMMENT 'SITEID. Pass NULL for all sites.',
    no_movement_days INT COMMENT 'Threshold in days (e.g. 365)'
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of (item, storeroom) with on-hand > 0 and no MATUSETRANS issue in N days.'
RETURN (
    WITH balances AS (
        SELECT itemnum, location, siteid, SUM(curbal) AS on_hand
        FROM {{catalog}}.{{silver_schema}}.invbalances
        GROUP BY itemnum, location, siteid
        HAVING SUM(curbal) > 0
    ),
    recent_movement AS (
        SELECT DISTINCT itemnum, location, siteid
        FROM {{catalog}}.{{silver_schema}}.matusetrans
        WHERE issuetype = 'ISSUE'
          AND transdate >= current_date() - make_interval(0, 0, 0, no_movement_days, 0, 0, 0)
    )
    SELECT COUNT(*)
    FROM balances b
    LEFT JOIN recent_movement r
        ON r.itemnum = b.itemnum
       AND r.location = b.location
       AND r.siteid = b.siteid
    WHERE r.itemnum IS NULL
      AND (siteid_param IS NULL OR b.siteid = siteid_param)
);


-- =============================================================================
-- Grants (uncomment + substitute principal)
-- =============================================================================
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.item_on_hand          TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.item_total_on_hand    TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.reorder_alert_count   TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.inventory_turns       TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.dead_stock_count      TO `{{principal}}`;
