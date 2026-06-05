---
name: example-overview
description: |
  REPLACE THIS. The family root — DELIBERATELY BROAD. This description should
  match ANY question about <source> so Genie loads it as baseline literacy
  before delegating to a more specific module skill. Include: source name +
  synonyms (e.g. "IBM Maximo, Maximo, EAM, CMMS, asset management"), the
  domain in one line ("work orders, assets, reliability, inventory, …"), and
  the kinds of customers who deploy it. Don't list every table; the module
  descriptions handle precision. Aim for "loads on anything <source>-related"
  not "loads only on the most specific question".
metadata:
  version: "0.1.0"
---

# <Source> Overview

The foundation skill for the `<source>` family. Loaded as baseline literacy for any question that touches this source. Module skills (`<source>-work-orders`, `<source>-<other>`, …) build on top.

## What this source is

One paragraph: who builds it, what it manages, the dominant data shapes (e.g. "IBM Maximo is the system of record for EAM — work orders, assets, locations, labor, PMs. Its data model is MBO-based with composite `SITEID`-scoped keys.").

## Module map

When the user's question is more specific, defer to the right module skill:

| Domain | Skill | Triggers |
|---|---|---|
| Work orders, backlog, labor | `<source>-work-orders` | "open WO backlog", "labor by craft", "completion time" |
| Reliability, MTBF/MTTR, PM compliance | `<source>-reliability` | "MTBF", "PM compliance", "bad-actor assets" |
| (add rows for each module in the family) | … | … |

## Universal gotchas

Cross-cutting traps that every module skill assumes you know. Detail per-module is in the module's `gotchas.md`.

- **Composite keys.** `WONUM`, `ASSETNUM`, `LOCATION`, etc. are unique only within `SITEID`. Always include the site in joins.
- **Status history vs current state.** Header tables hold *current* status; history lives in audit tables (e.g. `WOSTATUS`). Use the right one.
- **(add 2–3 more cross-cutting source-wide gotchas)**

## Pre-flight (per session)

1. **Catalog/schema** — confirm via the workspace glossary skill if installed, or ask.
2. **Glossary skill** — is a `<customer>-<source>-glossary` workspace skill installed? Prefer it for business-term resolution.

## What's in this skill

- [data-model.md](data-model.md) — **load when** the user's question crosses module boundaries or needs the broader entity diagram.
- [module-map.md](module-map.md) — optional. The same map as above but expanded with examples.

## Composes with

- **`<source>-setup`** — for one-time workspace bootstrap (glossary, UC comments).
- **`<source>-data-engineering`** — for Bronze→Silver/Gold pipeline questions.
- **`<source>-data-quality`** — for "this number looks wrong" diagnostics.
- All **`<source>-<module>`** skills — defer specific analytical work to them.
