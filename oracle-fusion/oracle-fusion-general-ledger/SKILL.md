---
name: oracle-fusion-general-ledger
description: |
  Oracle Fusion Cloud ERP / Fusion Financials / Fusion GL general-ledger
  analytics — journals, balances, trial balance, account analysis, and
  actual-vs-budget. Use for querying, analyzing, or building pipelines /
  dashboards / Genie Agents on the GL journal and balance tables:
  GL_JE_BATCHES -> GL_JE_HEADERS -> GL_JE_LINES (journal entries; STATUS P/U,
  ACTUAL_FLAG A/B/E, JE_SOURCE, JE_CATEGORY, PERIOD_NAME) and GL_BALANCES
  (actual / budget / encumbrance balances by ledger + code combination +
  currency + period). Triggers on: "trial balance", "account balance",
  "GL account analysis", "journal volume", "journal lines", "posted journals",
  "actual vs budget", "budget variance", "net activity", "debits and credits",
  "period balances", "ACTUAL_FLAG", "code combination", "by cost center",
  "by natural account". Hard-depends on the keystone oracle-fusion-ledger-coa
  for currency conversion, period status, and CCID decode — composes it rather
  than restating accounting mechanics.
metadata:
  version: "0.1.0"
parent: oracle-fusion-overview
---

# Oracle Fusion — General Ledger

Help the user query, analyze, or build pipelines/dashboards/Genie Agents on Oracle Fusion GL journal and balance data — trial balance, account balances, journal volume, account analysis, and actual-vs-budget. This skill adds the GL-specific schema, gold-standard queries, reusable views, Trusted UDFs, and a metric view on top of the keystone's accounting model.

> **FIRST:** load the `oracle-fusion-overview` skill — it carries the org model (Ledger / LE / BU), the landing-pattern-agnostic rule, and the universal gotchas. This skill builds on it. It also **hard-depends on the keystone `oracle-fusion-ledger-coa`** for code-combination decode, currency conversion, and period status — compose those, don't restate them.

## When to use

GL reporting and analysis questions:
- "Give me the trial balance for OCT-25."
- "What's the balance of account X this period?"
- "Actual vs budget variance by cost center."
- "Top accounts by net activity this quarter."
- "How many journals did Payables post last month?" (journal volume by source)
- "Show me the journal lines behind this account balance."
- "Build a GL / financial-reporting dashboard or Genie Agent."

**Defer to siblings when:**
- Decoding a CCID, resolving segment meaning, converting currency, or checking period open/close → keystone `oracle-fusion-ledger-coa` (this skill *calls* its UDFs/views).
- Transaction-level subledger detail with the source document (the AP invoice / PO behind a journal) → keystone (XLA bridge), then the relevant module.
- Procurement spend-by-account → `oracle-fusion-procurement`.

## Top gotchas

These silently produce wrong financials. Full set in [gotchas.md](gotchas.md); the keystone owns segment/currency/period mechanics and the overview the org-wide ones.

1. **Never sum across `ACTUAL_FLAG`.** `A` (Actual), `B` (Budget), `E` (Encumbrance) are *different balance types* sharing one table. Summing them is nonsense. **Every** GL aggregate must filter `ACTUAL_FLAG` to exactly one value (and budget needs a `BUDGET_VERSION_ID`, encumbrance an `ENCUMBRANCE_TYPE_ID`). This is the single most common GL error.
2. **Posted-only for financials.** Trial balance, account balances, and actuals use **posted** journals only — `GL_JE_HEADERS.STATUS = 'P'` (and line `STATUS = 'P'`). Unposted (`'U'`) entries are not yet in the books and must not appear in a balance or actuals number.
3. **Pick the currency basis deliberately.** Lines carry `ENTERED_DR/CR` (document currency) and `ACCOUNTED_DR/CR` (ledger currency); balances carry a `CURRENCY_CODE` and a `TRANSLATED_FLAG`. Never sum `ENTERED` across currencies — cross-account/ledger totals use **accounted/ledger** amounts. Conversion is the keystone's `convert_to_ledger_currency`; do not hand-roll rate math.
4. **Order periods by effective period number, never `PERIOD_NAME`.** `'APR-25'` sorts before `'JAN-25'` alphabetically. Use the keystone's `v_gl_period` sort key (`PERIOD_YEAR*10000 + PERIOD_NUM`), and respect period status — an open period is not final. Use `is_period_open` / `period_for_date` from the keystone.
5. **A CCID is a key, not a readable account.** `GL_JE_LINES.CODE_COMBINATION_ID` / `GL_BALANCES.CODE_COMBINATION_ID` are surrogate keys. To group "by cost center" / "by natural account" you must decode via the keystone's `v_code_combination` / `decode_ccid_segments` — **segment positions are per-tenant config**, never assume `SEGMENT2` = cost center.

## Questions to surface first

Surface these before answering — there is no defensible default (these compose the keystone's ledger/account questions):

1. **Balance type?** Actual, Budget, or Encumbrance (`ACTUAL_FLAG` A/B/E)? If Budget, **which `BUDGET_VERSION_ID`**; if Encumbrance, which `ENCUMBRANCE_TYPE_ID`? You cannot mix them (gotcha 1).
2. **Which ledger + currency basis?** A single primary ledger or a consolidated set, and entered (document), accounted (ledger), or translated balances (gotcha 3)? Totals differ by basis.
3. **Posted-only, and as-of which period + date basis?** Posted only (default yes for financials)? Which `PERIOD_NAME`, and is the metric driven by the effective/accounting date (`DEFAULT_EFFECTIVE_DATE`) or the posted date?
4. **Account scope?** Which balancing segment values (legal entities) / natural-account ranges, and summary vs detail accounts? "Revenue" / "headcount cost" depend on the customer's segment-value ranges (resolve via the glossary / keystone).

## Pre-flight (per session)

One-time session config — cache, don't re-ask:

1. **Catalog/schema** — confirm via the workspace glossary skill or ask. Placeholders are Databricks-native: `:catalog`, `:silver_schema`, `:gold_schema`.
2. **Glossary skill** — is `<customer>-oracle-fusion-glossary` installed? It holds the **segment→meaning map**, the physical→canonical table mapping, the ledger/BU list, and budget-version names. Prefer it over assumptions.
3. **Landing pattern** — BICC PVO vs FDI changes physical names + which currency-basis columns exist; the glossary maps them. Never hard-code a physical table name (landing-agnostic rule).
4. **Keystone registered?** `v_code_combination`, `v_gl_period`, and the keystone UDFs must be registered (via `oracle-fusion-setup`) for this skill's views/UDFs to resolve. If not, offer to run setup.

## Workflow

**Building a semantic layer / Genie Agent / dashboard (the most common ask):** start from [metric_view.yaml](metric_view.yaml) — the governed GL semantic layer over a gold view. Its measures (`debit_amount`, `credit_amount`, `net_activity`, `period_net`, …) and **agent metadata** (synonyms like "trial balance", "net activity", "GL spend") are defined once and sliceable by ledger / legal entity / natural account / cost center / period / balance type — with posted-only baked into the `filter`. Defer creation & registration mechanics to the platform skill [`databricks-metric-views`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-metric-views); `oracle-fusion-setup` owns registration.

**Answering an ad-hoc question:** resolve in this order:

1. **Metric view** — if `gl_metrics` is registered, query it with `MEASURE(...)`; it encodes the canonical definitions and the posted-only / balance-type discipline. Always group `net_activity` by the `balance_type` dimension so you never sum across `ACTUAL_FLAG` (gotcha 1).
2. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `trial_balance`, `account_balance`, `journal_count` — when the metric takes parameters (ledger, period, CCID, balance type).
3. **Parameterized example query** — check [examples.sql](examples.sql) for an existing pattern; use it with the user's parameters.
4. **Pre-joined view** — compose using `v_gl_journal_enriched` / `v_trial_balance` from [views.sql](views.sql) (which already join the keystone's `v_code_combination` and `v_gl_period`).
5. **Raw canonical tables** — `GL_JE_HEADERS`/`GL_JE_LINES`/`GL_BALANCES` — only when the view layer doesn't cover the shape. Resolve physical names via the glossary first; explain why you're skipping the views.

## What's in this skill

- [schema.md](schema.md) — **load when** joining or selecting GL columns. Canonical reference for `GL_JE_BATCHES` → `GL_JE_HEADERS` → `GL_JE_LINES` and `GL_BALANCES`, with cardinality and the landing-pattern note.
- [gotchas.md](gotchas.md) — **load before** writing non-trivial GL queries. The inline 5 plus balances-vs-journals reconciliation, summary-vs-detail accounts, translated balances, JE_SOURCE/CATEGORY, and the Activity Amount sign convention.
- [views.sql](views.sql) — DDL for `v_gl_journal_enriched` (journals + decoded account + period status) and `v_trial_balance` (posted actual balances by ledger/account/period, ledger currency). Composes the keystone views. Registered once via `oracle-fusion-setup`.
- [metric_udfs.sql](metric_udfs.sql) — Trusted Asset UC functions: `trial_balance`, `account_balance`, `journal_count`. Registered once via `oracle-fusion-setup`.
- [examples.sql](examples.sql) — **load when** the question matches a pattern (trial balance for a period, actual-vs-budget variance, top accounts by net activity, journal volume by source, balance converted to ledger currency).
- [metric_view.yaml](metric_view.yaml) — **load when** building/extending the GL semantic layer, a Genie Agent, or a dashboard. Canonical measures + agent metadata over the gold GL view, posted-only filter baked in. Register once via `oracle-fusion-setup`; mechanics live in `databricks-metric-views`.

## What NOT to do

- Don't sum across `ACTUAL_FLAG` — actual/budget/encumbrance are distinct balance types; always pin one (gotcha 1).
- Don't include unposted journals (`STATUS = 'U'`) in balances or actuals (gotcha 2).
- Don't sum `ENTERED` amounts across currencies — use accounted/ledger, and convert via the keystone's `convert_to_ledger_currency` (gotcha 3).
- Don't sort or filter periods by `PERIOD_NAME` string — use the keystone's effective-period-number sort key (gotcha 4).
- Don't `GROUP BY` a raw `CODE_COMBINATION_ID` and call it "by account" — decode via the keystone's `v_code_combination` / `decode_ccid_segments`, and never assume segment positions (gotcha 5).
- Don't add `GL_JE_LINES` amounts to `GL_BALANCES` or to XLA subledger detail — they reconcile but are different grains (double-counting); one level only.
- Don't redefine the keystone's UDFs/views (`convert_to_ledger_currency`, `v_gl_period`, `v_code_combination`, …) — call them.
- Don't hard-code a physical table name without the glossary; don't write/alter UC comments (owned by `oracle-fusion-setup`, preview-then-apply).

## Composes with

- **`oracle-fusion-overview`** — org model + universal gotchas. Always loaded first.
- **`oracle-fusion-ledger-coa`** (KEYSTONE, hard dependency) — CCID decode (`v_code_combination` / `decode_ccid_segments`), currency conversion (`convert_to_ledger_currency`), period model (`v_gl_period` / `is_period_open` / `period_for_date`), and the XLA→GL bridge. This skill's views and examples compose those; it never restates them.
- **`oracle-fusion-procurement`** — for spend-by-account analysis from the PO side; this skill owns the GL/journal side of the same accounts.
- **`oracle-fusion-data-quality`** — for "this trial balance doesn't tie out" diagnostics (unbalanced journals, GL↔subledger drift, currency gaps).
- **`oracle-fusion-setup`** — owns the segment→meaning map, the physical→canonical mapping, and registration of these views/UDFs/the metric view. Never run those scripts from this skill.
- **`databricks-metric-views`** (platform) — the *mechanics* of creating/registering/refreshing the GL metric view. This skill supplies the source-specific YAML + agent metadata; that skill supplies the how.
