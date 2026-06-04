---
name: example-skill
description: |
  REPLACE THIS — one or two sentences describing what this skill does and when
  Genie should use it. The description is the matcher: include specific trigger
  phrases (technical jargon AND business jargon). Be specific enough that Genie
  loads this skill only when it's actually relevant.
tags:
  - data-source:example
  - tier:module                 # or tier:foundation
  - industry:oil-and-gas        # repeatable; remove if industry-agnostic
  - persona:analyst             # repeatable: analyst, da-platform, reliability-engineer, integrity-engineer, hse-manager, data-scientist, etc.
---

# Skill Title

One-paragraph intro: what this skill teaches Genie and why it exists.

## When to use

- Trigger phrase / topic 1 (be specific)
- Trigger phrase / topic 2
- Edge cases that should also trigger this skill

If the user's question is better served by a different skill in this family, name it explicitly here so Genie can switch.

## Pre-flight checks (ask before the first action)

Cache the answers for the rest of the session — don't re-ask.

1. **First check** — e.g. "Which Unity Catalog catalog/schema holds your data?"
2. **Second check** — e.g. "Are your tables in the standard shape or has your ingestion reshaped them?"

If a workspace-specific glossary skill is available, consult it here. If a business term is ambiguous, **ask before guessing**.

## Workflow

Step-by-step instructions for how Genie should approach work in this skill's domain. Be explicit.

1. First, do X.
2. Then, do Y.
3. If condition, do Z; otherwise do W.

Reference supporting files where heavier content lives (loaded on demand):
- [schema.md](schema.md) — full data model reference
- [gotchas.md](gotchas.md) — error-prone joins, common mistakes
- [examples.sql](examples.sql) — parameterized gold-standard queries

## What NOT to do

- Don't fabricate columns or tables not in [schema.md](schema.md).
- Don't proceed when a business term is ambiguous — ask first.
- Don't include secrets or raw PII values in any generated artifact.

## References

- [schema.md](schema.md)
- [gotchas.md](gotchas.md)
- [examples.sql](examples.sql)
- Authoritative external docs (link out)
