---
name: pods-genie-space
description: |
  Use to scaffold, curate, or improve a Databricks Genie Space for PODS
  (Pipeline Open Data Standard) pipeline-integrity data — assembling the Genie
  instructions, certified example SQL, business synonyms, measure-unit handling,
  and Trusted Asset metric functions (ERF, remaining strength, range-overlap) a
  PODS Genie Space needs to answer correctly, then benchmarking its accuracy.
  Triggers on: "create a Genie Space for our pipeline data", "build a PODS Genie
  room", "curate Genie for ILI / integrity data", "Genie gives wrong anomaly
  answers", "improve our pipeline Genie", "benchmark the Genie Space", "what
  instructions should our PODS Genie have". Run pods-setup first so the
  physical→PODS column mapping, measure units, glossary, and UC comments exist.
metadata:
  version: "0.1.0"
parent: pods-overview
---

# PODS Genie Space

Stand up (or fix) a Genie Space that answers pipeline-integrity questions
accurately. Genie Space quality is **iterative**, not one-time — and PODS is
unusually unforgiving: a wrong unit or a route-vs-measure mistake yields a
*confident, invisible* error. This skill turns the PODS family's assets into the
four things a Genie Space needs, then benchmarks them.

> **FIRST:** load the `pods-overview` skill — it carries the PODS 7 data model, the linear-referencing networks, the module map, and the universal gotchas (foot-vs-meter units, route-vs-measure, ILI run vintage). This skill builds on that foundation.

## Prerequisites

1. **Run `pods-setup` first.** It maps the customer's physical columns/tables to
   canonical PODS concepts, records the **UNIT of each measure column**, registers
   UC comments (Genie's #1 quality lever), and generates the workspace glossary.
   A Genie Space built without these will be confidently wrong.
2. Confirm the conformed Silver/Gold catalog.schema and which tables/views to expose.

## The four ingredients (and where each comes from)

| Genie Space needs | Source in this family |
|---|---|
| **General instructions** | `pods-overview` gotchas (units, route-vs-measure, ILI vintage) + the workspace glossary from `pods-setup` |
| **Certified example SQL** | `pods-linear-referencing/examples.sql` and `pods-ili-integrity/examples.sql` |
| **Business synonyms + units** | the workspace glossary skill produced by `pods-setup` |
| **Trusted Asset functions** | `pods-ili-integrity/metric_udfs.sql` (ERF, remaining strength) and `pods-linear-referencing/metric_udfs.sql` (range-overlap) |

## Workflow

```
- [ ] Step 1: Confirm prerequisites (pods-setup done; catalog/schema; units known; tables to expose)
- [ ] Step 2: Pick scope (linear-referencing always; + ILI/CP/other modules present)
- [ ] Step 3: Assemble instructions (overview gotchas + glossary synonyms + the canonical measure unit)
- [ ] Step 4: Register Trusted Asset functions and add them to the Space
- [ ] Step 5: Load certified example SQL from the module examples.sql files
- [ ] Step 6: Run the benchmark; fix gaps; repeat
```

**Step 3 — Instructions.** State the canonical measure **unit** explicitly, that
route + measure together locate a feature (never measure alone), that anomalies
must be ranked by **ERF / predicted failure pressure, not raw depth**, and the
ILI-run-vintage rule for growth comparisons. Pull synonyms from the glossary.

**Step 4 — Trusted Assets.** Register the relevant `metric_udfs.sql` functions
(substituting the customer catalog.schema) so Genie computes ERF, remaining
strength, and range-overlap via *certified* functions. See
[Trusted Assets](https://docs.databricks.com/aws/en/genie/trusted-assets).

**Step 5 — Example SQL.** Add the parameterized queries from
`pods-linear-referencing/examples.sql` and `pods-ili-integrity/examples.sql` as
Genie example queries — these are the gold-standard LRS and severity patterns.

**Step 6 — Benchmark.** Run [benchmark.md](benchmark.md). For each miss, fix in
order: (a) UC comment / recorded unit, (b) glossary synonym / instruction,
(c) example query or Trusted Asset. Use the Genie **Monitoring** tab to feed real
misses back in.

## Creating / exporting the Space

Create and manage the Space via the Databricks Genie tooling (UI, or the Genie
API / `databricks` CLI). For programmatic create/export/import use the
`databricks-genie` skill from `databricks/databricks-agent-skills` — this skill
owns the **PODS curation content**, that one owns the **mechanics**.

## What NOT to do

- Don't build a Space before `pods-setup` has recorded units and registered UC comments.
- Don't expose measure columns without their unit documented — it is the #1 source of wrong answers.
- Don't let Genie rank anomalies by raw depth; force the ERF/remaining-strength Trusted Assets.
- Don't declare it "done" — schedule a re-curation pass from the Monitoring tab.

## References

- [benchmark.md](benchmark.md) — starter benchmark question set + scoring rubric
- [Genie best practices](https://docs.databricks.com/aws/en/genie/best-practices) · [Monitoring](https://docs.databricks.com/aws/en/genie/monitor) · [Trusted Assets](https://docs.databricks.com/aws/en/genie/trusted-assets)
