---
name: maximo-setup
description: |
  Bootstraps a customer's IBM Maximo (Maximo, EAM, CMMS) workspace for Genie —
  profiles the Maximo Silver layer first (distinct WORKORDER STATUS / WORKTYPE /
  WOCLASS, SITEID list, ASSET CLASSSTRUCTUREID, custom/extension columns, which
  modules are populated, PLUSG industry-solution presence, app-server timezone),
  then interviews a Maximo SME to confirm the gaps (which statuses count as
  "open", SYNONYMDOMAIN renamings, worktype mappings, business jargon), then
  generates a workspace-tier business-glossary skill and registers Unity Catalog
  table/column comments on the Maximo Silver tables. Runs ONCE per workspace.
  Triggers on: "set up Maximo for Genie", "profile our Maximo data", "set up our
  Maximo glossary", "configure Genie for our Maximo data", "Genie doesn't know
  our business terms", "register Maximo schema comments", "map our Maximo
  jargon".
compatibility: Requires databricks CLI >= v0.294.0 (experimental aitools)
metadata:
  version: "0.3.0"
parent: maximo-overview
---

# Maximo Setup

Bootstrap a Databricks workspace so Genie Code can answer Maximo questions using the customer's own business jargon. This is a **one-time setup** per workspace, run by the D&A team. After it completes, every other Maximo skill works more effectively.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas (SITEID composite keys, `WOCLASS` filtering, `ISTASK` dedup, WOSTATUS-vs-WORKORDER history). This skill builds on that foundation.

## Why run this first (and the value it creates)

Out of the box Genie doesn't know *your* Maximo — it guesses at table/column meaning, your "open"-status set, and your business terms, and produces confident-but-wrong SQL. This setup teaches the workspace your Maximo so **every other `maximo-*` skill** (work-orders, reliability, maintenance-cost, pm-planning, genie-space, …) answers in your vocabulary and avoids those errors. **Explain this to the user up front.** It's a **one-time** step that **pays off on its own** — you do *not* need to build a Genie Space afterward for it to be worth running.

## What it creates, and where

**The default flow creates one asset** — a workspace-tier glossary skill at `<skills-root>/<customer>-maximo-glossary/` (**flat, at the top level of the skills directory — NOT nested under `<skills-root>/maximo/`**). Genie Code's auto-discovery doesn't reliably traverse nested subfolders, so every skill — including this generated glossary — must live as a direct child of `.assistant/skills/` to be discoverable. **UC comment registration is opt-in only** (see *Optional: UC comment registration* below). UC writes go through a heavily vetted flow; setup never offers them automatically.

```
<skills-root>/<customer>-maximo-glossary/
├── SKILL.md                ← the Genie-loaded glossary skill (rendered view)
├── answers.json            ← structured source of truth (re-run input)
├── draft_profile.json      ← most-recent Phase 0 profile
├── activity_report.md      ← most-recent Module Activity Heatmap
└── history/                ← timestamped snapshots; --no-history disables
```

(`<skills-root>` = `/Workspace/.assistant/skills` for a workspace install, or `/Users/<email>/.assistant/skills` for a user install.)

**What the glossary carries**: customer business terms (e.g. "Region North", "Plant 3", "centrifugal pump") mapped to Maximo schema (SITEIDs, LOCATION hierarchy levels, CLASSSTRUCTUREIDs); customer-specific values within the universal mechanics owned by `maximo-overview` (open-status set, app-server timezone, SYNONYMDOMAIN renamings); and customer-specific customization knowledge (workflows, criticality scheme, failure-code scheme, currency, assignment model, custom columns).

**If the customer also wants UC table/column comments registered** on the Maximo Silver tables — they must explicitly request it. That's a separate, opt-in flow with multi-checkpoint vetting (the *Optional* section below). UC writes modify customer-owned tables and must never run as a side effect of the default setup.

## When to use

- "Set up Maximo for Genie / configure Genie for our Maximo data"
- "Set up our business glossary for Maximo"
- "Genie doesn't understand our customer-specific terms (regional names, business unit names, asset-class jargon)"
- "Register column comments on our Maximo tables"
- One of the first things a new customer should run after the Maximo skill family is installed

## Pre-flight

1. **Catalog/schema location**: "Which catalog/schema holds your Maximo Silver layer?" (e.g. `eam.maximo_silver`)
2. **Workspace customer name**: "What short name should we use for your organization in skill filenames?" (e.g. `acme-energy`, `northstar`). This becomes part of the generated glossary skill name.
3. **Output scope**: workspace-wide (admin) or user-scoped?
4. **Check default Genie Code instructions**: if the workspace already has default Genie Code instructions configured (Workspace Settings → Genie Code → Default instructions), **read them first**. Anything documented there — catalog/schema, base currency, timezone, open-status set, customer jargon — is already in Genie's per-turn context and should NOT be re-asked. Use them to pre-populate `draft_profile.json` and skip the corresponding interview questions. If no default instructions exist, proceed normally.

## Questions to surface first

These deployment-level ambiguities have NO defensible default and decide whether every downstream `maximo-*` skill is correct. Surface them up front (the full, profile-grounded version lives in [interview.md](interview.md)); never finalize the glossary by guessing them.

1. **Which `STATUS` values count as "open" / backlog in this shop?** There is no universal set — every deployment defines its own (plus custom statuses like `WPCOND`, `NEEDREV`). The profiler proposes; only the SME confirms. This is the single most-reused fact across the family.
2. **Has the customer renamed any status synonyms?** Status columns store the customer-renamable synonym (`SYNONYMDOMAIN.VALUE`), not the internal `MAXVALUE` Maximo logic uses — see [maximo-overview](../maximo-overview/) status-is-a-synonym-domain gotcha. If they have renamed values, the glossary must record the actual stored `VALUE` strings so generated SQL matches.
3. **What timezone is the Maximo app server configured to?** Maximo stores datetimes in the app server's local TZ (often UTC, but that's a config choice, not a guarantee) — see [maximo-overview](../maximo-overview/) datetime gotcha. This skill OWNS capturing the deployment's actual TZ, because day/week/month bucketing across sites is wrong without it. Ask; do not assume UTC.
4. **Which modules are run in Maximo vs. another system of record?** Empty/sparse indicator tables usually mean the process lives in SAP/Oracle/GIS — confirm before any skill treats those tables as authoritative.
5. **What is the migration cutover date (if any)?** Pre-cutover WOs often carry null history / placeholder statuses; the glossary should record the cutover so trend metrics can exclude the gap.

## Workflow

**Profile the data first, then interview to confirm the gaps, then generate.** Don't ask the customer what the data can already tell you.

### Phase 0 — Profile the data (automated first pass)

Profile the schema and extract the data-provable facts — distinct `WOCLASS`/`STATUS`/`WORKTYPE`, the `SITEID` list, `ASSET.CLASSSTRUCTUREID` list, custom/extension columns, which modules are populated, PLUSG presence, `SYNONYMDOMAIN` rows for status domains (to detect customer renamings — see [maximo-overview](../maximo-overview/) status gotcha), `HISTORYFLAG` distribution (to confirm closed/history records are present — see [maximo-overview](../maximo-overview/) HISTORYFLAG gotcha), and row/null stats — into a DRAFT for the interview. The app-server timezone is NOT data-provable; flag it for the interview (Question 3). **Pick the path that matches how Genie Code is attached** (both produce the same facts):

**Path A — workspace / serverless compute (can run Python):** run the profiler script. (It builds on the [`data-exploration`](../../_common/data-exploration/) mechanics.)
```bash
# In-workspace: omit --profile (ambient auth). Local runs: add --profile <name>.
python scripts/introspect_schema.py \
  --catalog <catalog> --schema <silver-schema> \
  --output draft_profile.json
```

**Path B — SQL warehouse only (e.g. Genie started from the Unity Catalog data page):** the CLI/Python may not be attached. Run the portable SQL profiler instead — [`scripts/profile_queries.sql`](scripts/profile_queries.sql) — substituting `{{catalog}}`/`{{schema}}`. It returns the same facts (tables, custom columns, distinct dimensions, module presence, PLUSG, row counts), all read-only. The SQL is the source of truth; the Python script is just a wrapper around it.

> Genie Code attached to the workspace can run Python, SQL, and shell on serverless compute; attached to a warehouse (UC data page) it is SQL-only. Don't assume Python is available — detect it, and fall back to Path B if not.

Present the findings. This turns Phase 1 from "answer 20 questions cold" into "confirm/correct what we found, and supply only what the data can't prove."

### Phase 1 — Interview (confirm the gaps)

See [interview.md](interview.md) — run it like a Maximo implementation consultant who can already see the data. Ask in **batches of 2–3**; never dump the whole list. **Batch 0 (industry & how they use Maximo today) goes first** — it scopes everything else.

The data can't prove these — they are what the interview captures:
- **Industry & usage** (Batch 0): industry / sub-segment, industry-solution add-ons (PLUSG…), which modules are actually used vs. another system of record, maturity, KPI definitions.
- **Meaning of the profiled values**: which `STATUS` count as "open"; the `WORKTYPE` → corrective / preventive / capital mapping.
- **Business jargon → schema**: site names ↔ `SITEID`, asset-class names ↔ `CLASSSTRUCTUREID`, hierarchy levels, criticality, synonyms ("PTW" → Permit to Work).
- **Custom columns**: what each detected extension field stores and who relies on it.
- **Process reality**: failure-reporting completeness, labor booking, migration history, timezone — the things that decide whether a metric is trustworthy.

Record answers as `answers.json` (shape + the `draft_profile.json` → `answers.json` mapping are in [interview.md](interview.md)).

### Phase 2 — Generate the workspace glossary skill

Once interview is complete, run. Write the glossary **as a direct child of `<skills-root>/`** (FLAT, top-level — NOT nested under `<skills-root>/maximo/` or any other subfolder):

```bash
python scripts/generate_glossary.py \
  --customer <short-name> \
  --answers <path-to-answers.json> \
  --output <skills-root>/<customer>-maximo-glossary/SKILL.md
# <skills-root> = /Workspace/.assistant/skills        (workspace install)
#              or /Users/<email>/.assistant/skills     (user install — per the scope pre-flight)
#
# CORRECT:   /Users/.../.assistant/skills/northstar-maximo-glossary/SKILL.md
# WRONG:     /Users/.../.assistant/skills/maximo/northstar-maximo-glossary/SKILL.md  ← nested; auto-discovery doesn't find it
```

The script writes a skill file using [glossary_template.md](glossary_template.md) as the structure. See [example_glossary.md](example_glossary.md) for a worked output.

> **The flat-top-level rule is non-negotiable.** Genie Code's auto-discovery does not reliably recurse into nested subfolders — a glossary placed at `<skills-root>/maximo/<customer>-maximo-glossary/` will load *only* when explicitly named or referenced from user instructions, not when its description matches a question. The other `maximo-*` family skills must also be flat at the skills root for the same reason. If you find the existing family installed under a `maximo/` parent folder, that's a discovery bug — flatten it.

> **If you can't run Python here:** write the glossary `SKILL.md` **directly** from [glossary_template.md](glossary_template.md), filling it with the confirmed interview answers — the script only renders that template. Keep the standard frontmatter (`name`, `description`, `metadata.version`, `parent: maximo-overview`) and **record every unconfirmed item as `_unknown_ — confirm with <role>`** rather than guessing. Include a short follow-up table (who confirms what) so the flagged items aren't lost. Place the file at `<skills-root>/<customer>-maximo-glossary/SKILL.md` — flat, top-level.

## When setup completes — summarize this for the user

Close with a clear recap of **what was created, where, and the value** — then present next steps as **options**, not an automatic hand-off.

**Assets created** (all co-located in the customer's glossary folder)

| Asset | Where | Value |
|---|---|---|
| `<customer>-maximo-glossary` skill (`SKILL.md`) | `<skills-root>/<customer>-maximo-glossary/SKILL.md` | Genie now answers in the customer's vocabulary; auto-loads for any Maximo question |
| `answers.json` (structured source of truth) | same folder | Re-run reads this directly. Audit/diff target |
| `draft_profile.json` | same folder | Most-recent Phase 0 profile. Used for diffing on re-run |
| `activity_report.md` | same folder | Most-recent Module Activity Heatmap (per-module verdicts + evidence) |
| `history/<timestamp>_*` snapshots | same folder | Versioned audit trail. `--no-history` disables for git-versioned customers |

**What this already unlocks (no further steps required):** every other `maximo-*` skill now resolves the customer's sites, asset classes, open-status set, worktypes, customizations, and custom columns — so backlog/reliability/cost/PM questions are correct today.

**Optional next steps — surface them at the end of setup as available options. Suggest, don't assume; never auto-execute:**
- Ask Maximo questions now (the glossary already improves answers significantly) — usually the right immediate move.
- **Optionally**, write a **skill-loading routing block** to the user's `.assistant_instructions.md` via the *Optional: write a skill-loading routing block to user instructions* section below. This is the HIGHEST-VALUE follow-up after the glossary itself — without it, Genie's auto-discovery cap may cause downstream `maximo-*` module skills to silently not load, leaving Genie answering with only the glossary + inline SQL. Run **only if the customer explicitly approves** the preview.
- **Optionally**, register UC table/column comments via the *Optional: UC comment registration* section. Run **only if the customer explicitly asks** — never offer as a default next step beyond surfacing it as an available option here.
- **Optionally**, write a customer-facts summary to default Genie Code workspace instructions via the *Optional: write a summary to default Genie Code instructions* section. Run **only if the customer explicitly approves**.
- **Optionally**, build a curated **Genie Space** with `maximo-genie-space` *if the user wants a shareable NL surface*. Offer it; don't start it automatically.
- Follow up on the flagged `_unknown_` items with the right owners (reliability / integrity / compliance / planners).

> **Surface these to the user when setup completes** — they should see "here are the optional next steps you can take" so they know the routing block and the other opt-ins exist. **Do not auto-execute any of them.** Each requires an explicit user request + the vetted preview-then-apply flow per the corresponding `## Optional` section below.

## Optional: UC comment registration (opt-in only, multi-checkpoint vetted)

**This section runs ONLY when the user explicitly requests UC comment registration.** Setup never offers it as an automatic next step. *"Set up complete — would you like to register UC comments?"* is the wrong pattern; the user must ask first ("register the comments", "apply the column metadata", or equivalent).

UC comments are Genie's #1 SQL-quality lever, but they modify customer-owned tables. Per the repo rule, writes to existing UC objects must run through a heavily vetted, multi-checkpoint flow. Four non-skippable checkpoints:

### Checkpoint 1 — Preview (writes nothing)

Generate the full COMMENT/ALTER statement list. Show the customer:
- **Scope**: count of tables + columns to be modified, scoped to ACTIVE modules from the heatmap (use `--scope all` to include DORMANT modules; default is ACTIVE-only).
- **Diff**: which tables already have comments (would be **overwritten**) vs which are fresh.
- **Statements**: the full `COMMENT ON TABLE` / `ALTER TABLE … ALTER COLUMN COMMENT` SQL.

**Python preferred** (default when Python is attached):
```bash
python scripts/apply_uc_comments.py \
  --catalog <catalog> --schema <silver-schema> \
  --comments-file scripts/maximo_comments.json \
  --emit-sql apply_uc_comments.sql
# Prints the statements; writes apply_uc_comments.sql for SQL Editor execution.
# No UC writes. No --apply means no execution.
```

**SQL fallback** (when Python isn't attached — e.g. Genie Code launched from the UC data page on a Pro warehouse): open the committed [`scripts/apply_uc_comments.sql`](scripts/apply_uc_comments.sql), bind `:catalog` / `:silver_schema`, review in SQL Editor. **The committed copy is generated from `maximo_comments.json` via the `--emit-sql` flag** — they always match.

### Checkpoint 2 — Unambiguous verbal approval

After showing the preview, ask explicitly: *"This will write {N} table comments and {M} column comments to your Unity Catalog. Do you want me to apply?"*

**Interpret only unambiguous affirmation as approval.** Words like:
- ✅ "yes apply", "go ahead and apply", "apply them", "yes, run it"

NOT these:
- ❌ "looks good", "okay", "sounds fine", "this looks right" — these are **acknowledgments of the preview**, not approval to write. Re-ask explicitly.

If the customer hesitates or says "let me think" — defer. Don't proceed.

### Checkpoint 3 — Customer executes

The customer chooses their path:

**Python path** (default, when Python is attached):
```bash
python scripts/apply_uc_comments.py \
  --catalog <catalog> --schema <silver-schema> \
  --comments-file scripts/maximo_comments.json \
  --apply --warehouse-id <id>
```

**SQL fallback** (when Python isn't attached): the customer runs `apply_uc_comments.sql` themselves in SQL Editor against the appropriate warehouse.

**The setup skill never auto-executes the apply step.** The customer triggers it themselves with explicit affirmation from Checkpoint 2.

### Checkpoint 4 — Post-apply verification

Confirm comments landed:

```sql
SELECT table_name, column_name, comment
FROM   system.information_schema.columns
WHERE  table_catalog = :catalog AND table_schema = :silver_schema
  AND  comment IS NOT NULL
ORDER  BY table_name, ordinal_position;
```

Surface any rows where comments are missing or unexpected. If a write failed silently, the customer needs to know.

### Path-selection rule (mirrors Phase 0)

- **Default**: Python via `apply_uc_comments.py`. Used whenever Python is attached.
- **Fallback**: committed `apply_uc_comments.sql` artifact. Used only when Python isn't available.
- Detect which path is available; prefer Python; never silently downgrade.

### Scoping by module activity

By default the preview includes comments for ACTIVE modules only (per the heatmap in `activity_report.md`). DORMANT modules are skipped — customers who want comprehensive coverage can pass `--scope all` to include them. Either way, the customer sees the full scope at Checkpoint 1 before approving.

The shipped `maximo_comments.json` covers the standard Maximo MBO-backed tables; extend it from the glossary for the customer's renamed/custom tables.

## Optional: write a summary to default Genie Code instructions (opt-in only, vetted)

**This section runs ONLY when the user explicitly requests it.** Default Genie Code instructions are workspace-level configuration that Genie reads at every session — distinct from skill loading. Writing to them is a customer-owned workspace-config change, so it goes through the same vetting flow as UC writes.

**Why offer it**: default instructions persist across sessions and apply even when no skill is loaded. A short summary of the customer's key facts (catalog/schema, base currency, timezone, open-status set, glossary skill name) in default instructions means Genie has those facts in *every* turn — including turns that don't match the glossary skill's description.

**The summary the customer might want written** (none of this is auto-applied):
```
Maximo (v0.3.0 setup):
- Silver data: <catalog>.<silver_schema>
- App-server timezone: <tz>
- Open-status set: <list>
- Multi-currency base: <currency>
- Glossary skill: <customer>-maximo-glossary (loaded for Maximo questions)
```

### Vetted flow (mirrors UC comments)

1. **Preview**: show the customer the proposed summary text. Show diff against existing default instructions if any.
2. **Unambiguous approval**: same rule as Phase 3 — "yes apply" or equivalent; "looks good" / "okay" is not approval.
3. **Customer applies**: customer pastes the summary into Workspace Settings → Genie Code → Default instructions themselves. **The setup skill never auto-writes workspace config.** (Databricks doesn't expose a stable API for this at the moment of writing; even if it did, the same explicit-approval rule would apply.)
4. **Post-apply verification**: in a fresh Genie Code chat, ask a question that should reference the summary (e.g. "what catalog is our Maximo data in?") and confirm the answer reflects the new default instructions.

### When NOT to write to default instructions

- When the workspace serves multiple distinct customers / business units — default instructions are workspace-wide and would conflict.
- When the customer already maintains workspace-wide Genie Code instructions for other purposes — adding Maximo-specific content might clutter.
- When the customer prefers to keep all customer-specific knowledge inside skills (so it's git-trackable in their fork) — default instructions are workspace-config, not git-tracked.

Default to "no" unless the customer is single-deployment + wants Maximo facts visible in every turn.

## Optional: write a skill-loading routing block to user instructions (opt-in only, vetted)

**This section runs ONLY when the user explicitly requests it.** Same opt-in + vetted approval pattern as UC comments and the default-instructions facts block above.

### Why this exists

Genie Code's skill auto-discovery has a soft cap on how many skills it evaluates per session — in workspaces with many installed skills, some legitimate matches are missed. The symptom is that Genie answers Maximo questions using *only* the customer's glossary skill (which loads because the description matches customer-specific terms) but skips loading `maximo-overview` + the matching `maximo-<module>` skill. The result: inline SQL that reinvents metrics, ignores the `metric_view.yaml` semantic layer, and misses universal gotchas.

The fix is a **deterministic skill-loading routing block** in the user's `.assistant_instructions.md` (or workspace default instructions, depending on scope). This tells Genie *explicitly* when to load the Maximo skills, bypassing auto-discovery for the cases that matter.

### What the block looks like

```markdown
## Skill loading — Maximo

For ANY Maximo / EAM / CMMS-related question, ALWAYS load these skills
before answering:

1. **`maximo-overview`** — universal data model + gotchas. LOAD FIRST.
2. **`<customer>-maximo-glossary`** — customer-specific vocabulary.
3. **The matching `maximo-<module>` skill** based on the question:

| Question pattern | Skill |
|---|---|
| Work-order backlog / aging / completion / labor / status history | `maximo-work-orders` |
| MTBF / MTTR / PM compliance / failure analysis | `maximo-reliability` |
| PM forecasting / craft workload / JOBPLAN | `maximo-pm-planning` |
| Inventory / stockouts / parts / reorder | `maximo-inventory` |
| Cost / spend / budget vs actual | `maximo-maintenance-cost` |
| Labor / crew / qualifications / capacity | `maximo-labor-resources` |
| Hierarchical rollup ("by region" / "by station") | `maximo-asset-hierarchy` |
| Corrosion / integrity / regulatory inspection / RBI | `maximo-integrity` |
| HSE / permit-to-work / incidents / TRIR | `maximo-hse` |
| Workflow / approvals / "stuck in approval" | `maximo-workflow-and-approvals` |
| Procurement / PO / PR / invoice | `maximo-procurement` |
| **"Build a dashboard"** | matching module + `databricks-aibi-dashboards` |
| **"Build a Genie Agent"** | `maximo-genie-space` + modules + `databricks-genie` |
| Pipeline / Bronze→Silver modeling | `maximo-data-engineering` |
| "This number looks wrong" | `maximo-data-quality` |

Skills are at: `<skills-root>/maximo-*` (flat top-level, NOT nested under
`maximo/` — Genie's auto-discovery doesn't recurse into subfolders).

For dashboard builds: do NOT short-circuit Genie Code's "don't search for
data, immediately call createAsset" pattern without first loading the
Maximo skills. The `metric_view.yaml` in each module is the governed
measure layer — call `MEASURE(<measure>)` rather than reinventing metrics
inline.
```

Substitute `<customer>-maximo-glossary` with the actual customer glossary name.

### Vetted flow (mirrors Phase 3 and the default-instructions facts block)

1. **Preview** — show the customer the proposed routing block, parameterized for their customer name + glossary skill name. Show diff against existing user instructions if any.
2. **Unambiguous approval** — same rule: "yes apply" / "go ahead and apply" / equivalent; "looks good" / "okay" is not approval.
3. **Customer applies** — customer pastes the block into their personal `.assistant_instructions.md` (Workspace Settings → Genie Code → user instructions) themselves. **The setup skill never auto-writes to user instructions.**
4. **Post-apply verification** — in a fresh Agent-mode chat, ask a Maximo question and confirm the right skills load (visible in the trace). If only the glossary loads, the routing block isn't being honored — diagnose.

### When NOT to write this routing block

- When the workspace has few installed skills (auto-discovery isn't capped, no routing needed).
- When the customer maintains their own skill-loading conventions and adding a Maximo-specific block would conflict.
- When customer-managed Genie Code instructions are kept in a different config surface (e.g. team-shared rather than user-scoped) — adapt the placement.

Default to writing the block when (a) the workspace has >20 installed skills and (b) the customer reports any Maximo question hitting only the glossary (not module skills). The auto-discovery cap is the canonical failure mode this block fixes.

## Re-running (refresh, not rebuild)

A re-run never re-interviews from scratch and never blind-overwrites. When an existing `<customer>-maximo-glossary` is found, **ask the user how they want to re-run** before doing anything else:

> "You already have a Maximo glossary from a previous setup. Do you want to:
> **(a) Delta refresh** — I pick up only what's new or changed since last time, plus anything still flagged `_unknown_`, and leave your confirmed answers as-is; or
> **(b) Revisit existing answers** — we also walk back through what was confirmed before (sites, statuses, worktypes, asset classes, custom columns…) so you can re-confirm or correct it?"

Default to **(a)** if the user has no preference. **Both** modes re-profile first and **both** merge-and-back-up (never overwrite).

**Shared steps (both modes):**
1. **Detect & load** the existing glossary as the prior state.
2. **Re-profile** (Phase 0 — cheap, read-only).
3. **Diff** the new profile vs the glossary: new `SITEID`/`STATUS`/`WORKTYPE` values, new custom columns/tables, values that disappeared, plus still-open `_unknown_`s (the Needs-confirmation table is the worklist).

**Then, per the chosen mode:**
- **(a) Delta refresh:** ask only about the diff + open unknowns — *"Since last run: new status `X`, new column `Z`; still open: `WPCOND`."* Treat already-confirmed mappings **and manual edits** as authoritative — don't re-ask them.
- **(b) Revisit existing answers:** also walk the previously-confirmed mappings and let the user re-confirm or correct each (show the current value, ask "still right?"). Surface manual edits so they're not silently dropped.

**Finish (both):**
4. **Merge, don't overwrite.** `generate_glossary.py` backs up the existing file to `SKILL.md.bak` first; merge results into the prior file (preserving manual edits + the follow-up table). Bump `metadata.version`.
5. **UC comments:** re-apply only for changed/new columns (preview → `--apply` with approval).
6. Close with a **"what changed since last run"** summary.

Trigger a re-run on: new sites/asset classes/custom columns, or when the customer confirms items from the follow-up worklist.

## What NOT to do

- Don't skip Phase 0 — asking the customer what the data already shows wastes the expert's time and misses customizations the data would reveal.
- The profile **proposes**; the human **confirms**. Never finalize a profiled candidate (open-status set, worktype mapping, custom column meaning, industry/usage profile) without the customer validating it.
- **Never offer UC comment registration as an automatic next step** when setup completes. The *Optional: UC comment registration* section runs ONLY when the user explicitly requests it.
- **Never interpret "okay" / "looks good" / "sounds fine" / "this looks right" as approval to apply UC writes.** Those are acknowledgments of the preview, not approval to write. Require unambiguous affirmation ("yes apply", "go ahead and apply", or equivalent). When in doubt, re-ask.
- **Never apply UC comments (or any change to existing tables) without explicit user approval.** Preview is the default; `--apply` runs only after the customer's verbal go-ahead at Checkpoint 2. (Repo rule: writes to existing objects require explicit permission.)
- **Never auto-write to default Genie Code workspace instructions.** Setup may *read* default instructions in Pre-flight (to avoid re-asking what's already documented) but never writes to them without the same vetted opt-in flow as UC comments. The customer pastes the summary into Workspace Settings themselves after explicit approval.
- **Don't generate the glossary skill nested under a `maximo/` parent folder.** It must be a DIRECT child of `<skills-root>/` (e.g. `/Users/<email>/.assistant/skills/<customer>-maximo-glossary/SKILL.md`). Genie Code's auto-discovery doesn't reliably recurse into nested subfolders — a glossary at `<skills-root>/maximo/<customer>-maximo-glossary/` will fail to auto-load on description match, defeating the whole point. Flat, top-level, every time.
- Don't fabricate mappings if the customer doesn't know — write `_unknown_ — needs validation from <role>` and move on.
- Don't ask the full interview at once. Batch 2–3 questions, accept the answers, then continue.
- **Don't re-teach universal mechanics in the glossary or comments.** SITEID composite keys, `WOCLASS` filtering, `ISTASK` tasks-vs-child-WOs, status-is-a-synonym-domain (`SYNONYMDOMAIN`), `HISTORYFLAG`, and app-server-timezone datetimes are owned by [maximo-overview](../maximo-overview/) — capture the customer-specific *values* (their open set, their TZ, their renamed synonyms), not the mechanic itself.
- **Don't author metric definitions here.** Capturing a KPI's stated definition during the interview is fine, but the certified formulas live with their owners: PM compliance / MTBF / MTTR / reactive-vs-proactive / schedule-compliance → [maximo-reliability](../maximo-reliability/); cost rollup / estimate-vs-actual / multi-currency → [maximo-maintenance-cost](../maximo-maintenance-cost/). Record the customer's definition in `kpis`; defer the SQL to the owner.

## Composes with

This foundation skill feeds every other `maximo-*` skill — they read the generated glossary and the UC comments it registers. Defer to the owners for domain depth:

- **[maximo-overview](../maximo-overview/)** — baseline data model, module map, and all universal gotchas (SITEID, WOCLASS, ISTASK, SYNONYMDOMAIN status resolution, HISTORYFLAG, app-server timezone). Load first.
- **[maximo-data-engineering](../maximo-data-engineering/)** — building the Silver/Gold layer this skill profiles (references the platform skill `databricks-spark-declarative-pipelines`).
- **[maximo-data-quality](../maximo-data-quality/)** — completeness diagnostics; the interview's data-integrity findings (failure-report population, labor booking) feed here.
- **[maximo-genie-space](../maximo-genie-space/)** — optional curated NL surface built *after* setup (references the platform skill `databricks-genie`).
- **UC `ALTER TABLE` / `COMMENT ON` mechanics** → platform skill [`databricks-unity-catalog`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-unity-catalog); this skill provides the Maximo-specific comment content.

## References

- [scripts/introspect_schema.py](scripts/introspect_schema.py) — Phase 0 profiler (Path A, Python/serverless); emits `draft_profile.json`
- [scripts/profile_queries.sql](scripts/profile_queries.sql) — Phase 0 profiler (Path B, portable SQL for warehouse-only / UC-data-page sessions)
- [interview.md](interview.md) — the confirm-the-gaps interview (profile-grounded, consultant-style)
- [glossary_template.md](glossary_template.md) — structure of the generated workspace skill
- [example_glossary.md](example_glossary.md) — worked example for a fictional pipeline operator
- [scripts/generate_glossary.py](scripts/generate_glossary.py) — automation that writes the glossary skill
- [scripts/apply_uc_comments.py](scripts/apply_uc_comments.py) — automation that applies UC comments
- [scripts/maximo_comments.json](scripts/maximo_comments.json) — standard Maximo MBO comment definitions
