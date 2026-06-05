---
name: example-genie-agent
description: |
  REPLACE THIS. Use to scaffold a Genie Agent (formerly Genie Space) curated
  for <source> data — which UC tables/views to include, which semantic
  descriptions/synonyms to attach, which Trusted UDFs to register, sample
  questions the Agent should answer well. Defers Genie Agent creation
  mechanics to the platform skill databricks-genie. Triggers on: "create a
  genie agent for <source>", "scaffold a genie space for <source>", "build
  the genie experience for <source>", "what to curate in a <source> genie
  agent", "which trusted UDFs to register for the genie agent".
metadata:
  version: "0.1.0"
parent: example-overview
---

# <Source> Genie Agent Scaffolder

Curation content for standing up a Genie Agent on `<source>` data. The platform-layer [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md) skill handles creation mechanics (API calls, UI flows, current Trusted Assets registration). This skill answers the source-specific question: *what should go in the Agent so it answers `<source>` questions well?*

> **FIRST:** load `<source>-overview` for the data-model anchor. Also confirm `<source>-setup` has been run so UC comments are registered — the Agent's quality depends on them.

## When to use

- "Create a Genie Agent for `<source>`"
- "Scaffold a Genie Space curated for our Maximo deployment"
- "Which tables / views should the `<source>` Genie Agent include?"
- "Which sample questions should the Agent be tuned for?"

## Top gotchas

1. **UC comments must already be registered.** If `-setup` hasn't run, the Agent's SQL quality will be poor regardless of what's curated. Always confirm setup is complete first.
2. **Curate the Gold layer, not Bronze.** Pre-joined views (`v_workorder_enriched`, …) produce better Agent answers than raw tables. Include the views; expose raw tables only when needed.
3. **Trusted UDFs are governed metrics.** When the Agent has `open_wo_count`, `wo_aging_bucket`, etc. registered, it calls them as Trusted Assets instead of regenerating SQL. Include them in curation.

## Questions to surface first

1. **Audience.** Who will use this Agent — line-of-business users, IT, both? Affects naming, glossary terms, sample-question set.
2. **Scope.** Single-source (`<source>` only) or multi-source (joins to ERP / HR)? Defines the included-tables list.
3. **Customer-specific definitions.** Has the customer overridden any canonical definitions (open-status set, MTBF formula, "bad actor")? These need to land in the Agent's semantic descriptions.

## Pre-flight (per session)

1. **UC catalog/schema** for the curated Gold layer.
2. **`<source>-setup` completion check** — UC comments registered?
3. **Confirmed audience + scope** from the questions above.

## Workflow

1. **Platform mechanics** — load [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md). It handles the API/UI for creating + configuring a Genie Agent.
2. **Curation content** — this skill provides the source-specific list. See [curation.md](curation.md): which UC objects to include, which synonyms to attach, which Trusted UDFs to register.
3. **Sample-question library** — see [sample-questions.md](sample-questions.md). Seed the Agent with these to validate quality.

## What's in this skill

- [curation.md](curation.md) — **load when** assembling the include-list for the Agent. Lists curated Gold views, Trusted UDFs, and semantic-synonym additions.
- [sample-questions.md](sample-questions.md) — **load when** validating the Agent post-creation. Canonical questions the Agent should answer well.

## What NOT to do

- **Don't re-teach Genie Agent creation mechanics** (API shapes, UI screens, registration workflow). Reference [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md).
- **Don't curate raw Bronze tables** when a pre-joined Gold view exists.
- Don't ship a generic curation — customize per the customer's audience + scope.

## Composes with

- **`<source>-overview`** — data-model anchor.
- **`<source>-setup`** — UC comments are the foundation of Agent quality.
- **[`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md)** — creation/management mechanics.
- All module skills — their Gold views + Trusted UDFs are what the Agent curates.
