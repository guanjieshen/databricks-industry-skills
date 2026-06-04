---
name: pods-data-quality
description: |
  Use to diagnose PODS / pipeline data-quality issues, especially
  linear-referencing problems that silently break analytical queries —
  non-monotonic route measures, route gaps and overlaps, orphan events
  (anomalies on a route with no centerline), unit inconsistency (feet mixed
  with meters), duplicate anomalies across runs, and missing pipe attributes.
  Triggers on: "this number looks wrong", "my overlap returned nothing", "the
  anomaly count seems off", "data quality", "validate our PODS data", "why is
  this anomaly not in any HCA", "check our centerline".
tags:
  - data-source:pods
  - tier:foundation
  - industry:oil-and-gas
  - persona:da-platform
  - persona:integrity-engineer
---

# PODS Data Quality

A diagnostic playbook for PODS data issues. Most "wrong answer" reports on pipeline data trace to **linear-referencing data quality** — and because LRS errors are invisible in results, this skill exists to surface them deliberately.

## When to use

- "This anomaly count / result looks wrong"
- "My HCA overlap returned nothing (or too much)"
- "Why isn't this anomaly in any HCA / segment?"
- "Validate our PODS / centerline / ILI data before we trust it"
- Any unexplained gap between a Genie answer and what the engineer expected

## Discovery first

Use the repo's [`data-exploration`](../../_common/data-exploration/) cross-cutting skill to profile before diagnosing — it gives null counts, row counts, and samples in one call:

```bash
databricks experimental aitools tools discover-schema <catalog>.<schema>.<table> --profile <PROFILE>
```

Then run the targeted checks in [diagnostics.sql](diagnostics.sql).

## The diagnostic order (most-common first)

1. **Unit inconsistency** — the #1 cause. Are two measure columns being compared in different units (feet vs meters)? Profile the value ranges: a column maxing near 250,000 on a 50-mile line is feet; near 80,000 is meters. Confirm against the glossary.
2. **Non-monotonic measures** — does any route have measures that decrease then increase (reversals)? Breaks range joins.
3. **Route gaps / overlaps** — do segments on a route leave gaps or claim overlapping ranges? A point can match 0 or 2 ranges.
4. **Orphan events** — anomalies/events whose `route_id` has no centerline/route row. They vanish from joins.
5. **Duplicate anomalies** — same feature counted across runs because a vintage filter is missing.
6. **Missing pipe attributes** — anomalies with no OD/wall/SMYS/MAOP at their location → B31G/ERF returns NULL.

See [common_issues.md](common_issues.md) for the symptom → cause → fix mapping, and [diagnostics.sql](diagnostics.sql) for the queries.

## How to report findings

- Quantify (e.g. "12% of anomalies on L07 fall in a measure gap").
- Tie each finding to the *analytical* symptom it causes ("this is why your HCA overlap missed 40 anomalies").
- Recommend the fix at the right layer — most belong in `pods-data-engineering` (Silver→Gold), not in query patches.

## What NOT to do

- Don't patch a data-quality problem in a one-off query. Fix it in the conformed layer so every skill benefits.
- Don't assume a unit from a single value. Profile the range and confirm against the glossary.
- Don't silently drop orphan/duplicate rows — report the count so the engineer knows coverage.

## References

- [diagnostics.sql](diagnostics.sql) — the check queries
- [common_issues.md](common_issues.md) — symptom → cause → fix
- [`data-exploration`](../../_common/data-exploration/) — cross-cutting profiling / discovery skill
- `pods-linear-referencing/gotchas.md` — the LRS failure modes in depth
