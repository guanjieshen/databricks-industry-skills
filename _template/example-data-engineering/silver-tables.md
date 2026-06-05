# <Source> — Curated Silver Tables

The subset of `<source>`'s tables that downstream module skills depend on. Materializing more than this is a silent cost; materializing less breaks specific modules.

## Tables

| Table | Grain | CDC key | Notes |
|---|---|---|---|
| `EXAMPLE_TABLE` | one row per business object | `(EXAMPLE_ID, SITEID)` | SCD2 on STATUS + DESCRIPTION |
| `EXAMPLE_HISTORY_TABLE` | one row per status change | append-only | No CDC needed — already history-shaped |
| (add rows per source) | … | … | … |

## Cross-source-family notes

- Some customers extend `EXAMPLE_TABLE` via a `_EXT` companion table. Check via `<source>-setup`'s introspect step.
- `LOCANCESTOR` / `ASSETANCESTOR` closure tables are typically materialized as Gold from a recursive CTE on `LOCATIONS.PARENT` / `ASSET.PARENT`.
