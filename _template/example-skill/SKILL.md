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

## Trusted Assets (if this skill ships metrics)

Ship canonical metrics as UC SQL functions in [metric_udfs.sql](metric_udfs.sql)
so Genie Spaces call them as *certified, governed metrics* rather than ad-hoc SQL.
Register via the family `-setup` skill or by running the file, then reference the
functions by name.

## Genie Code conventions

- In-workspace, the CLI is already authenticated to the current workspace — don't
  pass `--profile`. Use it only for local runs against `~/.databrickscfg`.
- Reference tables with `@catalog.schema.table`; discover with `/findTables`.
- Skills load only in Agent mode; after editing a skill, start a new chat.

## What NOT to do

- Don't fabricate columns or tables not in [schema.md](schema.md).
- Don't proceed when a business term is ambiguous — ask first.
- Don't write UC comments or run destructive SQL without showing the diff first.
- Don't include secrets or raw PII values in any generated artifact.

## References

- [schema.md](schema.md) — full data model reference (add a `## Contents` ToC if >100 lines)
- [gotchas.md](gotchas.md) — error-prone joins, common mistakes
- [examples.sql](examples.sql) — parameterized gold-standard queries
- [views.sql](views.sql) — DDL for reusable views
- [metric_udfs.sql](metric_udfs.sql) — Trusted Asset UC functions
- Authoritative external docs (link out)
