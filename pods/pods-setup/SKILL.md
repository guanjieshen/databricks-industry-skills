---
name: pods-setup
description: |
  Use to bootstrap a customer's PODS workspace for Genie — introspects their
  PODS-ish schema, generates a workspace-tier glossary skill mapping their
  PHYSICAL columns/tables to canonical PODS concepts (and critically, the UNIT
  of each measure column), and registers Unity Catalog comments. Run ONCE per
  workspace. This is the load-bearing precondition: without an accurate mapping,
  the analytical PODS skills produce confident, invisible errors. Triggers on:
  "set up PODS for Genie", "configure Genie for our pipeline data", "Genie
  doesn't know our pipeline tables", "map our schema to PODS", "set up our PODS
  glossary", "what units are our measures in".
compatibility: Requires databricks CLI >= v0.294.0 (experimental aitools)
metadata:
  version: "0.1.0"
parent: pods-overview
---

# PODS Setup

Bootstrap a Databricks workspace so Genie Code can answer PODS questions accurately against the customer's **actual** schema. This is a **one-time setup** per workspace, run by the D&A / GIS team. After it completes, every other PODS skill works far more reliably.

> **FIRST:** load the `pods-overview` skill — it carries the PODS 7 data model, the linear-referencing networks, the module map, and the universal gotchas (foot-vs-meter units, route-vs-measure, ILI run vintage). This skill builds on that foundation.

**Why this is the most important skill in the family.** Operators "conform to PODS but not exactly" — renamed columns, different units, only some modules adopted. The analytical skills (`pods-ili-integrity`, etc.) are written against *canonical* PODS concepts. This skill builds the bridge from canonical → physical. Get it right and the analytical skills are accurate; skip it and Genie generates clean SQL against the wrong columns/units — **the failure the end user cannot see.**

Two outputs:

1. **A workspace-tier glossary skill** at `/Workspace/.assistant/skills/<customer>-pods-glossary/SKILL.md` mapping the customer's tables/columns to canonical PODS concepts, **with the unit of every measure column**, which modules are adopted, the route key, and business jargon (line names, segment names).
2. **UC table/column comments** registered on the PODS Silver tables.

## When to use

- "Set up PODS / our pipeline data for Genie"
- "Map our schema to PODS" / "Genie doesn't understand our table names"
- "What units are our stationing / measures in?" (this skill records that authoritatively)
- One of the first things a new customer runs after the PODS family is installed

## Pre-flight

1. **Catalog/schema location**: "Which catalog/schema holds your PODS / pipeline data?" (e.g. `pipeline.pods_silver`)
2. **Customer short name**: for skill filenames (e.g. `enbridge`, `acme-midstream`).
3. **Output scope**: workspace-wide (admin) or user-scoped?

## Workflow

### Phase 0 — Discover the schema (automated first pass)

Use the repo's [`data-exploration`](../../_common/data-exploration/) cross-cutting skill to discover what's actually in the workspace before mapping anything. It wraps `databricks experimental aitools tools` — the right discovery engine: it searches `information_schema` instead of manually walking catalogs, and `discover-schema` returns columns, types, 5-row samples, null counts, and row counts in one call. Let that skill auto-load alongside this one.

**Step 1 — find candidate PODS tables by keyword** (don't enumerate catalogs by hand):

```bash
databricks experimental aitools tools query \
  "SELECT table_catalog, table_schema, table_name
   FROM system.information_schema.tables
   WHERE table_schema = '<silver-schema>'
     AND (table_name ILIKE '%pipe%' OR table_name ILIKE '%ili%'
       OR table_name ILIKE '%anomal%' OR table_name ILIKE '%centerline%'
       OR table_name ILIKE '%route%' OR table_name ILIKE '%hca%'
       OR table_name ILIKE '%station%' OR table_name ILIKE '%cathodic%')" \
  --profile <PROFILE> --output json
```

**Step 2 — discover each candidate's schema + samples** (this is where you spot the measure columns and guess their units from sample values):

```bash
databricks experimental aitools tools discover-schema <catalog>.<schema>.<table> --profile <PROFILE>
```

Inspecting the 5-row samples is the fastest way to form a *hypothesis* about units (e.g. station values in the tens-of-thousands look like feet; values in the thousands along a 50-mile line look like meters) — but **always confirm units in the interview; never finalize a unit from samples alone.**

**Step 3 — run the introspection helper**, which wraps the same data-exploration commands and produces a draft mapping for the interview:

```bash
python scripts/introspect_schema.py \
  --catalog <catalog> --schema <silver-schema> \
  --profile <PROFILE> --output draft_mapping.json
```

The script uses `databricks experimental aitools tools query` + `discover-schema` under the hood, guesses each table's canonical PODS concept by column heuristics (e.g. `route_id` + a station-like column → an event table), and **flags every numeric measure column as needing a UNIT decision** — it cannot infer feet vs meters reliably, so that becomes a human confirmation in Batch 1 of the interview.

### Phase 1 — Interview (confirm + fill gaps)

See [interview.md](interview.md). Ask in **batches of 2–3**, never the whole list. Lead with the draft mapping ("I think `smartpig_features` is your ILI anomaly table and `feature_md` is the measure — is that right, and is it feet or meters?"). The minimum viable glossary needs:

- **Route key** — the column identifying line/route, and whether it's consistent across tables
- **Measure units** — feet vs meters for EVERY measure column (the critical one)
- **ILI anomaly table + key columns** — feature id, run id, measure, depth, length, feature type, and whether ERF/%SMYS are stored or must be computed
- **ILI runs table** — run date, vendor, tool type (for vintage + comparability)
- **Modules adopted** — which of IR/TVC/ILI/CP/SL/OFF exist (check `MODULE_METADATA` if present)
- **Line / segment business names** — "Line 4" → which `route_id`(s)
- **Pipe attributes for integrity math** — OD, wall thickness, SMYS, MAOP (table/columns), needed by `pods-ili-integrity`

### Phase 2 — Generate the workspace glossary skill

```bash
python scripts/generate_glossary.py \
  --customer <short-name> \
  --answers answers.json \
  --output /Workspace/.assistant/skills/<customer>-pods-glossary/SKILL.md
```

Uses [glossary_template.md](glossary_template.md). See [example_glossary.md](example_glossary.md) for a worked output.

### Phase 3 — Register UC comments

Apply table/column comments (especially the **unit** of each measure column — put it in the column comment so Genie sees it on `DESCRIBE`). Show the user the diff before writing; they may have customized comments.

## Output: what the customer ends up with

- A workspace skill `<customer>-pods-glossary` auto-loaded for any PODS question
- Every measure column's **unit** recorded (the single highest-value fact)
- Canonical-concept → physical-column mapping for every PODS skill to use
- The list of adopted modules, so module skills degrade gracefully

Re-run when the schema changes (new line, new ILI vendor, new module adopted).

## What NOT to do

- **Don't skip the unit confirmation.** A glossary without units per measure column is the dangerous failure mode — it lets the analytical skills join feet to meters silently.
- Don't write UC comments without showing the diff first.
- Don't fabricate a mapping the customer can't confirm — write `_unknown_ — needs validation from <role>` and move on.
- Don't ask the whole interview at once. Batch 2–3, lead with the introspection draft.
- Don't assume all six modules exist. Confirm via `MODULE_METADATA` / the customer.

## References

- [interview.md](interview.md) — the question list
- [glossary_template.md](glossary_template.md) — structure of the generated workspace skill
- [example_glossary.md](example_glossary.md) — worked example for a fictional midstream operator
- [scripts/introspect_schema.py](scripts/introspect_schema.py) — schema introspection / draft mapping (wraps the data-exploration tooling)
- [scripts/generate_glossary.py](scripts/generate_glossary.py) — writes the glossary skill
- [`data-exploration`](../../_common/data-exploration/) — the cross-cutting discovery skill (`databricks experimental aitools tools`) used in Phase 0
- [Databricks Genie best practices](https://docs.databricks.com/aws/en/genie/best-practices)
