---
name: maximo-setup
description: |
  Use to bootstrap a customer's Maximo workspace for Genie — PROFILES the Maximo
  data first (distinct statuses/worktypes, sites, asset classes, custom columns,
  which modules are used, industry), then interviews to confirm the gaps, then
  generates a workspace-tier business-jargon glossary skill and registers Unity
  Catalog table/column comments on the Maximo Silver layer. Run this ONCE per
  workspace. Triggers on: "set up Maximo for Genie", "profile our Maximo data",
  "set up our Maximo glossary", "configure Genie for our Maximo data", "Genie
  doesn't know our business terms", "register Maximo schema comments".
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

**Profile the data first, then interview to confirm the gaps, then generate.** Don't ask the customer what the data can already tell you.

### Phase 0 — Profile the data (automated first pass)

Use the cross-cutting [`data-exploration`](../../_common/data-exploration/) mechanics via the bundled profiler. It finds the Maximo tables and extracts the data-provable facts — distinct `WOCLASS`/`STATUS`/`WORKTYPE`, the `SITEID` list, `ASSET.CLASSSTRUCTUREID` list, custom/extension columns, which modules are populated, PLUSG presence, and row/null stats — and writes a DRAFT for the interview.

```bash
# In-workspace: omit --profile (ambient auth). Local runs: add --profile <name>.
python scripts/introspect_schema.py \
  --catalog <catalog> --schema <silver-schema> \
  --output draft_profile.json
```

Present the findings. This turns Phase 1 from "answer 20 questions cold" into "confirm/correct what we found, and supply only what the data can't prove."

### Phase 1 — Interview (confirm the gaps)

See [interview.md](interview.md) — run it like a Maximo implementation consultant who can already see the data. Ask in **batches of 2–3**; never dump the whole list. **Batch 0 (industry & how they use Maximo today) goes first** — it scopes everything else.

The data can't prove these — they are what the interview captures:
- **Industry & usage** (Batch 0): industry / sub-segment, industry-solution add-ons (PLUSG…), which modules are actually used vs. another system of record, maturity, KPI definitions.
- **Meaning of the profiled values**: which `STATUS` count as "open"; the `WORKTYPE` → corrective / preventive / capital mapping.
- **Business jargon → schema**: site names ↔ `SITEID`, asset-class names ↔ `CLASSSTRUCTUREID`, hierarchy levels, criticality, synonyms ("PTW" → Permit to Work).
- **Custom columns**: what each detected extension field stores and who relies on it.
- **Process reality**: failure-reporting completeness, labor booking, migration history, timezone — the things that decide whether a metric is trustworthy.

Record answers as `answers.json` (shape + the `draft_profile.json` → `answers.json` mapping are in [interview.md](interview.md)).

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

- Don't skip Phase 0 — asking the customer what the data already shows wastes the expert's time and misses customizations the data would reveal.
- The profile **proposes**; the human **confirms**. Never finalize a profiled candidate (the open-status set, the worktype mapping, a custom column's meaning, the industry/usage profile) without the customer validating it.
- Don't write to UC comments without showing the user the diff first — they may have customized comments.
- Don't fabricate mappings if the customer doesn't know — write `_unknown_ — needs validation from <role>` and move on.
- Don't ask the full interview at once. Batch 2–3 questions, accept the answers, then continue.

## References

- [scripts/introspect_schema.py](scripts/introspect_schema.py) — Phase 0 profiler; emits `draft_profile.json`
- [interview.md](interview.md) — the confirm-the-gaps interview (profile-grounded, consultant-style)
- [glossary_template.md](glossary_template.md) — structure of the generated workspace skill
- [example_glossary.md](example_glossary.md) — worked example for a fictional pipeline operator
- [scripts/generate_glossary.py](scripts/generate_glossary.py) — automation that writes the glossary skill
- [scripts/apply_uc_comments.py](scripts/apply_uc_comments.py) — automation that applies UC comments
- [scripts/maximo_comments.json](scripts/maximo_comments.json) — standard Maximo MBO comment definitions
