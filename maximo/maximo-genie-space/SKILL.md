---
name: maximo-genie-space
description: |
  Use to scaffold, curate, or improve a Databricks Genie Space for IBM Maximo
  (EAM/CMMS) data — assembling the Genie instructions, certified example SQL,
  business synonyms, and Trusted Asset metric functions a Maximo Genie Space
  needs to answer well, then benchmarking its accuracy. Triggers on: "create a
  Genie Space for Maximo", "build a Maximo Genie room", "curate Genie for our
  Maximo data", "Genie gives wrong Maximo answers", "improve our Maximo Genie",
  "benchmark the Genie Space", "what instructions should our Maximo Genie have",
  "add example queries to Genie". Run maximo-setup first so glossary and UC
  comments exist.
metadata:
  version: "0.1.0"
parent: maximo-overview
---

# Maximo Genie Space

Stand up (or fix) a Genie Space that answers Maximo questions accurately. Genie
Space quality is **not** a one-time setup — per Databricks it's *"an iterative
process"*. This skill turns the Maximo skill family's assets into the four things
a Genie Space needs, then benchmarks them.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data
> model, the module map, and the universal gotchas (SITEID composite keys,
> `WOCLASS` filtering, `ISTASK` dedup, WOSTATUS-vs-WORKORDER history). This skill builds on that foundation.

## Prerequisites

1. **Run `maximo-setup` first.** It registers UC table/column comments (Genie's #1
   quality lever — missing comments degrade SQL) and generates the workspace
   glossary skill. A Genie Space built without these will answer poorly.
2. Confirm the Silver/Gold catalog.schema and which tables/views to expose.

## The four ingredients (and where each comes from)

| Genie Space needs | Source in this family |
|---|---|
| **General instructions** | `maximo-overview` gotchas + the workspace glossary from `maximo-setup` |
| **Certified example SQL** | each module skill's `examples.sql` (work-orders, reliability, pm-planning, inventory, maintenance-cost, labor-resources, asset-hierarchy, integrity, hse, workflow-and-approvals) |
| **Business synonyms** | the `<customer>-maximo-glossary` skill produced by `maximo-setup` |
| **Trusted Asset functions** | each module's `metric_udfs.sql` (MTBF/MTTR/PM-compliance etc.) registered as UC functions |

## Workflow

```
- [ ] Step 1: Confirm prerequisites (maximo-setup done; catalog/schema; tables to expose)
- [ ] Step 2: Pick scope (which modules → which tables/views and example queries)
- [ ] Step 3: Assemble instructions (overview gotchas + glossary synonyms)
- [ ] Step 4: Register Trusted Asset functions and add them to the Space
- [ ] Step 5: Load certified example SQL from the module examples.sql files
- [ ] Step 6: Run the benchmark; fix gaps; repeat
```

**Step 3 — Instructions.** Draft the Genie Space general instructions from the
universal gotchas in `maximo-overview` (e.g. `WOCLASS='WORKORDER'`, `ISTASK=0`
for backlog, join on `SITEID`, WOSTATUS=history vs WORKORDER=current) plus the
synonym mappings from the workspace glossary. Keep instructions concise and
imperative.

**Step 4 — Trusted Assets.** Register the relevant `metric_udfs.sql` functions
(substituting the customer catalog.schema), then add them to the Space so Genie
computes MTBF/MTTR/PM-compliance via *certified* functions instead of ad-hoc SQL.
See [Trusted Assets](https://docs.databricks.com/aws/en/genie/trusted-assets).

**Step 5 — Example SQL.** Add the parameterized queries from each in-scope module's
`examples.sql` as Genie example queries — these are the gold-standard patterns.

**Step 6 — Benchmark.** Run [benchmark.md](benchmark.md) against the Space. For each
miss, fix in this order: (a) UC comment, (b) glossary synonym / instruction,
(c) add/repair an example query or Trusted Asset. Re-run until it passes. Use the
Genie **Monitoring** tab to find real questions it got wrong and feed them back.

## Creating / exporting the Space

Create and manage the Space via the Databricks Genie tooling (UI, or the Genie
API / `databricks` CLI). For programmatic create/export/import, use the
`databricks-genie` skill from `databricks/databricks-agent-skills` — this skill
owns the **Maximo curation content**, that one owns the **mechanics**.

## What NOT to do

- Don't build a Space before `maximo-setup` has registered UC comments and the glossary.
- Don't hand-write metric SQL into the Space — register the Trusted Asset functions instead.
- Don't expose raw Bronze tables; expose conformed Silver/Gold tables and views.
- Don't declare it "done" — schedule a re-curation pass from the Monitoring tab.

## References

- [benchmark.md](benchmark.md) — starter benchmark question set + scoring rubric
- [Genie best practices](https://docs.databricks.com/aws/en/genie/best-practices) · [Monitoring](https://docs.databricks.com/aws/en/genie/monitor) · [Trusted Assets](https://docs.databricks.com/aws/en/genie/trusted-assets)
