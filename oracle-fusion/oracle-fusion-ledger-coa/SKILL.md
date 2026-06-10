---
name: oracle-fusion-ledger-coa
description: |
  Use for the Oracle Fusion Cloud ERP accounting foundation — the chart of
  accounts / code combinations (GL_CODE_COMBINATIONS, CCID, SEGMENT1..30,
  CONCATENATED_SEGMENTS), the ledger / legal-entity / business-unit structure
  (GL_LEDGERS, LEDGER_ID, balancing segment values), the accounting calendar and
  period open/close status (GL_PERIODS, GL_PERIOD_STATUSES), currency conversion
  (entered vs accounted vs ledger currency, GL_DAILY_RATES, Spot/Corporate
  rates), and the subledger-accounting bridge to GL (XLA_AE_HEADERS,
  XLA_AE_LINES, GL_SL_LINK_ID). This is the KEYSTONE every Fusion financial
  question joins to. Triggers on: "chart of accounts", "code combination",
  "CCID", "natural account", "cost center segment", "which ledger", "legal
  entity", "business unit", "GL period", "period open or closed", "accounting
  calendar", "currency conversion", "accounted vs entered amount", "subledger
  to GL", "XLA", "reconcile subledger". Load it for anything touching accounts,
  balances, currency, periods, or org scope.
metadata:
  version: "0.1.0"
parent: oracle-fusion-overview
---

# Oracle Fusion — Ledger, Chart of Accounts & Accounting Foundation (keystone)

The accounting substrate every Fusion financial question depends on. General Ledger, Payables, Receivables, Procurement spend-by-account, and the accounting side of every SCM flow all join to the chart of accounts, a ledger, a period, and a currency. This skill encodes that model once — segment resolution, currency conversion, period mapping, and the subledger→GL bridge — so the module skills don't restate it.

> **FIRST:** load the `oracle-fusion-overview` skill — it carries the org model (Ledger / LE / BU), the landing-pattern-agnostic rule, and the universal gotchas. This skill is the accounting depth beneath them.

## When to use

- Decoding accounts: code combinations (CCID) → segment values → names; "which segment is cost center / natural account".
- Scoping by org: ledger, legal entity, balancing segment value, business unit.
- Anything period-related: GL periods, period open/close status, "as-of period", chronological period ordering.
- Currency: entered vs accounted vs ledger amounts, conversion via daily rates.
- Reconciling subledger (AP/AR/PO) to GL via XLA.

**Defer to siblings when:** the question is about journals/balances/trial-balance specifically (→ `oracle-fusion-general-ledger`) or procurement spend (→ `oracle-fusion-procurement`). Those skills *compose* this one for accounting dimensionality.

## Top gotchas

These silently produce wrong financials. Full set in [gotchas.md](gotchas.md); the overview carries the org-wide ones.

1. **Accounts are CCIDs, not strings, and segment meaning is customer config.** Rows carry `CODE_COMBINATION_ID`; the readable account is `GL_CODE_COMBINATIONS.CONCATENATED_SEGMENTS`. **Which `SEGMENT1..30` is company vs cost center vs natural account is per-tenant** — resolve via the workspace glossary, never assume positions. Decode segment values to names via the flexfield value sets (`FND_FLEX_VALUES_VL`).
2. **Never sum `ENTERED` across currencies.** `ENTERED_DR/CR` is document currency; `ACCOUNTED_DR/CR` is ledger currency. Cross-entity or multi-currency totals must use **accounted** amounts. Convert via `GL_DAILY_RATES` keyed on (from, to, conversion date, rate type).
3. **Respect period status; order by effective period number.** `GL_PERIOD_STATUSES` gives Open/Closed/Future/Never-Opened/Permanently-Closed/Close-Pending *per ledger+period*. Open periods are not final. Sort chronologically by `PERIOD_YEAR*10000 + PERIOD_NUM` — never alphabetically by `PERIOD_NAME`.
4. **XLA rolls up *into* GL — don't double-count.** Subledger lines (`XLA_AE_LINES`) transfer to `GL_JE_LINES` via `GL_SL_LINK_ID`. Use one level: GL for summarized posted numbers, XLA for transaction-level detail with the originating document. Untransferred entries (`GL_TRANSFER_STATUS_CODE`) aren't in GL yet.
5. **Balancing segment value ties a journal to a legal entity.** Consolidations and "by legal entity" reporting key off the BSV→LE assignment, not a raw LE column on the journal.

## Questions to surface first

Surface these before answering — there is no defensible default:

1. **Which ledger / currency basis?** A single primary ledger or a consolidated set? Entered (document), accounted (ledger), or — under FDI — analytics currency? Translated balances or not? Totals differ by basis.
2. **Account scope.** Which balancing segment values (legal entities), which natural-account ranges, summary vs detail accounts (`DETAIL_POSTING_ALLOWED_FLAG`)? "Revenue" / "headcount cost" depend on the customer's segment-value ranges.
3. **GL summarized balances vs subledger (XLA) detail?** Do they want the posted GL number, or transaction-level detail with the source document? These reconcile but answer different questions.

## Pre-flight (per session)

1. **Catalog/schema** — confirm via the glossary skill or ask. Placeholders: `:catalog`, `:silver_schema`, `:gold_schema`.
2. **Glossary skill** — is `<customer>-oracle-fusion-glossary` installed? It holds the **segment→meaning map**, the physical→canonical table mapping, and the ledger/BU list. Prefer it over assumptions.
3. **Landing pattern** — BICC PVO vs FDI changes physical names + currency-basis columns; the glossary maps them.

## Workflow

For any accounting-dimension question, resolve in this order:

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `decode_ccid_segments`, `convert_to_ledger_currency`, `period_for_date`, `is_period_open`. Call one if it matches.
2. **Pre-joined view** — compose from [views.sql](views.sql): `v_code_combination` (CCID + decoded segments), `v_gl_period` (period + status + sort key), `v_ledger_org` (ledger/LE/BU/BSV).
3. **Raw canonical tables** — `GL_CODE_COMBINATIONS`, `GL_PERIODS`, `GL_DAILY_RATES`, `XLA_AE_LINES` — only when the view layer doesn't cover the shape. Resolve physical names via the glossary first.

## What's in this skill

- [schema.md](schema.md) — **load when** joining or selecting accounting-foundation columns. Canonical reference for `GL_LEDGERS`, `GL_CODE_COMBINATIONS`, `GL_PERIODS`/`GL_PERIOD_STATUSES`, `GL_DAILY_RATES`, `XLA_AE_HEADERS`/`XLA_AE_LINES`, and the LE/BU/BSV assignment.
- [gotchas.md](gotchas.md) — **load before** writing non-trivial accounting joins. The inline 5 plus segment-decode, currency-basis, period-ordering, XLA-bridge, and consolidation traps.
- [views.sql](views.sql) — DDL for `v_code_combination`, `v_gl_period`, `v_ledger_org`. Registered once via `oracle-fusion-setup`.
- [metric_udfs.sql](metric_udfs.sql) — Trusted Asset UC functions: segment resolution, currency conversion, period mapping. Registered once via `oracle-fusion-setup`.
- [examples.sql](examples.sql) — **load when** the question matches a pattern (decode an account, convert a balance to ledger currency, find the period for a date, reconcile XLA to GL).

## What NOT to do

- Don't assume segment positions/meanings — resolve via the glossary (gotcha 1).
- Don't sum entered amounts across currencies — use accounted (gotcha 2).
- Don't sort or filter periods by `PERIOD_NAME` string — use the effective period number (gotcha 3).
- Don't add GL and XLA amounts together — one level only (gotcha 4).
- Don't write or alter UC comments / metadata from this skill — owned by `oracle-fusion-setup` (preview-then-apply).

## Composes with

- **`oracle-fusion-overview`** — org model + universal gotchas. Always loaded first.
- **`oracle-fusion-general-ledger`** — journals/balances/trial-balance build directly on this skill's period, currency, and CCID model.
- **`oracle-fusion-procurement`** — composes this skill for spend-by-account/cost-center (PO distributions carry the CCID) and currency normalization.
- **`oracle-fusion-setup`** — owns the segment→meaning map, physical→canonical mapping, and registration of these views/UDFs. Never run those scripts from this skill.
