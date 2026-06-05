# Reviewer checklist

Run this before merging any new or changed skill. Load
[SKILL.md](SKILL.md) for the rationale behind each item — especially the
*North star: three-layer skill stack* section, which the first checks below
enforce.

## Contents
- Layer placement & roles
- Built for Genie Code's competencies (don't re-teach)
- Discovery
- Frontmatter
- Body & progressive disclosure
- Genie-Code-native value
- Safety — writes to existing objects
- Evals & verification

## Layer placement & roles (north star)

- [ ] Layer named explicitly: **platform** / **source-data (middle)** / **business-process (top)**. This repo is middle-layer; document why if not.
- [ ] If middle-layer: skill carries content for BOTH roles —
  - [ ] **SME-substitute** content present (schema / gotchas / views / Trusted UDFs)
  - [ ] **SME-question-surfacer** content present (a `## Questions to surface first` section with ≥2 ambiguity-resolving questions)
- [ ] `## Questions to surface first` and `## Pre-flight` are **separate** sections (per-request ambiguity vs one-time session setup)
- [ ] If the skill smells outcome-driven (e.g. "analyze contractor performance"), it should be top-layer and NOT live in this repo as a `<source>-*` skill — middle-layer prerequisites are built here; outcome skills compose them elsewhere

## Built for Genie Code's competencies (don't re-teach)

Assumption: Genie Code is a competent data agent and is the **target harness** specifically. Skills fill **domain gaps** Genie Code cannot infer from UC metadata + lineage alone — not to re-teach platform mechanics that already live in the canonical platform skills at [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills).

Be precise: **Genie Code** is the agent harness; **Genie Spaces** is a text-to-SQL data product Genie Code can create. Skills target Genie Code's capabilities; `<source>-genie-space` skills (if any) help Genie Code stand up well-curated Genie Spaces.

- [ ] **No re-teaching** of Genie Code's native competencies. The skill MUST NOT explain:
  - [ ] How to build/debug Lakeflow Spark Declarative Pipelines, AutoCDC flows, Auto Loader, data quality expectations → reference [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines)
  - [ ] How to create / manage Genie Spaces → reference [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md)
  - [ ] How to train/evaluate/serve ML models, MLflow, model serving → reference [`databricks-mlflow-evaluation`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-mlflow-evaluation) and [`databricks-model-serving`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-model-serving)
  - [ ] How to author AI/BI Dashboards → reference [`databricks-aibi-dashboards`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-aibi-dashboards)
  - [ ] How Unity Catalog mechanics work (comments, grants, tags, lineage traversal) → reference [`databricks-unity-catalog`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-unity-catalog)
  - [ ] How to schedule jobs / workflows → reference [`databricks-jobs`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-jobs)
  - [ ] How to discover data assets (Genie has `/findTables`, popularity-driven search, lineage traversal)
  - [ ] How to monitor pipelines / triage failures / analyze agent traces (Genie's production-observability layer)
  - [ ] Generic Spark / SQL / Python tutorials
  - [ ] How MCP integrations or persistent memory work (harness-managed, not skill content)
- [ ] **Feature-agnostic content only** — no coupling to today's specific Genie Code feature mechanics (Spaces API/UI shape, Trusted Assets registration UI, MCP integrations, background-agent specifics). Anchor to durable behaviors, not current surfaces.
- [ ] **Content is in scope** only if it fills one of these gaps:
  - [ ] Source-specific schema semantics not captured by UC comments
  - [ ] Domain gotchas (canonical filters, join keys, closure-table conventions)
  - [ ] **Customer-specific deployment knowledge** — what THIS organization's instance of the source looks like (workspace glossary, status sets, conventions)
  - [ ] Industry-canonical metric formulas (e.g. IBM-specific MTBF, SMRP compliance)
  - [ ] Trusted UDFs encoding those formulas
  - [ ] SME-clarifying questions (per the *Layer placement & roles* section above)
  - [ ] Business-jargon → physical-schema mapping (workspace glossary content)
  - [ ] Source-specific composition patterns ("compose work-orders + asset-hierarchy for region rollups")
- [ ] Spot-check: if Genie Code is the reader, encountering this source's data for the first time in THIS organization's deployment, does the skill teach it something *only* an SME would know? If it instead teaches Databricks platform content, cut that content and link to the canonical platform skill.
- [ ] Platform-mechanic references use body links (not the `parent:` field — parent is reserved for the family's own `<source>-overview`).

## Discovery (the description is the matcher)
- [ ] `description` is third person (no "I"/"you"), ≤1024 chars, non-empty
- [ ] Leads with the data-source name + synonyms (e.g. "IBM Maximo, Maximo, EAM, CMMS")
- [ ] Includes exact technical identifiers the user might type (table/column names)
- [ ] Includes business phrasings ("open work orders", "WO backlog")
- [ ] States both *what it does* and *when to use it*
- [ ] Root `-overview` description is broad; module descriptions are narrow & distinctive
- [ ] Sibling skills are distinguishable from this one's description alone

## Frontmatter
- [ ] `name` is `<source>-<topic>`, ≤64 chars, lowercase/numbers/hyphens, globally unique
- [ ] `metadata.version` present
- [ ] `parent: <source>-overview` set (unless this IS the overview, or it depends on `databricks-core`)
- [ ] `compatibility` present iff the skill runs CLI commands
- [ ] NO `tags:` and NO `owners:`

## Body & progressive disclosure
- [ ] Body < 500 lines / ~5k tokens
- [ ] Non-root skills open with the `> **FIRST:** load the <source>-overview skill …` line
- [ ] Required sections present in order: `## When to use` → `## Top gotchas` → `## Questions to surface first` → `## Pre-flight` → `## Workflow` → `## What's in this skill` → `## What NOT to do` → `## Composes with`
- [ ] Top 3–5 must-know gotchas are inline in SKILL.md (not only in gotchas.md)
- [ ] `## Questions to surface first` lists ≥2 SME-reflex clarifying questions (definition / threshold / convention disambiguation), inline in SKILL.md
- [ ] Heavy content lives in sibling files with explicit "load when …" triggers
- [ ] References are one level deep from SKILL.md
- [ ] Reference files > 100 lines have a `## Contents` ToC
- [ ] One recommended default per decision, not a menu of options
- [ ] No time-sensitive statements (use an "old patterns" note)
- [ ] Consistent terminology throughout

## Genie-Code-native value
- [ ] If the family has a `-setup` skill, it registers UC table/column comments
- [ ] Canonical metrics ship as Trusted Asset UC functions (`metric_udfs.sql`) where applicable
- [ ] CLI examples rely on ambient in-workspace auth (no `--profile`; that's local-only)
- [ ] MCP tools, if any, are fully qualified (`ServerName:tool_name`)

## Safety — writes to existing objects
- [ ] No write to existing tables/data/metadata happens as a side effect
- [ ] Writing scripts default to preview (no-op) and require an explicit `--apply`-style flag
- [ ] The skill shows the preview/diff and asks for explicit user approval before applying
- [ ] **For `-setup` skills**: UC comment registration is in an `## Optional` section, NEVER offered spontaneously
- [ ] **For `-setup` skills**: ambiguous customer responses ("okay" / "looks good") MUST NOT be interpreted as approval to apply UC writes — require unambiguous affirmation
- [ ] **For `-setup` skills**: default Genie Code workspace instructions are READ only in Pre-flight (to skip already-documented questions); writing to them is a separate opt-in flow with the same vetting as UC comments

## `-setup` skills — additional checklist

(Applies only to `<source>-setup` skills — the customer-deployment encoding pattern.)

- [ ] Phase 0 has dual-path implementation: Python preferred (`introspect_schema.py`); SQL fallback (`profile_queries.sql`) for warehouse-only sessions
- [ ] Phase 0 profile detects: module presence + recency (MAX(date) per module's primary table) + cross-table population + customization signals (workflows, calendars, currencies, criticality scheme, assignment model, asset specs)
- [ ] Activity heatmap output uses the **4-verdict scheme** (`ACTIVE` / `DORMANT` / `NOT_INGESTED` / `INSUFFICIENT_DATA`); DORMANT threshold = 365 days
- [ ] `module → primary table → date-column` map defined for this source (mirrors the Maximo example in `authoring-industry-skills` SKILL.md §"Building a -setup skill")
- [ ] Source's overview-as-ledger: cross-cutting facts captured in `<source>-overview`'s universal-gotchas section; `-setup` captures customer-specific *values* within those mechanics, not the mechanics themselves
- [ ] Phase 0.5 reads default Genie Code workspace instructions (if any) to pre-populate the profile and skip already-documented interview questions
- [ ] Interview opens with **Q0 (familiarity check)** before any batch questions
- [ ] Every interview question carries `Tier:` / `Trigger:` / `Skip behavior:` / `Records to:` headers
- [ ] Batch-opening "Concepts in this batch" sidebars present; suppressed when `<source>_familiarity` is `Expert` / `Familiar`
- [ ] Universal skip-defer affordance documented; skipped questions → `answers.followups` with `owner: <role>`
- [ ] Persistent state lives in `<skills-root>/<source>/<customer>-<source>-glossary/` — all artifacts co-located
- [ ] `history/` timestamped snapshots in place; `--no-history` flag for git-versioned customers
- [ ] Phase 3 (UC comment registration) is in an `## Optional` section, **NOT** in the default `## Workflow`
- [ ] Phase 3 documents the 4-checkpoint vetted flow (Preview → Unambiguous approval → Customer executes → Post-apply verification)
- [ ] Phase 3 has both Python and SQL paths: `apply_uc_comments.py --emit-sql` generates + a committed `apply_uc_comments.sql` artifact ships
- [ ] If the skill also writes to default Genie Code instructions, that's an `## Optional` section with the same 4-checkpoint vetting
- [ ] At least 4 evals: Expert path / Limited-or-None path / data-signal trigger fired (e.g. multi-currency) / mostly-skip path

## Evals & verification
- [ ] ≥3 eval cases added under `<source>/evals/`
- [ ] At least one eval exercises a Question-to-surface-first ambiguity (the expected behavior is "ask the user to disambiguate", not a final answer)
- [ ] Verified in a NEW Agent-mode chat: the right skill loads, no false triggers
- [ ] When asked an ambiguity-prone question, the skill surfaces the clarifying question instead of guessing
- [ ] If it mis-triggered/missed, the **description** was fixed first
