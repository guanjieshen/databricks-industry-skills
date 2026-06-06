# WellView evals

Representative `query → expected_behavior` cases that measure two things:

1. **Discovery** — does the *right* skill load for the query? (Genie selects by `description`
   only, so a miss here is a description bug — fix the description first.)
2. **Quality** — given the skill, is the answer correct? WellView errors are usually *silent*
   (units, record-tree joins, well/job double-count, NPT definition), so these cases target
   the confident-wrong-answer failure modes — including at least one that exercises a
   **Questions-to-surface-first** ambiguity (the skill must *ask*, not guess).

There's no built-in runner; use these in a fresh **Agent-mode** chat and score by hand, or
wire them into your own harness. Each file is one case (see `_template/evals/example-eval.json`
for the shape): `name`, `description`, `query`, `expected_skill`, `expected_behavior`,
`anti_behavior`.

When a case fails on discovery, fix the **description**. When it fails on quality, fix in
order: UC comment / recorded unit → glossary / instruction → example query / Trusted UDF.
