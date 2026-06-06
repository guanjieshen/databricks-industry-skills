# Oracle Fusion General Ledger — Schema Reference

Canonical column reference for the GL journal and balance tables. Table/column names follow the **E-Business Suite-derived canonical model** (`GL_JE_HEADERS`, `GL_BALANCES`, …) that Fusion's underlying physical tables keep almost verbatim. Column lists are the most commonly used columns, not exhaustive — customers carry additional descriptive flexfield (`ATTRIBUTE1..n`) and audit columns.

**Landing-pattern note (read once).** Fusion Cloud is SaaS — there is no raw-table access. What lands in the lakehouse is **BICC Public View Objects (PVOs)** (e.g. `JournalSourceExtractPVO`, `GlBalancesExtractPVO`) or **Fusion Data Intelligence (FDI)** star-schema artifacts, with **different physical names** from the canonical model below. The meaning is identical; the names vary by customer. This file describes the canonical model — **the physical→canonical mapping for THIS customer lives in the `<customer>-oracle-fusion-glossary`** produced by `oracle-fusion-setup`. Always resolve a physical name via the glossary before binding it into a query; never promise raw-table access. (Landing-agnostic rule — see `oracle-fusion-overview`.)

Catalog/schema is customer-specific. SQL uses Databricks-native parameter placeholders — `:catalog`, `:silver_schema` (the canonical GL layer), `:gold_schema` (Trusted UDFs / metric view). Bind at execution / registration. Columns marked *(inferred)* should be verified against the glossary at build time — exact names vary by extract.

## Contents

- The journal hierarchy: `GL_JE_BATCHES` → `GL_JE_HEADERS` → `GL_JE_LINES`
- `GL_JE_BATCHES` — journal batch
- `GL_JE_HEADERS` — journal entry header
- `GL_JE_LINES` — journal entry line
- `GL_BALANCES` — account balances (actual / budget / encumbrance)
- How journals reconcile to balances
- Keystone tables this skill joins to (not detailed here)
- Cardinality summary

## The journal hierarchy: `GL_JE_BATCHES` → `GL_JE_HEADERS` → `GL_JE_LINES`

A posted journal is a three-level tree: a **batch** groups one or more **headers** (the actual journal entries), and each header has many **lines** (the debit/credit detail against code combinations). Posting is a batch-level event; `STATUS = 'P'` propagates to headers and lines.

## `GL_JE_BATCHES` — journal batch

One row per journal batch. The unit of posting and the link to the source/period context.

| Column | Type | Notes |
|---|---|---|
| `JE_BATCH_ID` | BIGINT | PK — batch surrogate key |
| `NAME` | STRING | Batch name |
| `LEDGER_ID` | BIGINT | FK to `GL_LEDGERS` (keystone). **Scope every query by ledger.** |
| `STATUS` | STRING | `'P'` = Posted, `'U'` = Unposted, `'S'`/`'I'` = in-process. Financials use Posted only (gotcha: posted-only). |
| `DEFAULT_PERIOD_NAME` | STRING | Default accounting period for the batch |
| `POSTED_DATE` | TIMESTAMP | When the batch posted |
| `ACTUAL_FLAG` | STRING | `'A'` Actual / `'B'` Budget / `'E'` Encumbrance — propagates to headers/lines. **Never aggregate across values** (gotcha 1). |
| `RUNNING_TOTAL_ACCOUNTED_DR` / `_CR` | DECIMAL | Batch control totals (accounted/ledger currency) |

## `GL_JE_HEADERS` — journal entry header

One row per journal entry. The grain for "journal count / volume" and the carrier of source/category/period/currency.

| Column | Type | Notes |
|---|---|---|
| `JE_HEADER_ID` | BIGINT | PK — header surrogate key |
| `JE_BATCH_ID` | BIGINT | FK to `GL_JE_BATCHES` |
| `LEDGER_ID` | BIGINT | FK to `GL_LEDGERS` (keystone). Always scope by ledger. |
| `NAME` | STRING | Journal name |
| `JE_SOURCE` | STRING | Origin of the entry — e.g. `Manual`, `Payables`, `Receivables`, `Spreadsheet`, `Revaluation`, `Cost Management`. Use for journal volume by source. |
| `JE_CATEGORY` | STRING | Category within source — e.g. `Purchase Invoices`, `Adjustment`, `Reclass`. |
| `PERIOD_NAME` | STRING | Accounting period (e.g. `OCT-25`). **Order by the keystone's effective-period-number sort key, never alphabetically** (gotcha 4). |
| `CURRENCY_CODE` | STRING | Document/entered currency of the entry |
| `STATUS` | STRING | `'P'` = Posted, `'U'` = Unposted. **Financials filter `STATUS = 'P'`** (gotcha 2). |
| `ACTUAL_FLAG` | STRING | `'A'` Actual / `'B'` Budget / `'E'` Encumbrance. **Pin to one value** (gotcha 1). |
| `BUDGET_VERSION_ID` | BIGINT | Required when `ACTUAL_FLAG = 'B'` — which budget version. |
| `ENCUMBRANCE_TYPE_ID` | BIGINT | Required when `ACTUAL_FLAG = 'E'`. |
| `DEFAULT_EFFECTIVE_DATE` | DATE | Accounting/effective date of the entry — the date most "GL date" metrics mean (vs the source transaction date). |
| `POSTED_DATE` | TIMESTAMP | When the entry posted |
| `RUNNING_TOTAL_ACCOUNTED_DR` / `_CR` | DECIMAL | Header control totals (ledger currency) |

## `GL_JE_LINES` — journal entry line

One row per debit/credit line against a code combination. The grain for "journal line count" and the lowest level of journal-side activity.

| Column | Type | Notes |
|---|---|---|
| `JE_HEADER_ID` | BIGINT | FK to `GL_JE_HEADERS` (composite PK with `JE_LINE_NUM`) |
| `JE_LINE_NUM` | INT | Line number within the header |
| `LEDGER_ID` | BIGINT | FK to `GL_LEDGERS` (keystone) |
| `CODE_COMBINATION_ID` | BIGINT | FK to `GL_CODE_COMBINATIONS` (keystone). **A key, not a readable account — decode via `v_code_combination`** (gotcha 5). |
| `PERIOD_NAME` | STRING | Accounting period (denormalized from header) |
| `ENTERED_DR` / `ENTERED_CR` | DECIMAL | Debit / credit in **document (entered) currency**. Never sum across currencies (gotcha 3). |
| `ACCOUNTED_DR` / `ACCOUNTED_CR` | DECIMAL | Debit / credit in **ledger (accounted) currency** — use these for cross-account/ledger totals (gotcha 3). |
| `STATUS` | STRING | `'P'` Posted / `'U'` Unposted (mirrors header) |
| `DESCRIPTION` | STRING | Line description |
| `GL_SL_LINK_ID` | BIGINT | Link to the originating subledger line (`XLA_AE_LINES`) — the XLA→GL bridge owned by the keystone. *(inferred — confirm name via glossary)* |

**Activity Amount convention:** journal-side net activity for a line = `ACCOUNTED_DR - ACCOUNTED_CR` (entered basis: `ENTERED_DR - ENTERED_CR`). A debit is positive, a credit negative. Aggregate this per account/period for "net activity" — and only within one `ACTUAL_FLAG`.

## `GL_BALANCES` — account balances (actual / budget / encumbrance)

Stores **period balances** per ledger + code combination + currency + period + balance type, for both detail and summary accounts. This is the source for trial balance and account-balance reporting — it is *not* the same grain as journal lines (see reconciliation note).

| Column | Type | Notes |
|---|---|---|
| `LEDGER_ID` | BIGINT | FK to `GL_LEDGERS` (keystone) |
| `CODE_COMBINATION_ID` | BIGINT | FK to `GL_CODE_COMBINATIONS` (keystone) — decode via `v_code_combination` (gotcha 5) |
| `CURRENCY_CODE` | STRING | Currency of this balance row. Pick the basis deliberately (gotcha 3). |
| `PERIOD_NAME` | STRING | Accounting period. Order by the keystone sort key (gotcha 4). |
| `ACTUAL_FLAG` | STRING | `'A'` Actual / `'B'` Budget / `'E'` Encumbrance. **Never sum across values** (gotcha 1). |
| `BUDGET_VERSION_ID` | BIGINT | Set when `ACTUAL_FLAG = 'B'` |
| `ENCUMBRANCE_TYPE_ID` | BIGINT | Set when `ACTUAL_FLAG = 'E'` |
| `BEGIN_BALANCE_DR` / `BEGIN_BALANCE_CR` | DECIMAL | Opening balance for the period (debit / credit) |
| `PERIOD_NET_DR` / `PERIOD_NET_CR` | DECIMAL | Net debit / credit activity within the period |
| `TRANSLATED_FLAG` | STRING | Marks translated (reporting-currency) balances. `'Y'`/`'R'` vs untranslated — filter deliberately so you don't mix translated with primary-currency balances (gotcha: translated balances). *(inferred — confirm name/values via glossary)* |
| `PERIOD_TYPE` | STRING | Calendar period type *(inferred — confirm via glossary)* |

**Trial-balance math:** ending balance for an account in a period = `(BEGIN_BALANCE_DR - BEGIN_BALANCE_CR) + (PERIOD_NET_DR - PERIOD_NET_CR)`, filtered to one `LEDGER_ID`, one `CURRENCY_CODE` basis, one `PERIOD_NAME`, `ACTUAL_FLAG = 'A'`, posted. Group/decode by account via the keystone.

## How journals reconcile to balances

`GL_BALANCES` is the *summarized* result of posting `GL_JE_LINES`; the two reconcile but are **different grains**. For one ledger/CCID/period/currency/balance-type, `SUM(PERIOD_NET_DR - PERIOD_NET_CR)` in balances should equal `SUM(ACCOUNTED_DR - ACCOUNTED_CR)` of posted lines for that period. Use **balances** for trial-balance / point-in-time reporting; use **journal lines** for "show me the entries behind this number". **Never add the two together** — that double-counts (see gotchas.md, balances-vs-journals reconciliation).

## Keystone tables this skill joins to (not detailed here)

Owned and documented by `oracle-fusion-ledger-coa` — load it for their schema:

- `GL_LEDGERS` — ledger definitions (the 4 Cs). FK `LEDGER_ID` everywhere above.
- `GL_CODE_COMBINATIONS` — account combinations; decode a `CODE_COMBINATION_ID` to segment values/names via the keystone's `v_code_combination` / `decode_ccid_segments`. The balancing segment value ties an account to a legal entity.
- `GL_PERIODS` / `GL_PERIOD_STATUSES` — accounting calendar + open/close status; chronological order and "as-of period" come from the keystone's `v_gl_period` / `period_for_date` / `is_period_open`.
- `GL_DAILY_RATES` — currency conversion rates; use the keystone's `convert_to_ledger_currency`, never hand-rolled rate math.
- `XLA_AE_HEADERS` / `XLA_AE_LINES` — subledger detail behind a journal, via `GL_SL_LINK_ID` (the XLA→GL bridge). One level only — don't add to GL.

## Cardinality summary

| Relationship | Cardinality |
|---|---|
| `GL_JE_BATCHES` → `GL_JE_HEADERS` | 1:N |
| `GL_JE_HEADERS` → `GL_JE_LINES` | 1:N |
| `GL_JE_LINES` → `GL_CODE_COMBINATIONS` | N:1 (via `CODE_COMBINATION_ID`) |
| `GL_JE_LINES` → `XLA_AE_LINES` | N:1 / 1:1 (via `GL_SL_LINK_ID`; only for subledger-sourced lines) |
| `GL_BALANCES` → `GL_CODE_COMBINATIONS` | N:1 |
| `GL_BALANCES` → `GL_LEDGERS` | N:1 |
| `GL_BALANCES` ↔ `GL_JE_LINES` | reconcile by ledger/CCID/period/currency/flag — **do not union or sum together** |
| `GL_*` → `GL_LEDGERS` | N:1 (via `LEDGER_ID`) |
