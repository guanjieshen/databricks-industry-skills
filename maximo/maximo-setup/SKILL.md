---
name: maximo-setup
description: |
  Use to bootstrap a customer's Maximo workspace for Genie — generates a
  workspace-tier business-jargon glossary skill and registers Unity Catalog
  table/column comments on the Maximo Silver layer. Run this ONCE per workspace.
  Triggers on: "set up Maximo for Genie", "set up our Maximo glossary",
  "configure Genie for our Maximo data", "Genie doesn't know our business
  terms", "register Maximo schema comments".
compatibility: Requires databricks CLI >= v0.294.0 (experimental aitools)
metadata:
  version: "0.1.0"
parent: maximo-overview
---

# Maximo Setup

Bootstrap a Databricks workspace so Genie Code can answer Maximo questions using the customer's own business jargon. This is a **one-time setup** per workspace, run by the D&A team. After it completes, every other Maximo skill works more effectively.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas (SITEID composite keys, `WOCLASS` filtering, `ISTASK` dedup, WOSTATUS-vs-WORKORDER history). This skill builds on that foundation.

Two outputs:

1. **A workspace-tier glossary skill** at `/Workspace/.assistant/skills/<customer>-maximo-glossary/SKILL.md` that maps customer business terms ("Mainline", "Region", "centrifugal pump") to Maximo schema (SITEIDs, LOCATION hierarchy levels, CLASSSTRUCTUREIDs).
2. **UC table and column comments** registered on the Maximo Silver tables, using standardized Maximo MBO descriptions plus any customer-specific notes.

Why both: the glossary handles **value-level and concept-level** mapping (jargon → schema). UC comments handle **column-level** semantics (what does this column mean). Both are essential for Genie quality per [Databricks Genie best practices](https://docs.databricks.com/aws/en/genie/best-practices).

## When to use

- "Set up Maximo for Genie / configure Genie for our Maximo data"
- "Set up our business glossary for Maximo"
- "Genie doesn't understand our terms like Mainline / Region / Field"
- "Register column comments on our Maximo tables"
- One of the first things a new customer should run after the Maximo skill family is installed

## Pre-flight

1. **Catalog/schema location**: "Which catalog/schema holds your Maximo Silver layer?" (e.g. `eam.maximo_silver`)
2. **Workspace customer name**: "What short name should we use for your organization in skill filenames?" (e.g. `enbridge`, `acme-energy`). This becomes part of the generated glossary skill name.
3. **Output scope**: workspace-wide (admin) or user-scoped?

## Workflow

Run as a guided interview, then apply the answers in two steps.

### Phase 1 — Interview (collect mappings)

See [interview.md](interview.md) for the full question list. Ask in **batches of 2–3 questions at a time**; never dump the whole list. Use the customer's vocabulary back at them — confirm understanding before moving on.

The minimum viable glossary needs:
- Sites (business name ↔ SITEID list)
- Asset hierarchy (region / segment / station / equipment levels and how they map to LOCATIONS hierarchy)
- Asset classes the customer references by name (e.g. "centrifugal pump" → CLASSSTRUCTUREID list)
- Open-status set (which WORKORDER STATUS values count as "open" in the customer's vocabulary)
- Worktype codes (especially the corrective vs preventive split)
- Custom WORKORDER / ASSET columns (extension fields) the customer relies on

Optional but high-value:
- Region / segment / business unit groupings
- "Critical" / "high criticality" thresholds on `ASSET.CRITICALITY`
- Common synonyms (e.g. "PTW" → "Permit to Work")

### Phase 2 — Generate the workspace glossary skill

Once interview is complete, run:

```bash
python scripts/generate_glossary.py \
  --customer <short-name> \
  --output /Workspace/.assistant/skills/<customer>-maximo-glossary/SKILL.md \
  --answers <path-to-answers.json>
```

The script writes a workspace-tier skill file using [glossary_template.md](glossary_template.md) as the structure. See [example_glossary.md](example_glossary.md) for a worked output.

### Phase 3 — Register UC table/column comments on Silver

Apply standardized Maximo MBO descriptions as UC `COMMENT`s. Genie uses these heavily — missing comments degrade SQL quality.

```bash
python scripts/apply_uc_comments.py \
  --catalog <catalog> \
  --schema <silver-schema> \
  --comments-file scripts/maximo_comments.json
```

The shipped `maximo_comments.json` covers the standard MBO-backed tables. Customer extensions are added as a follow-up.

## Output: what the customer ends up with

After running this skill:

- A workspace skill `<customer>-maximo-glossary` is installed and auto-loaded for any Maximo question
- Every Maximo Silver table has TABLE and COLUMN comments registered in UC
- Subsequent calls to `maximo-work-orders`, `maximo-reliability`, etc. work in the customer's vocabulary — "Mainline" resolves to SITEID list, "centrifugal pump" to CLASSSTRUCTUREID, etc.

Re-run this skill any time the customer's setup changes materially (new sites, new asset classes, new custom columns).

## What NOT to do

- Don't write to UC comments without showing the user the diff first — they may have customized comments.
- Don't fabricate mappings if the customer doesn't know — write `_unknown_ — needs validation from <role>` and move on.
- Don't ask the full interview at once. Batch 2–3 questions, accept the answers, then continue.

## References

- [interview.md](interview.md) — the question list
- [glossary_template.md](glossary_template.md) — structure of the generated workspace skill
- [example_glossary.md](example_glossary.md) — worked example for a fictional pipeline operator
- [scripts/generate_glossary.py](scripts/generate_glossary.py) — automation that writes the glossary skill
- [scripts/apply_uc_comments.py](scripts/apply_uc_comments.py) — automation that applies UC comments
- [scripts/maximo_comments.json](scripts/maximo_comments.json) — standard Maximo MBO comment definitions
