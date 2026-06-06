# Fusion Genie Agent benchmark — sample questions

A starter set to measure whether a Fusion **Genie Agent** answers correctly. Ask each question in the Agent, then score against the expected canonical behavior. Add the customer's own real questions (especially misses from the Monitoring tab) over time. Run against the persona-appropriate Agent (Finance or Procurement/SCM); see [curation.md](curation.md) for the object sets.

## Contents
- How to score
- Finance — GL / trial balance / actual-vs-budget
- Procurement / SCM — spend / POs / suppliers / match
- Ambiguity (Agent should ASK, not guess)
- Cross-cutting / traps
- A note on confident-wrong answers

## How to score

For each question, the answer **passes** only if it: uses the right view / metric view / Trusted UDF (not hand-written SQL), applies the universal gotchas (scope `_ALL` by BU/ledger; posted-only `STATUS='P'`; pin one `ACTUAL_FLAG`; accounted not entered currency; period sort by effective number; decode CCIDs via the keystone, never assume segment positions; spend basis explicit; no GL+XLA mixing), resolves the customer's business terms via the glossary, and returns the number a Fusion SME would accept. A confident wrong answer is the worst outcome — log it. (See `oracle-fusion-overview` and the keystone for what each mechanic means.)

| Score | Meaning |
|---|---|
| Pass | Correct object, scope, filters, currency basis, and result |
| Partial | Right approach, wrong filter/term/basis (fix glossary, instruction, or example) |
| Fail | Wrong object/metric, mixed balance types/currencies, undecoded CCID, or fabricated columns (fix UC comment / segment map / certified example) |

## Finance — GL / trial balance / actual-vs-budget

- "Trial balance for OCT-25." → `v_trial_balance` / `trial_balance`, `ACTUAL_FLAG='A'`, **posted-only**, ledger currency, period resolved via `v_gl_period` (not alphabetical).
- "What's the balance of account X this period?" → decode account via `v_code_combination`; `account_balance`; posted, one balance type, stated currency basis.
- "Actual vs budget variance by cost center this quarter." → `gl_metrics` by decoded cost-center segment + `balance_type`; budget pinned to a `BUDGET_VERSION_ID`; **never sums across `ACTUAL_FLAG`**.
- "Top 10 natural accounts by net activity this period." → `net_activity` by decoded natural account; one balance type; posted-only.
- "How many journals did Payables post last month?" → `journal_count`, `JE_SOURCE='Payables'`, posted, period filter.
- "Show the journal lines behind account X's balance." → `v_gl_journal_enriched` for the decoded account; drills balance→lines without adding GL to XLA detail.

## Procurement / SCM — spend / POs / suppliers / match

- "Total spend by supplier last quarter." → procurement spend metric view by supplier, BU-scoped, **basis stated**, canceled POs excluded.
- "Open PO backlog by business unit." → conformed PO view, open (not `CANCEL_FLAG`/`CLOSED_CODE`), grouped by `PRC_BU_ID`.
- "Spend by cost center this year." → spend joined to `PO_DISTRIBUTIONS_ALL` CCID decoded via `v_code_combination`; accounted currency.
- "PO cycle time from requisition to PO." → requisition view → PO view duration.
- "Top suppliers by blanket-agreement usage." → `TYPE_LOOKUP_CODE` = BLANKET; supplier rollup via `POZ_SUPPLIERS`.

## Ambiguity (Agent should ASK, not guess)

These have no defensible default — a **Pass** means the Agent surfaces the question rather than silently picking:

- "What's our total spend this year?" → must surface the **spend-definition** ambiguity (ordered vs received vs invoiced) before answering; does not silently pick a basis.
- "Show me the match exceptions." → must surface the **match-rule** question (2-way / 3-way / 4-way is a customer deployment fact) before reporting.
- "Give me the balance for the company." → must surface **balance type** (actual/budget/encumbrance) and **currency basis** (entered/accounted/translated), and confirm which segment value means "company" via the segment map.
- "What were our results last quarter?" → must clarify ledger / currency basis / posted-only and which period, not assume.

## Cross-cutting / traps (these catch the common failures)

- "How much did we spend?" → must scope `_ALL` by BU/ledger and state the spend basis; never an unscoped multi-org sum.
- "Total revenue this year." → posted-only, one `ACTUAL_FLAG`, accounted currency; "revenue" resolved to the customer's natural-account range via the glossary, not a guess.
- "Balance by cost center." → decode CCID via `v_code_combination`; **does not assume `SEGMENT2` = cost center** (segment meaning is customer config).
- "Convert this balance to USD." → uses the keystone `convert_to_ledger_currency` (`GL_DAILY_RATES`, rate type + date); does not hand-roll rate math or sum `ENTERED` across currencies.
- "Trend by month: APR, JAN, …" → periods ordered by effective period number (`v_gl_period`), never alphabetically by `PERIOD_NAME`.
- A question using a customer term not in the glossary → Agent should ask, not guess.

## A note on confident-wrong answers

The dangerous Fusion failures are **invisible**: a balance that silently summed actual + budget, a "spend" total that mixed business units or used the wrong basis, a "by cost center" grouping on an undecoded or wrong segment. These look plausible and pass a glance. Always confirm the Agent applied the governed asset and the right scope — log any confident-wrong answer as a new benchmark case and fix the UC comment / segment map / certified example.
