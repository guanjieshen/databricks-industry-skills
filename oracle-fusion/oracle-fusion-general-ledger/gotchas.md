# Oracle Fusion General Ledger — Gotchas

## Contents

- 1. Never aggregate across `ACTUAL_FLAG` (A / B / E are different balance types)
- 2. Posted vs unposted — financials are posted-only
- 3. Currency basis: entered vs accounted vs translated
- 4. Period ordering and period status
- 5. A CCID is a key, not a readable account
- 6. Balances vs journals — reconcile, never sum together
- 7. Summary vs detail accounts — don't double-count rollups
- 8. Translated balances are a separate population
- 9. `JE_SOURCE` / `JE_CATEGORY` and what "manual" means
- 10. Activity Amount sign convention and the debit/credit balance

The traps that will silently produce wrong financials. The keystone `oracle-fusion-ledger-coa` owns segment/currency/period *mechanics* (the UDFs/views); the overview owns the org-wide ones. Read this before writing any non-trivial GL query.

## 1. Never aggregate across `ACTUAL_FLAG` (A / B / E are different balance types)

`ACTUAL_FLAG` on `GL_JE_BATCHES` / `GL_JE_HEADERS` / `GL_BALANCES` partitions the data into three **incompatible balance types**:

| `ACTUAL_FLAG` | Meaning | Extra key required |
|---|---|---|
| `A` | Actual — real posted accounting | — |
| `B` | Budget | `BUDGET_VERSION_ID` (which budget) |
| `E` | Encumbrance | `ENCUMBRANCE_TYPE_ID` (commitment/obligation type) |

Summing across them is meaningless (you'd add a budget to an actual). **Every GL aggregate must pin `ACTUAL_FLAG` to exactly one value.** Actual-vs-budget is a *comparison of two filtered populations* for the same accounts/periods — not a sum.

```sql
-- WRONG — mixes actual + budget + encumbrance:
SELECT code_combination_id, SUM(period_net_dr - period_net_cr) AS net
FROM :catalog.:silver_schema.GL_BALANCES
WHERE ledger_id = :ledger_id AND period_name = :period_name
GROUP BY code_combination_id;

-- RIGHT — actuals only:
SELECT code_combination_id, SUM(period_net_dr - period_net_cr) AS net
FROM :catalog.:silver_schema.GL_BALANCES
WHERE ledger_id = :ledger_id AND period_name = :period_name
  AND actual_flag = 'A'
GROUP BY code_combination_id;
```

For budget, also pin `budget_version_id = :budget_version_id`; for encumbrance, `encumbrance_type_id = :encumbrance_type_id`. In the metric view, expose `balance_type` as a dimension and instruct the agent to always group `net_activity` by it — that structurally prevents the cross-type sum.

## 2. Posted vs unposted — financials are posted-only

`GL_JE_HEADERS.STATUS` (and `GL_JE_LINES.STATUS`, `GL_JE_BATCHES.STATUS`) is `'P'` Posted or `'U'` Unposted (with transient in-process states). **Unposted entries are not in the books.** Trial balance, account balances, and any "actuals" number must filter `STATUS = 'P'`.

`GL_BALANCES` only reflects *posted* activity, so balance-based queries are inherently posted-only — but the moment you drop to `GL_JE_LINES` for detail you must add `STATUS = 'P'` yourself, or unposted drafts leak into the total. Conversely, if the user is doing a *pre-close review* ("what's pending posting?"), that's the one case where `STATUS = 'U'` is the point — confirm intent.

## 3. Currency basis: entered vs accounted vs translated

Three different "amounts" exist and answer different questions (the keystone owns conversion; this is the GL-table-specific framing):

- **Entered** (`ENTERED_DR/CR` on lines) — the document/transaction currency. Valid per-currency, **never summed across currencies**.
- **Accounted** (`ACCOUNTED_DR/CR` on lines) — the ledger currency. Use for any cross-account / cross-entity total within a ledger.
- **Balance `CURRENCY_CODE`** (`GL_BALANCES`) — balances are stored per currency; the ledger-currency rows are the trial-balance basis. Translated/reporting-currency rows are flagged separately (gotcha 8).

To convert an entered amount to ledger currency, call the keystone's `convert_to_ledger_currency` — do **not** hand-roll `GL_DAILY_RATES` math (rate type + conversion date selection is subtle and owned there).

## 4. Period ordering and period status

`PERIOD_NAME` is a label (`'OCT-25'`), not a sortable key — `'APR-25'` sorts before `'JAN-25'` alphabetically, silently scrambling any trend or "latest period" logic. **Order chronologically by the keystone's effective-period-number key** (`PERIOD_YEAR*10000 + PERIOD_NUM`, exposed by `v_gl_period`).

Period **status** matters too: an *open* period is not final (numbers still move), and "as-of period X" must respect the accounting calendar. Use the keystone's `is_period_open` and `period_for_date` rather than reasoning about period names. A trial balance for an open period is a snapshot, not a closed-book figure — say so.

## 5. A CCID is a key, not a readable account

`CODE_COMBINATION_ID` on lines and balances is a surrogate key into `GL_CODE_COMBINATIONS`. Grouping or filtering on the raw CCID gives you opaque integers, and the natural-account / cost-center / company **segment positions are per-tenant configuration** — `SEGMENT2` is not necessarily cost center.

Always decode via the keystone's `v_code_combination` (CCID + decoded segments + names) or `decode_ccid_segments`, and resolve which segment is which via the workspace glossary. "Balance by cost center" / "by natural account" / "by legal entity (balancing segment)" all depend on this decode — `v_gl_journal_enriched` and `v_trial_balance` in this skill already join `v_code_combination` so you get readable segments for free.

## 6. Balances vs journals — reconcile, never sum together

`GL_BALANCES` is the *summarized* posting result; `GL_JE_LINES` is the *detail*. They tie out (per ledger/CCID/period/currency/balance-type, `SUM(period_net_dr - period_net_cr)` ≈ `SUM(accounted_dr - accounted_cr)` of posted lines) but are **different grains**. Adding a balance row to its own underlying journal lines double-counts.

Rule of thumb:
- **Trial balance / point-in-time / "what's the balance"** → `GL_BALANCES` (it already includes opening balance, which journal lines alone don't).
- **"Show me the entries behind this number" / journal volume / line-level drill** → `GL_JE_HEADERS` / `GL_JE_LINES`.

Likewise, never add `GL_JE_LINES` to `XLA_AE_LINES` (subledger detail) — XLA rolls *up into* GL via `GL_SL_LINK_ID` (keystone, one level only).

## 7. Summary vs detail accounts — don't double-count rollups

`GL_BALANCES` stores balances for **both detail and summary (parent) accounts**. Summary accounts are rollups of detail accounts; if you sum a population that contains both, you double-count the detail. A trial balance is built from **detail (posting-allowed) accounts only** — filter via the keystone's account attribute (`DETAIL_POSTING_ALLOWED_FLAG` on `GL_CODE_COMBINATIONS`) before aggregating, or scope to detail CCIDs explicitly. When the user wants a rollup, use the account hierarchy deliberately, not a blind `SUM` over all balance rows.

## 8. Translated balances are a separate population

When a ledger is translated/revalued to a reporting currency, `GL_BALANCES` carries additional rows flagged via `TRANSLATED_FLAG` (and a different `CURRENCY_CODE`). These represent the *same* accounting restated in another currency — **mixing translated and primary-currency rows double-counts and conflates bases.** Decide explicitly whether the question wants primary-ledger-currency balances (the usual trial balance) or translated reporting-currency balances, and filter `TRANSLATED_FLAG` / `CURRENCY_CODE` accordingly. (Column name/values vary by extract — confirm via the glossary; marked inferred in schema.md.)

## 9. `JE_SOURCE` / `JE_CATEGORY` and what "manual" means

`JE_SOURCE` identifies where a journal came from — `Manual`, `Spreadsheet` (ADFdi), `Payables`, `Receivables`, `Cost Management`, `Revaluation`, `Translation`, etc. `JE_CATEGORY` sub-classifies within a source. For "journal volume by source" or "manual-journal review" these are the grouping columns.

Two cautions:
- Source values are configurable/extensible — a customer may rename or add sources. Confirm the set that exists (glossary) before hard-coding `JE_SOURCE = 'Manual'`.
- Subledger sources (`Payables`, `Receivables`, `Cost Management`) are GL representations of XLA-transferred activity. Counting "Payables journals" in GL is fine for *journal volume*, but for *invoice-level* detail go to the subledger via the keystone's XLA bridge — don't conflate journal count with document count.

## 10. Activity Amount sign convention and the debit/credit balance

Net activity (the "Activity Amount") for an account = **Debit − Credit**. On journal lines that is `ACCOUNTED_DR - ACCOUNTED_CR` (or `ENTERED_DR - ENTERED_CR` on the entered basis); on balances the period movement is `PERIOD_NET_DR - PERIOD_NET_CR` and the running balance adds `BEGIN_BALANCE_DR - BEGIN_BALANCE_CR`.

Sign by account nature: assets/expenses carry **debit** (positive) balances, liabilities/equity/revenue carry **credit** (negative under this convention) balances. A correct, fully-posted trial balance nets to **zero** across all accounts in a ledger for a balance type — if it doesn't, suspect a missing posted population, a currency-basis mix, an `ACTUAL_FLAG` leak, or unposted lines (a `oracle-fusion-data-quality` question). Don't take the absolute value or flip signs to "make it look right" — present Debit and Credit columns and let the natural sign stand.
