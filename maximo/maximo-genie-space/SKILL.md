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
- [ ] Step 3: Draft the Description (SHORT — 1–2 sentences; distinct from Instructions)
- [ ] Step 4: Draft the Instructions (persona + semantic rules; NOT a copy of the Description)
- [ ] Step 5: Register Trusted Asset functions and add them to the Space
- [ ] Step 6: Add certified example SQL from the module examples.sql files
- [ ] Step 6b: Declare composite-key joins in the Joins configuration
- [ ] Step 7: Run the benchmark; fix on the matching surface; repeat
- [ ] Step 8: Ship the prompting cookbook to end users (paste into Space README / launchpad)
```

The Genie Space has multiple text + config surfaces. Match content to the right one — each has a sweet spot:

| Genie Space field | Source in this family | What goes here |
|---|---|---|
| **Description** (short, user-facing) | This skill, Step 3 | 1–2 sentences: what the Space is for, who it's for. Visible to end users in the Space picker. NOT the agent's behavior rules. |
| **General instructions** (agent behavior) | This skill, Step 4 — persona + semantic rules from `maximo-overview` gotchas + workspace glossary | How the agent should think and answer. Substantial when there's substantial content (persona, semantic rules, KPI definitions, tribal knowledge). |
| **Certified example SQL** | each in-scope module skill's `examples.sql` | Pattern teaching — query shapes Genie learns from. |
| **Business synonyms** | the `<customer>-maximo-glossary` skill from `maximo-setup` | Customer vocabulary → schema mappings. |
| **Trusted Asset functions** | each module's `metric_udfs.sql` | Governed metric definitions Genie calls via `MEASURE()` / function call. |
| **Joins configuration** | Step 6b below | Declarative composite-key joins between Maximo tables. |

**Step 3 — Description (SHORT, 1–2 sentences).** This is a **distinct field** from the Instructions field — don't conflate. The Description is what end users see in the Space picker / Space list; it answers *"what is this Space for?"* in 1–2 sentences. It is NOT the agent's behavior rules.

Template:
```
<Customer>'s Maximo <domain> agent. Ask natural-language questions
about <in-scope topics — work orders, PM compliance, integrity
inspections, etc.> for <customer-specific scope, e.g. Mainline +
Field operations>.
```

Example for a work-orders-scoped Enbridge Space:
```
Enbridge's Maximo work-order agent. Ask natural-language questions
about open backlog, completion trends, labor utilization, and PM-vs-
corrective mix across Mainline and Field operations.
```

Keep it under ~30 words. Specific enough that a user can tell whether this Space is the right one to pick. Do NOT put behavior rules, persona prose, table filters, or any imperative content here — those go in the Instructions field (Step 4).

**Step 4 — Instructions.** A Genie Space has multiple surfaces (Instructions, Example SQL, Joins config, Trusted Assets, Business synonyms, UC comments). Each has a sweet spot — **match content to the right surface**. Instructions are the right surface for things that *only* prose can carry: persona, judgment guidance, semantic rules, boundaries, customer-specific tribal knowledge. Use them heavily for that content. Don't use them to teach things examples or the Joins config carry better. Three-part block, in this order:

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

**Part B — Semantic rules, business logic, and judgment guidance.** Content that genuinely belongs here, used heavily:

- *Semantic rules examples can't capture* — *"Datetimes are stored in the app-server timezone (`<customer's TZ>`). Bucket day/week/month accordingly — do not assume UTC."* / *"`CAP` work-type is capital, not maintenance — exclude from any 'maintenance' total."*
- *Custom-status / customer-vocabulary meanings* — *"`WPCOND` means waiting on permit conditions and counts as backlog at Enbridge. `EM` is emergency maintenance — counts as corrective in trends but tracked in its own bucket. `INSP` is regulatory inspection — its own category, do NOT roll into preventive."*
- *Customer-specific tribal knowledge* — *"Mainline integrity inspections are tracked as `WORKTYPE='INSP' AND wo_reg_flag='Y'` — both flags needed. Other inspection types do not carry `wo_reg_flag='Y'`."*
- *KPI definitions specific to the customer* (where they aren't already in Trusted UDFs) — *"Schedule compliance at Enbridge is computed weekly, target 95%, against PMs in the `WSCH` status at week-start."*
- *Judgment guidance / "when in doubt..."* — *"For cost questions, first check `wo_currencycode` — POs may be in CAD, USD, or MXN; convert to base currency before aggregating."*
- *Scope and boundaries* — *"You answer questions about work orders, PMs, labor, and HSE permits. For cost methodology or rollup, defer to the cost analyst (use `maximo-maintenance-cost`'s metric view)."*

Use as much prose as you need to convey these accurately — they're what makes the Agent a Maximo SME rather than a SQL bot. The anti-pattern is *imperative rules that examples already teach* (see *What goes where* below) — those should be example queries, not instructions.

**Part C — What to defer to the user.** A list of the customer's still-open follow-ups from the glossary (the Needs-confirmation table). Instruction wording: *"For questions about <X>, ask the user before answering — the customer's convention is still unconfirmed."* This belongs in instructions because it's judgment (when to ask vs when to proceed), not a query pattern.

Order matters: persona first (how to think), then semantic rules and business logic (what mindset to bring), then defer-to-user list (when to ask). Reversed = rules without mindset.

### What goes where — *match content to surface*

Genie Space has multiple surfaces, each with a sweet spot. Use the one that fits the content; don't duplicate the same content across surfaces.

| Content | Right surface | Why |
|---|---|---|
| `WOCLASS='WORKORDER'`, `ISTASK=0`, `HISTORYFLAG=0` filter patterns | **Example SQL** | Genie learns these by pattern-matching against query examples in the `WHERE` clause. Repeating them as prose imperatives is redundant. |
| `SYNONYMDOMAIN` status resolution pattern | **Example SQL** + UC comment on `STATUS` column | One canonical query shows the resolution; the column comment names the column behavior. |
| Table-to-table joins (`WORKORDER`→`ASSET`, `WORKORDER`→`LOCATIONS` on composite `SITEID` keys) | **Joins configuration** (declarative) | Genie respects declared joins without instruction text. Declare the composite-key join once in Joins config. |
| Synonym vocabulary (Mainline → SITEIDs, etc.) | **Business synonyms** field + glossary skill | Dedicated surface for vocabulary mappings. |
| Canonical metric definitions (open WO count, MTBF, PM compliance) | **Trusted Assets** (UC SQL functions) + `metric_view.yaml` measures | `MEASURE()` calls in examples teach Genie to reach for the metric view rather than reinventing. |
| Persona / mindset / how to think | **Instructions Part A** | Only place that captures *how to think*. |
| Semantic rules, business logic, judgment, KPI definitions, tribal knowledge, scope/boundaries, defer-to-user logic | **Instructions Part B/C** | These can't be conveyed by a single query or a declarative join. Use as much prose as needed. |

The anti-pattern isn't *long* instructions — it's *imperative-rule instructions that examples already teach*. *"Always filter `WOCLASS='WORKORDER'`"* duplicates what every example query shows; that rule belongs in examples. *"`CAP` is capital, exclude from maintenance"* is a semantic interpretation no query shows on its own; that rule belongs in instructions. Different content, different surface.

**Step 5 — Trusted Assets.** Register the relevant `metric_udfs.sql` functions
(substituting the customer catalog.schema), then add them to the Space so Genie
computes metrics via *certified* functions. Each metric's definition is owned by
its module skill — do not redefine it here. See
[Trusted Assets](https://docs.databricks.com/aws/en/genie/trusted-assets).

**Step 6 — Example SQL (do most of the heavy lifting here).** Add the parameterized queries from each in-scope module's `examples.sql` as Genie example queries. **Examples teach patterns, not just seed answers** — every filter / join / dedup convention should appear in at least one example query, so Genie learns by pattern-matching rather than by rule-reciting. If you find yourself writing prose in Step 4 to teach a pattern, add (or repair) an example query instead.

**Step 6b — Joins configuration (declare relationships, don't describe them).** Use the Genie Space's **Joins** configuration to declaratively register the composite-key joins between Maximo tables (`WORKORDER`↔`ASSET` on `assetnum + siteid`; `WORKORDER`↔`LOCATIONS` on `location + siteid`; etc.). Genie respects declared joins without needing instruction text. **Never write "always join on `SITEID`" in instructions** — declare the join once in Joins config and it applies to every query.

**Step 7 — Benchmark (add to the Space, not just run externally).** Two parts: (a) load the benchmark questions into the Space's **Benchmark** tab so they persist as a validation set the Space owns; (b) run them and iterate.

**Step 7a — Add benchmark questions to the Space's Benchmark tab.** Don't just keep [benchmark.md](benchmark.md) as an external doc you grade by hand. The Genie Space has a first-class Benchmark feature — load the questions there so:
- The Space carries its own regression-validation set (anyone can re-run it).
- Genie tracks pass/fail across versions of the Space, surfacing drift.
- New real-world questions caught in the **Monitoring** tab can be promoted into the benchmark with one click.

Source the questions from [benchmark.md](benchmark.md) (the starter set), then add the customer's own actual-business questions on top — those are the ones that matter most. Coverage target:
- ≥3 questions per in-scope module (one each: simple count, breakdown, time-windowed)
- ≥2 ambiguity-resolution questions (open-status set, criticality scheme — Genie should ask back, not guess)
- ≥2 cross-module / hierarchical questions (e.g. "backlog at Mainline by work type") to exercise Joins config + glossary

**Step 7b — Run + iterate.** Run the benchmark from the Space. For each miss, **diagnose what kind of miss it is** and fix on the matching surface — don't dump every fix into instructions, and don't avoid instructions when they're the right surface:

| Miss shape | Fix surface |
|---|---|
| Genie misread a column's meaning | **UC comment** (via `maximo-setup`) |
| Genie wrote a wrong join (missing composite key, wrong direction) | **Joins configuration** |
| Genie reinvented a metric inline instead of calling the governed one | **Trusted Asset / metric_view measure** (add the function or fix the `MEASURE()` reference) |
| Genie missed a query pattern (filter, dedup, status resolution) | **Example SQL** — add or repair an example that demonstrates the pattern |
| Genie missed a vocabulary mapping | **Business synonyms** field |
| Genie answered like a generic SQL bot instead of a Maximo SME | **Instructions Part A** (persona) — strengthen the mindset opening |
| Genie applied a wrong semantic interpretation (timezone, CAP-vs-maintenance, custom-status meaning, KPI definition) | **Instructions Part B** (semantic rules) — add or refine |
| Genie should have asked the user but didn't | **Instructions Part C** (defer-to-user) — name the unconfirmed convention |

Use the Genie **Monitoring** tab to find real questions it got wrong and feed them back.

**Step 8 — Prompting cookbook (user-facing).** The six surfaces above all live *inside* the Space. There's a seventh surface that lives *outside*: a short prompting cookbook for the human users so they ask the Space well. Per [Genie Code best practices](https://docs.databricks.com/aws/en/genie-code/use-genie-code), specificity (level of detail, `@<table>` references, output shape, scope narrowing) significantly improves answer quality. The cookbook teaches that for Maximo's vocabulary.

Load [prompting_cookbook.md](prompting_cookbook.md) and paste the relevant entries into the customer's Space launchpad / README / onboarding doc. NOT for the Agent's Instructions field — that's for *agent behavior*. The cookbook is for the *human* prompting the Agent.

Each cookbook entry has three parts: a vague prompt (what users naturally type), a specific prompt (what gets a good answer), and the why (which Genie behavior the specificity exploits). Customize the examples for the customer's actual modules, site IDs, status set, and timezone before shipping.

## What's in this skill

- [benchmark.md](benchmark.md) — load when validating Space quality. A starter
  question set spanning work-management, reliability, integrity, HSE, and the
  cross-cutting traps, plus a Pass/Partial/Fail scoring rubric.
- [prompting_cookbook.md](prompting_cookbook.md) — load at Step 8. Maximo-specific
  worked examples of vague → specific user prompts (with `@<table>` references,
  status-set narrowing, timezone hints, output-shape steering, `/findTables`
  usage). Customize per customer (their modules, sites, status set, TZ), then
  ship to end users in the Space launchpad / README.

For programmatic create/export/import of the Space itself, load the platform
skill [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md).
This skill provides the Maximo curation content; that one provides the mechanics.

## What NOT to do

- Don't build a Space before `maximo-setup` has registered UC comments and the
  glossary — that is the #1 cause of wrong answers.
- Don't hand-write metric SQL into the Space — register the Trusted Asset
  functions instead. The metric *definitions* belong to the module skills
  (`maximo-reliability`, `maximo-maintenance-cost`, etc.), not here.
- Don't use instructions to teach query patterns examples already teach (filters like `WOCLASS='WORKORDER'` / `ISTASK=0` / `HISTORYFLAG=0`). The fix isn't to shrink instructions — it's to add example queries that demonstrate the pattern. Instructions stay for content that examples *can't* carry (persona, semantic rules, judgment, scope, tribal knowledge, KPI definitions, defer-to-user logic) — use them heavily for that.
- Don't describe table-to-table joins in prose. Composite-key joins (`WORKORDER`↔`ASSET` on `assetnum + siteid`; `WORKORDER`↔`LOCATIONS` on `location + siteid`; etc.) are declarative — register them once in the Genie Space Joins configuration and Genie respects them automatically. Writing *"always join on `SITEID`"* in instructions duplicates what the Joins config should be saying.
- Don't dump every fix into instructions during benchmarking. Match the fix to the kind of miss (see Step 7b table) — a wrong-metric miss fixes at Trusted Assets, a missed-pattern miss fixes at example SQL, a wrong-mindset miss fixes at instructions Part A.
- Don't conflate the **Description** and **Instructions** fields. Description is a SHORT 1–2 sentence user-facing summary (what the Space is for; who picks it). Instructions is the agent's behavior block (persona + semantic rules). Putting persona / behavior rules into the Description field surfaces them to end users in the Space picker — wrong audience, wrong surface. Step 3 = Description; Step 4 = Instructions; keep them separate.
- Don't skip Step 7a (loading benchmark questions into the Space's Benchmark tab). Running [benchmark.md](benchmark.md) externally is fine for the first pass, but the questions need to LIVE in the Space so the Space carries its own validation set, regressions are visible across versions, and Monitoring-tab finds can be promoted in with one click.
- Don't expose raw Bronze tables; expose conformed Silver/Gold tables and views.
- Don't write or alter UC comments / table metadata from this skill — UC comments
  are owned by `maximo-setup` (preview-then-apply, gated on explicit user
  approval). Defer to it.
- Don't re-implement Genie create/export/import — defer to
  [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md).
- Don't declare it "done" — schedule a re-curation pass from the Monitoring tab.
- Don't put prompting cookbook content into the Agent's Instructions field. The cookbook teaches *humans how to prompt the Agent*; Instructions tell *the Agent how to answer*. Different audiences, different surfaces. Ship the cookbook in the Space launchpad / README / onboarding doc, not as Instructions text.

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
