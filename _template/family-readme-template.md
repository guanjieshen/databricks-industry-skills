# `<source>/` — Family README template

Copy this file to `<source>/README.md` when forking the template for a new data-source family. It's the install-and-orient document a customer sees when they land on the family folder.

---

# `<source>/` — <Source Name> Skill Family

A library of [Genie Code skills](https://docs.databricks.com/aws/en/genie-code/skills) for working with `<Source Name>` data in Databricks. Install into a Databricks workspace; Genie Code immediately becomes a domain specialist for `<Source Name>`.

## What this family covers

One paragraph: the source's primary business domain (e.g. *"Enterprise asset management — work orders, assets, locations, labor, PMs, failure reporting."*), the typical industries that deploy it, and the kinds of questions the skills make Genie Code competent at answering.

## Who it's for

Primary customer: a **Databricks customer organization** with `<Source Name>` data ingested into their workspace. Within that:

- **IT data engineer** — has Databricks chops, lacks `<Source Name>` domain knowledge. The skills close that gap.
- **Business data engineer / SME** — has `<Source Name>` domain knowledge. Provides answers to the few clarifying questions the skills surface.

## Install

```bash
git clone https://github.com/<your-org>/<repo>.git

# user-scoped install
databricks workspace import-dir \
  <repo>/<source> \
  /Workspace/Users/<your-email>/.assistant/skills/ \
  --overwrite

# OR workspace-scoped install (admin)
databricks workspace import-dir \
  <repo>/<source> \
  /Workspace/.assistant/skills/ \
  --overwrite
```

After install, **start a new Genie Code chat in Agent mode** — skills are picked up automatically by description match.

## Required platform skills

This family references the following platform skills at [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills). Install them alongside:

- [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md) — Genie Agent creation
- [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines) — Lakeflow pipelines (for `-data-engineering`)
- [`databricks-unity-catalog`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-unity-catalog) — UC mechanics (for `-setup`)

## Family layout

```
<source>/
├── README.md                       ← this file
├── <source>-overview/              ← FOUNDATION: data-model literacy + module map
├── <source>-setup/                 ← FOUNDATION: customer-specific deployment (glossary, UC comments)
├── <source>-data-engineering/      ← FOUNDATION: Bronze→Silver/Gold pipeline patterns
├── <source>-data-quality/          ← FOUNDATION: "this number looks wrong" diagnostic playbook
├── <source>-work-orders/           ← MODULE
├── <source>-<other-module>/        ← MODULE
├── <source>-genie-agent/           ← optional: scaffolder for a curated Genie Agent
└── evals/                          ← <skill>-<scenario>.json eval cases
```

## Module map

| Skill | Triggers | Persona |
|---|---|---|
| `<source>-work-orders` | "open WO backlog", "labor by craft", "WO aging" | maintenance planner, IT DE |
| `<source>-reliability` | "MTBF", "PM compliance", "bad actors" | reliability engineer |
| `<source>-<other>` | … | … |

## Install order (recommended)

1. Install all platform skill prerequisites (see above)
2. Install this family
3. Open a new Agent-mode Genie Code chat
4. Ask: *"Set up `<Source Name>` in my workspace"* — `<source>-setup` will walk the customer-specific bootstrap workflow

## Contributing

See [`_authoring/authoring-industry-skills/`](../_authoring/authoring-industry-skills/SKILL.md) for the contributor standard before adding new skills.
