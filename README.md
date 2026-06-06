# Databricks Industry Skills

A library of [Genie Code skills](https://docs.databricks.com/aws/en/genie-code/skills) for working with **industry data sources** in Databricks. Each data source (IBM Maximo, SAP PM, Oracle EAM, and so on) is a self-contained family of skills. Install one in a Databricks workspace and Genie Code can work that system like a domain specialist instead of guessing at it.

The skill format follows the [Agent Skills](https://agentskills.io/) standard.

## Why this exists

**The pain point.** An IT data engineer gets asked to build a work-order-optimization dashboard from their org's Maximo data, which now lives in Databricks. They don't know which tables to use, which columns matter, what `WOSTATUS` actually tracks, or how a "WO backlog" maps to the dashboard's KPIs. So they Slack the Maximo IT specialist, book a call, wait, ask a follow-up the next day, wait again. By the time they ship, the calendar has eaten more time than the build did.

**What this repo changes.** Once a customer installs these skills into their workspace, Genie Code carries the domain knowledge that used to live only in the Maximo IT specialist's head: the tables, joins, gotchas, canonical metric formulas, customer-specific conventions, and the questions that genuinely *require* the business's input. The IT data engineer loads the skill, gets answers right away, and only goes back to the business for the few clarifications the skill says to batch (like "which status set counts as 'open' in your deployment?"). The time from business question to production data product collapses.

## Who this is for

The primary customer is a **Databricks customer organization** installing the family into their own workspace. Within that, two personas:

| Persona | Has | Lacks | What the skills do |
|---|---|---|---|
| **IT data engineer** | Deep Databricks / data engineering chops | Domain knowledge of the business app (Maximo, SAP, etc.) | Closes the **domain gap**: schema, joins, gotchas, canonical metrics, customer conventions, gold queries |
| **Business data engineer** | Deep business-app domain knowledge | Limited data engineering chops | Closes the **platform gap** (Genie Code already does this): natural-language questions to pipelines, Genie Spaces, dashboards |

Genie Code closes the platform gap natively. This repo closes the domain gap. **Together they let the two personas build data products without the round-trip they used to need to consult a Maximo IT SME, or each other.**

## Success metric

Time from "business user asks for a data product" to "production data product is shipped." Anything in the skills that's correct but slow to consume (long preambles, deep cross-references, generic Databricks tutorial content) actively defeats the value prop. Length and depth aren't free. They're a tax on the IT data engineer's clock.

## North star

> Every skill in this repo fills source/domain knowledge gaps that **Databricks Genie Code** can't infer from Unity Catalog + lineage alone. We don't re-teach what Genie Code already does well, including what's already covered by the canonical platform skills at [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills).

**The target agent harness is Databricks Genie Code specifically.** Skills follow the open Agent Skills format on disk, but the content is written for Genie Code's capabilities, integrations, and deployment model.

Be precise about which Databricks "Genie" is which:
- **Genie Code** = the **agent harness** (an agentic data-work tool that builds pipelines, trains ML models, ships dashboards, scaffolds Genie Spaces, runs background agents). *This is what loads and uses these skills.*
- **Genie Spaces** = a **data product** Genie Code can create, a natural-language text-to-SQL interface to UC data. A `<source>-genie-space` skill helps Genie Code stand one up well.

**Write content that's feature-agnostic within Genie Code.** Anchor to Genie Code's durable behaviors (deep UC integration, agentic data work, skill-driven extensibility, governance enforcement), not to today's specific feature mechanics (Spaces API shape, Trusted Assets registration UI, MCP integrations, background-agent specifics). Features evolve. The harness's core role doesn't.

- ❌ Don't re-teach Lakeflow pipelines, ML training, dashboards, UC mechanics, lineage, MLflow, model serving. Those live in the [canonical platform skills](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills). Reference them, don't duplicate.
- ✅ Do author content on source-specific schema semantics, domain gotchas, customer-deployment specifics, industry-canonical metric formulas (Trusted UDFs), SME-clarifying questions, business-jargon to physical-schema mapping, and source-specific composition patterns.

### Operationalized via three commitments

1. **Layer placement.** Skills are the middle layer in a three-layer stack:

   | Layer | Knows | Where it lives |
   |---|---|---|
   | **Platform** (bottom) | How to build/operate on Databricks | [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills): `databricks-genie`, `databricks-spark-declarative-pipelines`, `databricks-unity-catalog`, etc. |
   | **Source / domain-data** (middle, **this repo**) | What the data *means* once landed | `databricks-industry-skills/` |
   | **Business process** (top) | How to answer a business question end-to-end | Wherever the customer's business-process skills live. Typical hosts: [`databricks-solutions/ai-dev-kit`](https://github.com/databricks-solutions/ai-dev-kit), [`databricks/databricks-agent-skills`](https://github.com/databricks/databricks-agent-skills/tree/main/skills), or a customer's internal skills repo |

   Top-layer composes middle-layer composes platform-layer. Outcome-driven requests ("reduce contractor spend") are top-layer and live elsewhere.

2. **Two jobs per middle-layer skill.** The skill must do both:
   - **SME-substitute**: encode what an SME would *do* (schemas, gotchas, gold queries, Trusted UDFs)
   - **SME-question-surfacer**: encode what an SME would *ask before answering* (a required `## Questions to surface first` section)

   The second job is the one most easily under-built. By definition the non-expert doesn't know what to ask.

3. **Foundation + module tiers.** Every source family ships `-overview`, `-setup`, `-data-engineering`, `-data-quality` (foundation) plus one module per analytical domain. The `-setup` skill is especially load-bearing: business applications are customizable per organization, so it encodes the **customer's specific deployment** (workspace glossary, UC comments content, conventions). UC comments and skill content are split on purpose. Facts that fit cleanly in a UC column comment get registered there (Genie reads them directly), and everything else lives in the skill body and can graduate to UC comments later.

Full framework + checklists in [`_authoring/authoring-industry-skills/`](./_authoring/authoring-industry-skills/SKILL.md).

## Layout

```
databricks-industry-skills/
├── README.md            ← this file
├── _authoring/          ← the repo standard, as a skill (load before building/reviewing skills)
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

> **Contributing?** Load the [`authoring-industry-skills`](./_authoring/authoring-industry-skills/SKILL.md) skill first. It defines the frontmatter standard, how to write descriptions Genie will match, the tiers, progressive disclosure, Trusted Assets, and the review checklist every skill in this repo follows.

Cross-cutting skills (universal, not tied to one data source):

| Skill | Status | What it does |
|---|---|---|
| [`_common/data-exploration/`](./_common/data-exploration/) | shipped | Discover tables and run SQL queries using `databricks experimental aitools tools` |

Currently shipped data-source families:

| Family | Status | Industries primarily served |
|---|---|---|
| [`maximo/`](./maximo/) | Beta | Oil & gas, utilities, mining, manufacturing, federal |
| [`pods/`](./pods/) | WIP, not ready for use | Midstream oil & gas (pipeline integrity) |
| [`wellview/`](./wellview/) | WIP, not ready for use | Upstream oil & gas (drilling, completions, workovers, daily ops/cost) |

Only `maximo/` is at Beta and ready to try. `pods/` and `wellview/` are works in progress, so don't rely on them yet.

Planned future families (see `_template/`):

- `sap-pm/`: SAP Plant Maintenance
- `oracle-eam/`: Oracle Enterprise Asset Management
- `osisoft-pi/`: OSIsoft / AVEVA PI (historian)
- `salesforce/`: Salesforce CRM + Service Cloud

## Install into a Databricks workspace

Each family folder is self-contained, so install only the ones you need.

### Option 1 (recommended): the installer notebook

Import [`install_industry_skills.py`](./install_industry_skills.py) into your workspace
(**Workspace → Import → File**) and run it. No clone or CLI setup needed. It pulls the skills
straight from GitHub. Pick the data source(s) you want in the `FAMILIES` widget (e.g. `maximo`)
and the `SCOPE` (`user` or `workspace`), and it installs **all skills in each selected family**.
Nothing installs until you select a family.

### Option 2: workspace-scoped install via CLI (admin, visible to all users)

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

### Option 3: user-scoped install via CLI (just for you)

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

After install, open a **new** Genie Code chat. Skills get picked up automatically when their description matches your prompt.

## Skill structure

Genie Code loads a skill **only by matching its `description`**, and only in **Agent mode**. After you edit a skill, start a **new chat** for the change to take effect.

Every skill is a folder with a `SKILL.md`. The only required frontmatter is `name` and `description`. This repo also uses `metadata.version`, `parent` (composition), and `compatibility` (when the skill runs a CLI). Don't use `tags:` or `owners:`, since Genie ignores them. Put any persona or industry signal into the `description` instead.

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

- **Focused**: one coherent unit of work per skill
- **Discoverable**: the description carries source name + synonyms + table names + business phrasings
- **Layered**: modules set `parent: <source>-overview`, and the body opens with a `> **FIRST:** load <source>-overview` line
- **Progressive disclosure**: body under 500 lines, heavy content in sibling files with "load when…" triggers, and ref files over 100 lines get a `## Contents` ToC
- **Genie-native**: register UC comments (`-setup`) and ship metrics as Trusted Asset UC functions
- **Tested**: add evals under `<source>/evals/`, then verify discovery in a new Agent-mode chat

## Authoring a new family

1. **Load the [`authoring-industry-skills`](./_authoring/authoring-industry-skills/SKILL.md) skill.** It's the standard.
2. Copy `_template/` to `<your-data-source>/` and read `_template/README.md`.
3. Build the foundation tier first (overview + setup + data-engineering + data-quality), then the modules, then a `<source>-genie-space` scaffolder.
4. Review against [`_authoring/authoring-industry-skills/checklist.md`](./_authoring/authoring-industry-skills/checklist.md) before shipping.

## License

TBD. I'll set a license before sharing the repo publicly.
