# Oracle Fusion — Ledger & Chart of Accounts Gotchas

## Contents

- 1. Accounts are CCIDs (integer keys), not strings
- 2. Segment meaning is customer config — never assume positions
- 3. Decode segment *values* to names via `FND_FLEX_VALUES_VL`
- 4. Entered vs accounted vs ledger currency — never sum `ENTERED` across currencies
- 5. Currency conversion: rate type + conversion date both matter
- 6. Order periods by `effective_period_number`, never by `PERIOD_NAME`
- 7. Period open/close is per-ledger — open periods are not final
- 8. Adjustment periods overlap normal-period dates
- 9. XLA rolls *up into* GL — one level only, never add them
- 10. Untransferred XLA entries aren't in GL yet
- 11. Balancing segment value ties a journal to a legal entity (consolidation)
- 12. Summary vs detail accounts — don't mix postable and rollup
- 13. Ledger category: primary vs secondary vs reporting-currency

The traps that silently produce wrong financials. Read before writing any non-trivial
accounting join. The `oracle-fusion-overview` skill carries the org-wide versions
(multi-org `_ALL` scoping, accounting-vs-transaction date, posted-vs-unposted); this
file owns the accounting-foundation mechanics.

## 1. Accounts are CCIDs (integer keys), not strings

Every journal line, balance, and subledger line stores the account as a
`CODE_COMBINATION_ID` (CCID) — **an integer surrogate key**, not a readable account
string. The human-readable account is `GL_CODE_COMBINATIONS.CONCATENATED_SEGMENTS`
(e.g. `100-30-4100-CC-001`).

```sql
-- WRONG — there is no account string on the line:
WHERE l.account = '100-30-4100-CC-001'

-- RIGHT — filter on the resolved CCID (or join to GL_CODE_COMBINATIONS):
JOIN :catalog.:silver_schema.GL_CODE_COMBINATIONS cc
  ON cc.code_combination_id = l.code_combination_id
WHERE cc.concatenated_segments = '100-30-4100-CC-001'
```

Because the CCID is an integer, two combinations that *look* alike (e.g. a disabled
old combination and a new one) are distinct CCIDs. Filter `ENABLED_FLAG = 'Y'` and the
`START_DATE_ACTIVE`/`END_DATE_ACTIVE` window for current-state reporting.

## 2. Segment meaning is customer config — never assume positions

`GL_CODE_COMBINATIONS` has `SEGMENT1..SEGMENT30`. **Which position is company vs cost
center vs natural account vs balancing segment is per-tenant chart-of-accounts
configuration.** `SEGMENT2` is *not* universally "cost center."

The segment→meaning map (and which segment is the **balancing segment** and which is
the **natural account**, which drives `ACCOUNT_TYPE`) lives in the
`<customer>-oracle-fusion-glossary` skill produced by `oracle-fusion-setup`. **Resolve
it there before writing any per-segment filter or GROUP BY.** Never hard-code a segment
position from the example in this skill.

If no glossary is installed, surface the question ("which segment is your natural
account / cost center / balancing segment?") rather than guessing.

## 3. Decode segment *values* to names via `FND_FLEX_VALUES_VL`

The `SEGMENTn` columns hold raw value codes (`100`, `4100`, …). Their **names** and
rollup hierarchy come from the key-flexfield value sets in `FND_FLEX_VALUES_VL` (the
`_VL` translated view). To show "Cost Center 30 = North Region Ops," join the segment
value to its value set's `FLEX_VALUE` → `DESCRIPTION`.

Each segment maps to a different `FLEX_VALUE_SET_ID`; that segment→value-set mapping is
COA config (glossary). The `v_code_combination` view pre-joins the *natural-account*
decode for convenience; deeper per-segment name decode composes `FND_FLEX_VALUES_VL`.

## 4. Entered vs accounted vs ledger currency — never sum `ENTERED` across currencies

GL and XLA lines carry **two** debit/credit pairs:

| Pair | Currency | Safe to sum? |
|---|---|---|
| `ENTERED_DR` / `ENTERED_CR` | Document currency (`CURRENCY_CODE` on the line) | **No — only within one currency.** A EUR row and a USD row both have `ENTERED_*` in their own currency; adding them is meaningless. |
| `ACCOUNTED_DR` / `ACCOUNTED_CR` | Ledger (functional) currency (`GL_LEDGERS.CURRENCY_CODE`) | Yes — already normalized to the ledger currency. |

**Cross-entity, multi-currency, and "total" figures must use `ACCOUNTED_*`.** Use
`ENTERED_*` only when the user explicitly wants document-currency detail for a single
currency. Under FDI there may additionally be an *analytics/reporting* currency basis —
confirm which basis the question means (surfaced in SKILL.md *Questions to surface
first*).

## 5. Currency conversion: rate type + conversion date both matter

When you must convert to a currency that is **not** the ledger currency (e.g. a group
reporting currency), use `GL_DAILY_RATES` — and it is keyed on **four** things:
`(FROM_CURRENCY, TO_CURRENCY, CONVERSION_DATE, CONVERSION_TYPE)`.

- **Rate type matters.** Seeded types are `Spot`, `Corporate`, `User`, `Fixed`; the same
  day's USD→EUR rate differs by type. Confirm which type the metric uses; don't default
  silently. `convert_to_ledger_currency` takes the rate type as a parameter for this
  reason.
- **Conversion date matters.** Match the transaction's accounting/conversion date, not
  `current_date()`. A missing (date, type) rate row yields no conversion — handle the
  gap (a `oracle-fusion-data-quality` concern), don't silently drop rows.

## 6. Order periods by `effective_period_number`, never by `PERIOD_NAME`

`PERIOD_NAME` (e.g. `Jan-25`, `Feb-25`) **does not sort chronologically as a string** —
`Apr-25` < `Jan-25` alphabetically. Always derive and sort by the effective period
number:

```sql
(p.period_year * 10000 + p.period_num) AS effective_period_number
```

Use it for ORDER BY, for "last 6 periods" ranges, and for "as-of period" comparisons.
The `v_gl_period` view exposes it as `effective_period_number`. This is also why "the
period before `Mar-25`" must be resolved by number, not by string math on the name.

## 7. Period open/close is per-ledger — open periods are not final

`GL_PERIOD_STATUSES` holds a `CLOSING_STATUS` **per ledger + period**. The same
`PERIOD_NAME` can be `O` (Open) in one ledger and `C` (Closed) in another, so **always
filter by `LEDGER_ID`** when checking status.

| Status | Code | Meaning for analytics |
|---|---|---|
| Open | `O` | Postings still allowed — **numbers can change.** `is_period_open` returns TRUE only for this. |
| Closed | `C` | No new postings without reopening — numbers are final-ish. |
| Future Enterable | `F` | Not yet the live period; entry permitted ahead. |
| Never Opened | `N` | No activity. |
| Permanently Closed | `P` | Locked. |
| Close Pending | `W` | Closing in progress. |

If a user asks for "final" actuals, restrict to closed periods (or warn that an open
period is still moving). Don't treat an open period's balance as settled.

## 8. Adjustment periods overlap normal-period dates

`GL_PERIODS.ADJUSTMENT_PERIOD_FLAG = 'Y'` marks **adjusting periods** (e.g. `Adj-25`,
year-end true-ups) whose `START_DATE`/`END_DATE` **overlap the calendar dates of normal
periods.** If you bucket by *date*, an adjustment-period entry can fall into both the
adjustment period and the normal month — double-counting.

- When summing by `PERIOD_NAME`, this is fine (they're distinct names).
- When summing by *date range*, decide explicitly whether adjustment periods are in or
  out, and filter `ADJUSTMENT_PERIOD_FLAG` accordingly. `period_for_date` returns a
  non-adjustment period by default — confirm if the user wants adjustment periods.

## 9. XLA rolls *up into* GL — one level only, never add them

Subledger transactions (AP invoices, AR receipts, PO receipts, costing) are accounted
by the **Create Accounting** process into `XLA_AE_HEADERS` → `XLA_AE_LINES`, then
**transferred and summarized into `GL_JE_LINES`.** The same money exists at both levels.

```
Subledger txn → XLA_AE_HEADERS → XLA_AE_LINES  --(GL_SL_LINK_ID)-->  GL_JE_LINES → GL_BALANCES
                       (transaction detail)                          (summarized posted GL)
```

**Pick one level for any total:**
- **GL** (`GL_JE_LINES` / `GL_BALANCES`) for summarized posted numbers and trial
  balance.
- **XLA** (`XLA_AE_LINES`) for transaction-level detail with the originating document.

Adding a GL journal amount to an XLA line amount **double-counts.** To *reconcile* the
two (prove they agree), join on **both** `GL_SL_LINK_ID` **and** `GL_SL_LINK_TABLE`
(see examples.sql) — that is a comparison, not a sum of both.

## 10. Untransferred XLA entries aren't in GL yet

`XLA_AE_HEADERS.GL_TRANSFER_STATUS_CODE` indicates whether an entry has been transferred
to GL. **Untransferred entries exist in XLA but not in `GL_JE_LINES`/`GL_BALANCES`.** So:

- A GL-only total will *understate* recent subledger activity that hasn't transferred.
- An XLA-vs-GL reconciliation must account for in-flight (untransferred) entries, not
  treat the difference as an error.

Filter on transfer/accounting-entry status deliberately when reconciling.

## 11. Balancing segment value ties a journal to a legal entity (consolidation)

There is usually **no raw `LEGAL_ENTITY_ID` on a GL journal line.** "By legal entity"
and consolidation reporting key off the **balancing segment value (BSV) → legal entity**
assignment:

1. Read the **BSV** from the balancing-segment position of the CCID (which `SEGMENTn`
   that is = customer config, gotcha 2).
2. Map BSV → LE via the assignment metadata (`GL_LEGAL_ENTITIES_BSV`, glossary).

So a "revenue by legal entity" query decodes the balancing segment per CCID, joins to
the BSV→LE map, then aggregates. Don't look for an LE column on the line.

## 12. Summary vs detail accounts — don't mix postable and rollup

`GL_CODE_COMBINATIONS` carries two flags that change what a row *is*:

- `DETAIL_POSTING_ALLOWED_FLAG = 'Y'` → a **detail** account you can post to.
- `SUMMARY_FLAG = 'Y'` → a **summary** (parent/rollup) combination built over a summary
  template. Balances may exist at summary level for fast rollup reporting.

**Never sum summary and detail rows together** — you'd count the detail once and again
inside its summary parent. For transactional analytics, restrict to
`DETAIL_POSTING_ALLOWED_FLAG = 'Y'` (postable) accounts unless the user explicitly wants
the summary rollups.

## 13. Ledger category: primary vs secondary vs reporting-currency

`GL_LEDGERS.LEDGER_CATEGORY_CODE` distinguishes `PRIMARY`, `SECONDARY`, and `ALC`
(reporting/analytics-currency) ledgers. A primary ledger and its reporting-currency
ledger hold **the same transactions in different currencies** — summing across them
double-counts. Scope to a single ledger (or a deliberate ledger set) for any total;
confirm which ledger basis the user means (SKILL.md *Questions to surface first*).
