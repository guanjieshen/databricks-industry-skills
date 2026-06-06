---
name: maximo-genie-space
description: |
  Use to scaffold, curate, or improve a Databricks Genie Space (Genie Agent) for
  IBM Maximo / Maximo / EAM / CMMS data — assembling the general instructions,
  certified example SQL, business synonyms, and Trusted Asset metric functions a
  Maximo Genie Space needs to answer accurately, then benchmarking it. Encodes
  which WORKORDER / ASSET / LABTRANS tables and views to expose and which
  universal Maximo traps (WOCLASS, ISTASK, SITEID, status synonyms, HISTORYFLAG)
  to bake into instructions. Triggers on: "create a Genie Space for Maximo",
  "build a Maximo Genie room", "curate Genie for our Maximo data", "Genie gives
  wrong Maximo answers", "improve our Maximo Genie", "benchmark the Genie Space",
  "what instructions should our Maximo Genie have", "add example queries to
  Genie", "Maximo text-to-SQL". Run maximo-setup first so glossary and UC
  comments exist; defer Genie create/export mechanics to databricks-genie.
metadata:
  version: "0.2.0"
parent: maximo-overview
---

# Maximo Genie Space

Stand up (or fix) a Genie Space that answers Maximo questions accurately. Genie
Space quality is **not** a one-time setup — per Databricks it is an *"iterative
process"*. This skill turns the Maximo skill family's assets into the four things
a Genie Space needs, then benchmarks them. It owns the **Maximo curation
content**; the platform skill [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md)
owns the **create/export/import mechanics**.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data
> model, the module map, and the universal gotchas (SITEID composite keys,
> `WOCLASS` filtering, `ISTASK` tasks-vs-child-WOs, status-is-a-synonym-domain /
> `SYNONYMDOMAIN` resolution, `HISTORYFLAG`, app-server-timezone datetimes,
> `STATUS`-current-vs-`WOSTATUS`-history). This skill builds on that foundation —
> it does not re-teach those mechanics; it tells you which to encode as Genie
> instructions.

## When to use

Triggered by Genie-Space curation and quality questions for Maximo:
- "Create / build a Genie Space (Genie Agent) for our Maximo data"
- "Genie keeps giving wrong Maximo answers — how do we fix it?"
- "What general instructions should our Maximo Genie have?"
- "Add certified example queries / synonyms / Trusted Assets to the Space"
- "Benchmark the Maximo Genie Space"

**Defer when:**
- The question is about the *create/export/import API or UI* (not Maximo content)
  → [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md).
- The fix is a missing UC comment or a customer glossary term → `maximo-setup`
  (it owns UC comments and the workspace glossary; preview-then-apply).
- The miss is a module's metric semantics (e.g. MTBF, PM compliance, cost rollup)
  → that module skill owns the formula; this skill just registers its UDF.

## Top gotchas

These are the curation traps that make a Maximo Genie Space answer wrong. (The
*underlying* data mechanics are owned and explained by `maximo-overview` — here
the point is how they surface during curation.)

1. **Garbage-in instructions.** A Genie Space is only as good as its UC comments,
   synonyms, and examples. Build it **after** `maximo-setup` has registered UC
   comments and the workspace glossary, or it answers poorly. UC comments are the
   #1 quality lever.
2. **Bake the universal filters into the general instructions.** The single most
   common Maximo Genie failure is unscoped counts. Add explicit instruction text:
   filter `WOCLASS='WORKORDER'`, count `ISTASK=0`, always join on `SITEID`,
   resolve status via `SYNONYMDOMAIN` (not literals), and be aware closed records
   carry `HISTORYFLAG=1`. Do **not** re-explain *why* in the instructions — state
   them as rules; the rationale lives in `maximo-overview`.
3. **Register metrics as Trusted Assets, never hand-write metric SQL.** MTBF,
   MTTR, PM compliance, cost rollups have contested definitions and live as
   certified UC functions in each module's `metric_udfs.sql`. Add those functions
   to the Space so Genie calls the *governed* metric instead of regenerating
   ad-hoc SQL it will get subtly wrong.
4. **Expose conformed Silver/Gold only.** Pointing the Space at raw Bronze
   re-introduces every universal trap (unfiltered `WOCLASS`, history rows,
   per-row currency). Expose the conformed tables and the family's views.
5. **It is never "done."** Use the Genie **Monitoring** tab to harvest real
   questions it got wrong and feed them back as new examples / instructions /
   synonyms. Schedule a re-curation pass.

## Questions to surface first

Surface these before curating — there is no defensible default:

1. **Scope: which modules / tables go in this Space?** One broad Maximo Space vs
   a focused one (e.g. work-management only) changes which tables, examples, and
   Trusted Assets to load. A too-broad Space dilutes accuracy. Confirm the
   in-scope modules and their tables/views.
2. **Whose definitions seed the instructions?** "Open", "completed", "corrective
   vs preventive", "bad actor", "PM compliance" all have multiple valid framings
   (owned by the module skills). Confirm the customer's chosen definitions so the
   general instructions and examples encode *their* convention, not a default.
3. **Glossary present?** Has `maximo-setup` produced the
   `<customer>-maximo-glossary` skill and registered UC comments? If not, curate
   those first — a Space built without them is the #1 cause of wrong answers.
4. **Benchmark acceptance bar.** What pass rate / which question set must the
   Space clear before it goes to business users? Seed [benchmark.md](benchmark.md)
   with the customer's real questions, not just the starters.

## Pre-flight (per session)

One-time session config — cache, don't re-ask:

1. **`maximo-setup` done?** UC comments registered + workspace glossary generated.
2. **Catalog/schema** for the conformed Silver/Gold tables and views to expose.
3. **Glossary skill** — confirm the `<customer>-maximo-glossary` skill is
   installed; prefer it for business-term resolution.

## Workflow

```
- [ ] Step 1: Confirm prerequisites (maximo-setup done; catalog/schema; tables to expose)
- [ ] Step 2: Pick scope (which modules → which tables/views and example queries)
- [ ] Step 3: Assemble instructions (overview gotchas as rules + glossary synonyms)
- [ ] Step 4: Register Trusted Asset functions and add them to the Space
- [ ] Step 5: Load certified example SQL from the module examples.sql files
- [ ] Step 6: Run the benchmark; fix gaps; repeat
```

The four ingredients and where each comes from:

| Genie Space needs | Source in this family |
|---|---|
| **General instructions** | `maximo-overview` gotchas (encoded as rules) + the workspace glossary from `maximo-setup` |
| **Certified example SQL** | each in-scope module skill's `examples.sql` |
| **Business synonyms** | the `<customer>-maximo-glossary` skill from `maximo-setup` |
| **Trusted Asset functions** | each module's `metric_udfs.sql` (MTBF/MTTR/PM-compliance/cost) registered as UC functions |

**Step 3 — Instructions.** Keep the written instructions **short**. Genie Space has dedicated surfaces (Joins config + Example SQL + Trusted Assets + UC comments) for most rules — instructions are the smallest of the surfaces, not the largest. Three-part block, in this order:

**Part A — Persona opening (FIRST section, always).** Establish *who the Agent is* and *what it cares about* before any technical rule. Without this, Genie answers like a generic SQL bot; with this, it reasons like a Maximo SME. Template:

```markdown
You are an expert Maximo analyst focused on <domain>. You have a deep
understanding of <key entities and the customer's deployment>. You care
about <the outcomes the user cares about — backlog health, reliability,
permit compliance, cost variance, etc.> and you reason in the user's
business vocabulary (<key customer terms from the glossary>).

You prefer governed answers: when a Trusted UDF or metric_view measure
exists for a question, call it (`MEASURE(<measure>)`) rather than
reinventing the metric inline. When you don't know the customer's
convention for something (status set / criticality scheme / etc.), ASK
before guessing.
```

Scope `<domain>` to the in-scope modules — if the Space spans work-orders + reliability + PM planning, the persona is *"a maintenance reliability analyst"*; if it's HSE-focused, the persona is *"an HSE / safety analyst"*. Match the customer's primary persona from the family README's persona map.

**Part B — Rules that *can't* be shown by an example query.** Keep this list tight. Move anything an example query can demonstrate over to Step 5; move anything about *relationships between tables* over to the Joins config (see *What goes where* below). What's left in instructions is genuinely semantic — things no single query teaches:

- *"Datetimes are stored in the app-server timezone (`<customer's TZ>`). Bucket day/week/month accordingly — do not assume UTC."*
- *"`CAP` work-type is capital, not maintenance — exclude from any 'maintenance' total."*
- *"Status `WPCOND` means waiting on permit conditions and counts as backlog."* (terse — let the example queries show the full status set in `WHERE` clauses.)

Three or four lines, not twenty. The verbose imperative-rule style ("always filter X, always join on Y, count Z=0…") **belongs in example queries, not here**.

**Part C — What to defer to the user.** A short list of the customer's still-open follow-ups from the glossary (the Needs-confirmation table). Instruction wording: *"For questions about <X>, ask the user before answering — the customer's convention is still unconfirmed."*

Order matters: persona first (how to think), then semantic rules (what to keep in mind), then defer-to-user list (when to ask). Reversed = rules without mindset.

### What goes where — *avoid duplicating rules across surfaces*

| Goal | Surface | Why |
|---|---|---|
| Teach `WOCLASS='WORKORDER'` filter | **Example SQL** | Every "open backlog" example query shows it in the `WHERE` clause. Genie learns the pattern. |
| Teach `ISTASK=0` parent-dedup | **Example SQL** | Same — every count example shows it. |
| Teach `SYNONYMDOMAIN` status resolution | **Example SQL** + UC comment on `STATUS` column | One canonical query shows the resolution; the column comment names the column behavior. |
| Teach `HISTORYFLAG=0` filtering (when applicable) | **Example SQL** + UC comment on `HISTORYFLAG` column | Same pattern. |
| Encode table-to-table joins (`WORKORDER`→`ASSET`, `WORKORDER`→`LOCATIONS` on composite `SITEID` keys) | **Joins configuration** (declarative) | Genie respects declared joins without instruction text. Don't write *"always join on `SITEID`"* — declare the composite-key join once in Joins config. |
| Encode synonym vocabulary (Mainline → SITEIDs, etc.) | **Business synonyms** field in Genie Space + glossary skill | Don't bake into instructions; use the dedicated surface. |
| Encode canonical metrics (open WO count, MTBF, PM compliance) | **Trusted Assets** (UC SQL functions) + `metric_view.yaml` measures | `MEASURE()` calls in examples teach Genie to reach for the metric view rather than reinventing. |
| Establish persona / mindset | **Instructions Part A** | Only place that captures *how to think* — no other surface does this. |
| Truly-semantic rules (timezone interpretation, capital-vs-maintenance, custom-status meaning) | **Instructions Part B** | Examples can't fully capture; needs prose. Keep terse. |

Rule of thumb: if you find yourself writing *"always filter X"* / *"always join on Y"* / *"always count Z=0"* in instructions, that rule belongs in an example query, the Joins config, or a UC comment instead. Prose instructions are the **last** surface, not the first.

**Step 4 — Trusted Assets.** Register the relevant `metric_udfs.sql` functions
(substituting the customer catalog.schema), then add them to the Space so Genie
computes metrics via *certified* functions. Each metric's definition is owned by
its module skill — do not redefine it here. See
[Trusted Assets](https://docs.databricks.com/aws/en/genie/trusted-assets).

**Step 5 — Example SQL (do most of the heavy lifting here).** Add the parameterized queries from each in-scope module's `examples.sql` as Genie example queries. **Examples teach patterns, not just seed answers** — every filter / join / dedup convention should appear in at least one example query, so Genie learns by pattern-matching rather than by rule-reciting. If you find yourself writing prose in Step 3 to teach a pattern, add (or repair) an example query instead.

**Step 5b — Joins configuration (declare relationships, don't describe them).** Use the Genie Space's **Joins** configuration to declaratively register the composite-key joins between Maximo tables (`WORKORDER`↔`ASSET` on `assetnum + siteid`; `WORKORDER`↔`LOCATIONS` on `location + siteid`; etc.). Genie respects declared joins without needing instruction text. **Never write "always join on `SITEID`" in instructions** — declare the join once in Joins config and it applies to every query.

**Step 6 — Benchmark.** Run [benchmark.md](benchmark.md) against the Space. For each miss, fix in this order — **examples first, instructions last**:

1. **UC comment** (via `maximo-setup`) — if Genie misread a column meaning
2. **Joins configuration** — if Genie wrote a wrong join (missing composite key, wrong direction)
3. **Trusted Asset / metric_view measure** — if Genie reinvented a metric instead of calling the governed one
4. **Example SQL** — if Genie missed a pattern (filter, dedup, status resolution). **Most misses fix here**, not in instructions.
5. **Business synonym** — if Genie missed a vocabulary mapping
6. **Instructions (Part A persona or Part B semantic rule)** — last resort. Only if no example query / join / synonym can encode it.

Use the Genie **Monitoring** tab to find real questions it got wrong and feed them back.

## What's in this skill

- [benchmark.md](benchmark.md) — load when validating Space quality. A starter
  question set spanning work-management, reliability, integrity, HSE, and the
  cross-cutting traps, plus a Pass/Partial/Fail scoring rubric.

For programmatic create/export/import of the Space itself, load the platform
skill [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md).
This skill provides the Maximo curation content; that one provides the mechanics.

## What NOT to do

- Don't build a Space before `maximo-setup` has registered UC comments and the
  glossary — that is the #1 cause of wrong answers.
- Don't hand-write metric SQL into the Space — register the Trusted Asset
  functions instead. The metric *definitions* belong to the module skills
  (`maximo-reliability`, `maximo-maintenance-cost`, etc.), not here.
- Don't write verbose imperative-rule instructions ("always filter X", "always join on Y", "always count Z=0"). If an example query can demonstrate the pattern, add the example; if a join belongs in the Joins configuration, declare it there. Instructions are the smallest surface, not the largest — keep them short and reserved for genuinely semantic rules examples can't capture (timezone interpretation, capital-vs-maintenance, custom-status meaning). See *What goes where* in Step 3.
- Don't re-teach the universal data mechanics in the instructions — state them as
  example-query patterns and let `maximo-overview` carry the rationale.
- Don't write `"always join on SITEID"` into the instructions text — that's the Joins config's job. Declare the composite-key joins (`WORKORDER`↔`ASSET` on `assetnum + siteid`; `WORKORDER`↔`LOCATIONS` on `location + siteid`; etc.) once in the Genie Space Joins configuration and Genie respects them automatically.
- Don't expose raw Bronze tables; expose conformed Silver/Gold tables and views.
- Don't write or alter UC comments / table metadata from this skill — UC comments
  are owned by `maximo-setup` (preview-then-apply, gated on explicit user
  approval). Defer to it.
- Don't re-implement Genie create/export/import — defer to
  [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md).
- Don't declare it "done" — schedule a re-curation pass from the Monitoring tab.

## Composes with

- **`maximo-setup`** — runs FIRST; owns UC comments and the
  `<customer>-maximo-glossary` skill that seed instructions and synonyms. Never
  write UC comments from this skill; defer to setup's preview-then-apply.
- **`maximo-overview`** — source of the universal gotchas this skill encodes as
  Genie instructions (it does not re-author them).
- **Module skills** (`maximo-work-orders`, `maximo-reliability`,
  `maximo-pm-planning`, `maximo-inventory`, `maximo-maintenance-cost`,
  `maximo-labor-resources`, `maximo-asset-hierarchy`, `maximo-integrity`,
  `maximo-hse`, `maximo-workflow-and-approvals`) — source of the certified
  `examples.sql` and `metric_udfs.sql` to load. Each owns its metric definitions;
  this skill only assembles them into the Space.
- **`databricks-genie`** (platform) — Space create / export / import / API
  mechanics. This skill provides the Maximo content; that one provides the how.

## References

- [benchmark.md](benchmark.md) — starter benchmark question set + scoring rubric
- [Genie best practices](https://docs.databricks.com/aws/en/genie/best-practices) · [Monitoring](https://docs.databricks.com/aws/en/genie/monitor) · [Trusted Assets](https://docs.databricks.com/aws/en/genie/trusted-assets)
