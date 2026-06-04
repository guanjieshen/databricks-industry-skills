-- =============================================================================
-- Maximo Asset & Location Hierarchy — UC SQL Function (Trusted UDF) DDL
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} and {{catalog}}.{{metrics_schema}}.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS {{catalog}}.{{metrics_schema}}
COMMENT 'Trusted-asset SQL functions for Maximo asset / location hierarchy';


-- -----------------------------------------------------------------------------
-- descendant_count — how many descendants does this location have?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.descendant_count(
    root_location STRING,
    site_id STRING,
    system_id STRING COMMENT 'Hierarchy SYSTEMID — typically PRIMARY'
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of descendant LOCATIONS under a parent in a hierarchy system (excludes self).'
RETURN (
    SELECT COUNT(*)
    FROM {{catalog}}.{{silver_schema}}.locancestor la
    WHERE la.ancestor = root_location
      AND la.siteid   = site_id
      AND la.systemid = system_id
      AND la.location <> la.ancestor
);


-- -----------------------------------------------------------------------------
-- is_ancestor — is location A an ancestor of location B?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.is_ancestor(
    ancestor_loc STRING,
    descendant_loc STRING,
    site_id STRING,
    system_id STRING
)
RETURNS BOOLEAN
COMMENT 'Trusted predicate: TRUE if ancestor_loc is an ancestor of descendant_loc in the given hierarchy system.'
RETURN (
    SELECT EXISTS (
        SELECT 1 FROM {{catalog}}.{{silver_schema}}.locancestor la
        WHERE la.location = descendant_loc
          AND la.ancestor = ancestor_loc
          AND la.siteid   = site_id
          AND la.systemid = system_id
    )
);


-- -----------------------------------------------------------------------------
-- level_in_hierarchy — depth of a location from the root of its hierarchy
-- -----------------------------------------------------------------------------
-- Depth = number of distinct ancestors (excluding self).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.level_in_hierarchy(
    location_param STRING,
    site_id STRING,
    system_id STRING
)
RETURNS INT
COMMENT 'Trusted metric: depth of a location from root in the given hierarchy system. Root level = 0.'
RETURN (
    SELECT CAST(COUNT(*) AS INT)
    FROM {{catalog}}.{{silver_schema}}.locancestor la
    WHERE la.location = location_param
      AND la.siteid   = site_id
      AND la.systemid = system_id
      AND la.ancestor <> la.location
);


-- -----------------------------------------------------------------------------
-- path_to_root — concatenated parent chain
-- -----------------------------------------------------------------------------
-- Returns a slash-separated path from root down to the location.
-- Approximate when LOCANCESTOR doesn't carry an explicit depth column —
-- relies on chain traversal via LOCHIERARCHY.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.path_to_root(
    location_param STRING,
    site_id STRING,
    system_id STRING
)
RETURNS STRING
COMMENT 'Trusted metric: slash-separated path from hierarchy root to the location.'
RETURN (
    WITH RECURSIVE chain (location, parent, path, depth) AS (
        SELECT
            lh.location,
            lh.parent,
            lh.location                                     AS path,
            0                                               AS depth
        FROM {{catalog}}.{{silver_schema}}.lochierarchy lh
        WHERE lh.location = location_param
          AND lh.siteid   = site_id
          AND lh.systemid = system_id

        UNION ALL

        SELECT
            lh.location,
            lh.parent,
            lh.location || ' / ' || c.path                  AS path,
            c.depth + 1
        FROM chain c
        JOIN {{catalog}}.{{silver_schema}}.lochierarchy lh
            ON lh.location = c.parent
           AND lh.siteid   = site_id
           AND lh.systemid = system_id
        WHERE c.depth < 20    -- defensive cap
          AND c.parent IS NOT NULL
    )
    SELECT path
    FROM chain
    ORDER BY depth DESC
    LIMIT 1
);


-- -----------------------------------------------------------------------------
-- cost_rolled_up_to_ancestor — composes with maximo-maintenance-cost
-- -----------------------------------------------------------------------------
-- Total maintenance cost (labor + material) attributable to assets under a
-- location ancestor in a window. Uses LABTRANS + MATUSETRANS with ASSET join.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.cost_rolled_up_to_ancestor(
    ancestor_loc STRING,
    site_id STRING,
    system_id STRING,
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: total maintenance cost (LABTRANS + MATUSETRANS) for assets whose LOCATION is descendant of ancestor_loc in the named hierarchy system.'
RETURN (
    WITH descendants AS (
        SELECT location FROM {{catalog}}.{{silver_schema}}.locancestor
        WHERE ancestor = ancestor_loc AND siteid = site_id AND systemid = system_id
    ),
    asset_set AS (
        SELECT a.assetnum FROM {{catalog}}.{{silver_schema}}.asset a
        WHERE a.siteid = site_id AND a.__END_AT IS NULL
          AND a.location IN (SELECT location FROM descendants)
    ),
    labor AS (
        SELECT SUM(lt.linecost) AS cost
        FROM {{catalog}}.{{silver_schema}}.labtrans lt
        JOIN {{catalog}}.{{silver_schema}}.workorder w
            ON w.wonum = lt.wonum AND w.siteid = lt.siteid
        WHERE lt.siteid = site_id
          AND lt.transtype = 'WORK'
          AND lt.startdate BETWEEN window_start AND window_end
          AND w.assetnum IN (SELECT assetnum FROM asset_set)
    ),
    materials AS (
        SELECT
            SUM(CASE WHEN mt.issuetype = 'ISSUE'  THEN mt.linecost ELSE 0 END)
          - SUM(CASE WHEN mt.issuetype = 'RETURN' THEN mt.linecost ELSE 0 END) AS cost
        FROM {{catalog}}.{{silver_schema}}.matusetrans mt
        JOIN {{catalog}}.{{silver_schema}}.workorder w
            ON w.wonum = mt.wonum AND w.siteid = mt.siteid
        WHERE mt.siteid = site_id
          AND mt.issuetype IN ('ISSUE', 'RETURN')
          AND mt.transdate BETWEEN window_start AND window_end
          AND w.assetnum IN (SELECT assetnum FROM asset_set)
    )
    SELECT COALESCE(l.cost, 0) + COALESCE(m.cost, 0)
    FROM labor l, materials m
);


-- =============================================================================
-- Grants (uncomment + substitute principal)
-- =============================================================================
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.descendant_count           TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.is_ancestor                TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.level_in_hierarchy         TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.path_to_root               TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.cost_rolled_up_to_ancestor TO `{{principal}}`;
