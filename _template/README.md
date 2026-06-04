# `_template/` — How to build a new data-source family

> **Load the `authoring-industry-skills` skill first** ([`_authoring/`](../_authoring/authoring-industry-skills/SKILL.md)).
> It is the repo standard — frontmatter, description-writing, tiers, progressive
> disclosure, Trusted Assets, and the new-skill checklist. This README is the
> quick mold; that skill is the full rationale.

Fork this folder to start a skill family for a new data source (e.g. `sap-pm/`, `oracle-eam/`).

```bash
cp -r _template <your-data-source>
```

Then customize:

1. **`README.md`** — family overview, persona map, install order
2. **`<source>-overview/`** — universal orientation (always-loaded foundation skill)
3. Build the rest of the foundation + module skills following the same shape

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
- [ ] Metrics ship as Trusted Asset UC functions; `-setup` registers UC comments
- [ ] ≥3 evals under `<source>/evals/`; discovery verified in a new Agent-mode chat
- [ ] Automation is in `scripts/`, guidance is in markdown
- [ ] Reviewed against [`_authoring/authoring-industry-skills/checklist.md`](../_authoring/authoring-industry-skills/checklist.md)
