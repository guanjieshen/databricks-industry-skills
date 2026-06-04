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
├── _authoring/          ← the repo standard, as a skill — load before building/reviewing skills
│   └── authoring-industry-skills/
├── _common/             ← cross-cutting skills used regardless of data source
│   └── data-exploration/
├── _template/           ← canonical skill skeleton (fork to start a new data-source family)
└── <data-source>/       ← one folder per supported data source
    ├── README.md        ← family overview, persona map, install order
    ├── <source>-overview/   ← foundation root (every other skill sets parent: <source>-overview)
    ├── <skill>/
    │   ├── SKILL.md
    │   └── ... supporting files
    └── evals/           ← query → expected_behavior cases (discovery + quality)
```

> **Contributing?** Load the [`authoring-industry-skills`](./_authoring/authoring-industry-skills/SKILL.md)
> skill first — it defines the frontmatter standard, how to write descriptions
> Genie will match, tiers, progressive disclosure, Trusted Assets, and the
> review checklist that every skill in this repo follows.

Cross-cutting skills (universal, not tied to one data source):

| Skill | Status | What it does |
|---|---|---|
| [`_common/data-exploration/`](./_common/data-exploration/) | shipped | Discover tables and run SQL queries using `databricks experimental aitools tools` |

Currently shipped data-source families:

| Family | Status | Industries primarily served |
|---|---|---|
| [`maximo/`](./maximo/) | v2 in progress | Oil & gas, utilities, mining, manufacturing, federal |
| [`pods/`](./pods/) | v1 (foundation + ILI flagship) | Midstream oil & gas (pipeline integrity) |

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

## Skill structure

Genie Code loads a skill **only by matching its `description`** — in **Agent mode**
only. After you edit a skill, start a **new chat** for the change to take effect.

Every skill is a folder with a `SKILL.md`. Required frontmatter is just `name` +
`description`; this repo also uses `metadata.version`, `parent` (composition), and
`compatibility` (when the skill runs a CLI). **Do not use `tags:`/`owners:`** —
Genie ignores them; put persona/industry signal into the `description` instead.

```yaml
---
name: <data-source>-<topic>        # ≤64 chars, lowercase/hyphens, source-prefixed (globally unique)
description: |
  Third person, ≤1024 chars. Lead with the data-source name + synonyms, then
  technical identifiers (table/column names) AND business phrasings. State both
  what it does and when to use it. (This text is the ONLY thing Genie matches on.)
metadata:
  version: "0.1.0"
parent: <data-source>-overview     # omit only in the overview itself
# compatibility: Requires databricks CLI >= v0.294.0 (experimental aitools)  # only if it runs the CLI
---

# Skill body (markdown)
```

Best practices (full rationale in the [`authoring-industry-skills`](./_authoring/authoring-industry-skills/SKILL.md) skill):

- **Focused** — one coherent unit of work per skill
- **Discoverable** — the description carries source name + synonyms + table names + business phrasings
- **Layered** — modules set `parent: <source>-overview`; body opens with a `> **FIRST:** load <source>-overview` line
- **Progressive disclosure** — body < 500 lines; heavy content in sibling files with "load when…" triggers; ref files > 100 lines get a `## Contents` ToC
- **Genie-native** — register UC comments (`-setup`) and ship metrics as Trusted Asset UC functions
- **Tested** — add evals under `<source>/evals/`; verify discovery in a new Agent-mode chat

## Authoring a new family

1. **Load the [`authoring-industry-skills`](./_authoring/authoring-industry-skills/SKILL.md) skill** — it's the standard.
2. Copy `_template/` to `<your-data-source>/` and read `_template/README.md`.
3. Build the foundation tier first (overview + setup + data-engineering + data-quality), then modules, then a `<source>-genie-space` scaffolder.
4. Review against [`_authoring/authoring-industry-skills/checklist.md`](./_authoring/authoring-industry-skills/checklist.md) before shipping.

## License

TBD — set a license before sharing the repo publicly.
