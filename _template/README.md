# `_template/` — How to build a new data-source family

> **Load the [`authoring-industry-skills`](../_authoring/authoring-industry-skills/SKILL.md) skill first.**
> It is the repo standard — full rationale for everything below. This README is the quick mold.

## Before you fork: the north star

> Every skill in this repo fills source/domain knowledge gaps that **Databricks Genie Code** (the agent harness) cannot infer from Unity Catalog + lineage alone. We never re-teach what Genie Code already does well — including what's already taught by the canonical platform skills at [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills).

**The target agent harness is Databricks Genie Code specifically.** Skills follow the open Agent Skills format on disk, but content is written for Genie Code's capabilities, integrations, and deployment model.

Be precise about which "Genie" is which:
- **Genie Code** = the **agent harness** (agentic data-work tool that loads Agent Skills, builds pipelines, trains ML, scaffolds Genie Agents). What loads these skills.
- **Genie Agents** = a **data product** Genie Code creates (formerly "Genie Spaces") — curated no-code agents end users query in natural language.

**Within Genie Code, write feature-agnostic content** — anchored to durable behaviors (deep UC integration, agentic data work, skill-driven extensibility, governance enforcement), not to today's API/UI mechanics. Features evolve (e.g. Genie Spaces → Genie Agents rebrand); the harness's core role doesn't.

- ❌ **Out of scope**: how to build a Lakeflow pipeline, train an ML model, construct a dashboard, traverse lineage, use MLflow, configure access controls, or anything else Genie Code does natively. Reference the canonical platform skill at [`ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills) — don't duplicate. Also out of scope: anything tied to a current feature's API/UI shape.
- ✅ **In scope**: source-specific schema semantics, domain gotchas, **customer-specific deployment knowledge** (what `-setup` encodes), canonical metric formulas (Trusted UDFs), SME-clarifying questions, business-jargon → physical-schema mapping, source-specific composition patterns.

### Operationalized via three commitments

1. **Layer placement** — you're building middle-layer skills. Platform mechanics live at [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills); business-process / outcome skills live in customer-specific or framework repos. This repo sits between them.
2. **Two jobs per middle-layer skill** — every non-foundation skill carries both:
   - **SME-substitute** (primary value) — schema/gotchas/views/Trusted UDFs so a non-expert produces correct work without consulting the source-app SME
   - **SME-question-surfacer** (correctness guardrail) — a required `## Questions to surface first` section with ≥2 SME-reflex clarifying questions (definitions, thresholds, conventions) the IT DE batches into a single round of consultation with the business DE
3. **Foundation + module tiers** — every family ships `-overview`, `-setup`, `-data-engineering`, `-data-quality` plus one module per analytical domain, optionally a `-genie-agent` scaffolder. **`-setup` is split-responsibility**: customer-specific facts that fit cleanly in a UC comment go into `<source>_comments.json` (Genie reads them directly); the rest lives in skill content and can graduate to UC comments later.

Spot-check while authoring: would Genie Code, seeing this source's data for the first time in this organization's specific deployment, learn something *only* an SME would know? If yes — keep it. If you're explaining a Databricks primitive or a current Genie Code feature mechanic — link to the canonical platform skill and cut it.

## Fork the template

```bash
cp -r _template <your-data-source>
```

Then customize:

1. **`<your-data-source>/README.md`** — copy from [`family-readme-template.md`](./family-readme-template.md). Family overview, persona map, install order, required platform skills.
2. **Rename every `example-*/` skill folder** to `<source>-*` (e.g. `example-work-orders` → `maximo-work-orders` if you renamed `_template` to `maximo`).
3. **Fill in the frontmatter `description` of every SKILL.md** — this is the matcher; Genie Code selects skills ONLY by matching it. See [`../_authoring/authoring-industry-skills/SKILL.md`](../_authoring/authoring-industry-skills/SKILL.md) §Writing the description.

## Template contents — one skill folder per shape

The template ships **one example per skill shape** so an author building a new family sees every pattern they'll need:

| Folder | Shape | What it demonstrates |
|---|---|---|
| [`example-overview/`](./example-overview/) | Foundation root | Broad description, no FIRST-load preamble, data-model anchor + module map, universal gotchas |
| [`example-setup/`](./example-setup/) | Foundation | Customer-deployment encoding — workspace glossary + UC comments (preview-then-apply gated on user approval). `scripts/`, `example_comments.json`, interview playbook |
| [`example-data-engineering/`](./example-data-engineering/) | Foundation | Source-specific pipeline patterns; defers SDP mechanics to [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines) |
| [`example-data-quality/`](./example-data-quality/) | Foundation | "This number looks wrong" diagnostic playbook — ordered probes |
| [`example-module/`](./example-module/) | Module | The 8-section canonical shape every analytical module follows |
| [`example-genie-agent/`](./example-genie-agent/) | Optional | Genie Agent curation; defers creation mechanics to [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md) |
| [`evals/`](./evals/) | — | One sample eval JSON showing the `query` → `expected_behavior` shape |
| [`family-readme-template.md`](./family-readme-template.md) | — | Copy to `<source>/README.md` |

## Family layout (after rename)

```
<your-data-source>/
├── README.md                         ← family overview (from family-readme-template.md)
├── <source>-overview/                ← FOUNDATION root
├── <source>-setup/                   ← FOUNDATION
├── <source>-data-engineering/        ← FOUNDATION
├── <source>-data-quality/            ← FOUNDATION
├── <source>-<module-1>/              ← MODULE (clone example-module/ per analytical domain)
├── <source>-<module-2>/              ← MODULE
├── <source>-genie-agent/             ← optional scaffolder
└── evals/                            ← <skill>-<scenario>.json cases
```

## Per-skill folder convention

Every skill is a folder containing at minimum a `SKILL.md`. Supporting files load on demand.

```
<skill-name>/
├── SKILL.md          ← required: frontmatter + the 8 required sections (modules)
├── schema.md         ← optional: data-model reference
├── gotchas.md        ← optional: error-prone joins, common mistakes
├── examples.sql      ← optional: parameterized gold-standard queries
├── views.sql         ← optional: DDL for reusable Gold views
├── metric_udfs.sql   ← optional: Trusted Asset UC SQL functions
└── scripts/          ← optional: automation (Python/bash)
```

Per the [Agent Skills standard](https://agentskills.io/home): **guidance** (intent, workflow, decisions) → markdown; **automation** (repeatable actions) → scripts. Keep these separate.

### Frontmatter standard

Required by the spec: `name`, `description`. This repo also uses `metadata.version`, `parent`, and `compatibility` (when the skill runs a CLI). **NEVER use `tags:` or `owners:`** — Genie ignores them; put persona/industry signal into the `description` instead.

```yaml
---
name: <source>-<topic>            # ≤64 chars, lowercase/numbers/hyphens, source-prefixed
description: |
  Third person, ≤1024 chars. Lead with source name + synonyms, then technical
  identifiers (table/column names) AND business phrasings. State what it does
  and when to use it. THIS IS THE MATCHER — Genie selects skills only by
  matching this text.
metadata:
  version: "0.1.0"
parent: <source>-overview         # omit only in the overview itself
# compatibility: Requires databricks CLI >= v0.294.0   # only if the skill runs the CLI
---
```

**Do NOT chain `parent:` across layers.** `parent:` is for the family's own `<source>-overview`. Reference platform skills via body links, not the frontmatter.

## Checklist before shipping a new family

- [ ] `README.md` clearly states what the family covers and who benefits (use [`family-readme-template.md`](./family-readme-template.md))
- [ ] All four foundation skills exist (`-overview`, `-setup`, `-data-engineering`, `-data-quality`)
- [ ] At least one module skill exists with a concrete user value prop
- [ ] Every description leads with source name + synonyms and includes table names AND business phrasings
- [ ] Root `-overview` description is broad; module descriptions are narrow + distinctive
- [ ] Frontmatter: no `tags:`/`owners:`; `parent:` set (no cross-layer chains); `metadata.version` present
- [ ] Body < 500 lines; top gotchas inline; reference files > 100 lines have a `## Contents` ToC
- [ ] **Every non-foundation module skill has a `## Questions to surface first` section with ≥2 SME-clarifying questions**
- [ ] **`## Pre-flight` and `## Questions to surface first` are distinct sections** (session setup vs per-request ambiguity)
- [ ] Platform mechanics referenced via body link to [`ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills); never duplicated
- [ ] Metrics ship as Trusted Asset UC functions; `-setup` registers UC comments
- [ ] ≥3 evals under `<source>/evals/`; discovery verified in a new Agent-mode chat; at least one eval exercises a Question-to-surface ambiguity
- [ ] Automation is in `scripts/`, guidance is in markdown
- [ ] Any write to existing tables/data/metadata is preview-by-default + gated on explicit user approval
- [ ] Reviewed against [`../_authoring/authoring-industry-skills/checklist.md`](../_authoring/authoring-industry-skills/checklist.md)

## When a skill is universal (not data-source-specific)

If a skill is cross-cutting — useful regardless of which data source the user is working with — it belongs in **`_common/`** at the repo root, not in a data-source family. Example: `_common/data-exploration/`.

Rule of thumb: if the skill never references one specific data source's tables or jargon, it's a `_common/` skill. If it teaches Genie about a particular vendor's schema, it belongs in that vendor's family.

## Module-tier examples

- Maximo: `maximo-work-orders`, `maximo-reliability`, `maximo-integrity`, `maximo-asset-hierarchy`, `maximo-labor-resources`
- SAP PM: `sap-pm-notifications`, `sap-pm-equipment`, `sap-pm-maintenance-plans`
- Salesforce: `salesforce-accounts`, `salesforce-cases`, `salesforce-opportunities`

A new module skill earns its slot if (a) it serves a distinct persona / sub-workflow not already well-served, and (b) without it, Genie writes provably-wrong queries or misses canonical formulas.
