---
name: oracle-fusion-genie-agent
description: |
  Use to scaffold, curate, or improve a Databricks Genie Agent (the curated
  text-to-SQL data product, formerly "Genie Space") over Oracle Fusion Cloud ERP
  data — Finance (general ledger, trial balance, account analysis, actual vs
  budget) and Procurement / SCM (PO spend, suppliers, requisitions, receipts,
  three-way match). Assembles which Unity Catalog objects, metric views, Trusted
  UDFs, semantic descriptions, and synonyms to curate into a Fusion Genie Agent,
  the certified example questions->SQL to seed it, and how to benchmark accuracy.
  Triggers on: "create a Genie Agent / Genie Space for our Fusion data", "build a
  Fusion Financials Genie", "curate Genie for Oracle Cloud ERP", "Genie gives
  wrong GL / trial-balance / spend answers", "improve our Fusion Genie",
  "benchmark the Fusion Genie Agent", "what instructions should our Fusion Genie
  have", "add example questions to the Fusion Genie", "Fusion text-to-SQL". Run
  oracle-fusion-setup first so the glossary and UC comments exist; defer Genie
  Agent create/export/import mechanics to databricks-genie.
metadata:
  version: "0.1.0"
parent: oracle-fusion-overview
---

# Oracle Fusion — Genie Agent scaffolder

Stand up (or fix) a **Genie Agent** — the curated text-to-SQL data product (formerly "Genie Space") — that answers Oracle Fusion Cloud ERP questions accurately. Genie Agent quality is **not** a one-time setup; per Databricks it is an *iterative process*. This skill turns the `oracle-fusion-*` family's assets — the GL and procurement metric views, the keystone Trusted UDFs, the conformed views, and the workspace glossary — into the things a Fusion Genie Agent needs, then benchmarks them. It owns the **Fusion curation content**; the platform skill [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md) owns the **create / export / import / API mechanics**.

> **FIRST:** load the `oracle-fusion-overview` skill — it carries the org model (Ledger / LE / BU), the landing-pattern-agnostic rule, and the universal gotchas (multi-org `_ALL` scoping, CCID segments are customer config, accounting vs transaction date, period open/close, entered vs accounted currency, GL↔XLA double-count, posted-vs-unposted, BICC deletes-not-captured). This skill builds on that foundation — it does not re-teach those mechanics; it tells you which to encode as Genie Agent instructions.

**Naming, so it's unambiguous:** *Genie Code* is the agent harness that loads these skills. A *Genie Agent* (formerly "Genie Space") is the curated text-to-SQL data product you build for business users. This skill is the **scaffolder** for that data product — it curates **content**; it does not create the Agent. Creation mechanics live in `databricks-genie`.

## When to use

Triggered by Genie-Agent curation and quality questions for Fusion:
- "Create / build a Genie Agent (Genie Space) for our Fusion Financials / Procurement data"
- "Genie keeps giving wrong GL / trial-balance / spend answers — how do we fix it?"
- "What general instructions should our Fusion Genie Agent have?"
- "Add certified example questions / synonyms / Trusted Assets to the Agent"
- "Benchmark the Fusion Genie Agent"

**Defer when:**
- The question is about the *create / export / import API or UI* (not Fusion content) → [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md).
- The fix is a missing UC comment, a segment→meaning map entry, or a customer glossary term → `oracle-fusion-setup` (it owns UC comments and the `<customer>-oracle-fusion-glossary`; preview-then-apply).
- The miss is a module's metric semantics (trial balance, net activity, spend basis, three-way match) → that module skill (`oracle-fusion-general-ledger`, `oracle-fusion-procurement`) owns the definition and the metric view / UDF; this skill just curates it into the Agent.
- The miss is accounting dimensionality (CCID decode, currency conversion, period status) → keystone `oracle-fusion-ledger-coa`; this skill curates its Trusted UDFs into the Agent.

## Top gotchas

These are the curation traps that make a Fusion Genie Agent answer wrong. (The *underlying* data mechanics are owned and explained by `oracle-fusion-overview` and the keystone `oracle-fusion-ledger-coa` — here the point is how they surface during curation.)

1. **Garbage-in instructions.** A Genie Agent is only as good as its UC comments, synonyms, and examples. Build it **after** `oracle-fusion-setup` has registered UC comments and generated the `<customer>-oracle-fusion-glossary` (including the **segment→meaning map** and the physical→canonical table mapping). Without that, Genie can't even tell which `SEGMENT` is cost center. UC comments are the #1 quality lever.
2. **Bake the universal filters into the general instructions.** The most common Fusion Genie failures are unscoped sums and mixed balance types. Add explicit instruction text: always scope `_ALL` tables by business unit / ledger (`PRC_BU_ID`, `LEDGER_ID`); financials use **posted** journals only (`GL_JE_HEADERS.STATUS='P'`); **pin exactly one `ACTUAL_FLAG`** (A/B/E) on every GL aggregate; never sum `ENTERED` across currencies (use accounted/ledger); order periods by effective period number, never `PERIOD_NAME`; never assume a segment position. State them as rules — the rationale lives in `oracle-fusion-overview` / the keystone.
3. **Register metrics + accounting logic as Trusted Assets, never hand-write the SQL.** Trial balance, net activity, account balance, spend, three-way-match, plus CCID decode / currency conversion / period mapping have contested or customer-specific definitions and live as **certified UC functions** and **metric views** in the family. Curate those into the Agent so Genie calls the *governed* asset instead of regenerating ad-hoc SQL it will get subtly wrong (mixed balance types, wrong currency basis, undecoded CCID).
4. **Expose conformed Silver/Gold + the metric views, not raw Bronze.** Pointing the Agent at raw `_ALL` Bronze re-introduces every universal trap (unscoped multi-org, mixed `ACTUAL_FLAG`, raw CCIDs, entered-currency mixing). Expose the family's gold views and metric views, where posted-only / balance-type / org discipline is already baked in.
5. **One Agent per persona / domain, not one giant Fusion Agent.** A Finance Agent (controller / FP&A) and a Procurement/SCM Agent (sourcing / supply-chain analyst) want different tables, synonyms, and examples. A too-broad Agent dilutes accuracy and crosses the spend↔GL grain (double-count risk). Split by persona; see [curation.md](curation.md).
6. **It is never "done."** Use the Genie **Monitoring** tab to harvest real questions it got wrong and feed them back as new examples / instructions / synonyms. Schedule a re-curation pass.

## Questions to surface first

Surface these before curating — there is no defensible default:

1. **Which Agent / which persona?** A **Finance** Agent (GL / trial balance / actual-vs-budget for controller + FP&A) or a **Procurement/SCM** Agent (spend / suppliers / POs / receipts for sourcing + supply-chain analyst)? This decides which tables, metric views, Trusted UDFs, synonyms, and examples to load. Confirm before assembling — see [curation.md](curation.md) for the two object sets.
2. **Whose definitions seed the instructions?** "Spend" (ordered vs received vs invoiced), "balance" (entered vs accounted vs translated), "revenue" / "headcount cost" (which segment-value ranges), the match rule (2-way / 3-way / 4-way) — all have multiple valid framings owned by the module skills. Confirm the customer's chosen conventions so instructions and examples encode *their* convention, not a default.
3. **Glossary + setup present?** Has `oracle-fusion-setup` produced the `<customer>-oracle-fusion-glossary` (segment→meaning map, physical→canonical mapping, ledger/BU/budget-version list) and registered UC comments? If not, curate those first — an Agent built without them is the #1 cause of wrong answers, and without the segment map Genie literally cannot decode accounts.
4. **Landing pattern.** BICC PVO vs Fusion Data Intelligence (FDI) changes physical names and which currency-basis columns exist. The Agent must point at the conformed canonical model the family describes; the glossary maps physical names.
5. **Benchmark acceptance bar.** What pass rate / which question set must the Agent clear before it goes to business users? Seed [sample-questions.md](sample-questions.md) with the customer's real questions, not just the starters.

## Pre-flight (per session)

One-time session config — cache, don't re-ask:

1. **`oracle-fusion-setup` done?** UC comments registered + `<customer>-oracle-fusion-glossary` generated (incl. segment→meaning map). Keystone + module views/UDFs/metric views registered.
2. **Catalog/schema** for the conformed Silver/Gold tables, views, and metric views to expose. Placeholders: `:catalog`, `:silver_schema`, `:gold_schema`.
3. **Glossary skill** — confirm `<customer>-oracle-fusion-glossary` is installed; prefer it for segment, physical-name, and business-term resolution.

## Workflow

```
- [ ] Step 1: Confirm prerequisites (oracle-fusion-setup done; catalog/schema; glossary present)
- [ ] Step 2: Pick the Agent (Finance vs Procurement/SCM persona) and its object set
- [ ] Step 3: Add the curated UC objects — gold views + metric views + the tables they read
- [ ] Step 4: Register/attach the Trusted Asset UDFs (keystone + module) as the governed metrics
- [ ] Step 5: Assemble general instructions (overview/keystone gotchas as rules + glossary synonyms)
- [ ] Step 6: Add semantic descriptions + synonyms; load certified example questions->SQL
- [ ] Step 7: Run the benchmark; fix gaps; repeat from the Monitoring tab
```

The ingredients and where each comes from:

| Genie Agent needs | Source in this family |
|---|---|
| **Curated UC objects** (tables + gold views + **metric views**) | GL: `v_trial_balance` / `v_gl_journal_enriched` + the `gl_metrics` metric view (`metric_view.yaml`). Procurement: the conformed PO/supplier gold views + the procurement spend metric view. Keystone: `v_code_combination`, `v_gl_period`, `v_ledger_org`. |
| **Trusted Asset functions** (governed metrics) | Keystone `metric_udfs.sql`: `decode_ccid_segments`, `convert_to_ledger_currency`, `period_for_date`, `is_period_open`. GL `metric_udfs.sql`: `trial_balance`, `account_balance`, `journal_count`. Procurement `metric_udfs.sql`: the spend / match metrics. |
| **General instructions** | `oracle-fusion-overview` + keystone gotchas, encoded as terse rules, plus the glossary synonyms from `oracle-fusion-setup`. |
| **Semantic descriptions + synonyms** | Metric-view **agent metadata** (e.g. GL's "trial balance" / "net activity" / "GL spend") + the `<customer>-oracle-fusion-glossary`. |
| **Certified example questions->SQL** | each in-scope module's `examples.sql` (GL trial balance / actual-vs-budget / journal volume; procurement open-PO backlog / supplier spend / cycle time / 3-way-match) + [curation.md](curation.md). |

**Step 4 — Trusted Assets.** Curate the relevant UC functions (substituting the customer `catalog.schema`) into the Agent so Genie computes metrics and accounting transforms via *certified* assets: the keystone's `decode_ccid_segments` / `convert_to_ledger_currency` / `period_for_date` / `is_period_open`, GL's `trial_balance` / `account_balance` / `journal_count`, and procurement's spend/match functions. Each definition is owned by its skill — do not redefine it here. See [Trusted Assets](https://docs.databricks.com/aws/en/genie/trusted-assets).

**Step 5 — Instructions.** Draft the general instructions as terse imperative rules from the universal gotchas (scope `_ALL` by BU/ledger; posted-only `STATUS='P'`; pin one `ACTUAL_FLAG`; accounted not entered for cross-currency; period sort by effective number; decode CCIDs, never assume segment positions; spend basis is explicit; don't add GL to XLA) plus the synonym mappings from the workspace glossary.

**Step 6 — Semantic + examples.** Carry the metric-view agent metadata (descriptions + synonyms) into the Agent, and add the parameterized queries from each in-scope module's `examples.sql` as certified example questions — the gold-standard patterns. See [curation.md](curation.md) for the synonym seed list and [sample-questions.md](sample-questions.md) for the benchmark set.

**Step 7 — Benchmark.** Run [sample-questions.md](sample-questions.md) against the Agent. For each miss, fix in this order: (a) UC comment / segment-map entry (via `oracle-fusion-setup`), (b) glossary synonym / instruction, (c) add/repair a certified example or Trusted Asset / metric view. Re-run until it clears the acceptance bar. Use the Genie **Monitoring** tab to find real misses and feed them back.

## What's in this skill

- [curation.md](curation.md) — **load when** picking what goes into an Agent. The curation checklist: the object set for a Finance Genie Agent vs a Procurement/SCM Genie Agent, the synonyms to seed, and certified example questions->SQL.
- [sample-questions.md](sample-questions.md) — **load when** validating Agent quality. A benchmark question set spanning finance and procurement, each with the expected canonical behavior, plus a Pass/Partial/Fail rubric.

For programmatic create / export / import of the Agent itself, load the platform skill [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md). This skill provides the Fusion curation content; that one provides the mechanics. Metric-view creation/registration mechanics live in [`databricks-metric-views`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-metric-views).

## What NOT to do

- Don't build an Agent before `oracle-fusion-setup` has registered UC comments, the segment→meaning map, and the glossary — the #1 cause of wrong answers.
- Don't hand-write metric or accounting SQL into the Agent — curate the Trusted Asset functions and metric views instead. The definitions belong to the module/keystone skills, not here.
- Don't re-teach the universal data mechanics in the instructions — state them as rules and let `oracle-fusion-overview` / the keystone carry the rationale.
- Don't expose raw Bronze `_ALL` tables; expose the conformed gold views and metric views where org / posted-only / balance-type discipline is baked in.
- Don't build one giant Fusion Agent — split Finance vs Procurement/SCM by persona to protect accuracy and avoid crossing the spend↔GL grain.
- Don't write or alter UC comments / table metadata or the segment map from this skill — owned by `oracle-fusion-setup` (preview-then-apply, gated on explicit approval). Defer to it.
- Don't re-implement Genie Agent create/export/import — defer to [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md).
- Don't promise raw-table access; Fusion Cloud is SaaS (BICC/FDI extracts only).
- Don't declare it "done" — schedule a re-curation pass from the Monitoring tab.

## Composes with

- **`oracle-fusion-setup`** — runs FIRST; owns UC comments, the segment→meaning map, and the `<customer>-oracle-fusion-glossary` that seed instructions and synonyms, plus registration of all views/UDFs/metric views. Never write UC comments from this skill; defer to setup's preview-then-apply.
- **`oracle-fusion-overview`** — source of the universal gotchas this skill encodes as Genie instructions (it does not re-author them).
- **`oracle-fusion-ledger-coa`** (KEYSTONE) — source of the accounting Trusted UDFs (`decode_ccid_segments`, `convert_to_ledger_currency`, `period_for_date`, `is_period_open`) and the `v_code_combination` / `v_gl_period` / `v_ledger_org` views to curate into every financial Agent.
- **Module skills** (`oracle-fusion-general-ledger`, `oracle-fusion-procurement`) — source of the certified `examples.sql`, `metric_udfs.sql`, and `metric_view.yaml` to curate. Each owns its metric definitions; this skill only assembles them into the Agent. (Fast-follow modules — payables, receivables, inventory, order-management, cost-management, fixed-assets, subledger-recon, expenses — extend the relevant Agent as they ship.)
- **`databricks-genie`** (platform) — Agent create / export / import / API mechanics. This skill provides the Fusion content; that one provides the how.
- **`databricks-metric-views`** (platform) — the mechanics of creating / registering / refreshing the GL and procurement metric views curated into the Agent.

## References

- [curation.md](curation.md) — object set per Agent + synonym seed + certified example questions->SQL
- [sample-questions.md](sample-questions.md) — benchmark question set + scoring rubric
- [Genie best practices](https://docs.databricks.com/aws/en/genie/best-practices) · [Monitoring](https://docs.databricks.com/aws/en/genie/monitor) · [Trusted Assets](https://docs.databricks.com/aws/en/genie/trusted-assets)
- Oracle Fusion Financials data model (OEDMF): `https://docs.oracle.com/en/cloud/saas/financials/25c/oedmf/`
- Oracle Fusion Procurement data model (OEDMP): `https://docs.oracle.com/en/cloud/saas/procurement/25c/oedmp/`
