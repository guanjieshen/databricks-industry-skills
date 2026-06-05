# Maximo Asset & Location Hierarchy — Gotchas

## Contents

- 1. Closure tables vs naïve PARENT self-joins
- 2. `LOCHIERARCHY.SYSTEMID` filtering
- 3. `SITEID` propagation — the hierarchy-specific twist (universal rule owned by maximo-overview)
- 4. Closure tables may be missing — recursive CTE fallback
- 5. Physical hierarchy ≠ classification hierarchy
- 6. Self-inclusion convention varies (does ancestor include self?)
- 7. Depth limits for recursive CTEs
- 8. Network-type systems are graphs, not trees
- 9. `CLASSSTRUCTURE` doesn't ship with a closure table
- 10. `LOCATIONS.PARENT` and `LOCHIERARCHY` can drift

The first 5 are also inline in `SKILL.md`. Reproduced here in full with additional gotchas for queries that go deeper.

## 1. Closure tables vs naïve `PARENT` self-joins

A single-level self-join walks one parent step only:

```sql
-- WRONG for multi-level rollup — returns only immediate children
SELECT child.location FROM locations child
JOIN locations parent ON parent.location = child.parent
WHERE parent.location = 'REGION-WEST';
```

`LOCANCESTOR` does the right thing for arbitrary depth:

```sql
-- All descendants of REGION-WEST (at any depth)
SELECT la.location FROM locancestor la
WHERE la.ancestor = 'REGION-WEST'
  AND la.systemid = 'PRIMARY'
  AND la.siteid   = '<your-siteid>';
```

The shipped `v_location_rollup_keys` view materializes this and is the recommended entry point for hierarchical queries.

## 2. `LOCHIERARCHY.SYSTEMID` filtering

Locations belong to multiple hierarchies. `LOCHIERARCHY` has one row per (location, parent, system). Most analytics want the **primary operating hierarchy** (`SYSTEMID = 'PRIMARY'`).

```sql
-- WRONG — returns one row per (location, system), inflating counts
SELECT lh.location, lh.parent FROM lochierarchy lh
WHERE lh.location = 'STN-04';

-- RIGHT
SELECT lh.location, lh.parent FROM lochierarchy lh
WHERE lh.location = 'STN-04' AND lh.systemid = 'PRIMARY';
```

Workspace glossary should specify the customer's hierarchy system convention.

## 3. `SITEID` propagation — the hierarchy-specific twist

The SITEID composite-key rule is universal and owned by `maximo-overview` (don't re-derive it). The hierarchy-specific twist: a rollup query has **two** joins to thread `SITEID` through — the closure JOIN (`LOCANCESTOR`/`ASSETANCESTOR`) *and* the metric JOIN (workorder/asset/cost). Dropping it on either side cross-products. `LOCANCESTOR` rows carry `SITEID`; so does the metric table.

```sql
-- RIGHT — SITEID on BOTH the closure join and the metric join
SELECT la.ancestor, COUNT(*)
FROM :catalog.:silver_schema.locancestor la
JOIN :catalog.:silver_schema.workorder w
    ON w.location = la.location AND w.siteid = la.siteid   -- metric join
WHERE la.ancestor = 'STN-04'
  AND la.siteid   = '<your-siteid>'                        -- closure filter
  AND la.systemid = 'PRIMARY'
GROUP BY la.ancestor;
```

## 4. Closure tables may be missing — recursive CTE fallback

Probe first:

```sql
SELECT COUNT(*) FROM locancestor LIMIT 1;
-- Or for the materialized-table check:
SELECT table_name FROM system.information_schema.tables
WHERE table_schema = '<silver_schema>' AND table_name = 'locancestor';
```

If `LOCANCESTOR` doesn't exist or is sparse, fall back to a recursive CTE:

```sql
WITH RECURSIVE loc_tree (root, location, depth) AS (
    SELECT location, location, 0 FROM locations
    WHERE location = 'REGION-WEST' AND siteid = 'MAIN-WEST'

    UNION ALL

    SELECT t.root, l.location, t.depth + 1
    FROM loc_tree t
    JOIN locations l ON l.parent = t.location AND l.siteid = 'MAIN-WEST'
    WHERE t.depth < 20   -- defensive limit
)
SELECT location FROM loc_tree;
```

Note: the recursive CTE walks `LOCATIONS.PARENT` which is single-system. For multi-system traversal, walk `LOCHIERARCHY` filtered to the system you want.

## 5. Physical hierarchy ≠ classification hierarchy

| Question | Hierarchy |
|---|---|
| "All assets at station 4" | Physical (LOCATIONS / LOCANCESTOR) |
| "All compressors" | Classification (CLASSSTRUCTURE) |
| "All centrifugal pumps at station 4" | Both — physical filter on LOCANCESTOR + classification filter on CLASSSTRUCTURE |

Don't try to traverse one when you mean the other. The shipped `v_class_tree` view flattens the classification side; `v_location_rollup_keys` / `v_asset_rollup_keys` flatten the physical side.

## 6. Self-inclusion convention varies

Some Maximo installations have `LOCANCESTOR` rows where `LOCATION = ANCESTOR` (the location is an ancestor of itself, at depth 0). Others do not. Check before assuming:

```sql
SELECT COUNT(*) FROM locancestor WHERE location = ancestor LIMIT 1;
```

If self-inclusion is missing and you want "all assets at or under REGION-WEST", you need to `UNION` the location itself with its descendants. The shipped views include the self row explicitly to remove ambiguity.

## 7. Depth limits for recursive CTEs

Some Maximo customers have hierarchies 10+ levels deep (especially pipeline operators with kilometer-level GIS-derived locations). Recursive CTEs without a depth cap can run unbounded if there's a data quality issue (a parent loop). Always include `WHERE depth < N` as a defensive cap (20 is reasonable for real Maximo hierarchies).

## 8. Network-type systems are graphs, not trees

`SYSTEM.NETWORK = 1` marks a network-type hierarchy (e.g. an electrical network where junctions have multiple parents). Closure tables for network systems can have ambiguous "ancestor" semantics. For network systems, prefer explicit graph traversal (e.g. shortest path) over generic rollups.

Most analytics target tree-type systems (`NETWORK = 0`, typically `PRIMARY`). If a customer has network systems, ask before assuming a rollup is meaningful.

## 9. `CLASSSTRUCTURE` doesn't ship with a closure table

Unlike `LOCATIONS` and `ASSET`, `CLASSSTRUCTURE` has only the `PARENT` self-reference — there's no `CLASSANCESTOR` in stock Maximo. For class hierarchy rollups, you must either:

- Use the shipped `v_class_tree` view (recursive CTE, materialized as a view)
- Write an inline recursive CTE

## 10. `LOCATIONS.PARENT` and `LOCHIERARCHY` can drift

`LOCATIONS.PARENT` is a denormalized cache; `LOCHIERARCHY` is the system of record (for multi-system membership). In a properly-maintained Maximo, `LOCATIONS.PARENT` equals `LOCHIERARCHY.PARENT` for `SYSTEMID = 'PRIMARY'`. In practice, manual data fixes occasionally desync them.

If you see weird rollup numbers, probe:

```sql
SELECT l.location, l.parent AS denormalized_parent,
       lh.parent AS lochierarchy_parent
FROM locations l
JOIN lochierarchy lh
    ON lh.location = l.location AND lh.siteid = l.siteid AND lh.systemid = 'PRIMARY'
WHERE l.parent <> lh.parent
LIMIT 20;
```

If this returns rows, `LOCATIONS.PARENT` is stale. Prefer `LOCHIERARCHY` for system-aware traversal; prefer `LOCANCESTOR` for closure queries.
