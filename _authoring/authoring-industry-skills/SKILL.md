---
name: authoring-industry-skills
description: |
  Use when creating, authoring, reviewing, or refactoring a Genie Code skill or
  a new data-source family (SAP PM, Oracle EAM, OSIsoft PI, Salesforce, etc.) in
  the databricks-industry-skills repo. Defines the repo's skill standard:
  frontmatter fields, how to write descriptions Genie will actually match,
  family tiers, progressive disclosure, Trusted Assets, UC comments, and the
  Genie-Code-native conventions every skill must follow. Triggers on: "create a
  skill", "author a new skill", "new data-source family", "review this skill",
  "add a skill to the library", "is this skill discoverable", "fix the
  frontmatter", "contribute to industry-skills", "skill best practices".
metadata:
  version: "0.1.0"
---

# Authoring Industry Skills

The contributor standard for this repo. Load this before creating, reviewing, or
refactoring any skill so every new skill inherits the same discovery and quality
rules. Grounded in the [Genie Code skills spec](https://docs.databricks.com/aws/en/genie-code/skills),
[Genie Code tips](https://docs.databricks.com/aws/en/genie-code/tips), the
[Agent Skills best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices),
and the canonical [databricks/databricks-agent-skills](https://github.com/databricks/databricks-agent-skills) repo.

## The golden rule

Genie Code loads a skill **only by matching its `description`** — *"automatically
loads skills when relevant, based on your request and the skill's description."*
Nothing else in the file is used for selection. So **every discovery problem is a
description problem**, and anything not in the description is invisible until
*after* the skill is already chosen.

Corollary: skills work **only in Agent mode**, and after you edit a skill you must
**start a new chat** for the change to take effect.

## Frontmatter standard

Only `name` and `description` are required by the spec. This repo also uses
`metadata.version`, `parent` (composition), and `compatibility` (when the skill
shells out to a CLI). **Do not use `tags:` or `owners:`** — Genie ignores them and
they are dead weight. Put any persona/industry signal into the `description` text
instead, where matching happens.

Family **root** (the `<source>-overview` skill):
```yaml
---
name: <source>-overview
description: |
  <broad description — should match ANY question about this data source>
metadata:
  version: "0.1.0"
---
```

Every **other** skill in the family:
```yaml
---
name: <source>-<topic>
description: |
  <narrow, distinctive description — see rules below>
metadata:
  version: "0.1.0"
parent: <source>-overview
---
```

Add `compatibility` when the skill runs CLI commands itself:
```yaml
compatibility: Requires databricks CLI >= v0.294.0 (experimental aitools)
```

Field rules (hard limits from the spec):
- `name`: ≤64 chars, lowercase letters/numbers/hyphens only, globally unique once
  installed (all family skills flatten into one `.assistant/skills/` dir, so
  **always prefix with the data source**, e.g. `maximo-`). No `claude`/`anthropic`.
- `description`: ≤1024 chars, non-empty, **third person**, no XML tags.

## Writing a description Genie will match

This is the highest-leverage thing you do. Model every description on
`maximo-work-orders`. A good description carries all four:

1. **What it does** + **when to use it** ("Use when querying/analyzing …").
2. **The data-source name and synonyms** up front (e.g. "IBM Maximo, Maximo, EAM, CMMS").
3. **Technical identifiers** — exact table/column names the user might type
   (`WORKORDER`, `WOSTATUS`, `ASSETNUM`).
4. **Business phrasings** — how a human asks ("open work orders", "WO backlog",
   "labor hours by craft").

Then calibrate breadth by tier:
- **Root (`-overview`)**: deliberately **broad** — it should load for *any* question
  about the source, to provide baseline literacy.
- **Modules**: **narrow and distinctive** so Genie disambiguates siblings
  (work-orders vs reliability vs integrity) *at selection time*. Disambiguation
  that lives only in the body is too late — Genie has already picked.

Third person only. ✅ "Use for asset reliability metrics…" ❌ "I can help you…" / "You can use this to…".

## Family structure & tiers

```
<data-source>/
├── README.md                  ← family overview, persona map, install order
├── <source>-overview/         ← FOUNDATION root: data model + module map + universal gotchas
├── <source>-setup/            ← FOUNDATION: one-time glossary + UC comments bootstrap
├── <source>-data-engineering/ ← FOUNDATION: Bronze→Silver/Gold pipeline patterns
├── <source>-data-quality/     ← FOUNDATION: diagnostic playbook for "this number looks wrong"
├── <source>-<module>/         ← MODULES: one coherent analytical domain each
└── <source>-genie-space/      ← scaffolds a curated Genie Space from the family's assets
```

Build the **foundation tier first**, then modules. Each skill must pass the test:
*"Would Genie behave better with this loaded than without?"* If not, cut it.

Scope each skill as a **coherent unit** (like a function): not so narrow that one
task needs five skills, not so broad it won't activate precisely.

## Progressive disclosure

- Keep `SKILL.md` body **under 500 lines / ~5k tokens** — core instructions only.
- Move heavy content to sibling files (`schema.md`, `gotchas.md`, `examples.sql`,
  `views.sql`, `metric_udfs.sql`) and **tell Genie when to load each** ("read
  `gotchas.md` before writing non-trivial joins"), not a generic "see references".
- Keep references **one level deep** from SKILL.md — Genie may only partially read
  files reached through a chain of links.
- Any reference file **>100 lines gets a `## Contents` table of contents** at the
  top, so a partial read still reveals the full scope.
- **Keep the top 3–5 must-know gotchas inline in SKILL.md** — Genie may not load
  `gotchas.md` at the moment it's about to make the mistake.

## Genie-Code-native features (what makes these worth more than generic skills)

1. **UC comments are the #1 quality lever.** Genie uses Unity Catalog table/column
   comments heavily — *missing comments degrade SQL quality.* Every family's
   `-setup` skill must register standardized UC comments. Reference:
   [Genie best practices](https://docs.databricks.com/aws/en/genie/best-practices).
2. **Trusted Assets.** Ship canonical metrics as **UC SQL functions** (`metric_udfs.sql`)
   so Genie Spaces call them as *certified, governed metrics* instead of
   regenerating ad-hoc SQL. Reference: [Trusted Assets](https://docs.databricks.com/aws/en/genie/trusted-assets).
3. **A workspace glossary skill.** `-setup` generates a workspace-tier skill that
   maps the customer's business jargon to physical schema. This is the
   value-level/concept-level layer UC comments can't capture.
4. **CLI auth:** in-workspace Genie Code is already authenticated to the current
   workspace — **don't** add `--profile`. The `--profile` flag (and the
   separate-shell caveat) applies only to local runs against `~/.databrickscfg`.
5. Tell users to reference tables with **`@catalog.schema.table`** and discover with
   **`/findTables`**.
6. **MCP tools** (if a skill uses them) must be fully qualified: `ServerName:tool_name`.

## Calibrating control

Match prescriptiveness to fragility:
- **High freedom** (prose steps) when many approaches work — e.g. exploratory analysis.
- **Low freedom** (exact scripts, "run this command, don't modify it") when
  operations are fragile or order matters — e.g. writing UC comments, migrations.

Provide a **default, not a menu**. One recommended tool/pattern with a brief escape
hatch beats listing five options.

## Repo rule: writing to existing objects requires explicit user permission

**Any skill or script that modifies existing tables, data, or metadata MUST get the
user's explicit approval first — it must never write as a side effect.** This covers
UC comments (`COMMENT ON` / `ALTER TABLE … ALTER COLUMN`), and any
`ALTER`/`DROP`/`UPDATE`/`DELETE`/`MERGE`/`INSERT OVERWRITE` or schema-changing SQL on
objects the customer already owns.

- **Scripts that write must default to a no-op preview** — print the exact statements
  and write nothing — and require an explicit flag (e.g. `--apply`) to execute. The
  pattern: [`../../maximo/maximo-setup/scripts/apply_uc_comments.py`](../../maximo/maximo-setup/scripts/apply_uc_comments.py) (preview by default, `--apply` to write).
- **Skills must show the preview/diff and ask for confirmation** before the apply step.
- **Creating brand-new objects** in a scratch/demo schema is fine without this gate —
  the rule is about touching things the customer already owns.

## New-skill workflow

Copy this checklist into your working notes and check off as you go:
```
- [ ] Started from real expertise (a worked example or real schema), not generic LLM knowledge
- [ ] Folder named <source>-<topic>; SKILL.md present
- [ ] Frontmatter: name + description + metadata.version (+ parent, + compatibility if CLI)
- [ ] NO tags:/owners:
- [ ] Description: 3rd person, ≤1024 chars, source name + synonyms + table names + business phrasings
- [ ] parent: <source>-overview (unless this IS the overview)
- [ ] Body <500 lines; top gotchas inline; heavy content in sibling files with "load when…" triggers
- [ ] Reference files >100 lines have a ## Contents ToC
- [ ] Metrics shipped as Trusted Asset UC functions where applicable
- [ ] At least 3 evals added under <source>/evals/
- [ ] Any write to existing tables/data/metadata is preview-by-default + gated on explicit user approval (no side-effect writes)
- [ ] Verified discovery in a NEW Agent-mode chat (did the right skill load? any false triggers?)
```

See [checklist.md](checklist.md) for the full reviewer checklist, and copy the
mold from [`_template/`](../../_template/) (`../../_template/example-skill/SKILL.md`).

## Evals — build them before more content

Add `<source>/evals/*.json` with representative `query` → `expected_behavior`
cases. Run them in a fresh Agent-mode chat to confirm (a) the right skill loads
(discovery) and (b) the answer is correct (quality). When a skill mis-triggers or
misses, fix the **description** first. See [`maximo/evals/`](../../maximo/evals/)
for the format.

## What NOT to do

- Don't add `tags:` / `owners:` — they don't drive discovery.
- Don't bury trigger terms in the body; they belong in the `description`.
- Don't explain things Genie already knows (what a PDF is, how SQL works). Add only
  what it would otherwise get **wrong**.
- Don't duplicate a skill that exists in `databricks/databricks-agent-skills`
  (e.g. core CLI/auth/exploration) — set `parent: databricks-core` and build on it.
- **Never modify existing tables/data/metadata** (UC comments, `ALTER`/`DROP`/`UPDATE`/`DELETE`/`MERGE`, schema changes) without **explicit user permission** — preview first, gate execution behind an `--apply`-style flag, then ask. See *Repo rule* above.
- Don't include time-sensitive text ("after August 2025…") — use an "old patterns" note instead.

## References
- [checklist.md](checklist.md) — full reviewer checklist
- [`_template/`](../../_template/) — the canonical mold to fork
- Genie Code: [skills](https://docs.databricks.com/aws/en/genie-code/skills) · [tips](https://docs.databricks.com/aws/en/genie-code/tips) · [use](https://docs.databricks.com/aws/en/genie-code/use-genie-code)
- [Agent Skills best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) · [agentskills.io](https://agentskills.io/skill-creation/best-practices)
