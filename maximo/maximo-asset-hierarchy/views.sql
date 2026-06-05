-- =============================================================================
-- Maximo Asset & Location Hierarchy — Gold Views
-- =============================================================================
-- Substitute :catalog.:silver_schema and :catalog.:gold_schema.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_location_rollup_keys
-- Per-(location, ancestor) rollup key with depth. Designed for "for each
-- location, give me every ancestor including itself" — denormalized for fast
-- JOIN-and-GROUP queries.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_location_rollup_keys
COMMENT 'Denormalized rollup keys for locations. One row per (location, ancestor) pair including self-row at depth 0. Filter SYSTEMID for the hierarchy you want. Use as a JOIN target for hierarchical rollup queries.'
AS
WITH base AS (
    SELECT
        location,
        ancestor,
        siteid,
        systemid
    FROM :catalog.:silver_schema.locancestor

    UNION

    -- Add self rows in case the customer's LOCANCESTOR doesn't include them
    SELECT
        l.location AS location,
        l.location AS ancestor,
        l.siteid,
        'PRIMARY'  AS systemid
    FROM :catalog.:silver_schema.locations l
    WHERE l.__END_AT IS NULL
)
SELECT
    b.location,
    b.ancestor,
    b.siteid,
    b.systemid,
    -- Compute depth via a self-join shortcut: depth = how many descendants are
    -- between this ancestor and the location. Approximate; if customer
    -- materialized depth in LOCANCESTOR, use that column instead.
    (
        SELECT COUNT(*) FROM :catalog.:silver_schema.locancestor mid
        WHERE mid.location = b.location
          AND mid.siteid   = b.siteid
          AND mid.systemid = b.systemid
          AND mid.ancestor != b.location
          AND EXISTS (
              SELECT 1 FROM :catalog.:silver_schema.locancestor sub
              WHERE sub.location = mid.ancestor
                AND sub.ancestor = b.ancestor
                AND sub.siteid   = b.siteid
                AND sub.systemid = b.systemid
          )
    ) AS depth_below_ancestor,
    a_loc.description                                       AS ancestor_description,
    a_loc.type                                              AS ancestor_type,
    l_loc.description                                       AS location_description
FROM base b
LEFT JOIN :catalog.:silver_schema.locations a_loc
    ON a_loc.location = b.ancestor AND a_loc.siteid = b.siteid AND a_loc.__END_AT IS NULL
LEFT JOIN :catalog.:silver_schema.locations l_loc
    ON l_loc.location = b.location AND l_loc.siteid = b.siteid AND l_loc.__END_AT IS NULL;


-- -----------------------------------------------------------------------------
-- v_asset_rollup_keys
-- Per-(asset, ancestor) rollup key for asset hierarchies via ASSETANCESTOR.
-- Includes self row.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_asset_rollup_keys
COMMENT 'Denormalized rollup keys for assets. One row per (assetnum, ancestor) pair including self at depth 0. Use as a JOIN target for hierarchical rollups by asset parent.'
AS
SELECT
    aa.assetnum, aa.ancestor, aa.siteid,
    aa.hierarchylevels                                      AS depth_below_ancestor,
    a_anc.description                                       AS ancestor_description,
    a_anc.classstructureid                                  AS ancestor_class
FROM :catalog.:silver_schema.assetancestor aa
LEFT JOIN :catalog.:silver_schema.asset a_anc
    ON a_anc.assetnum = aa.ancestor AND a_anc.siteid = aa.siteid AND a_anc.__END_AT IS NULL

UNION

-- Self rows
SELECT
    a.assetnum, a.assetnum AS ancestor, a.siteid,
    0                                                       AS depth_below_ancestor,
    a.description                                           AS ancestor_description,
    a.classstructureid                                      AS ancestor_class
FROM :catalog.:silver_schema.asset a
WHERE a.__END_AT IS NULL;


-- -----------------------------------------------------------------------------
-- v_class_tree
-- Flattened classification hierarchy via recursive CTE on CLASSSTRUCTURE.
-- One row per (root, descendant) pair with depth. Maximo doesn't ship a
-- CLASSANCESTOR closure table — this view replaces that need.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_class_tree
COMMENT 'Flattened classification tree via recursive CTE on CLASSSTRUCTURE.PARENT. One row per (root_class, descendant_class) pair with depth. Replaces the missing CLASSANCESTOR.'
AS
WITH RECURSIVE class_tree (root, root_description, descendant_class, descendant_description, depth) AS (
    SELECT
        cs.classstructureid                                 AS root,
        cs.description                                      AS root_description,
        cs.classstructureid                                 AS descendant_class,
        cs.description                                      AS descendant_description,
        0                                                   AS depth
    FROM :catalog.:silver_schema.classstructure cs

    UNION ALL

    SELECT
        ct.root,
        ct.root_description,
        cs.classstructureid                                 AS descendant_class,
        cs.description                                      AS descendant_description,
        ct.depth + 1                                        AS depth
    FROM class_tree ct
    JOIN :catalog.:silver_schema.classstructure cs
        ON cs.parent = ct.descendant_class
    WHERE ct.depth < 20    -- defensive cap
)
SELECT
    root                                                    AS root_class,
    root_description,
    descendant_class,
    descendant_description,
    depth                                                   AS depth_from_root
FROM class_tree;
