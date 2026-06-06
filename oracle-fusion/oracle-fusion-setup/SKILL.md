---
name: oracle-fusion-setup
description: |
  Bootstraps a customer's Oracle Fusion Cloud ERP (Fusion ERP / Fusion
  Financials / Fusion SCM / Oracle Cloud ERP) workspace for Genie — profiles
  the Fusion Silver layer first (which modules are populated, distinct ledgers /
  currencies, the COA structure and SEGMENT1..30 usage, balancing-segment
  values, business units, period calendar, custom/DFF columns, and the landing
  pattern that decides physical names), then interviews a Fusion SME to confirm
  the gaps (which segment means company / cost center / natural account, value-set
  meanings, ledger and BU scope, business jargon), then generates a workspace-tier
  business-glossary skill — INCLUDING the physical→canonical table/column mapping
  for the customer's landing pattern (BICC PVO / FDI / base tables) — and registers
  Unity Catalog table/column comments (preview-then-apply). Runs ONCE per workspace.
  Triggers on: "set up Oracle Fusion for Genie", "profile our Fusion data", "map our
  COA segments", "which segment is cost center", "set up our Fusion glossary",
  "configure Genie for Fusion", "Genie doesn't know our Fusion terms", "register
  Fusion schema comments", "map our PVO / FDI tables to canonical".
compatibility: Requires databricks CLI >= v0.294.0 (experimental aitools)
metadata:
  version: "0.1.0"
parent: oracle-fusion-overview
---

# Oracle Fusion Setup

Bootstrap a Databricks workspace so Genie Code can answer Oracle Fusion questions using the customer's own COA segment meanings, ledger/BU scope, landing-pattern physical names, and business jargon. This is a **one-time setup** per workspace, run by the D&A team. After it completes, every other `oracle-fusion-*` skill works more effectively.

> **FIRST:** load the `oracle-fusion-overview` skill — it carries the org model (Ledger / Legal Entity / Business Unit), the landing-pattern-agnostic rule, the canonical EBS-style table names, and the universal gotchas (`_ALL` multi-org scoping, CCID segments, accounting vs transaction date, period open/close, entered-vs-accounted currency, GL↔XLA). This skill builds on it.

## Why run this first (and the value it creates)

Out of the box Genie doesn't know *your* Fusion. It can't know which `SEGMENT1..30` is your company / cost center / natural account (that's per-tenant config), which ledgers and business units are in scope, or — critically — **what physical objects you actually receive**. Fusion Cloud is SaaS: you don't query `GL_JE_HEADERS` directly, you get BICC Public View Object (PVO) extracts, an FDI star schema, or base-table mirrors with *different names*. Without that mapping Genie guesses and produces confident-but-wrong SQL.

This setup teaches the workspace your Fusion so **every other `oracle-fusion-*` skill** (ledger-coa, general-ledger, procurement, data-engineering, data-quality, genie-agent) answers in your vocabulary against your actual tables. **Explain this to the user up front.** It is a **one-time** step that **pays off on its own** — you do not need to build a Genie Space afterward for it to be worth running.

## What it creates, and where

**The default flow creates one asset** — a workspace-tier glossary skill at `<skills-root>/oracle-fusion/<customer>-oracle-fusion-glossary/`. **UC comment registration is opt-in only** (see *Optional: UC comment registration*). UC writes go through the vetted preview-then-apply flow; setup never offers them automatically.

```
<skills-root>/oracle-fusion/<customer>-oracle-fusion-glossary/
├── SKILL.md                ← the Genie-loaded glossary skill (rendered view)
├── answers.json            ← structured source of truth (re-run input)
├── draft_profile.json      ← most-recent Phase 0 profile
└── history/                ← timestamped snapshots; --no-history disables
```

(`<skills-root>` = `/Workspace/.assistant/skills` for a workspace install, or `/Users/<email>/.assistant/skills` for a user install.)

**What the glossary carries** (three things, all customer-specific):
1. **The physical→canonical mapping** — for the customer's landing pattern, which PVO / FDI / base-table object and column corresponds to each canonical entity (`GL_JE_HEADERS`, `GL_CODE_COMBINATIONS`, `PO_HEADERS_ALL`, …). This is the landing-agnostic rule made concrete. Module skills reference canonical names; this map resolves them to what the customer actually has.
2. **COA segment meaning** — which `SEGMENT1..30` is company / cost center / natural account / etc., plus the value-set meanings (the natural-account ranges that mean "revenue", the cost-center values, the balancing-segment-value→legal-entity assignment). This is the single most-reused fact across the family.
3. **Business jargon + scope** — ledger names ↔ `LEDGER_ID`, business-unit names ↔ BU IDs, the in-scope ledgers/BUs, currency basis conventions, period calendar quirks, custom/DFF columns.

**If the customer also wants UC table/column comments registered** on the Fusion Silver tables — they must explicitly request it (the *Optional* section). UC writes modify customer-owned tables and never run as a side effect of the default setup.

## When to use

- "Set up Oracle Fusion for Genie / configure Genie for our Fusion data"
- "Map our COA segments — which segment is cost center / natural account?"
- "Map our BICC PVO (or FDI) tables to the canonical Fusion model"
- "Genie doesn't understand our ledger / BU / value-set names"
- "Register column comments on our Fusion tables"
- One of the first things a new customer should run after the `oracle-fusion` family is installed

## Pre-flight

1. **Catalog/schema location**: "Which catalog/schema holds your Fusion Silver layer?" Placeholders are Databricks-native: `:catalog`, `:silver_schema`, `:gold_schema`.
2. **Customer short name**: "What short name should we use in skill filenames?" (e.g. `acme`, `globex-financials`). Becomes part of the generated glossary skill name.
3. **Output scope**: workspace-wide (admin) or user-scoped?
4. **Check default Genie Code instructions**: if the workspace already has default Genie Code instructions (Workspace Settings → Genie Code → Default instructions), **read them first**. Anything documented there — catalog/schema, ledger currency, landing pattern, segment meanings — is already in Genie's per-turn context and should NOT be re-asked. Use it to pre-populate `draft_profile.json` and skip those questions.

## Questions to surface first

These deployment-level ambiguities have NO defensible default and decide whether every downstream `oracle-fusion-*` skill is correct. Surface them up front (the full, profile-grounded version is in [interview-playbook.md](interview-playbook.md)); never finalize the glossary by guessing them.

1. **What is the landing pattern, and what are the physical object names?** BICC PVO extracts, Fusion Data Intelligence (FDI/FAW star schema), or base-table mirrors? This decides the physical→canonical mapping — the central deliverable. Confirm the actual object/column names for each canonical entity in scope.
2. **Which `SEGMENT1..30` means what?** Company / cost center / natural account / intercompany / future-use is **per-tenant config**, and the #1 thing this skill captures. The profiler shows which segments carry distinct values; only the SME confirms the meaning. Also capture which segment is the **balancing segment** (its values map to legal entities).
3. **Which ledgers and business units are in scope, and what is the currency basis?** A single primary ledger or a consolidated set? Entered (document), accounted (ledger), or FDI analytics currency? `_ALL` tables hold every BU — which BUs are real vs test/decommissioned?
4. **Which Fusion modules are run in Fusion vs another system of record?** Empty/sparse canonical tables usually mean the process lives elsewhere — confirm before treating a table as authoritative.
5. **Does the BICC extract capture deletes?** Standard incremental (last-update-date) extracts catch INSERT/UPDATE only; hard deletes need a separate Deleted-Record extract or periodic full reload. Record whether deletes are captured — it scopes a `oracle-fusion-data-quality` concern (Bronze drift).

## Workflow

**Profile the data first, then interview to confirm the gaps, then generate, then (optionally) register comments.** Don't ask the customer what the data can already tell you.

### Phase 0 — Profile the data (automated first pass)

Profile the schema and extract the data-provable facts — which canonical (or PVO/FDI) tables are present and populated, distinct ledgers (`GL_LEDGERS` / `LEDGER_ID`) and currencies, which `SEGMENT1..30` columns carry distinct values (and their cardinality), distinct balancing-segment values, business-unit IDs on `_ALL` tables, the period calendar (`GL_PERIODS`), candidate custom/DFF columns (`ATTRIBUTE1..n`, `*_DFF`), and row/null stats — into a DRAFT for the interview. The **landing pattern** is partially data-provable (object naming gives it away) but confirm it in the interview. **Pick the path that matches how Genie Code is attached:**

**Path A — workspace / serverless compute (can run Python):**
```bash
# In-workspace: omit --profile (ambient auth). Local runs: add --profile <name>.
python scripts/introspect_schema.py \
  --catalog <catalog> --schema <silver-schema> \
  --output draft_profile.json
```

**Path B — SQL warehouse only (Genie started from the Unity Catalog data page):** the CLI/Python may not be attached. Run the equivalent profiling queries in SQL Editor (information_schema for tables/columns; `SELECT DISTINCT` for ledgers/currencies/segments/BSVs; `COUNT`/null stats), substituting `:catalog`/`:silver_schema`. Same facts, all read-only.

> Genie Code attached to the workspace can run Python, SQL, and shell on serverless; attached to a warehouse it is SQL-only. Don't assume Python is available — detect it, fall back to Path B if not.

Present the findings. This turns Phase 1 from "answer 20 questions cold" into "confirm/correct what we found, and supply only what the data can't prove."

### Phase 1 — Interview (confirm the gaps)

See [interview-playbook.md](interview-playbook.md) — run it like a Fusion implementation consultant who can already see the data. Ask in **batches of 2–3**; never dump the whole list. **Batch 0 (modules in use, landing pattern, industry) goes first** — it scopes everything else.

The data can't prove these — they are what the interview captures:
- **Landing pattern + physical names** (Batch 0 + the mapping batch): which PVO/FDI/base object maps to each canonical entity.
- **Segment meaning**: which `SEGMENT1..30` is company / cost center / natural account; the value-set meanings; the balancing segment.
- **Scope**: in-scope ledgers, legal entities, business units, currency basis, period-calendar quirks.
- **Custom/DFF columns**: what each `ATTRIBUTE*`/DFF stores and who relies on it.

Record answers as `answers.json` (shape + the `draft_profile.json` → `answers.json` mapping are in [interview-playbook.md](interview-playbook.md)).

### Phase 2 — Generate the workspace glossary skill

Once the interview is complete, write the glossary **into the `oracle-fusion/` group folder**, alongside the rest of the family, so it shares their discovery regime:

```
<skills-root>/oracle-fusion/<customer>-oracle-fusion-glossary/SKILL.md
# <skills-root> = /Workspace/.assistant/skills        (workspace install)
#              or /Users/<email>/.assistant/skills     (user install)
```

The generated `<customer>-oracle-fusion-glossary` skill MUST include, at minimum:
1. **Physical → canonical mapping table** — one row per canonical entity in scope (`GL_JE_HEADERS`, `GL_JE_LINES`, `GL_BALANCES`, `GL_CODE_COMBINATIONS`, `GL_PERIODS`, `GL_DAILY_RATES`, `PO_HEADERS_ALL`, `PO_LINES_ALL`, `PO_DISTRIBUTIONS_ALL`, `POZ_SUPPLIERS`, …) → the customer's actual PVO/FDI/base object + the key column renames. This is the landing-agnostic rule made concrete.
2. **COA segment map** — `SEGMENT1..30` → meaning, the balancing segment, and value-set meanings (natural-account ranges, cost-center values, BSV→legal-entity assignment).
3. **Scope + jargon** — in-scope ledgers (name ↔ `LEDGER_ID`), business units (name ↔ BU ID), currency basis, period-calendar notes, custom/DFF columns.
4. Standard frontmatter (`name`, `description`, `metadata.version` "0.1.0", `parent: oracle-fusion-overview` — no `tags:`/`owners:`).

Record every unconfirmed item as **`_unknown_ — confirm with <role>`** rather than guessing, and include a follow-up table (who confirms what) so flagged items aren't lost.

### Phase 3 — Register UC comments (optional, preview-then-apply)

See *Optional: UC comment registration* below. Runs **only when the user explicitly asks**.

## What NOT to do

- Don't skip Phase 0 — asking the customer what the data already shows wastes the SME's time and misses the landing-pattern naming the data reveals.
- The profile **proposes**; the human **confirms**. Never finalize a segment meaning, ledger/BU scope, landing-pattern mapping, or custom-column meaning without the customer validating it.
- **Don't omit the physical→canonical mapping from the glossary.** It is the central deliverable — without it the module skills can't resolve canonical names to the customer's PVO/FDI/base objects (landing-agnostic rule).
- **Don't assume segment positions/meanings.** `SEGMENT2` = cost center is a guess; resolve from the interview.
- **Never offer UC comment registration as an automatic next step** when setup completes — it runs ONLY on explicit user request through the vetted flow.
- **Never interpret "okay" / "looks good" / "sounds fine" as approval to apply UC writes.** Those acknowledge the preview, not approve the write. Require unambiguous affirmation ("yes apply", "go ahead and apply"). When in doubt, re-ask.
- **Never apply UC comments (or any change to existing tables) without explicit user approval.** Preview is the default; `--apply` runs only after the customer's verbal go-ahead. (Repo rule: writes to existing objects require explicit permission.)
- Don't fabricate mappings if the customer doesn't know — write `_unknown_ — needs validation from <role>` and move on.
- **Don't re-teach universal mechanics in the glossary or comments.** `_ALL` multi-org scoping, CCID-segment mechanics, accounting-vs-transaction date, period open/close, entered-vs-accounted currency, and the GL↔XLA bridge are owned by `oracle-fusion-overview` and `oracle-fusion-ledger-coa` — capture the customer-specific *values* (their segment meanings, their ledgers/BUs, their physical names), not the mechanic.
- **Don't author metric definitions here.** Capturing a KPI's stated definition during the interview is fine, but certified formulas live with their owners (`oracle-fusion-general-ledger`, `oracle-fusion-procurement`).

## Optional: UC comment registration (opt-in only, vetted preview-then-apply)

**This section runs ONLY when the user explicitly requests UC comment registration.** Setup never offers it automatically; the user must ask ("register the comments", "apply the column metadata").

UC comments are Genie's #1 SQL-quality lever, but they modify customer-owned tables. Per the repo rule, writes to existing UC objects run through a vetted, preview-then-apply flow.

### Checkpoint 1 — Preview (writes nothing)

```bash
python scripts/apply_uc_comments.py \
  --catalog <catalog> --schema <silver-schema> \
  --comments-file example_comments.json
# Prints every COMMENT ON TABLE / ALTER TABLE … COMMENT statement.
# No --apply means NO UC writes.
```
Show the customer the scope (count of tables + columns), which tables already have comments (would be overwritten), and the full statement list. Extend `example_comments.json` from the glossary for the customer's renamed/custom tables before previewing.

### Checkpoint 2 — Unambiguous verbal approval

Ask explicitly: *"This will write {N} table comments and {M} column comments to your Unity Catalog. Do you want me to apply?"* Interpret only unambiguous affirmation ("yes apply", "go ahead and apply") as approval — not "looks good" / "okay".

### Checkpoint 3 — Apply (only after approval)

```bash
python scripts/apply_uc_comments.py \
  --catalog <catalog> --schema <silver-schema> \
  --comments-file example_comments.json --apply --warehouse-id <id>
```
The setup skill never auto-executes the apply step.

### Checkpoint 4 — Post-apply verification

```sql
SELECT table_name, column_name, comment
FROM   :catalog.information_schema.columns
WHERE  table_schema = :silver_schema AND comment IS NOT NULL
ORDER  BY table_name, ordinal_position;
```
Surface any rows where comments are missing or unexpected.

## Re-running (refresh, not rebuild)

A re-run never re-interviews from scratch and never blind-overwrites. When an existing `<customer>-oracle-fusion-glossary` is found, **ask how to re-run**: (a) **Delta refresh** — pick up only what's new/changed (new ledgers, BUs, segments, custom columns) plus open `_unknown_`s, leaving confirmed answers as-is; or (b) **Revisit existing answers** — also walk previously-confirmed mappings to re-confirm/correct. Default to (a). Both re-profile first and **merge-and-back-up** (`SKILL.md.bak`), never overwrite. Bump `metadata.version`. Close with a "what changed since last run" summary. Trigger a re-run on: new ledgers/BUs/segments/custom columns, a landing-pattern change (e.g. BICC → FDI), or when the customer confirms items from the follow-up worklist.

## Composes with

This foundation skill feeds every other `oracle-fusion-*` skill — they read the generated glossary and the UC comments it registers.

- **[oracle-fusion-overview](../oracle-fusion-overview/)** — org model, landing-agnostic rule, universal gotchas. Load first.
- **[oracle-fusion-ledger-coa](../oracle-fusion-ledger-coa/)** — KEYSTONE; consumes the segment→meaning map and physical→canonical mapping this skill produces. Never run setup's writes from there.
- **[oracle-fusion-data-engineering](../oracle-fusion-data-engineering/)** — building the Silver layer this skill profiles.
- **[oracle-fusion-data-quality](../oracle-fusion-data-quality/)** — the interview's deletes-not-captured / scope findings feed here.
- **UC `ALTER TABLE` / `COMMENT ON` mechanics** → platform skill [`databricks-unity-catalog`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-unity-catalog); this skill provides the Fusion-specific content.

## References

- [interview-playbook.md](interview-playbook.md) — the confirm-the-gaps interview (profile-grounded, batched)
- [example_comments.json](example_comments.json) — example UC comment spec for canonical Fusion tables
- [scripts/apply_uc_comments.py](scripts/apply_uc_comments.py) — preview-then-apply UC comment registration (default preview; `--apply` gated on explicit approval)
- [scripts/introspect_schema.py](scripts/introspect_schema.py) — Phase 0 profiler (referenced; build on the family's data-exploration mechanics)
- Oracle Fusion Financials data model (OEDMF): `https://docs.oracle.com/en/cloud/saas/financials/25c/oedmf/`
