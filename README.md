# Databricks Industry Skills

A library of [Genie Code skills](https://docs.databricks.com/aws/en/genie-code/skills) for working with **industry data sources** in Databricks. Each data source (IBM Maximo, SAP PM, Oracle EAM, etc.) is a self-contained family of skills that, once installed in a Databricks workspace, lets Genie Code collaborate as a domain specialist for that system.

The skill format follows the [Agent Skills](https://agentskills.io/) standard.

## Why this exists

Out of the box, Genie Code can guess at what a `WORKORDER` table holds. With these skills installed, it knows the actual Maximo data model — the joins, the gotchas, the canonical metric formulas, the standard analytical questions, and the patterns for building pipelines / Genie Spaces / dashboards / ML features on top.

The same shape applies to every supported data source: load the family once, and Genie Code behaves like the customer has an IT implementation specialist for that system on call.

## Layout

```
databricks-industry-skills/
├── README.md            ← this file
├── _common/             ← cross-cutting skills used regardless of data source
│   └── data-exploration/
├── _template/           ← canonical skill skeleton (fork to start a new data-source family)
└── <data-source>/       ← one folder per supported data source
    ├── README.md        ← family overview, persona map, install order
    ├── <skill-1>/
    │   ├── SKILL.md
    │   └── ... supporting files
    └── ...
```

Cross-cutting skills (universal, not tied to one data source):

| Skill | Status | What it does |
|---|---|---|
| [`_common/data-exploration/`](./_common/data-exploration/) | shipped | Discover tables and run SQL queries using `databricks experimental aitools tools` |

Currently shipped data-source families:

| Family | Status | Industries primarily served |
|---|---|---|
| [`maximo/`](./maximo/) | v2 in progress | Oil & gas, utilities, mining, manufacturing, federal |

Planned future families (see `_template/`):

- `sap-pm/` — SAP Plant Maintenance
- `oracle-eam/` — Oracle Enterprise Asset Management
- `osisoft-pi/` — OSIsoft / AVEVA PI (historian)
- `salesforce/` — Salesforce CRM + Service Cloud

## Install into a Databricks workspace

Each family folder is self-contained — install only the families you need.

### Option 1: workspace-scoped install (admin, visible to all users)

```bash
# clone the repo
git clone https://github.com/guanjieshen/databricks-industry-skills.git

# install the common skills (recommended)
databricks workspace import-dir \
  databricks-industry-skills/_common \
  /Workspace/.assistant/skills/ \
  --overwrite

# install one family (e.g., maximo)
databricks workspace import-dir \
  databricks-industry-skills/maximo \
  /Workspace/.assistant/skills/ \
  --overwrite
```

### Option 2: user-scoped install (just for you)

```bash
databricks workspace import-dir \
  databricks-industry-skills/_common \
  /Workspace/Users/<your-email>/.assistant/skills/ \
  --overwrite

databricks workspace import-dir \
  databricks-industry-skills/maximo \
  /Workspace/Users/<your-email>/.assistant/skills/ \
  --overwrite
```

After install, open a **new** Genie Code chat — skills are picked up automatically when their description matches your prompt.

## Skill structure (per the Agent Skills standard)

Every skill is a folder containing at minimum a `SKILL.md` with YAML frontmatter and a body:

```yaml
---
name: <data-source>-<topic>
description: |
  Concise, specific description. Genie matches on this — include trigger
  phrases (both technical jargon and business terms).
tags:
  - data-source:ibm-maximo
  - tier:foundation             # or tier:module
  - industry:oil-and-gas        # repeatable
  - persona:analyst             # repeatable
---

# Skill body (markdown)
```

Best practices (from [agentskills.io](https://agentskills.io/home)):

- **Focused** — one task or workflow per skill
- **Clear names + descriptions** — the description is what Genie matches on
- **Example-driven** — concrete patterns Genie can reuse
- **Minimal context** — only what's needed for the task
- **Guidance vs automation separated** — markdown for intent, scripts for repeatable actions
- **Iterate** — treat skills as living workflows

## Authoring a new family

1. Copy `_template/` to `<your-data-source>/`.
2. Read `_template/README.md` and `_template/<skill-name>/SKILL.md` for the canonical shape.
3. Build the foundation tier first (overview + setup + data-engineering + data-quality), then add module skills.
4. Each skill should pass the "would Genie behave better with this loaded than without?" test before shipping.

## License

TBD.
