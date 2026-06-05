# <Source> Data Model

Broader entity diagram and cross-module concepts. Load when a question spans multiple modules.

## Core entities

| Entity | Table(s) | Owns it |
|---|---|---|
| Work Order | `WORKORDER`, `WOSTATUS` | `<source>-work-orders` |
| Asset | `ASSET`, `ASSETANCESTOR` | `<source>-work-orders` + `<source>-asset-hierarchy` |
| Location | `LOCATIONS`, `LOCANCESTOR`, `LOCHIERARCHY` | `<source>-asset-hierarchy` |
| (add rows) | … | … |

## Cross-module relationships

- `WORKORDER.ASSETNUM` + `SITEID` → `ASSET`
- (add more)

## Conventions

- All business keys are `SITEID`-scoped composites unless noted.
- Status changes are audited in a parallel `*STATUS` table per entity.
