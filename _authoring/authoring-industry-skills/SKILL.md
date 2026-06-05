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
  version: "0.2.1"
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

The three things that make a skill worth more than generic docs:

1. **UC comments are the #1 quality lever.** Missing comments degrade SQL quality. Every family's `-setup` registers standardized UC comments. Ref: [Genie best practices](https://docs.databricks.com/aws/en/genie/best-practices).
2. **Trusted Assets.** Ship canonical metrics as UC SQL functions (`metric_udfs.sql`) so Genie calls them as governed metrics instead of regenerating ad-hoc SQL. Ref: [Trusted Assets](https://docs.databricks.com/aws/en/genie/trusted-assets).
3. **Workspace glossary skill.** `-setup` generates a workspace-tier skill mapping customer jargon → physical schema (the value-/concept-level layer UC comments can't capture).

### Genie Code conventions

- **CLI auth:** in-workspace, Genie Code is already authenticated to the current workspace — don't add `--profile`. That flag is local-only.
- Reference tables with `@catalog.schema.table`; discover with `/findTables`.
- MCP tools must be fully qualified: `ServerName:tool_name`.

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
- Don't include time-sensitive text ("after August 2025…"). Use an "old patterns" note instead.
- Don't author outcome-driven content ("analyze contractor performance") in `<source>-*` skills — that's top-layer and lives elsewhere.

## References

- [checklist.md](checklist.md) — full reviewer checklist
- [`../../_template/`](../../_template/) — canonical mold to fork
- Platform-skills library: [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills)
- Genie Code docs: [skills](https://docs.databricks.com/aws/en/genie-code/skills) · [tips](https://docs.databricks.com/aws/en/genie-code/tips) · [use](https://docs.databricks.com/aws/en/genie-code/use-genie-code)
- [Agent Skills best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) · [agentskills.io](https://agentskills.io/skill-creation/best-practices)
