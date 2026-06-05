---
name: example-setup
description: |
  REPLACE THIS. Use to bootstrap the customer's deployment of <source> in this
  Databricks workspace — workspace glossary, UC comments registration on
  Silver tables, customer-convention capture (open-status set, MTBF
  definition, custom worktype codes, …). Triggers on: "set up <source>",
  "install the <source> family", "register UC comments for <source>",
  "configure <source> glossary", "preview <source> UC comments", "apply
  <source> comments", "what does my <source> deployment look like".
metadata:
  version: "0.1.0"
parent: example-overview
---

# <Source> Setup

The customer-specific deployment-knowledge layer. Different customers run different `<source>` deployments — different status sets, custom columns, naming conventions, metric definitions. This skill captures that and writes it into Unity Catalog comments so Genie reads it directly during every turn.

> **FIRST:** load `<source>-overview` for baseline data-model literacy.

## When to use

- "Set up the `<source>` family in my workspace"
- "Register UC comments on my `<source>` Silver tables"
- "Capture our customer-specific `<source>` conventions"
- "Preview the comments before applying"
- "What does my `<source>` deployment look like?" (introspection)

## Top gotchas

1. **Preview before apply.** UC `ALTER TABLE … COMMENT` modifies customer-owned objects. The scripts in this skill default to `--apply=false` (preview only). Never run `--apply` without showing the diff to the user and getting explicit approval.
2. **Customer customization is the point.** Don't blindly apply default conventions (open-status set, MTBF formula, …). Always interview first; capture the customer's actual values.
3. **The skill is the staging ground.** Facts that fit cleanly in a column comment graduate to `<source>_comments.json` and get applied. Facts that don't (multi-table semantics, glossary mappings, multi-valid-definition guards) stay in skill content.

## Questions to surface first

Per-customer conventions with no defensible default:

1. **Open-status set.** Maximo defaults usually mean "all statuses except COMP/CLOSE/CAN" but customers extend `WOSTATUS` synonyms. Confirm the exact set.
2. **Canonical metric definitions** that have multiple valid forms — MTBF formula, PM compliance, "bad actor" — which does this organization use?
3. **Custom worktype codes** that diverge from defaults (CM/PM/EM) — what does this deployment use?

## Pre-flight (per session)

1. **UC catalog and schema** holding the Silver tables (e.g. `eam.maximo_silver`).
2. **A SQL warehouse ID** for the apply step (only needed when running with `--apply`).
3. **A business contact** for customer-conventions interview.

## Workflow

The full bootstrap is a five-step sequence — each step gated on user approval before proceeding:

1. **Introspect schema** (`scripts/introspect_schema.py`) — discover which tables/columns actually exist in the customer's UC.
2. **Interview** — walk the customer through the Questions-to-surface-first list and record answers.
3. **Generate glossary skill** — emit a workspace-tier `<customer>-<source>-glossary` skill mapping their business jargon → physical schema.
4. **Preview UC comments** (`scripts/apply_uc_comments.py` with `--apply=false`) — print every `COMMENT ON TABLE` / `ALTER TABLE … ALTER COLUMN COMMENT` statement.
5. **Apply on approval only** (`scripts/apply_uc_comments.py --apply --warehouse-id <id>`). Never run this step without explicit user approval of the previewed statements.

## What's in this skill

- [scripts/apply_uc_comments.py](scripts/apply_uc_comments.py) — preview/apply UC comments. **Preview is the default; `--apply` is gated.**
- [scripts/introspect_schema.py](scripts/introspect_schema.py) — read-only schema discovery against the customer's UC.
- [example_comments.json](example_comments.json) — the canonical comment content for THIS source's MBOs / tables.
- [interview-playbook.md](interview-playbook.md) — the customer-conventions interview script.

## What NOT to do

- **Never run `--apply` without explicit user approval** of the previewed statements. This is the repo's central safety rule.
- **Don't re-teach UC mechanics** (how `ALTER TABLE … COMMENT` works) — reference [`databricks-unity-catalog`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-unity-catalog) for that.
- **Don't blindly write your own comment defaults** — interview first.

## Composes with

- **`<source>-overview`** — for the data-model anchor.
- **[`databricks-unity-catalog`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-unity-catalog)** (platform layer) — for the UC `ALTER TABLE` mechanics.
- All module skills — they consume the registered UC comments at query time without re-loading.
