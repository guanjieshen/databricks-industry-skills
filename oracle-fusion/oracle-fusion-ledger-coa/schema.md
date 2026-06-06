# Oracle Fusion — Ledger & Chart of Accounts Schema Reference

Canonical reference for the Fusion accounting-foundation entities every financial
question joins to: the ledger / legal-entity / business-unit org model, the chart
of accounts (`GL_CODE_COMBINATIONS`), the accounting calendar
(`GL_PERIODS` / `GL_PERIOD_STATUSES`), currency rates (`GL_DAILY_RATES`), and the
subledger-accounting bridge to GL (`XLA_AE_HEADERS` / `XLA_AE_LINES`).

Column lists below are the most commonly used columns, not exhaustive — Fusion
carries many more attributes and customer descriptive flexfields (DFFs). Types are
the canonical Oracle types; in a Delta mirror they land as the nearest Spark type
(`NUMBER` → `DECIMAL`/`BIGINT`, `VARCHAR2` → `STRING`, `DATE` → `DATE`/`TIMESTAMP`).

> **Landing-pattern note (read first).** These names are the **canonical** Fusion
> physical model — Fusion keeps the E-Business Suite table/column names almost
> verbatim under the covers. **What a customer actually receives is NOT these
> tables.** Fusion Cloud is SaaS; analytics data arrives as **BICC Public View
> Object (PVO)** extracts or as **Fusion Data Intelligence (FDI/FAW)** star-schema
> artifacts, with different physical names (e.g. a `GL_CODE_COMBINATIONS`-shaped
> PVO might land as `GlCodeCombinationsExtractPVO`, and under FDI the same data
> appears as a `Dim - GL Account` dimension). The **physical→canonical mapping for
> THIS customer lives in the `<customer>-oracle-fusion-glossary` skill** produced by
> `oracle-fusion-setup`. Resolve every physical name there before binding a query;
> never hard-code one of the names below, and never imply raw-table SaaS access.

Catalog/schema is customer-specific. SQL across this skill uses Databricks-native
parameter placeholders — `:catalog`, `:silver_schema` (the canonical GL/XLA mirror),
`:gold_schema` (Trusted UDFs). Bind at execution / registration.

## Contents

- The org model (Ledger / Legal Entity / Business Unit / BSV)
- `GL_LEDGERS` — ledger definitions (the "4 Cs")
- `GL_CODE_COMBINATIONS` — chart-of-accounts combinations (CCID)
- `GL_PERIODS` — accounting calendar
- `GL_PERIOD_STATUSES` — period open/close status per ledger
- `GL_DAILY_RATES` — currency conversion rates
- `XLA_AE_HEADERS` — subledger accounting entry headers
- `XLA_AE_LINES` — subledger accounting entry lines (the GL bridge)
- LE / BU / BSV assignment metadata
- Segment-value decode (`FND_FLEX_VALUES_VL`)
- Cardinality summary

## The org model (Ledger / Legal Entity / Business Unit / BSV)

Every GL/XLA row is scoped by an org structure Genie must respect. The
`oracle-fusion-overview` skill owns the narrative; this is the schema-level summary.

- **Ledger** (`GL_LEDGERS`, PK `LEDGER_ID`) — the central accounting context,
  defined by the **4 Cs: Chart of accounts, Calendar, Currency, Accounting method.**
  `LEDGER_ID` is the FK on virtually every GL and XLA row.
- **Legal Entity (LE)** — the legally-registered org. An LE is assigned to a ledger;
  **balancing segment values (BSVs) are assigned to legal entities**, and that is how a
  journal's balancing segment ties back to an LE (there is usually no raw `LE_ID`
  column on the journal line — you resolve it through the BSV).
- **Business Unit (BU)** — the operational division. **Fusion's BU ≈ E-Business Suite
  "Operating Unit."** A BU connects to a primary ledger + a default LE. Transactional
  `_ALL` tables are multi-org and scoped by BU.

## `GL_LEDGERS` — ledger definitions (the "4 Cs")

One row per ledger (primary, secondary, or reporting-currency). The anchor of every
financial query's currency/calendar/COA context.

| Column | Type | Notes |
|---|---|---|
| `LEDGER_ID` | NUMBER | PK. FK `LEDGER_ID` appears on GL_PERIOD_STATUSES, GL_BALANCES, GL_JE_HEADERS, XLA rows. |
| `NAME` | VARCHAR2 | Ledger name (e.g. `US Primary Ledger`). |
| `SHORT_NAME` | VARCHAR2 | Short ledger name. |
| `LEDGER_CATEGORY_CODE` | VARCHAR2 | `PRIMARY` / `SECONDARY` / `ALC` (reporting/analytics currency). Don't sum a primary and its reporting-currency ledger together. |
| `CHART_OF_ACCOUNTS_ID` | NUMBER | The COA structure (FK to the flexfield structure; matches `GL_CODE_COMBINATIONS.CHART_OF_ACCOUNTS_ID`). The "C" for Chart of accounts. |
| `PERIOD_SET_NAME` | VARCHAR2 | Accounting calendar name — the "C" for Calendar (joins to `GL_PERIODS.PERIOD_SET_NAME`). |
| `ACCOUNTED_PERIOD_TYPE` | VARCHAR2 | Period type of the calendar (e.g. `Month`). |
| `CURRENCY_CODE` | VARCHAR2 | Ledger (functional) currency — the "C" for Currency. `ACCOUNTED_DR/CR` are denominated in this. |
| `SLA_ACCOUNTING_METHOD_CODE` | VARCHAR2 | Subledger accounting method — the "C" for accounting Method. |
| -- `LEGAL_ENTITY_ID` | NUMBER | Default/owning LE for a single-LE ledger. `-- verify physical name via glossary` — multi-LE ledgers resolve LE via BSV assignment, not this column. |

## `GL_CODE_COMBINATIONS` — chart-of-accounts combinations (CCID)

One row per **valid account combination**. The account on every journal line, balance,
and subledger line is stored as a `CODE_COMBINATION_ID` (an **integer key, not a
string**) that points here.

| Column | Type | Notes |
|---|---|---|
| `CODE_COMBINATION_ID` | NUMBER | **PK — the CCID.** This is the integer FK carried on GL_BALANCES, GL_JE_LINES, XLA_AE_LINES, PO_DISTRIBUTIONS_ALL, etc. Never a readable account string. |
| `CHART_OF_ACCOUNTS_ID` | NUMBER | The COA structure this combination belongs to (matches `GL_LEDGERS.CHART_OF_ACCOUNTS_ID`). Segment *layout* is per COA structure. |
| `SEGMENT1` … `SEGMENT30` | VARCHAR2 | The flexfield segment **values** (raw codes, e.g. `100`, `30`, `4100`). **Which segment means company vs cost center vs natural account is CUSTOMER CONFIG** — resolve segment→meaning via the glossary; never assume `SEGMENT2` = cost center (gotcha). Decode each value's *name* via `FND_FLEX_VALUES_VL`. |
| `CONCATENATED_SEGMENTS` | VARCHAR2 | The human-readable concatenated account (e.g. `100-30-4100-CC-001`). Use this for display; it is derived from the `SEGMENTn` values. |
| `ACCOUNT_TYPE` | VARCHAR2(1) | `A` = Asset, `L` = Liability, `O` = Owners' equity, `R` = Revenue, `E` = Expense. Comes from the **natural-account** segment's value definition. Drives sign/rollforward logic. |
| `ENABLED_FLAG` | VARCHAR2(1) | `Y`/`N`. Disabled combinations should be excluded from current reporting. |
| `DETAIL_POSTING_ALLOWED_FLAG` | VARCHAR2(1) | `Y` = a **detail** (postable) account. `N` = posting not allowed at this combination. |
| `SUMMARY_FLAG` | VARCHAR2(1) | `Y` = a **summary** (parent/rollup) account built over a summary template — **never sum summary + detail together** (gotcha). `N` = detail. |
| `START_DATE_ACTIVE` | DATE | Combination valid-from. NULL = no lower bound. |
| `END_DATE_ACTIVE` | DATE | Combination valid-to. NULL = open-ended. Filter on the as-of date for point-in-time validity. |

## `GL_PERIODS` — accounting calendar

One row per period **definition** in a calendar (`PERIOD_SET_NAME`). Shared across all
ledgers using that calendar. Period *status* is separate (`GL_PERIOD_STATUSES`).

| Column | Type | Notes |
|---|---|---|
| `PERIOD_SET_NAME` | VARCHAR2 | Calendar name (joins to `GL_LEDGERS.PERIOD_SET_NAME`). |
| `PERIOD_NAME` | VARCHAR2 | PK within the calendar (e.g. `Jan-25`). **Do not sort/range alphabetically** (gotcha) — use the derived effective period number below. |
| `PERIOD_TYPE` | VARCHAR2 | e.g. `Month`, `Quarter`. |
| `PERIOD_YEAR` | NUMBER | Fiscal year. |
| `PERIOD_NUM` | NUMBER | Period number within the fiscal year (1..N). |
| `QUARTER_NUM` | NUMBER | Fiscal quarter (1–4). |
| `START_DATE` | DATE | First calendar date of the period. `period_for_date` maps a date to `PERIOD_NAME` via `START_DATE`/`END_DATE`. |
| `END_DATE` | DATE | Last calendar date of the period. |
| `ADJUSTMENT_PERIOD_FLAG` | VARCHAR2(1) | `Y` = an **adjusting period** (e.g. `Adj-25`) that overlaps normal-period dates. **Exclude or handle explicitly** when bucketing by date, or amounts double-count. |
| (derived) `effective_period_number` | NUMBER | **Chronological sort key** = `PERIOD_YEAR * 10000 + PERIOD_NUM`. Computed, not stored. Always sort/range by this, never by `PERIOD_NAME`. |

## `GL_PERIOD_STATUSES` — period open/close status per ledger

One row **per ledger + period** (status is per-ledger; the same `PERIOD_NAME` can be
Open in one ledger and Closed in another).

| Column | Type | Notes |
|---|---|---|
| `LEDGER_ID` | NUMBER | FK to `GL_LEDGERS`. **Status is per-ledger** — always filter by `LEDGER_ID`. |
| `PERIOD_NAME` | VARCHAR2 | FK to `GL_PERIODS.PERIOD_NAME`. |
| `PERIOD_YEAR` / `PERIOD_NUM` | NUMBER | Denormalized from `GL_PERIODS` for sorting. |
| `CLOSING_STATUS` | VARCHAR2(1) | The status code (see table below). `is_period_open` returns TRUE only for `O`. |
| `APPLICATION_ID` | NUMBER | The status is tracked per accounting application (GL = `101`; subledgers have their own). `-- verify physical name via glossary` — for GL period status filter to the GL application id. |

**`CLOSING_STATUS` codes:**

| Code | Meaning |
|---|---|
| `O` | Open — postings allowed; **numbers are not final** (open periods change). |
| `C` | Closed — no new postings without reopening. |
| `F` | Future Enterable — not yet open, but entry allowed ahead. |
| `N` | Never Opened. |
| `P` | Permanently Closed. |
| `W` | Close Pending (closing in progress). |

## `GL_DAILY_RATES` — currency conversion rates

One row per (from-currency, to-currency, conversion date, conversion type). The source
for converting an entered (document) amount to a ledger or reporting currency.

| Column | Type | Notes |
|---|---|---|
| `FROM_CURRENCY` | VARCHAR2 | ISO source currency. |
| `TO_CURRENCY` | VARCHAR2 | ISO target currency. |
| `CONVERSION_DATE` | DATE | The rate's effective date. Match to the accounting/conversion date of the transaction, not "today." |
| `CONVERSION_TYPE` | VARCHAR2 | Rate type. **Seeded types: `Spot`, `Corporate`, `User`, `Fixed`** (customers add more). Different types give different rates — confirm which the metric wants. `-- verify physical name via glossary` (some landings expose the user-readable rate-type name vs the internal code). |
| `CONVERSION_RATE` | NUMBER | Multiplier: `to_amount = from_amount * CONVERSION_RATE`. |

> Currency rule (gotcha): rows in GL/XLA carry both `ENTERED_DR/CR` (document
> currency) and `ACCOUNTED_DR/CR` (ledger currency). **Never sum `ENTERED` across
> currencies.** Cross-entity totals use `ACCOUNTED` (already in ledger currency); only
> use `GL_DAILY_RATES` when converting to a *different* target currency than the
> ledger's.

## `XLA_AE_HEADERS` — subledger accounting entry headers

One row per **subledger journal entry** (the accounting created by AP / AR / PO-receipt
/ Costing etc. via the Create Accounting process). Header for `XLA_AE_LINES`.

| Column | Type | Notes |
|---|---|---|
| `AE_HEADER_ID` | NUMBER | PK. FK to `XLA_AE_LINES.AE_HEADER_ID`. |
| `APPLICATION_ID` | NUMBER | **Which subledger** produced the entry (AP / AR / Costing / …). Always scope by this if mixing subledgers. |
| `LEDGER_ID` | NUMBER | FK to `GL_LEDGERS`. |
| `ENTITY_ID` | NUMBER | FK to the XLA transaction entity (the source document) — joins to `XLA_TRANSACTION_ENTITIES`. `-- verify physical name via glossary`. |
| `ACCOUNTING_DATE` | DATE | The accounting/effective date (drives the period). |
| `PERIOD_NAME` | VARCHAR2 | The GL period the entry posts to. |
| `GL_TRANSFER_STATUS_CODE` | VARCHAR2(1) | Whether the entry has been transferred to GL (`Y` = transferred). **Untransferred entries aren't in GL yet** — they exist in XLA but not in `GL_JE_LINES`. |
| `ACCOUNTING_ENTRY_STATUS_CODE` | VARCHAR2 | Final / Draft / Invalid. Use Final entries for reconciliation. |

## `XLA_AE_LINES` — subledger accounting entry lines (the GL bridge)

One row **per debit/credit line** of a subledger journal entry. **This is where the
CCID, the entered/accounted amounts, and the link to GL live.** XLA detail rolls **up
into** `GL_JE_LINES` — **never add GL and XLA amounts together** (gotcha).

| Column | Type | Notes |
|---|---|---|
| `AE_HEADER_ID` | NUMBER | FK to `XLA_AE_HEADERS`. |
| `AE_LINE_NUM` | NUMBER | Line number within the header (PK = `AE_HEADER_ID` + `AE_LINE_NUM`). |
| `APPLICATION_ID` | NUMBER | Which subledger (denormalized from the header). |
| `CODE_COMBINATION_ID` | NUMBER | **The CCID** charged on this line (FK to `GL_CODE_COMBINATIONS`). |
| `ACCOUNTED_DR` / `ACCOUNTED_CR` | NUMBER | Debit / credit in **ledger currency**. Safe to sum across the ledger. |
| `ENTERED_DR` / `ENTERED_CR` | NUMBER | Debit / credit in **document (`CURRENCY_CODE`) currency**. **Never sum across currencies.** |
| `CURRENCY_CODE` | VARCHAR2 | The entered (document) currency for this line. |
| `ACCOUNTING_CLASS_CODE` | VARCHAR2 | The accounting class (e.g. `LIABILITY`, `ITEM EXPENSE`, `GAIN`/`LOSS`) — identifies the role of the line within the entry. |
| `GL_SL_LINK_ID` | NUMBER | **The bridge key to GL.** Joins XLA detail to the summarized `GL_JE_LINES` row it rolled into (paired with `GL_SL_LINK_TABLE`). Use for subledger↔GL reconciliation. |
| `GL_SL_LINK_TABLE` | VARCHAR2 | Companion of `GL_SL_LINK_ID` — names the link source. Join on **both** columns. |

## LE / BU / BSV assignment metadata

How the org dimensions resolve. Exact physical table names vary most here by landing
pattern — **resolve via the glossary.** Canonical shapes:

| Concept | Canonical source | Notes |
|---|---|---|
| Legal Entity master | `XLE_ENTITY_PROFILES` / `XLE_REGISTRATIONS` | LE id + name + registration. `-- verify physical name via glossary`. |
| **BSV → Legal Entity** | `GL_LEGAL_ENTITIES_BSV` (assignment) | **The link that ties a journal's balancing segment value to an LE** — the basis for "by legal entity" and consolidation reporting (gotcha). `-- verify physical name via glossary`. |
| Business Unit | `FUN_ALL_BUSINESS_UNITS_V` / HR org units | BU id + name; BU ≈ EBS Operating Unit; carries primary ledger + default LE. `-- verify physical name via glossary`. |
| LE ↔ Ledger | (on `GL_LEDGERS` for single-LE; assignment table for multi-LE) | A ledger can have multiple LEs; the BSV assignment partitions them. |

The **balancing segment** itself is one of the `SEGMENT1..30` positions in
`GL_CODE_COMBINATIONS` — **which position is customer config** (resolve via glossary).
You read the BSV off that segment, then map BSV→LE through the assignment above.

## Segment-value decode (`FND_FLEX_VALUES_VL`)

Segment *values* in `GL_CODE_COMBINATIONS.SEGMENTn` are raw codes. Their **names /
descriptions** (and parent rollups) come from the key-flexfield value sets:

| Column | Type | Notes |
|---|---|---|
| `FLEX_VALUE_SET_ID` | NUMBER | Which value set (one per segment; the segment→value-set map is COA config — glossary). |
| `FLEX_VALUE` | VARCHAR2 | The value code (matches a `SEGMENTn` value). |
| `DESCRIPTION` | VARCHAR2 | Readable name (the `_VL` view is the translated/active-language row). |
| `ENABLED_FLAG` / `SUMMARY_FLAG` | VARCHAR2(1) | Enabled; and whether the value is a parent (summary) value. |
| `PARENT_FLEX_VALUE_LOW` | VARCHAR2 | For hierarchy/rollup traversal. `-- verify physical name via glossary`. |

## Cardinality summary

| Relationship | Cardinality |
|---|---|
| `GL_LEDGERS` → `GL_PERIOD_STATUSES` | 1:N (one status row per period per ledger) |
| `GL_PERIODS` (calendar) → `GL_PERIOD_STATUSES` | 1:N (shared calendar, per-ledger status) |
| `GL_CODE_COMBINATIONS` → GL/XLA lines | 1:N (one CCID, many lines reference it) |
| `GL_CODE_COMBINATIONS.SEGMENTn` → `FND_FLEX_VALUES_VL` | N:1 per segment (value → name) |
| `XLA_AE_HEADERS` → `XLA_AE_LINES` | 1:N |
| `XLA_AE_LINES` → `GL_JE_LINES` | N:1 **roll-up** via `GL_SL_LINK_ID` + `GL_SL_LINK_TABLE` (XLA detail summarizes into GL — owned across to `oracle-fusion-general-ledger`) |
| `GL_LEDGERS` → Legal Entity | 1:N (LEs assigned to a ledger) |
| Legal Entity → Balancing Segment Value | 1:N (BSVs assigned to an LE) |
| `GL_LEDGERS` → Business Unit | 1:N (BUs reference a primary ledger) |
