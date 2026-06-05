# `_template/` — How to build a new data-source family

> **Load the `authoring-industry-skills` skill first** ([`_authoring/`](../_authoring/authoring-industry-skills/SKILL.md)).
> It is the repo standard — frontmatter, description-writing, tiers, progressive
> disclosure, Trusted Assets, and the new-skill checklist. This README is the
> quick mold; that skill is the full rationale.

## Before you fork: the north star

> Every skill in this repo fills source/domain knowledge gaps that **Databricks Genie Code** cannot infer from Unity Catalog + lineage alone. We never re-teach what Genie Code already does well — including what's taught by the canonical platform skills at [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills).

**The target agent harness is Databricks Genie Code specifically.** Skills follow the open Agent Skills format on disk, but the content is written for Genie Code's capabilities, integrations, and deployment model.

Be precise about which "Genie" is which:
- **Genie Code** = the **agent harness** (agentic data-work tool — builds pipelines, trains ML, ships dashboards, scaffolds Genie Spaces). What loads these skills.
- **Genie Spaces** = a **data product** Genie Code creates — a natural-language text-to-SQL interface to UC data. A `<source>-genie-space` skill helps Genie Code stand one up well.

**Within Genie Code, write feature-agnostic content** — anchored to Genie Code's durable behaviors (deep UC integration, agentic data work, skill-driven extensibility), not to today's specific feature mechanics (Spaces API/UI shape, Trusted Assets registration, MCP integrations, background-agent specifics). Features evolve; the harness's core role endures.

- ❌ Out of scope: how to build a Lakeflow pipeline, train an ML model, construct a dashboard, traverse lineage, use MLflow, configure access controls, or anything else Genie Code does natively. Reference [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills) for platform mechanics. Also out of scope: anything tied to a specific Genie Code feature's current API/UI shape.
- ✅ In scope: source-specific schema semantics, domain gotchas, **customer-specific deployment knowledge** (what `-setup` encodes), canonical metric formulas (Trusted UDFs), SME-clarifying questions, business-jargon → physical-schema mapping, source-specific composition patterns.

### Operationalized via three commitments

1. **Layer placement** — you're building middle-layer skills. Platform mechanics live at [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills); business-process / outcome skills live in customer-specific or framework repos ([`ai-dev-kit`](https://github.com/databricks-solutions/ai-dev-kit), [`databricks-agent-skills`](https://github.com/databricks/databricks-agent-skills/tree/main/skills), or internal). This repo sits between them.
2. **Two jobs per middle-layer skill** — every non-foundation skill must carry both:
   - **SME-substitute** — schema/gotchas/views/Trusted UDFs so a non-expert produces correct work
   - **SME-question-surfacer** — a required `## Questions to surface first` section listing ≥2 SME-reflex clarifying questions (definitions, thresholds, conventions) the user must disambiguate *before* the skill answers
3. **Foundation + module tiers** — every family ships `-overview`, `-setup`, `-data-engineering`, `-data-quality` plus one module per analytical domain. **`-setup` is split-responsibility**: customer-specific facts that fit cleanly in a UC comment go into `<source>_comments.json` (Genie reads them directly); the rest lives in skill content and can graduate to UC comments later as the surface area grows.

If you cannot list ≥2 SME-clarifying questions for a module skill you're scoping, you are almost certainly missing domain content — the questions are how you surface "what they don't know they don't know." Full framework + examples in [`_authoring/authoring-industry-skills/SKILL.md`](../_authoring/authoring-industry-skills/SKILL.md).

Spot-check while authoring: would Genie Code, seeing this source's data for the first time in this organization's specific deployment, learn something *only* an SME would know? If yes — keep it. If you're explaining a Databricks primitive or a current Genie Code feature mechanic — link to the canonical platform skill and cut it from yours.

## Fork the template

Fork this folder to start a skill family for a new data source (e.g. `sap-pm/`, `oracle-eam/`).

```bash
cp -r _template <your-data-source>
```

Then customize:

1. **`README.md`** — family overview, persona map, install order
2. **`<source>-overview/`** — universal orientation (always-loaded foundation skill)
3. Build the rest of the foundation + module skills following the same shape — each module skill ships both SME-substitute content (schema/gotchas/views/UDFs) and an inline `## Questions to surface first` section

## Family layout convention

Every data-source family should follow this layout:

```
<your-data-source>/
├── README.md                         ← family overview
├── <source>-overview/                ← FOUNDATION: orientation (data model, gotchas, module map)
├── <source>-setup/                   ← FOUNDATION: customer-specific setup (glossary, UC comments)
├── <source>-data-engineering/        ← FOUNDATION: bronze→silver→gold modeling
├── <source>-data-quality/            ← FOUNDATION: data quality / debug playbook
├── <source>-<module-1>/              ← MODULE: focused workflow for one domain
├── <source>-<module-2>/              ← MODULE: ...
└── ...
```

### Foundation tier (4 universal skills, every family ships these)

| Skill | Purpose | Loaded for |
|---|---|---|
| `*-overview` | Orient Genie on the data model + universal gotchas | Any question mentioning the data source |
| `*-setup` | Customer-specific setup (business glossary, UC comments) | One-time setup per workspace |
| `*-data-engineering` | Silver/Gold modeling patterns | Data engineering / pipeline questions |
| `*-data-quality` | Diagnostic playbook for data quality issues | "This number looks wrong" investigations |

### When a skill is universal (not data-source-specific)

If a skill is cross-cutting — useful regardless of which data source the user is working with — it belongs in **`_common/`** at the repo root, **not** in a data-source family. Example: `_common/data-exploration/` covers `databricks experimental aitools tools` for any table in any catalog.

Rule of thumb: if the skill never references one specific data source's tables or jargon, it's a `_common/` skill. If it teaches Genie about a particular vendor's schema, it belongs in that vendor's family.

### Module tier (one per Maximo module / SAP transaction / Salesforce object / etc.)

Modules are the domain-specific specializations. Examples:
- Maximo: `maximo-work-orders`, `maximo-reliability`, `maximo-integrity`, `maximo-hse`
- SAP PM: `sap-pm-notifications`, `sap-pm-equipment`, `sap-pm-maintenance-plans`
- Salesforce: `salesforce-accounts`, `salesforce-cases`, `salesforce-opportunities`

A new module skill earns its slot if:
- It serves a distinct persona (or sub-workflow) not already well-served
- Without it, Genie writes provably-wrong queries or misses canonical formulas

## Per-skill folder convention

Every skill is a folder containing at minimum a `SKILL.md`. Supporting files are loaded on demand by Genie.

```
<skill-name>/
├── SKILL.md          ← required: frontmatter + guidance body
├── schema.md         ← optional: data model reference (loaded when Genie needs schema detail)
├── gotchas.md        ← optional: error-prone joins, edge cases, common mistakes
├── examples.sql      ← optional: parameterized gold-standard queries
├── views.sql         ← optional: DDL for reusable Delta views
├── metric_udfs.sql   ← optional: Trusted Asset UC SQL functions (certified metrics Genie Spaces call)
└── scripts/          ← optional: automation (Python/bash for repeatable actions)
    └── ...
```

Per the [Agent Skills standard](https://agentskills.io/home):
- **Guidance** (intent, workflow, decisions) → markdown
- **Automation** (repeatable actions) → scripts
- Keep these separate.

## SKILL.md template

See [`example-skill/SKILL.md`](./example-skill/SKILL.md) for the canonical structure and its sibling reference files.

### Frontmatter standard

Only `name` + `description` are required by the spec; this repo also uses
`metadata.version`, `parent`, and `compatibility`. **Never use `tags:` or
`owners:`** — Genie ignores them; put persona/industry signal into the
`description` instead. Genie selects skills **only by matching the description**.

```yaml
---
name: <source>-<topic>            # ≤64 chars, lowercase/numbers/hyphens, source-prefixed (globally unique)
description: |
  Third person, ≤1024 chars. Lead with the data-source name + synonyms, then
  technical identifiers (table/column names) AND business phrasings. State what
  it does and when to use it.
metadata:
  version: "0.1.0"
parent: <source>-overview          # omit only in the overview itself; use databricks-core if building on core
# compatibility: Requires databricks CLI >= v0.294.0 (experimental aitools)  # only if the skill runs the CLI
---
```

## Checklist before shipping a new family

- [ ] `README.md` clearly states what the family covers and who benefits
- [ ] All four foundation skills exist (+ a `<source>-genie-space` scaffolder where useful)
- [ ] At least one module skill exists with a concrete user value prop
- [ ] Frontmatter follows the standard above — no `tags:`/`owners:`, `parent:` set, `metadata.version` present
- [ ] Every description leads with source name + synonyms and includes table names AND business phrasings
- [ ] Root `-overview` description is broad; module descriptions are narrow & distinctive
- [ ] Body < 500 lines; top gotchas inline; reference files > 100 lines have a `## Contents` ToC
- [ ] **Every non-foundation module skill has a `## Questions to surface first` section with ≥2 SME-clarifying questions** (the question-surfacing job; see *North star* above)
- [ ] **`## Pre-flight` and `## Questions to surface first` are distinct sections** (session setup vs per-request ambiguity)
- [ ] Metrics ship as Trusted Asset UC functions; `-setup` registers UC comments
- [ ] ≥3 evals under `<source>/evals/`; discovery verified in a new Agent-mode chat; at least one eval exercises a Question-to-surface ambiguity
- [ ] Automation is in `scripts/`, guidance is in markdown
- [ ] Reviewed against [`_authoring/authoring-industry-skills/checklist.md`](../_authoring/authoring-industry-skills/checklist.md)
