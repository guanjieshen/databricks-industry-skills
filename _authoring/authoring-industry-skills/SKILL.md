---
name: authoring-industry-skills
description: |
  Use when creating, authoring, reviewing, or refactoring any Genie Code skill
  or data-source family in databricks-industry-skills (Maximo, SAP PM, Oracle
  EAM, OSIsoft PI, Salesforce, ServiceNow, …). Defines the repo's standard:
  the three-layer skill stack, the two jobs every middle-layer skill must do
  (SME-substitute + SME-question-surfacer), frontmatter, description-writing,
  family tiers, progressive disclosure, Trusted Assets, UC comments,
  Genie-Code-native conventions. Triggers on: "create a skill", "author a new
  skill", "add a new module", "add a module to maximo", "build a new source
  family", "scaffold a skill family", "new data-source family",
  "review this skill", "audit a skill", "is this skill discoverable",
  "my skill isn't triggering", "write a description Genie will match",
  "fix the frontmatter", "promote skill content to UC comments",
  "split responsibility between setup and skills",
  "contribute to industry-skills", "skill best practices".
metadata:
  version: "0.2.2"
---

# Authoring Industry Skills

The contributor standard for this repo. Load before creating, reviewing, or refactoring any skill. Grounded in the [Genie Code skills spec](https://docs.databricks.com/aws/en/genie-code/skills), [Agent Skills best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices), and the canonical platform-skills library at [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills).

## North star

> Every skill in this repo fills source/domain knowledge gaps that **Databricks Genie Code** (the agent harness) cannot infer from Unity Catalog + lineage alone. We never re-teach what Genie Code already does well — including what's already taught by the canonical platform skills at [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills).

Write **feature-agnostic** content anchored to Genie Code's durable behaviors (deep UC integration, agentic data work, skill-driven extensibility, governance enforcement). Features evolve — the Genie Spaces → Genie Agents rebrand changes the brand, not the concept; skills authored to the concept survive. Re-audit annually.

### The Genie taxonomy (be precise)

| Product | What it is | Relevance |
|---|---|---|
| **Genie Code** | The technical environment / agent harness — agentic data-work tool that loads Agent Skills, builds pipelines, trains ML, scaffolds the rest | **The target of this repo** |
| **Genie Agents** | Curated, no-code agents for targeted use cases (formerly *Genie Spaces*) — a Genie Code-authored data product end users query in natural language | What a `<source>-genie-agent` skill scaffolds |
| **Genie One** | The AI coworker for business users (chat / search / dashboards / agents) | Consumes the curated data layer |
| **AI/BI** | Dashboards + AI-assisted analytics, powered by Genie | Skills enable Genie Code to author dashboards with correct semantics |
| **Genie Apps** | No-code app development | Skills enable Genie Code to scaffold apps with correct data context |

Skills don't bind to a specific output type — they make Genie Code competent at producing *any* of these for a source.

### Who this is for

Primary customer: a **Databricks customer organization** installing the family into their own workspace. Two personas:

| Persona | Has | Lacks |
|---|---|---|
| **IT data engineer** (primary) | Databricks / DE chops | Domain knowledge of the business app |
| **Business data engineer** | Domain knowledge | Platform chops (Genie Code covers this) |

The IT DE today gets a task ("build a work-order-optimization dashboard"), doesn't know which tables/columns/conventions to use, has to schedule time with the business-app SME, and ships after multiple round-trips. **The skill removes the routine consultation entirely and batches the genuinely-ambiguous questions into one clarification round.**

### Success metric

Time from business request → production data product. **Length is a tax on the IT DE's clock.** Anything correct-but-slow-to-consume — long preambles, generic Databricks content, deep cross-references — defeats the value prop.

## Workspace layout (the one rule every skill obeys)

Every skill — shipped, generated, or customer-modified — lives as a **direct child of `.assistant/skills/`**, flat. Not nested under a family folder. Not in a subdirectory. Direct child.

```
✅ /Users/<email>/.assistant/skills/maximo-overview/SKILL.md
✅ /Users/<email>/.assistant/skills/maximo-work-orders/SKILL.md
✅ /Users/<email>/.assistant/skills/<customer>-maximo-glossary/SKILL.md
❌ /Users/<email>/.assistant/skills/maximo/maximo-overview/SKILL.md     ← nested; not discovered
❌ /Users/<email>/.assistant/skills/maximo/<customer>-maximo-glossary/  ← nested; not discovered
```

**Why**: Genie Code's auto-discovery does not reliably recurse into subfolders. A nested skill loads **only** when explicitly referenced by path (e.g. via user instructions or `@mention`) — never by description match. The whole "Genie selects skills by matching descriptions" loop fails for nested skills.

**Operational implications**:
- **Repo layout** stays grouped under `<source>/` folders for organization (`maximo/maximo-work-orders/`, `sap-pm/sap-pm-notifications/`, etc.) — that's a developer-side convention.
- **Install instructions** must flatten when pushing to a workspace. The shipped `databricks workspace import-dir <source>/ <skills-root>/` pattern in family READMEs is wrong — it creates the nested structure. **Use per-skill import to flatten**:
  ```bash
  for skill in <source>/*/; do
    name=$(basename "$skill")
    databricks workspace import-dir "$skill" "<skills-root>/$name" --overwrite
  done
  ```
- **`-setup` skills must generate their glossary output flat** — at `<skills-root>/<customer>-<source>-glossary/`, NOT at `<skills-root>/<source>/<customer>-<source>-glossary/`.

### Genie's auto-discovery cap

Genie Code's skill-matching loop has a soft cap on how many skill descriptions it evaluates per session. In workspaces with many installed skills (>20-ish), discovery may miss legitimate matches even when descriptions are perfect. The mitigation is a **deterministic skill-loading routing block in user instructions** (covered in *Phase 5* of `## Building a -setup skill` below) — for any source family, the `-setup` skill should offer to write that routing block as an opt-in vetted phase, so Genie has a reliable fallback when auto-discovery is rate-limited.

## The three commitments

### 1. Layer placement

| Layer | Knows | Where it lives |
|---|---|---|
| **Platform** (bottom) | How to build/operate on Databricks | [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills) |
| **Source / domain-data** (middle — **THIS REPO**) | What the data *means* once landed | `databricks-industry-skills/` |
| **Business process** (top) | How to answer a business question end-to-end | Customer-specific or framework repos (e.g. [`ai-dev-kit`](https://github.com/databricks-solutions/ai-dev-kit), [`databricks-agent-skills/skills`](https://github.com/databricks/databricks-agent-skills/tree/main/skills), internal) |

Top composes middle composes platform. Naming: middle = `<source>-<topic>`; top = by business question, not source. Outcome-driven requests ("reduce contractor spend") are top-layer and live elsewhere.

**Canonical platform skills — reference, never duplicate:**

| Platform skill | Use when middle-layer content needs to … |
|---|---|
| [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md) | Create/manage Genie Agents (formerly Spaces) |
| [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines) | Build Lakeflow pipelines (in `<source>-data-engineering`) |
| [`databricks-unity-catalog`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-unity-catalog) | UC mechanics — comments, grants, tags, lineage |
| [`databricks-aibi-dashboards`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-aibi-dashboards) | Author AI/BI dashboards |
| [`databricks-jobs`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-jobs) | Schedule pipelines/refreshes |
| [`databricks-dbsql`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-dbsql) | SQL warehouses |
| [`databricks-metric-views`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-metric-views) | Semantic metric layers |
| [`databricks-mlflow-evaluation`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-mlflow-evaluation), [`databricks-model-serving`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-model-serving) | ML eval / serving |
| [`databricks-vector-search`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-vector-search) | Vector indexes |

Reference via body links: *"For Genie Agent creation mechanics, load [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md). This skill provides the source-specific content."* **Do NOT chain `parent:` across layers — `parent:` is for the family's own `<source>-overview`.**

### 2. Two jobs per skill (primary + guardrail)

| Mode | Role | Where it shows up |
|---|---|---|
| **SME-substitute** (primary value) | Encode what an SME would *do*. Removes the routine consultation entirely | `schema.md`, `views.sql`, `metric_udfs.sql`, `gotchas.md`, inline top gotchas |
| **SME-question-surfacer** (correctness guardrail) | Encode what an SME would *ask before answering*. Collapses N round-trips into one batched ask | A dedicated `## Questions to surface first` section in `SKILL.md` |

**Every non-foundation skill MUST include `## Questions to surface first`** — separate from `## Pre-flight` (session config) and `## Top gotchas`. Lists ≥2 SME-reflex clarifying questions: definitions, thresholds, conventions with no defensible default. Examples:
- "PM compliance has 3+ valid definitions — which do you use?"
- "Which `STATUS` values count as 'open'?"
- "'Bad actor' has 4 valid framings — confirm which."

If you can't list ≥2, you are almost certainly missing domain content.

### 3. Foundation + module tiers

| Tier | Skill | Role |
|---|---|---|
| Foundation | `<source>-overview` | Universal orientation (data model, module map, universal gotchas) |
| Foundation | `<source>-setup` | **Customer-specific deployment knowledge.** Split-responsibility: UC comments (direct-read) + skill content (staging ground). See below |
| Foundation | `<source>-data-engineering` | Silver/Gold modeling patterns (refs `databricks-spark-declarative-pipelines`) |
| Foundation | `<source>-data-quality` | Diagnostic playbook for "this number looks wrong" |
| Module | `<source>-<topic>` | One coherent analytical domain |

**`-setup` is split-responsibility.** Business apps are customized per org. That customer-instance knowledge has two destinations:
1. **UC comments** (`<source>_comments.json` + preview-then-apply script) — facts that fit cleanly in a column comment. Genie reads them directly; no skill reload needed.
2. **Skill content** — everything else. The skill is the **staging ground**; stable per-column / per-table facts can graduate to UC comments next cycle.

`-setup` carries the **content** (the JSON spec for THIS customer). Defer UC `ALTER TABLE` mechanics to the platform-layer [`databricks-unity-catalog`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-unity-catalog) skill.

**`-genie-agent` scaffolder** (formerly `-genie-space`): encodes which UC objects + semantic descriptions / synonyms / Trusted UDFs to curate for a Genie Agent. Defer creation mechanics to [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md).

## Building a `-setup` skill (the customer-deployment encoding pattern)

The `-setup` skill is the most complex shape in a source family. Its job: encode the customer's specific deployment (their conventions, terminology, customizations) so every other module-tier skill in the family answers correctly *for this customer's data*. The Maximo family's `maximo-setup` v0.3.0 is the canonical implementation; the patterns below transfer to SAP PM, Oracle EAM, Salesforce, ServiceNow, OSIsoft PI, etc.

### The overview-as-ledger pattern

The source's `<source>-overview` is the **canonical home for cross-cutting facts** that every module-tier skill reuses (composite-key joins, status semantics, history vs current state, timezone conventions, hidden-record flags). Modules **reference** these from overview rather than restating them. The `-setup` skill captures the customer-specific *values* within those mechanics — the customer's open-status set, their app-server timezone, their renamed status synonyms — not the mechanics themselves.

For Maximo: SITEID composite keys, `WOCLASS` filtering, `ISTASK` tasks-vs-child-WOs, `SYNONYMDOMAIN` status resolution, `HISTORYFLAG`, app-server-timezone datetimes. Equivalent universal-fact catalogues exist per source.

### Phase architecture

| Phase | Purpose | Default? |
|---|---|---|
| **0 — Profile** | Read-only inspection of the customer's data. Python preferred (`introspect_schema.py`); SQL fallback (`profile_queries.sql`) for warehouse-only sessions. Output: `draft_profile.json` + `activity_report.md` | ✅ |
| **0.5 — Read default Genie Code instructions** | If the workspace has default Genie Code instructions, parse for any pre-documented facts (catalog, timezone, currency, jargon) and skip the corresponding interview questions | ✅ |
| **1 — Interview** | Adaptive, conversational gap-confirmation grounded in the profile. Captures `answers.json` | ✅ |
| **2 — Generate glossary** | Render `<customer>-<source>-glossary/SKILL.md` from `answers.json`. **Output at FLAT `<skills-root>/<customer>-<source>-glossary/`** — not nested under `<skills-root>/<source>/`. Co-located with `answers.json`, `draft_profile.json`, `activity_report.md`, and timestamped `history/` snapshots | ✅ |
| **3 — UC comment registration** | Modifies customer-owned UC objects | ❌ **Opt-in only**, multi-checkpoint vetted (see below) |
| **4 — Write customer-facts summary to default Genie Code instructions** | Modifies customer-owned workspace config | ❌ **Opt-in only**, same vetted flow as Phase 3 |
| **5 — Write skill-loading routing block to user instructions** | Modifies user-owned workspace config. Highest-value follow-up after the glossary itself because Genie's auto-discovery cap may otherwise cause downstream module skills to silently not load | ❌ **Opt-in only**, same vetted flow as Phase 3 |

Phases 3/4/5 share the same **4-checkpoint vetted flow**: preview → unambiguous approval → customer executes (the skill never auto-applies) → post-apply verification. Surface them as opt-in next steps in the closing summary; never auto-advance to any of them. The setup skill's job is to make them visible as available actions, not to execute them.

### 4-verdict module activity detection

Customers often ingest the entire source schema but only actively use a few modules. Activity detection scopes setup output to what's actually in use.

| Verdict | Definition | Default behavior |
|---|---|---|
| `ACTIVE` | Indicator tables present, rows > 0, MAX(date) within 365 days | Include in interview, glossary, Phase 3 preview |
| `DORMANT` | Tables present, rows > 0, MAX(date) > 365 days | Skip by default. `--include-all` overrides. Surface as confirm-or-include in interview |
| `NOT_INGESTED` | Indicator table missing | Silently skipped |
| `INSUFFICIENT_DATA` | No datetime column / sparse data | Treat as ACTIVE; surface for confirmation |

The verdict scheme needs a **module → primary table → date-column map** per source. For Maximo, that's `WORKORDER.STATUSDATE` for work_management, `PM.LASTCOMPDATE` for preventive_maintenance, etc. Each source has equivalent mappings.

Cross-table population probes (e.g. `% of WORKORDER with PMNUM populated`) feed the heatmap's evidence column and surface as glossary caveats when low.

### Adaptive interview design

Six design principles (apply universally):

1. **Data tells us what it can.** Never ask what the profiler can answer.
2. **Tier by correctness blast radius.** Tier 1 always asked; Tier 2 quality; Tier 3 edge/specialized.
3. **Default to skip, not interrogate.** Questions fire only when their trigger evaluates true.
4. **Skip-defer is always a valid answer.** Skipped items → `answers.followups` with `owner: <role>`. Customer is **never blocked**.
5. **Re-runs close gaps over time.** Delta-refresh revisits unconfirmed items.
6. **One accessible voice; explain source-specific concepts once per batch** (suppressed for Expert/Familiar customers via Q0).

**Q0 (familiarity check) is the first question.** It records `customer.<source>_familiarity` (Expert / Familiar / Limited / None) and drives:
- Batch-opening **concept sidebars** (shown for Limited/None; suppressed for Expert)
- **Defer affordance intensity** (eagerly offered for Limited/None)
- **SME suggestions** for sensitive batches (proactive for Limited/None)

**Question header pattern** in `interview.md`:
```markdown
### Q{N}: {Title}
**Tier**: 1 | 2 | 3
**Trigger**: <boolean over draft_profile + answers-so-far>
**Skip behavior**: defer to `_unknown_` with `owner: <role>`
**Records to**: answers.<key>

{Question prose — plain language, no dual phrasing}
```

**Three adaptation dimensions**:
1. Activity heatmap → scopes which modules' questions fire (Batch-level + question-level skipping).
2. Prior-answer branching → e.g. *"if customer said 'we use SAP for inventory', drop all inventory questions"*.
3. Data-signal triggers → e.g. *"only ask multi-currency question if `distinct_currencies > 1`"*.

### Persistent artifact layout

All setup state lives inside the customer's glossary skill folder — git-trackable, multi-customer-scoped, enterprise-fork-compatible. **Layout is FLAT at the skills root** (see *Workspace layout* above):

```
<skills-root>/<customer>-<source>-glossary/         ← flat, direct child of .assistant/skills/
├── SKILL.md                ← Genie-loaded glossary (rendered view)
├── answers.json            ← structured source of truth
├── draft_profile.json      ← most-recent Phase 0 profile
├── activity_report.md      ← most-recent Module Activity Heatmap
└── history/                ← timestamped snapshots; --no-history disables
```

NOT `<skills-root>/<source>/<customer>-<source>-glossary/` — nesting under a source-folder breaks Genie's auto-discovery (see *Workspace layout* above for the why).

Re-runs load `answers.json` directly (not parse rendered markdown). Customer-managed enterprise GitHub forks can `.gitignore` ephemeral artifacts and rely on git history; the framework's `--no-history` flag supports this cleanly.

### Phase 3 vetting — 4 non-skippable checkpoints

When the customer **explicitly requests** UC comment registration (never offered spontaneously):

1. **Preview** — emit full statement list + scope (ACTIVE-only by default; `--scope all` includes DORMANT) + diff against existing comments. No writes.
2. **Unambiguous approval** — "yes apply" or equivalent. **NOT** "okay" / "looks good" / "sounds fine" — those are acknowledgments, not approval.
3. **Customer executes** — Python `--apply` OR runs the committed `apply_uc_comments.sql` artifact themselves in SQL Editor. The skill never auto-applies.
4. **Post-apply verification** — confirm `system.information_schema.columns` reflects the comments.

Two SQL mechanisms ship for Phase 3:
- **Generated** via `apply_uc_comments.py --emit-sql <path>` — uses Databricks `IDENTIFIER()` parameterization for namespace binding in SQL Editor.
- **Committed** `apply_uc_comments.sql` — hand-runnable for warehouse-only customers. CI verifies it matches the generated output.

### Cross-source adaptation (what varies, what stays identical)

| Aspect | Varies per source | Stays identical |
|---|---|---|
| Module → primary table → date-column map | ✅ Maximo: `WORKORDER.STATUSDATE` etc.; SAP PM: `AUFK.ERDAT` etc.; Salesforce: `Case.LastModifiedDate` etc. | The 4-verdict scheme + 365-day threshold + recency probe pattern |
| Industry-solution / customization signals | ✅ Maximo: PLUSG/PLUSC/PLUST/PLUSU; SAP: IS-Oil, IS-Utilities, IS-MIL; Salesforce: Industry Cloud, Field Service | The probe-then-confirm interview pattern |
| Universal-fact catalogue in `-overview` | ✅ Per source (Maximo: SYNONYMDOMAIN, HISTORYFLAG, app-server-timezone; SAP: client-scoped tables, language-scoped texts, time-zone TVARV; Salesforce: org-wide defaults, multi-currency org, time zones) | The overview-as-ledger pattern itself |
| Customer-specific customization dimensions | ✅ workflows, calendars, criticality schemes, status renamings vary in shape per source | The interview-tier framework + skip-defer + re-run-closes-gaps principles |
| Phase 3 mechanics | All sources require some form of UC comment / metadata registration | 4-checkpoint vetting + opt-in only + 2 SQL mechanisms |
| Persistent artifact layout | The folder name (`<customer>-<source>-glossary/`) varies | Everything else (file names, history pattern, gitignore template) is identical |

The framework above is portable. When forking the `_template/example-setup/` for a new source, fill in the source-specific map but keep the pattern intact.

## Building a `-genie-agent` skill (the Genie Space scaffolder pattern)

A `-genie-agent` skill (formerly `-genie-space`) helps Genie Code stand up a curated **Genie Agent** for a source. The Agent has multiple text + config surfaces; the skill's job is to teach Genie *what content goes on which surface*.

### The six Genie Space surfaces

| Surface | What goes there | Use heavily? |
|---|---|---|
| **Description** (1-2 sentences, user-facing) | What the Space is for, who picks it. Visible in the Space picker. | No — keep ≤30 words |
| **Instructions** (agent behavior block) | Persona + semantic rules + judgment + KPI definitions + tribal knowledge + scope/boundaries + defer-to-user logic | **Yes** — substantial when there's substantial content |
| **Example SQL** (query patterns) | Filter/dedup/status-resolution patterns Genie learns by example | **Yes** — the pattern-teaching surface |
| **Joins configuration** (declarative relationships) | Composite-key joins between source tables | **Yes** — Genie respects declared joins automatically |
| **Trusted Assets** (UC SQL functions) | Governed metric definitions Genie calls via `MEASURE()` / function call | **Yes** — every certified metric in the family |
| **Business synonyms** (vocabulary mappings) | Customer business terms → physical schema | **Yes** — from the `-setup` glossary |

(UC table/column comments are a seventh content surface, owned by the family's `-setup` skill; they live in UC metadata, not the Space.)

### Match content to the right surface

Each surface has a sweet spot. The anti-pattern is **putting content on the wrong surface** — not "long instructions" or "short instructions." Three live-tested misuses to watch for:

1. **Behavior rules in the Description field.** Description is user-facing (in the Space picker); end users shouldn't see agent-behavior prose. Persona / rules go in **Instructions**. Skills must call out Description and Instructions as *distinct fields* with *distinct content*, with explicit templates for each.
2. **Query patterns as imperative rules in Instructions.** *"Always filter `WOCLASS='WORKORDER'`"* is a query pattern — it belongs in an **Example SQL** entry (every example query shows the filter in its `WHERE` clause; Genie learns by pattern). Don't repeat it as prose.
3. **Join logic in prose Instructions.** *"Always join on `SITEID`"* belongs in the **Joins configuration** — declared once, applied to every query. Don't describe joins in prose.

What DOES belong in Instructions (and where authors should put *substantial* content):
- **Persona opening** — *"You are an expert Maximo analyst focused on work-order operations. You care about backlog health, completion trends, labor utilization. You reason in the user's vocabulary…"* (FIRST section, always — without it the agent answers like a generic SQL bot)
- **Semantic rules examples can't capture** — *"Datetimes are in app-server timezone (`America/Edmonton`). `CAP` work-type is capital, not maintenance — exclude from maintenance totals."*
- **Customer-specific tribal knowledge** — *"Mainline integrity inspections are tracked as `WORKTYPE='INSP' AND wo_reg_flag='Y'` — both flags needed."*
- **KPI definitions** specific to the customer (when not already in Trusted UDFs)
- **Judgment guidance / "when in doubt"** — *"For cost questions, check `wo_currencycode` — convert to base currency before aggregating."*
- **Scope and boundaries** — *"You answer questions about work orders + labor + HSE permits. For cost methodology, defer."*

### Description vs Instructions — keep them separate

The single most common live-test misuse: Genie dumping behavior rules into the Description field. The `-genie-agent` skill MUST make this distinction explicit. Two separate steps in the workflow, two separate templates:

**Description template** (1-2 sentences, ≤30 words, no behavior rules):
```
<Customer>'s Maximo <domain> agent. Ask natural-language questions
about <in-scope topics> for <customer-specific scope>.
```

**Instructions template** (Part A persona + Part B semantic rules + Part C defer-to-user):
```
You are an expert <source> analyst focused on <domain>. You have a deep
understanding of <key entities and the customer's deployment>. You care
about <outcomes>. You reason in the user's vocabulary (<customer terms>).

You prefer governed answers: when a Trusted UDF or metric_view measure
exists, call it (MEASURE(<measure>)) rather than reinventing inline.
When you don't know the customer's convention, ASK before guessing.

[semantic rules — timezone, custom-status meanings, customer-specific
behavior logic, tribal knowledge, scope/boundaries]

[defer-to-user list — for questions about <X>, ask the user before
answering; the customer's convention is still unconfirmed]
```

### Benchmark — load INTO the Space, not external

The `-genie-agent` skill ships a `benchmark.md` (starter questions). During curation, those questions must be **loaded into the Genie Space's Benchmark tab**, not kept as an external doc you grade by hand. Reasons:
- The Space carries its own validation set (regressions visible across versions).
- Monitoring-tab questions promote in with one click.
- Anyone can re-run the benchmark from the Space.

Coverage target per the canonical pattern:
- ≥3 questions per in-scope module (count + breakdown + time-windowed)
- ≥2 ambiguity-resolution questions (the Agent should ask back, not guess)
- ≥2 cross-module / hierarchical questions (exercise Joins config + glossary)

### Benchmark fix order — match the fix to the miss

When the Space misses a question, *diagnose* before fixing. Each miss type fixes on a different surface:

| Miss shape | Fix surface |
|---|---|
| Wrong column meaning | UC comment (via `-setup`) |
| Wrong join (missing composite key) | Joins configuration |
| Reinvented a metric inline | Trusted Asset / metric_view (add the function; fix the `MEASURE()` reference) |
| Missed a query pattern | Example SQL (add or repair an example) |
| Missed a vocabulary mapping | Business synonyms |
| Generic-SQL-bot answer (no SME mindset) | Instructions Part A (persona) |
| Wrong semantic interpretation (timezone, scope rule) | Instructions Part B |
| Should have asked the user but didn't | Instructions Part C (defer-to-user) |

No "instructions first" or "instructions last." Each surface is first for its kind of miss.

### Prompting cookbook — a seventh, user-facing surface

The six surfaces above are inside the Genie Space. There's a seventh surface that lives **outside** the Space and improves answer quality without any in-Space change: a short, source-specific **prompting cookbook** the family ships for end users. Per [Databricks Genie Code best practices](https://docs.databricks.com/aws/en/genie-code/use-genie-code), Genie returns better answers when users specify level of detail, output structure, library, and reference tables explicitly (`@table-name`, `/findTables`). The cookbook teaches that for the source's vocabulary so customers learn to prompt their Space well.

What it is: a `prompting_cookbook.md` sibling file (or a README section) shipping with the `-genie-agent` skill, containing **3–7 worked example user prompts** showing the format and specificity Genie answers best with for *this* source. NOT instructions for the Agent — instructions for the *human* prompting the Agent.

Each entry has three parts:
- **Vague prompt** (what users naturally type)
- **Specific prompt** (what gets a good answer)
- **Why** (which Genie behavior the specificity exploits)

Pattern to cover:
- **Disambiguation by reference** — using `@<table-name>` or `@<column>` to lock context when natural language spans multiple modules/tables (Maximo: `@workorder` vs `@pm`; Salesforce: `@Case` vs `@Opportunity`).
- **Source-specific type-conversion / timezone hints** — when Genie needs help converting (Maximo datetimes are app-server-local; Salesforce datetimes are UTC; SAP dates are client-zone). Tell users when to specify the convention in-prompt.
- **Output-shape steering** — "as a bar chart" / "as a table grouped by site" / "step-by-step". Per Databricks docs, Genie respects explicit structure asks.
- **Scope-narrowing for the source's universal traps** — e.g. for Maximo: "open work orders" → "open work orders (`STATUS IN (WAPPR, APPR, INPRG, WMATL, WPCOND)`) on Mainline for the last 30 days". Steers Genie around the customer's status convention.
- **`/findTables` use** — when natural language is ambiguous about which table, recommend the slash command rather than guessing.

The cookbook lives with the `-genie-agent` skill so it ships and updates alongside the Space's curation. Customers can paste it into their Space's README/launchpad. Defer general Genie Code prompting tips to [Databricks docs](https://docs.databricks.com/aws/en/genie-code/use-genie-code) — only encode source-specific guidance here.

### Cross-source adaptation

The six-surface pattern (plus the seventh, user-facing cookbook) is universal. The source-specific content per surface varies:
- **Persona** is per-source / per-customer-persona (a Maximo planner ≠ a Salesforce SDR)
- **Joins configuration** is per-source-schema (Maximo's composite `SITEID` keys ≠ Salesforce's `AccountId` lookups)
- **Trusted UDFs** are per-source-and-module (MTBF for Maximo reliability ≠ pipeline conversion rate for Salesforce)
- **Benchmark questions** are per-customer-business (the customer's real questions are what matters; the shipped starter is just a seed)

When forking `_template/example-genie-agent/` for a new source, fill in the source-specific content but keep the six-surface pattern, the persona-first opening, the Description-vs-Instructions distinction, and the prompting cookbook intact.

## Quick start: a new module skill end-to-end

The order an author should actually follow:

1. **Read `<source>-overview/SKILL.md`** to anchor on the data model + module map
2. **Draft the description** — the matcher. 4 elements (what+when, source+synonyms, technical identifiers, business phrasings); ≤1024 chars; 3rd person
3. **List ≥2 SME-clarifying questions** for `## Questions to surface first` — definitions, thresholds, conventions with no defensible default. If you can't, you're missing domain content
4. **Draft 3–5 inline top gotchas** in SKILL.md (full set goes in `gotchas.md`)
5. **Add sibling files** with explicit "load when …" triggers: `schema.md`, `views.sql`, `metric_udfs.sql` (Trusted UDFs), `gotchas.md`, `examples.sql`
6. **Add ≥3 evals** under `<source>/evals/` — including ≥1 that exercises a Question-to-surface ambiguity
7. **Verify discovery in a NEW Agent-mode chat** — right skill loads on the trigger phrases, no false triggers on sibling skills
8. **Pre-merge:** walk the full reviewer [checklist.md](checklist.md)

## The golden rule

Genie Code loads a skill **only by matching its `description`**. Nothing else is used for selection. **Every discovery problem is a description problem.** Skills load only in Agent mode; after editing a skill, start a new chat for the change to take effect.

## Frontmatter

Required: `name`, `description`. This repo also uses `metadata.version`, `parent`, and `compatibility` (when the skill runs a CLI). **NEVER use `tags:` or `owners:`** — Genie ignores them.

```yaml
---
name: <source>-<topic>            # ≤64 chars, lowercase/hyphens, prefix with data source
description: |
  <see "Writing the description" below>
metadata:
  version: "0.1.0"
parent: <source>-overview         # omit only in the overview itself
# compatibility: Requires databricks CLI >= v0.294.0   # only if the skill runs the CLI
---
```

Hard limits: `name` ≤64 chars, globally unique once installed. `description` ≤1024 chars, third person, no XML tags.

## Writing the description (the matcher)

Highest-leverage thing you do. Every description carries four elements:

1. **What it does + when to use it** ("Use when querying / analyzing …").
2. **Data-source name + synonyms** ("IBM Maximo, Maximo, EAM, CMMS").
3. **Technical identifiers** the user might type (`WORKORDER`, `WOSTATUS`, `ASSETNUM`).
4. **Business phrasings** ("open work orders", "WO backlog", "labor hours by craft").

Calibrate by tier: root `-overview` is broad (matches *any* question about the source); modules are narrow + distinctive so Genie disambiguates siblings *at selection time*. Disambiguation in the body is too late.

Third person only. ✅ "Use for asset reliability metrics…" ❌ "I can help…" / "You can use this to…".

## Required SKILL.md sections (modules)

Order matters — it reflects how Genie should reason through a turn:

1. **`## When to use`** — trigger phrases + boundary with siblings
2. **`## Top gotchas`** — 3–5 must-know inline corrections
3. **`## Questions to surface first`** — ≥2 SME-clarifying questions
4. **`## Pre-flight (per session)`** — one-time session config (catalog/schema/glossary); cache, don't re-ask
5. **`## Workflow`** — resolution priority (parameterized example → view → raw table, or equivalent)
6. **`## What's in this skill`** — sibling files with "load when …" triggers
7. **`## What NOT to do`** — common mistakes / boundaries
8. **`## Composes with`** — pointers to sibling skills

`## Pre-flight` and `## Questions to surface first` are deliberately distinct (session setup vs per-request ambiguity).

## Progressive disclosure

- Body **<500 lines / ~5k tokens** — core instructions only.
- Heavy content in sibling files (`schema.md`, `gotchas.md`, `examples.sql`, `views.sql`, `metric_udfs.sql`) with explicit **"load when …" triggers** — never a generic "see references".
- References are **one level deep** from SKILL.md.
- Reference files **>100 lines get a `## Contents` ToC** so a partial read reveals scope.
- **Top gotchas + clarifying questions inline in SKILL.md** — Genie may not load sibling files at the moment of decision.
- Provide a **default, not a menu**. One recommended pattern with a brief escape hatch beats listing five options.

## Family structure

```
<data-source>/
├── README.md                       ← family overview, persona map, install order
├── <source>-overview/              ← FOUNDATION root
├── <source>-setup/                 ← FOUNDATION
├── <source>-data-engineering/      ← FOUNDATION
├── <source>-data-quality/          ← FOUNDATION
├── <source>-<module>/              ← MODULES
└── <source>-genie-agent/           ← optional scaffolder for a Genie Agent
```

Build foundation first, then modules. Every skill must pass: *"Would Genie behave better with this loaded than without?"* If not, cut it. Scope each skill as a **coherent unit** — not so narrow that one task needs five skills, not so broad it won't activate precisely.

## Genie-Code-native value adds

The things that make a skill worth more than generic docs:

1. **UC comments are the #1 quality lever.** Missing comments degrade SQL quality. Every family's `-setup` registers standardized UC comments. Ref: [Genie best practices](https://docs.databricks.com/aws/en/genie/best-practices).
2. **Metric views + agent metadata — the primary deliverable.** The most common thing customers build on top of a landed source is a **metric view**: a governed semantic layer (canonical measures, decoupled from grouping) that Genie Agents, AI/BI dashboards, and BI tools all consume. A module's canonical measures should ship as a `metric_view.yaml` whenever they're sliceable. The highest-leverage part is the **agent metadata** on each field/measure — `display_name`, `comment`, `format`, and especially `synonyms` (the real-world vocabulary that lets Genie *discover* a measure from natural language). This is the concept-level semantic layer UC comments alone cannot carry. Author the source-specific YAML here; defer creation/registration mechanics to the platform skill [`databricks-metric-views`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-metric-views). Refs: [metric views](https://docs.databricks.com/aws/en/business-semantics/metric-views/) · [agent metadata](https://docs.databricks.com/aws/en/business-semantics/agent-metadata) · [YAML reference](https://docs.databricks.com/aws/en/business-semantics/metric-views/yaml-reference) · [advanced techniques](https://docs.databricks.com/aws/en/business-semantics/metric-views/advanced-techniques).
3. **Trusted Assets.** Ship canonical metrics as UC SQL functions (`metric_udfs.sql`) so Genie calls them as governed, parameterized metrics instead of regenerating ad-hoc SQL. Complementary to metric views — the view is the sliceable surface, the UDF is the callable/parameterized form of the same definition. Ref: [Trusted Assets](https://docs.databricks.com/aws/en/genie/trusted-assets).
4. **Workspace glossary skill.** `-setup` generates a workspace-tier skill mapping customer jargon → physical schema (the value-/concept-level layer UC comments can't capture).

### Genie Code conventions

- **CLI auth:** in-workspace, Genie Code is already authenticated to the current workspace — don't add `--profile`. That flag is local-only.
- Reference tables with `@catalog.schema.table`; discover with `/findTables`.
- MCP tools must be fully qualified: `ServerName:tool_name`.
- **SQL parameter placeholders use Databricks-native `:param` syntax**, not Mustache `{{param}}`. Examples: `:catalog.:silver_schema.WORKORDER`, `WHERE wonum = :wonum`, `IN (:open_statuses)`. Databricks SQL warehouses, AI/BI Dashboards, and Genie Agents bind these natively at execution time. Use `:silver_schema` / `:gold_schema` when the source has both layers; `:schema` alone when there's only one.

## Repo rule: writes to existing objects require explicit user permission

**Any skill or script that modifies existing tables/data/metadata MUST get explicit approval first — never write as a side effect.** Covers UC comments (`COMMENT ON` / `ALTER TABLE … ALTER COLUMN`), `ALTER`/`DROP`/`UPDATE`/`DELETE`/`MERGE`/`INSERT OVERWRITE`, schema changes.

- **Writing scripts default to no-op preview** + require an explicit `--apply` flag. Pattern: [`../../maximo/maximo-setup/scripts/apply_uc_comments.py`](../../maximo/maximo-setup/scripts/apply_uc_comments.py).
- **Skills show the preview/diff and ask for confirmation** before the apply step.
- **Creating brand-new objects** in a scratch/demo schema is fine without this gate. The rule covers things the customer already owns.

## Evals — build them before more content

Add `<source>/evals/*.json` with `query` → `expected_behavior` cases. Run in a fresh Agent-mode chat to confirm (a) discovery (right skill loads) and (b) quality (correct answer). When a skill mis-triggers, **fix the description first.** See [`../../maximo/evals/`](../../maximo/evals/) for the format.

## What NOT to do

- Don't add `tags:` / `owners:` — they don't drive discovery.
- Don't bury trigger terms in the body; they belong in the `description`.
- **Don't re-teach what Genie Code already does** (Lakeflow, ML, dashboards, UC, lineage, MLflow, observability). Reference [`ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills); don't duplicate.
- **Don't couple to feature mechanics** (current API field names, UI screens, today's registration workflow). Author to the concept, not the surface.
- **Never modify existing tables/data/metadata without explicit user permission.** Preview first; gate on `--apply`; ask. See *Repo rule* above.
- **Never autonomously write to user / workspace instructions** (`.assistant_instructions.md`, default Genie Code workspace instructions). These are customer-owned config; writes go through the same 4-checkpoint vetted flow as UC writes (preview → unambiguous approval → customer applies themselves → post-apply verification). The `-setup` skill's Phase 4 (customer-facts summary) and Phase 5 (skill-loading routing block) cover this when the customer opts in. **Live-tested failure mode:** Genie Code is willing to autonomously edit these files during a skill's workflow if the skill doesn't explicitly forbid it. Every skill that touches workspace config must call this out in its own `## What NOT to do`.
- **Never install skills nested under a family folder in a workspace.** Repo layout under `<source>/` is a developer convention; workspace install must flatten to `.assistant/skills/<skill-name>/` direct children. Nested skills don't auto-discover. See *Workspace layout* above.
- **Never put behavior rules in a Genie Space's Description field.** Description is user-facing (Space picker) — 1-2 sentences, what the Space is for. Behavior rules go in the Instructions field. See *Building a `-genie-agent` skill* above for templates.
- Don't include time-sensitive text ("after August 2025…"). Use an "old patterns" note instead.
- Don't author outcome-driven content ("analyze contractor performance") in `<source>-*` skills — that's top-layer and lives elsewhere.

## References

- [checklist.md](checklist.md) — full reviewer checklist
- [`../../_template/`](../../_template/) — canonical mold to fork
- Platform-skills library: [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills)
- Genie Code docs: [skills](https://docs.databricks.com/aws/en/genie-code/skills) · [tips](https://docs.databricks.com/aws/en/genie-code/tips) · [use](https://docs.databricks.com/aws/en/genie-code/use-genie-code)
- [Agent Skills best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) · [agentskills.io](https://agentskills.io/skill-creation/best-practices)
