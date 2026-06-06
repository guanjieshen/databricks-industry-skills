---
name: oracle-fusion-overview
description: |
  Use whenever the user mentions Oracle Fusion Cloud ERP, Fusion ERP, Fusion
  Financials, Fusion SCM, Oracle Cloud ERP, OCR, or Fusion applications data —
  general ledger (GL, journals, GL_JE_HEADERS, GL_BALANCES, trial balance,
  chart of accounts, code combinations, CCID), payables/receivables, procurement
  (purchase orders, PO_HEADERS_ALL, requisitions, suppliers, spend), inventory,
  order management, subledger accounting (XLA). Orients Genie on the Fusion data
  model, the ledger / legal-entity / business-unit org structure, the
  subledger-to-GL bridge, and the universal gotchas that apply across any Fusion
  query (multi-org / business-unit scoping, code-combination segments,
  accounting vs transaction date, period open/close, entered-vs-accounted
  currency, BICC/PVO/FDI landing-pattern variation). The foundation skill loaded
  for any Oracle Fusion question and the canonical home for cross-cutting facts —
  other oracle-fusion skills layer on top and defer here.
metadata:
  version: "0.1.0"
---

# Oracle Fusion Cloud ERP — Overview

The foundation skill for working with Oracle Fusion Cloud ERP data (Financials + Supply Chain) in Databricks. Load it whenever the user mentions Oracle Fusion, Fusion ERP/SCM, Oracle Cloud ERP, or any Fusion concept. Other `oracle-fusion-*` skills layer on top — they set `parent: oracle-fusion-overview` so this stays loaded.

You are not a Fusion ERP specialist out of the box. With this skill loaded, you behave like one — you know the org model, the canonical entities, the joins that always go wrong, and how Fusion Cloud data actually arrives in a lakehouse.

## When to use

- Any user mention of: Oracle Fusion, Fusion ERP, Fusion Financials, Fusion SCM, Oracle Cloud ERP, OCR; GL / journals / trial balance / chart of accounts / code combinations; payables / receivables / suppliers; purchase orders / requisitions / procurement / spend; inventory; order management; subledger accounting / XLA.
- Any request to query, analyze, or build pipelines/dashboards/ML on Oracle Fusion data.
- Before activating any other `oracle-fusion-*` skill — this one provides the shared baseline.

If the question is module-specific (GL balances, procurement spend), the matching module skill (`oracle-fusion-general-ledger`, `oracle-fusion-procurement`) will also load. Compose them. **Anything that touches accounting dimensionality — ledger, code combinations, periods, currency — also pulls in the keystone `oracle-fusion-ledger-coa`.**

## How Fusion data lands in the lakehouse (read this first)

Fusion Cloud is **SaaS — there is no direct JDBC/ODBC to the transaction tables.** Analytics data leaves Fusion Cloud one of three ways, and **which one the customer uses changes the physical table/column names**, not the meaning:

| Path | What lands | Naming |
|---|---|---|
| **BICC** (BI Cloud Connector) — the **most common** Databricks source | Bulk file extracts of **Public View Objects (PVOs)** to object storage → ingested to Delta | PVO names like `JournalSourceExtractPVO`, `RequisitionHeaderExtractPVO` |
| **Fusion Data Intelligence (FDI/FAW)** | A prebuilt **star schema** (facts/dims, prebuilt metrics) | Subject areas like `Financials - GL Balance Sheet`, `Procurement - Spend` |
| **BI Publisher / OTBI** | Templated/real-time reporting extracts | Reporting subject-area PVOs |

**The landing-pattern-agnostic rule (central to this family):** Fusion's *underlying physical tables keep the E-Business Suite names almost verbatim* (`GL_JE_HEADERS`, `GL_BALANCES`, `GL_CODE_COMBINATIONS`, `PO_HEADERS_ALL`, `XLA_AE_LINES`). This family's `schema.md` files describe that **canonical model**. But what the customer actually *receives* is PVOs or FDI artifacts with different names. So **module skills reference canonical entities/columns; the physical-name mapping for THIS customer lives in the `<customer>-oracle-fusion-glossary` produced by `oracle-fusion-setup`.** Never hard-code a physical table name in a query without checking the glossary — and never promise raw-table access (it's SaaS).

## The Fusion org model (the "4 Cs" and the hierarchy)

Every financial row is scoped by an org structure that Genie must respect:

- **Ledger** — the central accounting context, defined by the **4 Cs: Chart of accounts, Calendar, Currency, Accounting method.** FK `LEDGER_ID` on virtually every GL/XLA row.
- **Legal Entity (LE)** — the legally-registered org (tax/statutory). LEs are assigned to ledgers; **balancing segment values (BSVs) tie a journal's balancing segment back to an LE.**
- **Business Unit (BU)** — the operational division. A BU connects to a primary ledger + default LE. **Fusion's Business Unit ≈ E-Business Suite "Operating Unit"** (the multi-org operational partition). Transactional `_ALL` tables are multi-org and scoped by BU (e.g. `PO_HEADERS_ALL.PRC_BU_ID`).

Hierarchy: `Ledger → (Legal Entities via BSV) / (Business Units) → transactions`.

## Universal gotchas (apply to almost every Fusion query)

Read these every time — they cause the majority of silently-wrong answers. **This is the canonical home; module skills reference and apply them rather than restating.** The accounting-specific mechanics (segments, currency, periods, XLA) are owned by the keystone `oracle-fusion-ledger-coa`.

1. **Multi-org / `_ALL` scoping.** Transactional tables carry an `_ALL` suffix and hold *every* business unit's rows. Summing without a BU / ledger / BSV filter mixes orgs. Always scope (e.g. `PRC_BU_ID` for procurement, `LEDGER_ID` for GL).

2. **Code-combination segments are customer-configured.** Accounts are stored as a `CODE_COMBINATION_ID` (CCID), not a readable string. Which segment means company vs cost center vs natural account is per-tenant config. Never assume `SEGMENT2` = cost center — resolve segment meaning via the glossary / `oracle-fusion-ledger-coa`.

3. **Accounting date vs transaction date vs GL date.** The books are driven by the accounting/effective date and `PERIOD_NAME`, not the entry/transaction date. Confirm which date a metric means before bucketing by time.

4. **Period open/close matters.** A period's status (`GL_PERIOD_STATUSES`: Open / Closed / Future / Never-Opened / Permanently-Closed / Close-Pending) determines whether numbers are final. Open periods change. Sort periods by effective period number, never alphabetically by `PERIOD_NAME`.

5. **Entered vs accounted vs ledger currency.** Rows carry both `ENTERED_DR/CR` (document currency) and `ACCOUNTED_DR/CR` (ledger currency). **Never sum `ENTERED` across currencies.** Cross-entity totals use accounted/ledger amounts; conversion uses `GL_DAILY_RATES` by rate type + date.

6. **GL ↔ subledger (XLA) — don't double-count.** Subledger transactions (AP/AR/PO receipts) become GL journals via the Create Accounting process: `XLA_AE_HEADERS` → `XLA_AE_LINES`, transferred to `GL_JE_LINES`. XLA detail rolls *up into* GL — never add GL journals to XLA detail. Untransferred XLA entries aren't in GL yet (`GL_TRANSFER_STATUS_CODE`). Owned by `oracle-fusion-ledger-coa`.

7. **Posted vs unposted; canceled/voided.** Trial balance and financials use **posted** journals only (`GL_JE_HEADERS.STATUS = 'P'`). Spend/order metrics must respect cancel/close flags (`PO_HEADERS_ALL.CANCEL_FLAG`, `CLOSED_CODE`). Don't count canceled POs as spend or unposted journals as actuals.

8. **BICC incremental extracts don't capture hard deletes by default.** Standard last-update-date extracts catch INSERT/UPDATE only; deletes need a separate Deleted-Record extract or a periodic full reload. Bronze can drift from source — a `oracle-fusion-data-quality` concern.

## The Fusion module map (canonical entities by area)

### Accounting foundation (keystone — `oracle-fusion-ledger-coa`)
- `GL_LEDGERS` — ledger definitions (the 4 Cs)
- `GL_CODE_COMBINATIONS` — account combinations; PK `CODE_COMBINATION_ID` (CCID), `SEGMENT1..30`, `CONCATENATED_SEGMENTS`, `ACCOUNT_TYPE`
- `GL_PERIODS` / `GL_PERIOD_STATUSES` — accounting calendar + open/close status
- `GL_DAILY_RATES` — currency conversion rates (Spot / Corporate / User / Fixed)
- `XLA_AE_HEADERS` / `XLA_AE_LINES` — subledger accounting (the subledger→GL bridge)
- Legal entity / BU / BSV assignment metadata

### General Ledger (`oracle-fusion-general-ledger`)
- `GL_JE_BATCHES` → `GL_JE_HEADERS` → `GL_JE_LINES` — journals (header `STATUS` P/U, `ACTUAL_FLAG` A/B/E, `JE_SOURCE`, `JE_CATEGORY`, `PERIOD_NAME`)
- `GL_BALANCES` — actual/budget/encumbrance balances by ledger + CCID + currency + period

### Procurement (`oracle-fusion-procurement`)
- `POR_REQUISITION_HEADERS_ALL` — requisitions
- `PO_HEADERS_ALL` → `PO_LINES_ALL` → `PO_LINE_LOCATIONS_ALL` (schedules; `QUANTITY_RECEIVED`/`QUANTITY_BILLED`) → `PO_DISTRIBUTIONS_ALL` (the charged account/CCID)
- `POZ_SUPPLIERS` + supplier sites — supplier master (`VENDOR_ID` / `VENDOR_SITE_ID`)
- `TYPE_LOOKUP_CODE`: STANDARD / BLANKET (BPA) / CONTRACT / PLANNED

### Fast-follow modules (not yet built — see README)
Payables (`AP_INVOICES_ALL`), Receivables (`RA_CUSTOMER_TRX_ALL`), Inventory, Order Management, Cost Management, Fixed Assets, Subledger reconciliation, Expenses.

## Pre-flight (ask once per session, then cache)

1. **Catalog/schema** — "Which Unity Catalog catalog/schema holds your Fusion data?" SQL placeholders use Databricks-native syntax: `:catalog`, `:silver_schema`, `:gold_schema`.
2. **Landing pattern** — BICC PVO extracts, Fusion Data Intelligence, or other? This determines physical names; the glossary maps them to canonical entities.
3. **Workspace glossary** — is a `<customer>-oracle-fusion-glossary` skill installed? If yes, defer physical-name + business-jargon + segment-meaning resolution to it.
4. **`oracle-fusion-setup` status** — if not yet run, the physical→canonical mapping, COA segment meanings, ledger/BU scope, and UC comments are missing — quality degrades. Offer to run it.

## What NOT to do

- Don't hard-code a physical table name without checking the glossary — Fusion lands as PVOs/FDI, and names vary by customer (landing-agnostic rule).
- Don't sum across business units (`_ALL` tables) without a BU/ledger scope.
- Don't sum `ENTERED` amounts across currencies — use accounted/ledger amounts.
- Don't add GL journal amounts to XLA subledger detail — that double-counts.
- Don't include unposted journals in actuals, or canceled POs in spend.
- Don't assume segment positions/meanings — they're customer config.
- Don't promise raw-table access; Fusion Cloud is SaaS (BICC/FDI extracts only).

## Composes with

Depth lives in the sibling skills. The overview routes; the keystone carries the accounting model; modules carry the analytical domains.

### Foundation tier
- [`oracle-fusion-setup`](../oracle-fusion-setup/) — one-time bootstrap: profiles the customer's Fusion data, interviews on COA segment meaning / ledgers / BUs / landing pattern, generates the `<customer>-oracle-fusion-glossary` skill (incl. the physical→canonical mapping), registers UC comments (preview-then-apply).
- [`oracle-fusion-ledger-coa`](../oracle-fusion-ledger-coa/) — **KEYSTONE.** The COA / ledger / LE / BU / period / currency / XLA model every financial question joins to. Ships Trusted UDFs for segment resolution, currency conversion, and period mapping. Load it for anything touching accounts, balances, currency, or periods.
- [`oracle-fusion-data-engineering`](../oracle-fusion-data-engineering/) — modeling BICC/FDI extracts → Silver/Gold (incremental, `_ALL`/org handling, deletes-not-captured). Defers SDP mechanics to [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines).
- [`oracle-fusion-data-quality`](../oracle-fusion-data-quality/) — "this number looks wrong" diagnostics (GL↔subledger drift, unbalanced journals, currency gaps, extract gaps).

### Module tier
- [`oracle-fusion-general-ledger`](../oracle-fusion-general-ledger/) — journals, balances, trial balance, account analysis, actual-vs-budget. Hard-depends on the keystone.
- [`oracle-fusion-procurement`](../oracle-fusion-procurement/) — requisitions, POs, agreements, receipts, supplier spend, PO cycle time, 3-way-match exceptions. Hands invoice/payment off to a future `oracle-fusion-payables` (P2P boundary).

### Genie Agent scaffolder
- [`oracle-fusion-genie-agent`](../oracle-fusion-genie-agent/) — curates a Genie Agent over Fusion data (UC objects, semantic descriptions, synonyms, Trusted UDFs, sample questions). Defers Agent creation mechanics to [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md).

### Platform skills (reference, never duplicate)
| Need | Platform skill |
|---|---|
| Genie Agent creation / management | [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md) |
| Lakeflow pipelines (SDP / Auto Loader / AutoCDC) | [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines) |
| UC mechanics (comments, grants, lineage) | [`databricks-unity-catalog`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-unity-catalog) |
| Semantic metric layers (metric views) | [`databricks-metric-views`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-metric-views) |
| AI/BI Dashboards | [`databricks-aibi-dashboards`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-aibi-dashboards) |

## References

- Oracle Fusion Financials data model (OEDMF): `https://docs.oracle.com/en/cloud/saas/financials/25c/oedmf/`
- Oracle Fusion Procurement data model (OEDMP): `https://docs.oracle.com/en/cloud/saas/procurement/25c/oedmp/`
- BICC (BI Cloud Connector): `https://docs.oracle.com/en/cloud/saas/applications-common/bicc/`
- Fusion Data Intelligence subject areas: `https://docs.oracle.com/en/cloud/saas/analytics/`
