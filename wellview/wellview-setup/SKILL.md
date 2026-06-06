---
name: wellview-setup
description: |
  Use to bootstrap a customer's Peloton WellView deployment in this Databricks
  workspace — introspect the WV/LV/SYS schema (200-300 tables), generate a
  workspace glossary mapping PHYSICAL tables/columns to canonical WellView
  concepts, record the MASTER UNIT of every numeric column (depth/footage feet
  vs metres, cost currency), decode the LV code tables, and register Unity
  Catalog comments on the Silver tables (preview-then-apply, gated on approval).
  The load-bearing precondition: without an accurate mapping AND units, every
  analytical WellView skill produces confident, invisible errors. Triggers on:
  "set up WellView", "install the WellView family", "configure WellView for
  Genie", "Genie doesn't know our WellView tables", "what units are our depths
  in", "decode our WellView codes", "register UC comments for WellView",
  "preview WellView comments".
compatibility: Requires databricks CLI >= v0.294.0 (experimental aitools)
metadata:
  version: "0.1.0"
parent: wellview-overview
---

# WellView Setup

The customer-specific deployment-knowledge layer. WellView follows strict conventions, but the
**physical names, master units, and code values are per-install** and Peloton publishes no public
data dictionary. This skill captures that and writes the durable facts into Unity Catalog comments
so Genie reads them directly every turn.

> **FIRST:** load `wellview-overview` for the record tree, the `WV`/`LV`/`SYS` grammar, and the
> universal gotchas (master units, calc-vs-stored, one-well-many-jobs, `LV` decode).

## When to use

- "Set up the WellView family in my workspace"
- "Map our schema to WellView / Genie doesn't understand our table names"
- "What units are our depth / footage / cost stored in?"
- "Decode our WellView operation / NPT / cost codes"
- "Preview the UC comments before applying"

## Top gotchas

1. **Preview before apply.** UC `ALTER TABLE … COMMENT` modifies customer-owned objects.
   `scripts/apply_uc_comments.py` defaults to preview (`--apply=false`). **Never run `--apply`
   without showing the diff and getting explicit approval** (the repo's central safety rule).
2. **Units are the highest-value fact.** A glossary without the **master unit per numeric column**
   lets analytical skills compare feet to metres (or mix currencies) silently. Source units from
   `SYSUNIT`; confirm in the interview; never finalize from sample values alone.
3. **The skill is the staging ground.** Facts that fit cleanly in a column comment graduate to
   `wellview_comments.json` and get applied; everything else (multi-table semantics, jargon,
   NPT-rule, cost parentage) stays in the glossary skill content.

## Questions to surface first

Per-customer conventions with no defensible default:

1. **Master units + currency.** Feet or metres for depth/footage? Which cost currency (and any
   multi-currency wells)? This blocks every metric until pinned.
2. **NPT definition.** Productive flag vs `LVWVCODENPT`, and does planned downtime count? The
   analytical skills inherit this rule.
3. **Cost parentage + open-job convention.** Does daily cost parent off the report or the job?
   What `WVJOB.STATUS` values count as an "open / active" job?

## Pre-flight (per session)

1. **UC catalog/schema** holding the WellView Silver tables (e.g. `wellview.silver`, or the
   Peloton-ETL-on-Snowflake landing schema).
2. **Customer short name** for the glossary skill filename (e.g. `northstar`).
3. **A SQL warehouse ID** (only for the `--apply` step) and a **business contact** for the interview.

## Workflow

A profile-then-interview-then-generate sequence; UC-comment application is **opt-in and gated**.

1. **Profile (read-only).** Inventory the `WV`/`LV`/`SYS` families by prefix and discover the spine
   tables' columns + samples (`scripts/introspect_schema.py`, wrapping
   [`data-exploration`](../../_common/data-exploration/)). Flag every numeric column as needing a
   unit decision and every coded column as needing an `LV` decode. **Scope to active modules** —
   a well's schema may have 200–300 tables but only some domains are populated.
2. **Interview.** Walk [interview-playbook.md](interview-playbook.md) in batches; lead with the
   profile draft. Confirm units, NPT rule, cost parentage, open-job set, `LV` decodes, business jargon.
3. **Generate the glossary skill** (`scripts/generate_glossary.py`) → a workspace-tier
   `<customer>-wellview-glossary/SKILL.md` (uses [glossary_template.md](glossary_template.md); see
   [example_glossary.md](example_glossary.md)).
4. **Preview UC comments** (`scripts/apply_uc_comments.py --apply=false`) — prints every
   `COMMENT ON` / `ALTER TABLE … ALTER COLUMN COMMENT` from [wellview_comments.json](wellview_comments.json),
   especially the **master unit** in each numeric column's comment.
5. **Apply on approval only** (`scripts/apply_uc_comments.py --apply --warehouse-id <id>`). Never
   without explicit user approval of the previewed statements.

## What's in this skill

- [interview-playbook.md](interview-playbook.md) — **load when** running the interview. Batched questions; leads with the profile.
- [glossary_template.md](glossary_template.md) — structure of the generated workspace glossary skill.
- [example_glossary.md](example_glossary.md) — **load when** you want a worked "good" output.
- [scripts/introspect_schema.py](scripts/introspect_schema.py) — read-only profile / draft mapping (wraps the data-exploration tooling).
- [scripts/generate_glossary.py](scripts/generate_glossary.py) — renders the glossary skill from `answers.json`.
- [scripts/apply_uc_comments.py](scripts/apply_uc_comments.py) — **preview/apply UC comments. Preview is the default; `--apply` is gated on approval.**
- [wellview_comments.json](wellview_comments.json) — the canonical comment content (per-table/column, incl. units) for this source.

## What NOT to do

- **Never run `--apply` without explicit user approval** of the previewed statements. The repo's central safety rule.
- **Don't re-teach UC mechanics** (`ALTER TABLE … COMMENT`) — reference [`databricks-unity-catalog`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-unity-catalog).
- Don't finalize a unit from sample values — confirm in the interview.
- Don't fabricate a mapping the customer can't confirm — write `_unknown_ — needs validation from <role>` and move on.
- Don't assume all 200–300 tables or all modules are in use.

## Composes with

- **`wellview-overview`** — the data-model anchor whose universal facts this skill captures customer *values* for.
- **[`databricks-unity-catalog`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-unity-catalog)** (platform) — the UC `ALTER TABLE` mechanics.
- All module skills (`wellview-daily-ops-cost`, …) — they consume the registered UC comments + glossary at query time without reloading.
