---
name: wellview-genie-agent
description: |
  Use to scaffold a Genie Agent (formerly Genie Space) curated for Peloton
  WellView data — which UC views/tables to include (the daily-ops/cost gold
  views + fact), which Trusted UDFs to register (cost_per_foot, npt_pct,
  afe_variance_pct, rop), the master-unit + NPT-definition instructions the
  Agent needs, the business synonyms from the glossary, and sample questions it
  should answer well. Defers Genie Agent creation mechanics to the platform
  skill databricks-genie. Triggers on: "create a genie agent for WellView",
  "scaffold a genie space for our well data", "build the drilling/cost genie
  experience", "what to curate in a WellView genie agent", "which trusted UDFs
  for the WellView agent".
metadata:
  version: "0.1.0"
parent: wellview-overview
---

# WellView Genie Agent Scaffolder

Curation content for standing up a Genie Agent on WellView daily-ops/cost data. The
platform-layer [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md) skill handles creation mechanics; this skill answers the WellView-specific
question: *what goes in the Agent so it answers well-construction questions correctly?*

> **FIRST:** load `wellview-overview` for the record-tree + unit anchor. Also confirm
> `wellview-setup` has run so UC comments + the glossary (physical names, **master units**,
> `LV` decodes) exist — the Agent's quality depends on them.

## When to use

- "Create a Genie Agent for WellView"
- "Scaffold a Genie Space for our drilling/cost data"
- "Which views/UDFs should the WellView Agent include?"
- "What instructions does the WellView Agent need?"

## Top gotchas

1. **UC comments + glossary must already exist.** Without `wellview-setup`, the Agent won't know master units, `LV` decodes, or the open-job convention — answers will be confidently wrong. Confirm setup first.
2. **Curate the Gold views/fact, not raw `WV` tables.** `v_daily_report_enriched`, `v_time_log_enriched`, `v_job_cost_rollup`, and `v_daily_ops_cost_fact` are unit-normalized and `LV`-decoded; raw tables are master-unit and coded. Expose raw tables only when needed.
3. **Bake the two non-negotiable instructions into the Agent.** (a) The NPT definition is customer-specific — state it. (b) Numbers are master-unit; the Gold layer is normalized to metres — state the unit. Both are silent-error sources otherwise.

## Questions to surface first

1. **Audience.** Drilling/workover supervisors, cost engineers, or both? Drives naming, glossary terms, and the sample-question set.
2. **NPT definition + cost-code scope.** The Agent must encode the customer's NPT rule and the default cost-per-foot scope (all-in vs intangibles-only) as instructions — confirm them.
3. **Scope.** Daily-ops/cost only, or also drilling-NPT / completions / integrity once those modules ship? Defines the included-objects list.

## Pre-flight (per session)

1. **UC catalog/schema** for the curated Gold layer.
2. **`wellview-setup` completion check** — UC comments + glossary registered?
3. **Confirmed audience + NPT/cost conventions** from the questions above.

## Workflow

1. **Platform mechanics** — load [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md) for the API/UI to create + configure the Agent.
2. **Curation content** — see [curation.md](curation.md): which UC objects to include, which Trusted UDFs to register, the synonyms + the master-unit/NPT instructions.
3. **Sample-question library** — see [sample-questions.md](sample-questions.md). Seed + validate the Agent with these.

## What's in this skill

- [curation.md](curation.md) — **load when** assembling the include-list. Gold views/fact, Trusted UDFs, synonyms, and the required Agent instructions.
- [sample-questions.md](sample-questions.md) — **load when** validating the Agent. Canonical daily-ops/cost questions it should answer well.

## What NOT to do

- **Don't re-teach Genie Agent creation mechanics** — reference [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md).
- **Don't curate raw `WV` tables** when a Gold view exists — the Agent loses unit normalization + `LV` decode.
- Don't ship without the master-unit and NPT-definition instructions — they're the top silent-error sources.

## Composes with

- **`wellview-overview`** — data-model anchor.
- **`wellview-setup`** — UC comments + glossary are the foundation of Agent quality.
- **`wellview-daily-ops-cost`** — supplies the Gold views, Trusted UDFs, and metric view the Agent curates.
- **[`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md)** (platform) — creation/management mechanics.
