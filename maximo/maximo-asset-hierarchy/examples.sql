-- =============================================================================
-- Maximo Asset & Location Hierarchy — Gold-Standard Query Examples
-- =============================================================================
-- Substitute :catalog.:silver_schema, :catalog.:gold_schema,
-- :catalog.:metrics_schema before running.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. All locations under a given parent (any depth)
-- -----------------------------------------------------------------------------
-- Trigger: "all locations under STN-04", "what's in region X"
SELECT
    la.location,
    l.description,
    l.type
FROM :catalog.:silver_schema.locancestor la
JOIN :catalog.:silver_schema.locations l
    ON l.location = la.location AND l.siteid = la.siteid AND l.__END_AT IS NULL
WHERE la.ancestor = ':root_location'
  AND la.siteid = ':siteid'
  AND la.systemid = 'PRIMARY'
ORDER BY l.type, la.location;


-- -----------------------------------------------------------------------------
-- 2. All assets under a process system (or any location parent)
-- -----------------------------------------------------------------------------
-- Trigger: "all assets in process system X", "assets under station Y"
SELECT
    a.assetnum, a.description AS asset_description,
    a.classstructureid, a.location, a.criticality
FROM :catalog.:silver_schema.locancestor la
JOIN :catalog.:silver_schema.asset a
    ON a.location = la.location AND a.siteid = la.siteid AND a.__END_AT IS NULL
WHERE la.ancestor = ':root_location'
  AND la.siteid = ':siteid'
  AND la.systemid = 'PRIMARY'
ORDER BY a.classstructureid, a.assetnum;


-- -----------------------------------------------------------------------------
-- 3. Maintenance cost rolled up to a location parent (composes with maintenance-cost)
-- -----------------------------------------------------------------------------
-- Trigger: "cost by region", "spend rollup", "maintenance cost under station X"
SELECT
    la.ancestor                                            AS rollup_location,
    SUM(s.total_labor_cost)                                AS labor_cost,
    SUM(s.total_material_cost)                             AS material_cost,
    SUM(s.total_cost)                                      AS total_cost,
    COUNT(DISTINCT s.assetnum)                             AS distinct_assets
FROM :catalog.:gold_schema.v_asset_cost_summary s
JOIN :catalog.:silver_schema.asset a
    ON a.assetnum = s.assetnum AND a.siteid = s.siteid AND a.__END_AT IS NULL
JOIN :catalog.:silver_schema.locancestor la
    ON la.location = a.location AND la.siteid = a.siteid AND la.systemid = 'PRIMARY'
WHERE s.period_start >= add_months(current_date(), -12)
GROUP BY la.ancestor
ORDER BY total_cost DESC
LIMIT 50;


-- -----------------------------------------------------------------------------
-- 4. Region rollup key for a PM-compliance metric (composes with reliability)
-- -----------------------------------------------------------------------------
-- Trigger: "PM compliance by region", "compliance rollup"
-- PM compliance has 3+ valid definitions and is OWNED by maximo-reliability.
-- This skill supplies ONLY the (asset -> region) grouping; do NOT re-derive the
-- compliance metric here. Join this rollup key to reliability's compliance
-- view/UDF and GROUP BY region. (Status literals like pm.status='ACTIVE' must be
-- resolved via SYNONYMDOMAIN per maximo-overview — leave that to the owner.)
SELECT
    a.assetnum,
    a.siteid,
    la.ancestor                                            AS region,
    a.location
FROM :catalog.:silver_schema.asset a
JOIN :catalog.:silver_schema.locancestor la
    ON la.location = a.location AND la.siteid = a.siteid AND la.systemid = 'PRIMARY'
WHERE a.__END_AT IS NULL;
-- Then: JOIN <reliability>.v_pm_compliance USING (assetnum, siteid), GROUP BY region.


-- -----------------------------------------------------------------------------
-- 5. Path to root for a specific location
-- -----------------------------------------------------------------------------
-- Trigger: "what's the parent chain of X", "show me the path to root"
SELECT
    la.ancestor                                            AS chain_node,
    l.description
FROM :catalog.:silver_schema.locancestor la
JOIN :catalog.:silver_schema.locations l
    ON l.location = la.ancestor AND l.siteid = la.siteid AND l.__END_AT IS NULL
WHERE la.location = ':location'
  AND la.siteid = ':siteid'
  AND la.systemid = 'PRIMARY'
ORDER BY la.ancestor;
-- Note: order is approximate without an explicit depth column. Use level_in_hierarchy
-- UDF or v_location_rollup_keys (which carries depth) for ordered path-to-root.


-- -----------------------------------------------------------------------------
-- 6. Asset classification tree — all classes under "Rotating Equipment"
-- -----------------------------------------------------------------------------
-- Trigger: "asset class hierarchy", "all classes under X"
SELECT
    ct.descendant_class                                    AS classstructureid,
    ct.descendant_description                              AS description,
    ct.depth_from_root
FROM :catalog.:gold_schema.v_class_tree ct
WHERE ct.root_description = ':class_root_description'
ORDER BY ct.depth_from_root, ct.descendant_class;


-- -----------------------------------------------------------------------------
-- 7. All assets in a class subtree (e.g. all centrifugal pumps + variants)
-- -----------------------------------------------------------------------------
-- Trigger: "all pumps", "all assets in classification X"
SELECT
    a.assetnum, a.siteid, a.description,
    a.classstructureid                                     AS leaf_class,
    ct.root_description                                    AS rollup_class
FROM :catalog.:gold_schema.v_class_tree ct
JOIN :catalog.:silver_schema.asset a
    ON a.classstructureid = ct.descendant_class AND a.__END_AT IS NULL
WHERE ct.root_description = ':class_root_description'
ORDER BY a.classstructureid, a.assetnum;


-- -----------------------------------------------------------------------------
-- 8. Find leaf locations under a parent (no further children)
-- -----------------------------------------------------------------------------
-- Trigger: "leaf locations", "deepest locations under X"
WITH descendants AS (
    SELECT location FROM :catalog.:silver_schema.locancestor
    WHERE ancestor = ':root_location'
      AND siteid = ':siteid'
      AND systemid = 'PRIMARY'
)
SELECT l.location, l.description, l.type
FROM :catalog.:silver_schema.locations l
WHERE l.location IN (SELECT location FROM descendants)
  AND l.siteid = ':siteid'
  AND l.__END_AT IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM :catalog.:silver_schema.lochierarchy child
      WHERE child.parent = l.location
        AND child.siteid = l.siteid
        AND child.systemid = 'PRIMARY'
  )
ORDER BY l.location;


-- -----------------------------------------------------------------------------
-- 9. Closure-table coverage probe
-- -----------------------------------------------------------------------------
-- Trigger: "is LOCANCESTOR populated", "do we have closure tables"
SELECT
    'locancestor' AS table_name,
    COUNT(*)      AS row_count,
    COUNT(DISTINCT systemid) AS distinct_systems,
    COUNT(DISTINCT siteid)   AS distinct_sites
FROM :catalog.:silver_schema.locancestor

UNION ALL

SELECT 'assetancestor', COUNT(*), 1, COUNT(DISTINCT siteid)
FROM :catalog.:silver_schema.assetancestor;


-- -----------------------------------------------------------------------------
-- 10. Open WOs rolled up to a location parent (composes with work-orders)
-- -----------------------------------------------------------------------------
-- Trigger: "open WOs under station X", "backlog rollup by region"
-- This skill supplies the GROUPING (location rollup). The open-status set + the
-- WOCLASS/ISTASK/HISTORYFLAG filters are owned by maximo-work-orders / overview:
-- STATUS stores the customer-renamable synonym (VALUE), so resolve via
-- SYNONYMDOMAIN rather than hard-coding literals; HISTORYFLAG=0 keeps history out.
-- See maximo-overview for the universal mechanics; defer the open-set definition
-- to maximo-work-orders.
SELECT
    la.ancestor                                            AS rollup_location,
    COUNT(*)                                               AS open_wo_count,
    SUM(CASE WHEN datediff(DAY, w.reportdate, current_date()) > 90 THEN 1 ELSE 0 END)
                                                            AS aged_over_90d
FROM :catalog.:silver_schema.workorder w
JOIN :catalog.:silver_schema.locancestor la
    ON la.location = w.location AND la.siteid = w.siteid AND la.systemid = 'PRIMARY'
WHERE w.woclass = 'WORKORDER'
  AND w.istask = 0
  AND w.historyflag = 0
  -- Resolve the open set from internal MAXVALUEs so customer synonyms are caught:
  AND w.status IN (
        SELECT value FROM :catalog.:silver_schema.synonymdomain
        WHERE domainid = 'WOSTATUS'
          AND maxvalue NOT IN ('COMP', 'CLOSE', 'CAN')
  )
GROUP BY la.ancestor
ORDER BY open_wo_count DESC
LIMIT 50;
