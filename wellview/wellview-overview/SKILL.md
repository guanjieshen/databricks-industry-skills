---
name: wellview-overview
description: |
  Use whenever the user mentions Peloton WellView, WellView, WV well data, well
  lifecycle, daily drilling/operations report, drilling or workover jobs, AFE /
  cost per foot, NPT (non-productive time), days vs depth, rate of penetration
  (ROP), or any well-construction data question. Orients Genie on the WellView
  data model — the GUID record tree (IDREC, IDRECPARENT, IDWELL), the WV / LV /
  SYS table grammar that navigates a 200-300 table schema, the well -> job ->
  daily-report -> cost hierarchy, and the universal gotchas that cause wrong,
  invisibly-wrong answers (master/storage units vs display units, calc-engine
  fields that are not stored columns, one-well-many-jobs double counting, AFE
  percentage allocation, configurable LV codes). This is the foundation skill
  loaded for any WellView question — other wellview-* skills layer on top.
metadata:
  version: "0.1.0"
---

# WellView Overview

This skill gives you the baseline literacy to work with Peloton **WellView**
well-lifecycle data in Databricks. Load it whenever a user mentions WellView, a daily
drilling/operations report, drilling/workover jobs, AFE/cost, NPT, days-vs-depth, ROP,
or any well-construction data concept.

You are not a WellView specialist out of the box. With this skill loaded, you behave
like one — you know the record tree, the table grammar, and the joins/units that always
go wrong. **The persona asking is usually a domain expert (drilling/workover
supervisor, cost/AFE engineer) who is NOT a WellView-schema expert and prompts
tersely.** Read intent generously, surface your assumptions, and ask when ambiguous.

> **⚠️ Names are canonical, not confirmed.** WellView's data dictionary is not public.
> The *model* below (record tree, grammar, grain, gotchas) is high-confidence; specific
> *physical names* (`WVJOBREPORT`, `WVJOBREPORTOP`, `WVCOST`, the `LV*` tables) and
> **the master unit of each numeric column** must be resolved through the
> `<customer>-wellview-glossary` produced by `wellview-setup`. Never assume a physical
> name or a unit exists — resolve it via the glossary, or ask.

## Genie Code tips (apply to every WellView question)

- **Auth is ambient in the workspace** — Genie Code is already authenticated to the
  current workspace, so do **not** pass `--profile` (it would usually fail). Use
  `--profile <name>` only when running locally against `~/.databrickscfg`.
- **Reference tables explicitly** with `@catalog.schema.table` and use **`/findTables`**
  to locate them — don't guess names.
- Skills load **only in Agent mode**, and Genie selects them **only by matching their
  `description`**. After editing a skill, start a **new chat**.
- If `wellview-setup` has not been run in this workspace, the physical→canonical mapping,
  the `LV` code meanings, and the **master units** are unknown — analytical skills then
  produce confident, invisible errors. Offer to run it.

## When to use

- Any mention of: Peloton WellView, WellView, WV, daily drilling report, daily
  operations report, tour sheet, time log, drilling/workover/completion **job**, spud,
  AFE, cost per foot, NPT, non-productive time, days vs depth, ROP, bit run, mud check,
  rig, `IDWELL`, `IDREC`, `WVWELLHEADER`, `WVJOB`, `WVJOBREPORT`
- Any request to query, analyze, or build pipelines/dashboards on well-construction data
- Before activating any other `wellview-*` skill — this one provides the shared baseline

If the question is module-specific (cost, NPT, integrity), the matching module skill
(`wellview-daily-ops-cost`, etc.) will also load. Compose them.

## Module map

When the question gets specific, defer to the right module skill:

| Domain | Skill | Triggers | Status |
|---|---|---|---|
| Daily ops, time log, cost, AFE, NPT | `wellview-daily-ops-cost` | "daily report", "cost per foot", "NPT", "over AFE", "days vs depth" | shipped |
| ROP/MSE, NPT root-cause, bit runs | `wellview-drilling-npt` | "ROP", "rate of penetration", "bit performance", "NPT by phase" | fast-follow |
| Completion, perforations, stimulation, workovers | `wellview-completions-workovers` | "perforations", "frac stages", "workover scope" | fast-follow |
| Barriers, pressure/annulus tests, well status | `wellview-well-integrity` | "barrier", "pressure test", "annulus", "well status" | fast-follow |
| Customer schema / units / codes setup | `wellview-setup` | "set up WellView", "what units", "decode our codes" | shipped |
| Pipelines / modeling | `wellview-data-engineering` | "build a pipeline", "model WellView", "normalize units" | shipped |
| "This number looks wrong" | `wellview-data-quality` | "cost looks off", "NPT too high", "doubled cost" | shipped |

## Pre-flight (ask once per session, then cache)

1. **Catalog/schema location**: "Which Unity Catalog catalog/schema holds your WellView
   data?" (e.g. `wellview.silver`). If unknown, use the repo's
   [`data-exploration`](../../_common/data-exploration/) skill to find it —
   `databricks experimental aitools tools query "SELECT table_catalog, table_schema, table_name FROM system.information_schema.tables WHERE table_name ILIKE 'wv%' OR table_name ILIKE 'wvjob%'"`.
2. **Workspace glossary**: Check whether a `<customer>-wellview-glossary` skill is
   installed. If yes, defer physical-name + unit resolution to it. If no, suggest running
   `wellview-setup`.
3. **Units & codes are customer-specific**: the master unit of each numeric column and
   the meaning of each `LV` code are per-install. **Never assume — resolve via glossary
   or ask.**

## The record tree — WellView's signature (read every time)

WellView is a **SQL Server tree of records**, not a star schema. Almost **every** `WV*`
table carries the same key contract:

| Column | Role |
|---|---|
| `IDREC` | **Primary key** of the row — a globally-unique GUID |
| `IDRECPARENT` | **FK to the parent row's `IDREC`** — the hierarchy edge |
| `IDWELL` | **Denormalized well GUID** carried on every descendant (fast well-scoped filter); equals `WVWELLHEADER.IDREC` |

Plus audit columns (`SYSCREATEDATE`/`SYSCREATEUSER`, `SYSMODDATE`/`SYSMODUSER`, `SYSTAG`)
and a sibling-ordering field (sequence/`SysSeqNo`-style).

**The master gotcha — internalize this:**
> Child rows relate to their parent via **`child.IDRECPARENT = parent.IDREC`**, **NOT**
> via `IDWELL`. `IDWELL` only tells you *which well* a row belongs to — it does **not**
> express the parent-child edge. Joining the tree on `IDWELL` fans out and
> **double-counts**. Use `IDWELL` to *filter to a well*, `IDRECPARENT→IDREC` to *relate*.

Confirmed shape (well → job → rig), generalizes down the tree:
```sql
FROM   wv.wvwellheader well
JOIN   wv.wvjob        job ON job.idwell      = well.idwell   -- well->job: idwell (well.idrec = well.idwell)
LEFT   JOIN wv.wvjobrig rig ON rig.idrecparent = job.idrec     -- child->parent: idrecparent = parent idrec
```

## The table grammar (so you navigate 200–300 tables, not memorize them)

A real WellView DB has **200–300 tables**. You don't memorize them — you learn the
grammar and predict / introspect the rest:

| Prefix | Meaning | Use |
|---|---|---|
| **`WV…`** | WellView **data** tables (the record tree) | The analytical surface |
| **`LV…`** | **L**ist of **V**alues — code → label lookups (operation, NPT, cost, job-type codes) | Join to decode coded columns; **codes are customer-configurable** |
| **`SYS…`** | System/config — units (`SYSUNIT`-style), calc definitions (`SYSCALC`-style), security, report layouts | Interpretation + ETL, not direct analytics |

Entity grammar within `WV`: `WV<entity>` is the spine row; `WV<entity><subpart>` are its
children. So you can predict `WVCASING` ⇒ `WVCASINGTUBULAR` / `WVCASINGCEMENT`. **Confirm
predicted names via the glossary or `/findTables` before querying.**

## The well → job → report → cost spine (the ~17 tables that matter most)

```
WVWELLHEADER (1 / well; IDREC = IDWELL)
└── WVJOB (1 / job — a well has MANY jobs: drill, completion, workover, P&A)
    ├── WVJOBRIG          (rig assignment)
    ├── WVJOBREPORT       (1 / day / job  ← daily operations report)
    │   ├── WVJOBREPORTOP (1 / activity   ← the time log: time-on/off, phase, op code, NPT flag)
    │   └── WVDAILYMUD    (mud checks)
    ├── WVCOST            (dated cost lines — parentage job vs report: confirm per instance)
    ├── WVAFE → WVAFEDETAIL  (AFE header + cost-code lines)
    └── WVBITRUN, WVSURVEY, WVCASING, ...  (job-scoped technical detail)
```

*(Names provisional where noted; grain & roles are the reliable part. The flagship
`wellview-daily-ops-cost` skill carries the detailed schema for this spine.)*

## The universal gotchas (apply to almost every WellView query)

Read these every time — they cause the majority of wrong, *invisibly* wrong answers.

1. **Walk the tree by `IDRECPARENT → IDREC`, not `IDWELL`.** (The master gotcha above.)
   `IDWELL` is the well bucket, not the parent edge.

2. **One well has MANY jobs.** Aggregating cost/footage/days across a well **without
   grouping by `WVJOB.IDREC`** double-counts when a well has had multiple jobs (drill +
   workover + re-entry). For a "current drilling" question, pick the relevant **job**,
   not the whole well. *(This is the daily-ops analog of mixing run vintages.)*

3. **Master/storage units ≠ display units.** WellView stores numbers in a fixed
   **master unit per quantity** and converts for display in the UI. **Raw tables return
   master units, unlabeled.** A depth reading 10,000 ft in the app may be stored in
   metres. **Confirm the master unit of every numeric column via the glossary and
   normalize before any math or comparison.** This is the #1 invisible error (WellView's
   foot-vs-metre). Cost has the same trap with **currency**.

4. **UI metrics may be calc-engine outputs, not stored columns.** `DaysFromSpud`,
   `CostCum`, `ROP` and similar are often computed by WellView's calc engine and **may
   not exist in a raw extract**. Don't assume a field you saw in WellView is a column —
   recompute via the certified UDFs if absent.

5. **Decode coded columns through `LV` tables — never hard-code.** Operation, phase, NPT,
   cost, and job-type codes live in customer-configurable `LV*` lookups. The same code
   means different things at different operators. Resolve labels via the `LV` table or
   the glossary.

6. **AFEs allocate many-to-many across jobs/wells by percentage.** Naive `AFE × job`
   joins **double-count cost**. Roll cost up by `WVJOB.IDREC` first, then to the well,
   de-duping shared AFE allocation. (See `wellview-daily-ops-cost`.)

7. **Time-on/time-off duration math.** Time-log activity hours should reconcile to ~24 h
   per report-day; segments can cross midnight. Prefer the stored duration; if computing
   from `DtTm` start/end, handle day boundaries.

## What NOT to do

- **Don't join the record tree on `IDWELL`.** Use `IDRECPARENT = parent.IDREC`. `IDWELL`
  filters to a well; it does not relate rows.
- **Don't roll cost/footage to the well without grouping by job** — multiple jobs
  double-count.
- **Don't treat raw numeric columns as display units.** Confirm the master unit; normalize.
- **Don't assume `DaysFromSpud`/`CostCum`/`ROP` are stored** — they may be calc-engine
  outputs. Recompute if absent.
- **Don't hard-code operation/NPT/cost codes** — decode via the `LV` tables / glossary.
- **Don't fabricate WellView table or column names.** Resolve via the glossary, ask, or
  `/findTables`. The schema "follows WellView conventions but the exact names are
  per-install."
- **Don't query a domain's tables before confirming they exist** in this install
  (modules and detail tables vary).

## What's in this skill

- [data-model.md](data-model.md) — **load when** a question crosses module boundaries or needs the entity catalogue beyond the daily-ops/cost spine (the universal column contract, the `WV`/`LV`/`SYS` grammar, entities by domain).

## Composes with

- **`wellview-setup`** — one-time workspace bootstrap (glossary, master units, `LV` decodes, UC comments).
- **`wellview-data-engineering`** — Bronze→Silver/Gold modeling and the gold fact the metric view consumes.
- **`wellview-data-quality`** — "this number looks wrong" diagnostics.
- All **`wellview-<module>`** skills — defer specific analytical work to them (see Module map).

## References

- [wellview-setup](../wellview-setup/) — builds the glossary (physical names + **units** + `LV` decode) every other skill depends on
- [wellview-daily-ops-cost](../wellview-daily-ops-cost/) — the flagship: daily report, time log, cost/ft, NPT %, AFE variance
- [wellview-data-engineering](../wellview-data-engineering/) — the conformed per-job Silver/Gold spine
- [wellview-data-quality](../wellview-data-quality/) — diagnose tree/unit/AFE issues
- [`_common/data-exploration`](../../_common/data-exploration/) — discovery mechanics (`databricks experimental aitools tools`)
- Peloton WellView: `https://www.peloton.com/products/well-data-lifecycle/wellview/data-analysis/`
