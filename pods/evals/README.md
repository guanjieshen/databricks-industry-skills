# PODS evals

Representative `query → expected_behavior` cases that measure two things:

1. **Discovery** — does the *right* skill load for the query? (Genie selects by
   `description` only, so a miss here is a description bug.)
2. **Quality** — given the skill, is the answer correct? PODS errors are usually
   *silent*, so these cases target the confident-wrong-answer failure modes
   (units, route-vs-measure, depth-vs-ERF).

There is no built-in runner; use these in a fresh **Agent-mode** chat and score by
hand, or wire them into your own harness. Each file is one case:

```json
{
  "query": "what assets are between station 1240+00 and 1310+00?",
  "expected_skill": "pods-linear-referencing",
  "expected_behavior": [
    "Loads pods-linear-referencing with pods-overview as parent",
    "Converts stationing to route measure",
    "Uses a route + measure range-overlap join (not measure alone)",
    "Returns results in the canonical unit recorded by pods-setup"
  ]
}
```

When a case fails on discovery, fix the **description** first. When it fails on
quality, fix in order: UC comment / recorded unit → glossary/instruction →
example query / Trusted Asset. Add real misses from the Monitoring tab over time.
