# Reviewer checklist

Run this before merging any new or changed skill. Load
[SKILL.md](SKILL.md) for the rationale behind each item.

## Contents
- Discovery
- Frontmatter
- Body & progressive disclosure
- Genie-Code-native value
- Evals & verification

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
- [ ] Top 3–5 must-know gotchas are inline in SKILL.md (not only in gotchas.md)
- [ ] Heavy content lives in sibling files with explicit "load when …" triggers
- [ ] References are one level deep from SKILL.md
- [ ] Reference files > 100 lines have a `## Contents` ToC
- [ ] One recommended default per decision, not a menu of options
- [ ] No time-sensitive statements (use an "old patterns" note)
- [ ] Consistent terminology throughout

## Genie-Code-native value
- [ ] If the family has a `-setup` skill, it registers UC table/column comments
- [ ] Canonical metrics ship as Trusted Asset UC functions (`metric_udfs.sql`) where applicable
- [ ] CLI examples pass `--profile` (separate-shell rule)
- [ ] MCP tools, if any, are fully qualified (`ServerName:tool_name`)

## Evals & verification
- [ ] ≥3 eval cases added under `<source>/evals/`
- [ ] Verified in a NEW Agent-mode chat: the right skill loads, no false triggers
- [ ] If it mis-triggered/missed, the **description** was fixed first
