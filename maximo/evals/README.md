# Maximo evals

Representative `query → expected_behavior` cases that measure two things:

1. **Discovery** — does the *right* skill load for the query? (Genie selects by
   `description` only, so a miss here is a description bug.)
2. **Quality** — given the skill, is the answer correct?

There is no built-in runner; use these in a fresh **Agent-mode** chat and score by
hand, or wire them into your own harness. Each file is one case:

```json
{
  "query": "what's our open work order backlog by site?",
  "expected_skill": "maximo-work-orders",
  "expected_behavior": [
    "Loads maximo-work-orders (and maximo-overview as parent)",
    "Filters WOCLASS='WORKORDER' and ISTASK=0",
    "Uses the customer open-status set from the glossary",
    "Groups by SITEID"
  ]
}
```

When a case fails on discovery, fix the **description** first. When it fails on
quality, fix in order: UC comment → glossary/instruction → example query / Trusted
Asset. Add real misses from the Genie Monitoring tab as new cases over time.
