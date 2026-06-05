---
name: example-skill
description: |
  REPLACE THIS. Third person, ≤1024 chars. Genie selects a skill ONLY by matching
  this text, so include: (1) the data-source name + synonyms (e.g. "IBM Maximo,
  Maximo, EAM, CMMS"), (2) exact technical identifiers the user might type
  (table/column names), and (3) business phrasings ("open work orders", "WO
  backlog"). State both what it does and when to use it. Make module descriptions
  narrow and distinctive so Genie picks this over sibling skills.
metadata:
  version: "0.1.0"
parent: example-overview   # REPLACE with <source>-overview. Remove this line only if this IS the overview.
# compatibility: Requires databricks CLI >= v0.294.0 (experimental aitools)  # uncomment if this skill runs the CLI itself
---

# Skill Title

One-paragraph intro: what this skill teaches Genie and why it exists.

> **FIRST:** load the `<source>-overview` skill — it carries the baseline data
> model, the module map, and the universal gotchas. This skill builds on it.
> (Delete this line only in the overview skill itself.)

## When to use

- Trigger phrase / topic 1 (be specific)
- Trigger phrase / topic 2
- Edge cases that should also trigger this skill

If a different skill in this family fits better, name it explicitly so Genie can switch.

## Top gotchas (keep the must-know ones HERE, inline)

Genie may never open `gotchas.md` at the moment it's about to make the mistake,
so the 3–5 highest-value, non-obvious corrections live in SKILL.md:

- Gotcha 1 — the concrete correction (e.g. "the `users` table uses soft deletes; always `WHERE deleted_at IS NULL`").
- Gotcha 2 — …
- Read [gotchas.md](gotchas.md) before writing non-trivial joins.

## Questions to surface first (REQUIRED for middle-layer skills)

These are the **SME-reflex clarifying questions** the agent must raise to the
user *before* answering — definitions, thresholds, and conventions a non-expert
would not know are ambiguous. List ≥2.

Distinct from `## Pre-flight` (one-time session setup, catalog/schema) — these
are per-request ambiguity. Examples of the shape:

- "X has 3+ valid definitions — which does your organization use?" (e.g. MTBF, PM compliance, "open" status set)
- "The default threshold here is Y — confirm or override?" (e.g. 90-day aging cutoff, SMRP 10% tolerance)
- "Z is classified by ID, not name — which IDs are you targeting?" (e.g. asset class hierarchy IDs)

If you cannot list ≥2 such questions for this skill, you are almost certainly
missing domain content — most ambiguity-prone business metrics have at least one.

## Pre-flight (per session, ask once and cache)

One-time session configuration. Cache the answers; don't re-ask.

1. **Catalog/schema** — "Which Unity Catalog catalog/schema holds your data?"
2. **Glossary skill** — Is a `<customer>-<source>-glossary` workspace skill installed? If yes, prefer it for business-term resolution.
3. **Shape** — "Standard shape, or has your ingestion reshaped the tables?"

If a business term is ambiguous and no glossary covers it, **ask before guessing**.

## Workflow

Be explicit. Resolve new questions in this priority order:

1. **Parameterized example** — check [examples.sql](examples.sql) for a matching pattern; use it with the user's parameters.
2. **Pre-joined view** — compose from [views.sql](views.sql).
3. **Raw tables** — only when the view layer doesn't cover the join shape; explain why.

## What's in this skill

Tell Genie *when* to load each sibling file — not just that it exists:

- [schema.md](schema.md) — **load when** joining tables or selecting columns. Full data model reference. (Add a `## Contents` ToC if >100 lines.)
- [gotchas.md](gotchas.md) — **load before** writing non-trivial joins. Extended versions of the inline top gotchas + the long-tail traps.
- [examples.sql](examples.sql) — **load when** the user's question matches a known pattern.
- [views.sql](views.sql) — DDL for pre-joined views. Registered once by the family's `-setup` skill (not run from this skill).
- [metric_udfs.sql](metric_udfs.sql) — Trusted Asset UC SQL functions. Genie calls them as governed metrics. Registered once via `-setup`.

## What NOT to do

- Don't fabricate columns or tables not in [schema.md](schema.md). If the user mentions a custom column, check the workspace glossary or ask.
- Don't proceed when a business term is ambiguous — surface the question (see *Questions to surface first*) instead of guessing.
- **Don't write or alter UC comments / table metadata from this skill** — UC comments are owned by `-setup` (preview-then-apply, gated on explicit user approval).
- **Don't re-teach platform mechanics** (Lakeflow, dashboards, UC, MLflow, …). Reference the canonical skill in [`ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills); don't duplicate.
- Don't include secrets or raw PII values in any generated artifact.

## Composes with

- **`<source>-overview`** — baseline data-model literacy + universal gotchas. Always load first.
- **`<source>-setup`** — registers the views in [views.sql](views.sql) and Trusted UDFs in [metric_udfs.sql](metric_udfs.sql). Never run those scripts from this skill — defer to setup's preview-then-apply workflow.
- **Other module skills** — name them explicitly. *"For X questions, load `<source>-other-module`."*
- **Platform skills** — when the user's request crosses into pipeline / dashboard / UC mechanics, reference the canonical platform skill (e.g. [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md), [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines)).
