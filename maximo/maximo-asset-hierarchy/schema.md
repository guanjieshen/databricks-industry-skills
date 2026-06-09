# Maximo Asset & Location Hierarchy — Schema Reference

## Contents

- `LOCATIONS` (the key columns for hierarchy)
- `LOCHIERARCHY` — multi-system parent-child rows
- `LOCANCESTOR` — location closure table
- `ASSET` (PARENT column) and `ASSETANCESTOR` — asset closure
- `SYSTEM` — hierarchy system definitions
- `CLASSSTRUCTURE` — asset / location classification tree
- `CLASSSPEC` and `ASSETSPEC` — specs at class and asset level
- Cardinality summary

For the universal Maximo data model (with LOCATIONS / ASSET base columns), see `maximo-overview`. This file focuses on hierarchy mechanics.

## `LOCATIONS` (hierarchy-relevant columns)

| Column | Notes |
|---|---|
| `LOCATION` | Business key — unique within SITEID |
| `SITEID` | Composite |
| `DESCRIPTION` | Free text |
| `TYPE` | `OPERATING`, `STOREROOM`, `LABOR`, `COURIER`, `REPAIR`, `SALVAGE`, `VENDOR` |
| `PARENT` | Immediate parent (one-level — for multi-level traversal use closure tables) |
| `LOCHIERARCHYID` | Convenience surrogate for the row in LOCHIERARCHY (links the multi-system info) |

## `LOCHIERARCHY` — multi-system parent-child rows

One row per (`LOCATION`, `PARENT`, `SYSTEMID`). The same physical location can appear in **multiple hierarchies** (Operating, Storeroom, Network) — each system has its own parent chain for that location.

| Column | Notes |
|---|---|
| `LOCATION` | The child |
| `PARENT` | The parent |
| `SYSTEMID` | The hierarchy this row belongs to — typically `PRIMARY` |
| `SITEID` | Composite |

**Always filter by `SYSTEMID`** unless you specifically want cross-system traversal:

```sql
SELECT location, parent FROM lochierarchy
WHERE systemid = 'PRIMARY' AND siteid = 'ZONE-W';
```

## `LOCANCESTOR` — location closure table

One row per **(ancestor, descendant) pair at any depth in a system**. The IBM-canonical traversal mechanism for rollups.

| Column | Notes |
|---|---|
| `LOCATION` | The descendant |
| `ANCESTOR` | An ancestor at any depth |
| `SYSTEMID` | Hierarchy system — same filter as LOCHIERARCHY |
| `SITEID` | Composite |

```sql
-- All locations under (and including) station 'STN-04'
SELECT la.location FROM locancestor la
WHERE la.ancestor = 'STN-04'
  AND la.systemid = 'PRIMARY'
  AND la.siteid   = 'ZONE-W';

-- All ancestors of valve 'V-42' (root chain)
SELECT la.ancestor FROM locancestor la
WHERE la.location = 'V-42'
  AND la.systemid = 'PRIMARY'
  AND la.siteid   = 'ZONE-W';
```

Includes the location itself as ancestor of itself in typical Maximo installations — verify the customer's convention.

## `ASSET` (PARENT) — self-join asset hierarchy

`ASSET.PARENT` references another `ASSETNUM` (one-level). Combined with `ASSETANCESTOR` for closure.

## `ASSETANCESTOR` — asset closure table

| Column | Notes |
|---|---|
| `ASSETNUM` | Descendant |
| `ANCESTOR` | Ancestor at any depth |
| `SITEID` | Composite |
| `HIERARCHYLEVELS` | Number of levels between descendant and ancestor (`0` = self if convention includes it) |

```sql
-- All assets under pump skid PMP-SKID-7
SELECT aa.assetnum FROM assetancestor aa
WHERE aa.ancestor = 'PMP-SKID-7' AND aa.siteid = 'ZONE-W';
```

## `SYSTEM` — hierarchy system definitions

Defines the systems a location can belong to. Standard out-of-the-box system is `PRIMARY`. O&G customers often have additional systems (e.g. `PROCESS`, `UTILITY`).

| Column | Notes |
|---|---|
| `SYSTEMID` | System identifier |
| `ORGID` | Org-scoped |
| `DESCRIPTION` | Free text |
| `NETWORK` | `1` if this is a network-type system (graph rather than tree) |
| `PRIMARYSYSTEM` | `1` if this is the default system |

## `CLASSSTRUCTURE` — asset / location classification tree

A taxonomy hierarchy applied to assets and locations. Different from physical hierarchy.

| Column | Notes |
|---|---|
| `CLASSSTRUCTUREID` | Class identifier |
| `PARENT` | Parent class |
| `DESCRIPTION` | E.g. "Centrifugal Pump", "Rotating Equipment", "Mechanical" |
| `CLASSIFICATIONID` | Full classification path string in some installs |
| `USEWITH` | Whether this class applies to ASSET, LOCATIONS, ITEM, etc. |

```sql
-- All assets in classes under "Rotating Equipment"
-- (Maximo doesn't ship a CLASSANCESTOR closure table by default — use recursive CTE)
WITH RECURSIVE class_tree (id, root) AS (
    SELECT classstructureid, classstructureid FROM classstructure
    WHERE description = 'Rotating Equipment'
    UNION ALL
    SELECT cs.classstructureid, ct.root
    FROM classstructure cs
    JOIN class_tree ct ON cs.parent = ct.id
)
SELECT a.assetnum, a.classstructureid
FROM asset a
JOIN class_tree ct ON ct.id = a.classstructureid;
```

## `CLASSSPEC` and `ASSETSPEC` — specifications

`CLASSSPEC` defines specification attributes at the class level (e.g. "pumps have a flow-rate attribute"). `ASSETSPEC` is the per-asset values for those specs.

| Table | Key columns |
|---|---|
| `CLASSSPEC` | `CLASSSTRUCTUREID`, `ASSETATTRID`, `DATATYPE`, `MANDATORY` |
| `ASSETSPEC` | `ASSETNUM`, `SITEID`, `ASSETATTRID`, `ALNVALUE` / `NUMVALUE` / `DATEVALUE` |

For analytics: "show me all pumps with flow rate > 5000 gpm" → join `ASSETSPEC` filtering on `ASSETATTRID = 'FLOWRATE'` and `NUMVALUE > 5000`.

## Cardinality summary

| Relationship | Cardinality |
|---|---|
| `LOCATIONS` → `LOCATIONS` (parent/child via PARENT) | self, 1-level |
| `LOCATIONS` → `LOCHIERARCHY` | 1 : N (one row per system membership) |
| `LOCATIONS` → `LOCANCESTOR` | 1 : N (one row per ancestor at any depth) |
| `SYSTEM` → `LOCHIERARCHY` | 1 : N |
| `ASSET` → `ASSET` (PARENT) | self, 1-level |
| `ASSET` → `ASSETANCESTOR` | 1 : N |
| `CLASSSTRUCTURE` → `CLASSSTRUCTURE` (PARENT) | self, 1-level |
| `CLASSSTRUCTURE` → `CLASSSPEC` | 1 : N |
| `ASSET` → `ASSETSPEC` | 1 : N |
| `CLASSSTRUCTURE` → `ASSET` (assets in this class) | 1 : N |
