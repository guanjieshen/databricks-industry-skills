# Fusion Genie Agent — curation checklist

What to curate into a Fusion **Genie Agent** (the curated text-to-SQL data product, formerly "Genie Space"). Split by persona: a **Finance** Agent and a **Procurement/SCM** Agent. Build each only after `oracle-fusion-setup` has registered UC comments, the segment→meaning map, and the `<customer>-oracle-fusion-glossary`. Defer Agent create/export mechanics to `databricks-genie`; metric-view registration to `databricks-metric-views`; UC comments / segment map to `oracle-fusion-setup`.

## Contents
- Principles
- Objects to include — Finance Genie Agent
- Objects to include — Procurement / SCM Genie Agent
- Shared keystone objects (both Agents)
- General instructions to bake in
- Synonyms to seed
- Certified example questions -> SQL
- Promotion checklist

## Principles

- **One Agent per persona/domain.** A giant Fusion Agent dilutes accuracy and risks crossing the spend↔GL grain (double-counting). Finance and Procurement/SCM get separate Agents.
- **Expose conformed gold views + metric views, not raw Bronze `_ALL` tables.** The gold layer bakes in org scoping, posted-only, and balance-type discipline.
- **Governed metrics only.** Curate the Trusted Asset UDFs and metric views; do not let Genie hand-write trial balance, spend, currency, or CCID-decode SQL.
- **Names are landing-agnostic.** Point the Agent at the conformed canonical model the family describes; the glossary maps the customer's physical (BICC PVO / FDI) names.

## Objects to include — Finance Genie Agent

Personas: **controller / GL accountant, FP&A analyst.**

| Object | Type | From | Why |
|---|---|---|---|
| `gl_metrics` (`metric_view.yaml`) | Metric view | `oracle-fusion-general-ledger` | Canonical GL measures (`debit_amount`, `credit_amount`, `net_activity`, `period_net`) sliceable by ledger / LE / natural account / cost center / period / balance type, **posted-only baked in**. Primary surface for the Finance Agent. |
| `v_trial_balance` | Gold view | `oracle-fusion-general-ledger` | Posted actual balances by ledger / account / period in ledger currency. |
| `v_gl_journal_enriched` | Gold view | `oracle-fusion-general-ledger` | Journals + decoded account + period status, for journal volume / account analysis / drill-down. |
| `trial_balance`, `account_balance`, `journal_count` | Trusted UDFs | `oracle-fusion-general-ledger` | Parameterized governed metrics (ledger, period, CCID, balance type). |
| `GL_BALANCES`, `GL_JE_HEADERS`, `GL_JE_LINES` | Tables | canonical | Only as the views' backing; prefer the views/metric view for questions. |

Add the **shared keystone objects** below.

## Objects to include — Procurement / SCM Genie Agent

Personas: **procurement / sourcing analyst, supply chain analyst.**

| Object | Type | From | Why |
|---|---|---|---|
| procurement spend metric view | Metric view | `oracle-fusion-procurement` | Canonical spend measures with the **spend basis** (ordered / received / invoiced) as an explicit dimension, sliceable by supplier / BU / category / cost center / period. Primary surface for the Procurement Agent. |
| conformed PO gold view | Gold view | `oracle-fusion-procurement` | `PO_HEADERS_ALL` → `PO_LINES_ALL` → `PO_LINE_LOCATIONS_ALL` → `PO_DISTRIBUTIONS_ALL` enriched, BU-scoped, with cancel/close flags resolved. |
| supplier master view | Gold view | `oracle-fusion-procurement` | `POZ_SUPPLIERS` + supplier sites for "by supplier" rollups. |
| requisition view | Gold view | `oracle-fusion-procurement` | `POR_REQUISITION_HEADERS_ALL` for requisition / req-to-PO cycle. |
| spend / three-way-match | Trusted UDFs | `oracle-fusion-procurement` | Governed spend (per basis) and 2-/3-/4-way match exception logic. |
| `POZ_SUPPLIERS`, `PO_*_ALL` | Tables | canonical | Only as the views' backing; prefer the views/metric view. |

Add the **shared keystone objects** below. Spend-by-account/cost-center needs the keystone CCID decode (PO distributions carry the CCID).

## Shared keystone objects (both Agents)

From `oracle-fusion-ledger-coa` (KEYSTONE) — every financial Agent curates these so accounts, currency, and periods resolve correctly:

| Object | Type | Why |
|---|---|---|
| `v_code_combination` | View | CCID → decoded segments + names. Required for any "by cost center / natural account" grouping. |
| `v_gl_period` | View | Period + status + chronological sort key (`PERIOD_YEAR*10000 + PERIOD_NUM`). |
| `v_ledger_org` | View | Ledger / LE / BU / BSV scope. |
| `decode_ccid_segments` | Trusted UDF | Segment resolution (positions are **customer config** — never assume). |
| `convert_to_ledger_currency` | Trusted UDF | Entered → accounted/ledger conversion via `GL_DAILY_RATES`. |
| `period_for_date`, `is_period_open` | Trusted UDFs | Date→period mapping and open/close status. |

## General instructions to bake in

Encode these as terse imperative rules (rationale lives in `oracle-fusion-overview` / the keystone — do not restate it):

**Both Agents**
- Scope every `_ALL` table by business unit and/or ledger (`PRC_BU_ID`, `LEDGER_ID`) — never sum across orgs.
- Never sum `ENTERED` (document) amounts across currencies; use **accounted/ledger** amounts via `convert_to_ledger_currency`.
- Order periods by the effective period number (`v_gl_period` sort key), never alphabetically by `PERIOD_NAME`.
- Accounts are CCIDs, not strings; decode via `v_code_combination` / `decode_ccid_segments`. Segment positions are **customer-configured** — never assume `SEGMENT2` = cost center.
- Distinguish accounting/effective date from transaction/entry date before bucketing by time.
- Don't add GL journal/balance amounts to XLA subledger detail — one level only.
- Fusion Cloud is SaaS; data is BICC/FDI extracts. Don't promise raw-table access; resolve physical names via the glossary.

**Finance Agent**
- Financials use **posted** journals only (`GL_JE_HEADERS.STATUS='P'`).
- Pin exactly one `ACTUAL_FLAG` (A/B/E) on every aggregate; budget needs a `BUDGET_VERSION_ID`, encumbrance an `ENCUMBRANCE_TYPE_ID`. Never sum across balance types.
- Prefer `gl_metrics` / `v_trial_balance`; group `net_activity` by the `balance_type` dimension.

**Procurement Agent**
- "Spend" is ambiguous — surface ordered vs received vs invoiced before answering; use the spend-basis dimension.
- Exclude canceled/closed POs from spend (`CANCEL_FLAG`, `CLOSED_CODE`).
- Match-rule (2-/3-/4-way) is a customer deployment fact — confirm before reporting exceptions.

## Synonyms to seed

Seed these, then extend from the `<customer>-oracle-fusion-glossary` (the glossary wins on customer-specific terms):

| Business term | Canonical concept |
|---|---|
| "trial balance", "TB" | posted actual balances by account/period (`v_trial_balance` / `gl_metrics`) |
| "net activity", "movement", "period activity" | `net_activity` measure (period debits − credits, one balance type) |
| "actuals" | `ACTUAL_FLAG='A'`, posted |
| "budget", "plan" | `ACTUAL_FLAG='B'` + `BUDGET_VERSION_ID` |
| "cost center", "department", "natural account", "company" | the customer's segment per the **segment→meaning map** (never assumed) |
| "legal entity", "LE" | balancing-segment-value → LE assignment |
| "ledger", "set of books" | `GL_LEDGERS` / `LEDGER_ID` |
| "spend", "purchases" | procurement spend measure — **basis must be specified** (ordered/received/invoiced) |
| "PO", "purchase order" | `PO_HEADERS_ALL` (conformed PO view) |
| "supplier", "vendor" | `POZ_SUPPLIERS` (`VENDOR_ID`) |
| "requisition", "PR", "req" | `POR_REQUISITION_HEADERS_ALL` |
| "received", "GR", "receipts" | `QUANTITY_RECEIVED` on schedules |
| "invoiced", "billed" | `QUANTITY_BILLED` / payables (P2P boundary) |
| "blanket", "BPA", "contract PO" | `TYPE_LOOKUP_CODE` = BLANKET / CONTRACT |
| "three-way match", "match exception" | 3-way match: PO ↔ receipt ↔ invoice |

## Certified example questions -> SQL

Add these as Genie certified examples (pull the actual parameterized SQL from each module's `examples.sql`; shown here as intent so the canonical behavior is unambiguous):

**Finance**
1. *"Trial balance for OCT-25, primary ledger."* → `v_trial_balance` / `trial_balance(ledger, 'OCT-25')`, `ACTUAL_FLAG='A'`, posted-only, ledger currency, period via `v_gl_period`.
2. *"Actual vs budget variance by cost center this quarter."* → `gl_metrics` grouped by decoded cost-center segment and `balance_type`; budget pinned to a `BUDGET_VERSION_ID`; never sums across `ACTUAL_FLAG`.
3. *"Top 10 natural accounts by net activity this period."* → `net_activity` by decoded natural account (`v_code_combination`), one balance type, posted-only.
4. *"How many journals did Payables post last month?"* → `journal_count` by `JE_SOURCE='Payables'`, posted, period filter.
5. *"Show the journal lines behind the balance of account X."* → `v_gl_journal_enriched` filtered to the decoded account; drill from balance to lines (same grain, no GL+XLA mixing).

**Procurement / SCM**
6. *"Total spend by supplier last quarter."* → procurement spend metric view by supplier, **basis stated** (e.g. invoiced), BU-scoped, canceled excluded.
7. *"Open PO backlog by business unit."* → conformed PO view, open POs (not canceled/closed), grouped by `PRC_BU_ID`.
8. *"Spend by cost center this year."* → spend joined to `PO_DISTRIBUTIONS_ALL` CCID decoded via `v_code_combination`; accounted currency.
9. *"PO cycle time from requisition to PO."* → requisition view → PO view, req-to-PO duration.
10. *"Three-way-match exceptions this month."* → match UDF, customer match rule, PO ↔ receipt (`QUANTITY_RECEIVED`) ↔ invoice (`QUANTITY_BILLED`).

## Promotion checklist

Before the Agent goes to business users:
- [ ] `oracle-fusion-setup` complete: UC comments + segment→meaning map + glossary registered.
- [ ] Persona scope chosen (Finance **or** Procurement/SCM); only its object set + the shared keystone objects exposed.
- [ ] Metric view(s) + Trusted UDFs curated; no hand-written metric/accounting SQL.
- [ ] General instructions baked in (org scoping, posted-only, one `ACTUAL_FLAG`, accounted currency, period sort, CCID decode, spend basis).
- [ ] Synonyms seeded from the table above + glossary.
- [ ] Certified examples added from `examples.sql`.
- [ ] [sample-questions.md](sample-questions.md) benchmark run; meets the acceptance bar.
- [ ] Monitoring-tab re-curation pass scheduled.
