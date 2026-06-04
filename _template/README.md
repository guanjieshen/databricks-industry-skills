# `_template/` — How to build a new data-source family

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
├── metric_udfs.sql   ← optional: UC SQL functions (Trusted asset candidates)
└── scripts/          ← optional: automation (Python/bash for repeatable actions)
    └── ...
```

Per the [Agent Skills standard](https://agentskills.io/home):
- **Guidance** (intent, workflow, decisions) → markdown
- **Automation** (repeatable actions) → scripts
- Keep these separate.

## SKILL.md template

See [`example-skill/SKILL.md`](./example-skill/SKILL.md) for the canonical structure.

## Checklist before shipping a new family

- [ ] `README.md` clearly states what the family covers and who benefits
- [ ] All four foundation skills exist
- [ ] At least one module skill exists with a concrete user value prop
- [ ] Every skill description is specific enough that Genie matches it correctly
- [ ] Every skill passes the "would Genie behave better with this loaded?" test
- [ ] Skills follow the focused / clear / example-driven / minimal-context standard
- [ ] Automation is in `scripts/`, guidance is in markdown
