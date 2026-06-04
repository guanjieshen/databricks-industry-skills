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

## Why run this first (and the value it creates)

Out of the box Genie doesn't know *your* Maximo — it guesses at table/column meaning, your "open"-status set, and your business terms, and produces confident-but-wrong SQL. This setup teaches the workspace your Maximo so **every other `maximo-*` skill** (work-orders, reliability, maintenance-cost, pm-planning, genie-space, …) answers in your vocabulary and avoids those errors. **Explain this to the user up front.** It's a **one-time** step that **pays off on its own** — you do *not* need to build a Genie Space afterward for it to be worth running.

## What it creates, and where

Two assets:

1. **A workspace-tier glossary skill** at `<skills-root>/maximo/<customer>-maximo-glossary/SKILL.md` — i.e. **inside the same `maximo/` group folder as the rest of the family**, so the glossary and the skills that read it share one discovery regime. (`<skills-root>` = `/Workspace/.assistant/skills` for a workspace install, or `/Users/<email>/.assistant/skills` for a user install.) It maps customer business terms ("Mainline", "Region", "centrifugal pump") to Maximo schema (SITEIDs, LOCATION hierarchy levels, CLASSSTRUCTUREIDs).
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

Profile the schema and extract the data-provable facts — distinct `WOCLASS`/`STATUS`/`WORKTYPE`, the `SITEID` list, `ASSET.CLASSSTRUCTUREID` list, custom/extension columns, which modules are populated, PLUSG presence, and row/null stats — into a DRAFT for the interview. **Pick the path that matches how Genie Code is attached** (both produce the same facts):

**Path A — workspace / serverless compute (can run Python):** run the profiler script. (It builds on the [`data-exploration`](../../_common/data-exploration/) mechanics.)
```bash
# In-workspace: omit --profile (ambient auth). Local runs: add --profile <name>.
python scripts/introspect_schema.py \
  --catalog <catalog> --schema <silver-schema> \
  --output draft_profile.json
```

**Path B — SQL warehouse only (e.g. Genie started from the Unity Catalog data page):** the CLI/Python may not be attached. Run the portable SQL profiler instead — [`scripts/profile_queries.sql`](scripts/profile_queries.sql) — substituting `{{catalog}}`/`{{schema}}`. It returns the same facts (tables, custom columns, distinct dimensions, module presence, PLUSG, row counts), all read-only. The SQL is the source of truth; the Python script is just a wrapper around it.

> Genie Code attached to the workspace can run Python, SQL, and shell on serverless compute; attached to a warehouse (UC data page) it is SQL-only. Don't assume Python is available — detect it, and fall back to Path B if not.

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

Once interview is complete, run. Write the glossary **into the `maximo/` group folder**, alongside the rest of the family, so it shares their discovery regime:

```bash
python scripts/generate_glossary.py \
  --customer <short-name> \
  --answers <path-to-answers.json> \
  --output <skills-root>/maximo/<customer>-maximo-glossary/SKILL.md
# <skills-root> = /Workspace/.assistant/skills        (workspace install)
#              or /Users/<email>/.assistant/skills     (user install — per the scope pre-flight)
```

The script writes a skill file using [glossary_template.md](glossary_template.md) as the structure. See [example_glossary.md](example_glossary.md) for a worked output. (The glossary must live in the **same** folder regime as the family — if the family is installed flat at the skills root instead of under `maximo/`, drop the `maximo/` segment so both stay co-located.)

> **If you can't run Python here:** write the glossary `SKILL.md` **directly** from [glossary_template.md](glossary_template.md), filling it with the confirmed interview answers — the script only renders that template. Keep the standard frontmatter (`name`, `description`, `metadata.version`, `parent: maximo-overview`) and **record every unconfirmed item as `_unknown_ — confirm with <role>`** rather than guessing. Include a short follow-up table (who confirms what) so the flagged items aren't lost.

### Phase 3 — Register UC table/column comments on Silver (requires explicit approval)

UC comments are Genie's #1 quality lever (missing comments degrade SQL). But this **modifies existing tables**, so per the repo rule it needs the user's **explicit permission**. **Preview first (writes nothing) → show the statements → get approval → only then apply:**

```bash
# 1) PREVIEW — prints the COMMENT/ALTER statements, writes NOTHING:
python scripts/apply_uc_comments.py \
  --catalog <catalog> --schema <silver-schema> \
  --comments-file scripts/maximo_comments.json

# 2) ONLY after the user reviews and explicitly approves:
python scripts/apply_uc_comments.py \
  --catalog <catalog> --schema <silver-schema> \
  --comments-file scripts/maximo_comments.json \
  --apply --warehouse-id <id>
```

The shipped `maximo_comments.json` covers the standard MBO-backed tables; extend it from the glossary for the customer's renamed/custom tables. **Never run `--apply` without explicit approval.**

## When setup completes — summarize this for the user

Close with a clear recap of **what was created, where, and the value** — then present next steps as **options**, not an automatic hand-off.

**Assets created**
| Asset | Where | Value |
|---|---|---|
| `<customer>-maximo-glossary` skill | `<skills-root>/maximo/<customer>-maximo-glossary/SKILL.md` | Genie now answers in the customer's vocabulary; auto-loads for any Maximo question |
| UC table/column comments | On the Silver tables in `<catalog>.<schema>` | Genie's #1 SQL-quality lever — every `maximo-*` skill writes more accurate SQL |
| `draft_profile.json` + confirmed `answers.json` | your working dir | The evidence behind the glossary; re-run input |

**What this already unlocks (no further steps required):** every other `maximo-*` skill now resolves the customer's sites, asset classes, open-status set, worktypes, and custom columns — so backlog/reliability/cost/PM questions are correct today.

**Optional next steps — suggest, don't assume:**
- Ask Maximo questions now (the glossary + comments already improve answers) — usually the right immediate move.
- **Optionally**, build a curated **Genie Space** with `maximo-genie-space` *if the user wants a shareable NL surface over this data*. Offer it; don't start it automatically.
- Follow up on the flagged `_unknown_` items with the right owners (reliability / integrity / compliance / planners).

> Do **not** auto-advance to Genie Space creation. Setup stands on its own; only build the Space when the user asks.

Re-run this skill any time the customer's setup changes materially (new sites, asset classes, custom columns).

## What NOT to do

- Don't skip Phase 0 — asking the customer what the data already shows wastes the expert's time and misses customizations the data would reveal.
- The profile **proposes**; the human **confirms**. Never finalize a profiled candidate (the open-status set, the worktype mapping, a custom column's meaning, the industry/usage profile) without the customer validating it.
- **Never apply UC comments (or any change to existing tables) without explicit user approval** — run `apply_uc_comments.py` with no `--apply` to preview, show the statements, and only run `--apply` after they confirm. (Repo rule: writes to existing objects require explicit permission.)
- Don't fabricate mappings if the customer doesn't know — write `_unknown_ — needs validation from <role>` and move on.
- Don't ask the full interview at once. Batch 2–3 questions, accept the answers, then continue.

## References

- [scripts/introspect_schema.py](scripts/introspect_schema.py) — Phase 0 profiler (Path A, Python/serverless); emits `draft_profile.json`
- [scripts/profile_queries.sql](scripts/profile_queries.sql) — Phase 0 profiler (Path B, portable SQL for warehouse-only / UC-data-page sessions)
- [interview.md](interview.md) — the confirm-the-gaps interview (profile-grounded, consultant-style)
- [glossary_template.md](glossary_template.md) — structure of the generated workspace skill
- [example_glossary.md](example_glossary.md) — worked example for a fictional pipeline operator
- [scripts/generate_glossary.py](scripts/generate_glossary.py) — automation that writes the glossary skill
- [scripts/apply_uc_comments.py](scripts/apply_uc_comments.py) — automation that applies UC comments
- [scripts/maximo_comments.json](scripts/maximo_comments.json) — standard Maximo MBO comment definitions
