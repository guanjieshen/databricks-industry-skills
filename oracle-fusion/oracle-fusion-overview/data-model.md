# Oracle Fusion — Cross-Module Data Model (entity-relationship reference)

**Load this when a question crosses module boundaries** — e.g. "spend by cost
center and legal entity," "reconcile procurement receipts to the GL," "PO
distributions by natural account," anything that joins the org/COA backbone to a
transactional module. For single-module depth, prefer that module's `schema.md`
(`oracle-fusion-ledger-coa`, `oracle-fusion-general-ledger`,
`oracle-fusion-procurement`). This file shows how they fit together.

> **Landing-pattern note.** All names here are the **canonical** Fusion (EBS-style)
> physical names. Fusion Cloud is SaaS; customers receive **BICC PVO** extracts or
> **FDI** star-schema artifacts under different names. The physical→canonical
> mapping for THIS customer lives in the `<customer>-oracle-fusion-glossary` from
> `oracle-fusion-setup`. Resolve every name there before binding a query.

## Contents

- The org model (Ledger / Legal Entity / Business Unit / BSV)
- The chart of accounts (CCID + segments)
- The GL journal → balance flow
- The subledger-accounting (XLA) bridge
- The procurement chain (header → line → schedule → distribution)
- How it all connects (text ER diagram)
- Cross-module cardinality table
- Cross-module join keys (quick reference)

## The org model (Ledger / Legal Entity / Business Unit / BSV)

The accounting backbone (owned by the keystone `oracle-fusion-ledger-coa`):

- **Ledger** (`GL_LEDGERS`, PK `LEDGER_ID`) — the accounting context, the **"4 Cs":
  Chart of accounts, Calendar, Currency, Accounting method.** `LEDGER_ID` is the FK on
  nearly every GL and XLA row.
- **Legal Entity (LE)** — the legally-registered org; assigned to a ledger.
  **Balancing Segment Values (BSVs) are assigned to LEs**, and that BSV→LE assignment
  is how a journal's balancing segment ties back to an LE (no raw LE column on the
  line). The basis for consolidation / "by legal entity."
- **Business Unit (BU)** — the operational division; **≈ EBS "Operating Unit."**
  A BU connects to a primary ledger + a default LE. Transactional `_ALL` tables are
  multi-org, scoped by BU (e.g. `PO_HEADERS_ALL.PRC_BU_ID`).

```
                    GL_LEDGERS (LEDGER_ID, 4 Cs)
                    /         |              \
       (BSV assignment)   (calendar)      (BU references primary ledger)
              |               |                   |
     Legal Entity        GL_PERIODS          Business Unit  ~ EBS Operating Unit
     (via BSV->LE)    GL_PERIOD_STATUSES     (PRC_BU_ID etc. on _ALL tables)
```

## The chart of accounts (CCID + segments)

- `GL_CODE_COMBINATIONS`, PK `CODE_COMBINATION_ID` (**CCID — an integer key**) is the
  account on every journal line, balance, subledger line, and PO distribution.
- Stored as `SEGMENT1..SEGMENT30` value codes + `CONCATENATED_SEGMENTS` (readable).
  **Which segment is company / cost center / natural account / balancing segment is
  customer config** — resolve via the glossary. `ACCOUNT_TYPE` (A/L/O/R/E) comes from
  the natural-account segment.
- Segment value *names* decode via `FND_FLEX_VALUES_VL`.

Everything downstream references the account **by CCID**, never by string.

## The GL journal → balance flow

Owned by `oracle-fusion-general-ledger`; summarized here for the cross-module joins:

```
GL_JE_BATCHES (batch)
   1:N
GL_JE_HEADERS (journal header; STATUS P/U, ACTUAL_FLAG A/B/E, JE_SOURCE, PERIOD_NAME)
   1:N
GL_JE_LINES (journal line; CODE_COMBINATION_ID, ACCOUNTED_DR/CR, ENTERED_DR/CR)
   rolls into
GL_BALANCES (by LEDGER_ID + CODE_COMBINATION_ID + CURRENCY_CODE + PERIOD_NAME)
```

- Trial balance / financials use **posted** journals only (`GL_JE_HEADERS.STATUS='P'`).
- `ACTUAL_FLAG`: `A` actual / `B` budget / `E` encumbrance — never mix.
- `GL_BALANCES` is the period-end summarized number; `GL_JE_LINES` is line detail.

## The subledger-accounting (XLA) bridge

Owned by `oracle-fusion-ledger-coa`. This is how AP / AR / PO-receipt / costing
transactions become GL:

```
Source document (e.g. PO receipt, AP invoice)
   --Create Accounting-->
XLA_AE_HEADERS (one per subledger journal entry; APPLICATION_ID = which subledger,
                LEDGER_ID, ACCOUNTING_DATE, PERIOD_NAME, GL_TRANSFER_STATUS_CODE)
   1:N
XLA_AE_LINES (debit/credit lines; CODE_COMBINATION_ID, ACCOUNTED_DR/CR, ENTERED_DR/CR,
              CURRENCY_CODE, ACCOUNTING_CLASS_CODE, GL_SL_LINK_ID + GL_SL_LINK_TABLE)
   --(GL_SL_LINK_ID + GL_SL_LINK_TABLE)-->
GL_JE_LINES (summarized posted GL)
```

**Critical rule:** XLA detail rolls **up into** GL — **never add GL and XLA amounts
together** (double-count). Pick one level: GL for summarized posted numbers, XLA for
transaction-level detail with the source document. Untransferred entries
(`GL_TRANSFER_STATUS_CODE <> 'Y'`) are in XLA but not yet in GL.

## The procurement chain (header → line → schedule → distribution)

Owned by `oracle-fusion-procurement`. The four-level P2P spine, and where it meets
accounting:

```
POR_REQUISITION_HEADERS_ALL (requisition)            POZ_SUPPLIERS (VENDOR_ID)
        |  (optional sourcing)                          |  + supplier sites (VENDOR_SITE_ID)
        v                                                v
PO_HEADERS_ALL  (PO header; PRC_BU_ID scopes the BU, TYPE_LOOKUP_CODE, CANCEL flags)
   1:N
PO_LINES_ALL    (what is being bought — item / category / amount)
   1:N
PO_LINE_LOCATIONS_ALL (schedule; ship-to, QUANTITY_RECEIVED, QUANTITY_BILLED)
   1:N
PO_DISTRIBUTIONS_ALL  (the charged account — CODE_COMBINATION_ID + the funding split)
        |
        +--- CODE_COMBINATION_ID --> GL_CODE_COMBINATIONS  (the COA backbone)
        +--- the receipt/invoice accounting flows through XLA into GL (above)
```

- **The CCID lives on `PO_DISTRIBUTIONS_ALL`** — that's the join from procurement to the
  chart of accounts (spend by cost center / natural account / legal entity).
- `PO_*_ALL` tables are **multi-org** — scope by `PRC_BU_ID` (BU) or you mix orgs.
- Spend must respect cancel/close flags; don't count canceled POs.
- Receipt → accounting → GL goes through the **XLA bridge** above, not a direct PO→GL
  column.

## How it all connects (text ER diagram)

```
                        GL_LEDGERS (LEDGER_ID)
        ___________________|________________________________
       |                   |                  |             |
   GL_PERIODS         Legal Entity        Business Unit   currency / COA
GL_PERIOD_STATUSES   (via BSV->LE)     (~Operating Unit)  (4 Cs of the ledger)
   (per ledger)            |                  |
                           |                  |  PRC_BU_ID
                           |                  v
                           |        PO_HEADERS_ALL
                           |             1:N
                           |        PO_LINES_ALL
                           |             1:N
                           |        PO_LINE_LOCATIONS_ALL
                           |             1:N
                           |        PO_DISTRIBUTIONS_ALL ---+
                           |                                | CODE_COMBINATION_ID
                           |                                v
                           |                    GL_CODE_COMBINATIONS (CCID)
                           |                      SEGMENT1..30 / CONCATENATED_SEGMENTS
                           |                      ACCOUNT_TYPE  --(natural acct)
                           |                                ^
   balancing segment value (read off the CCID) ------------+
   maps BSV -> Legal Entity (consolidation key)            |
                                                           used-by
                                                            |
   Source docs (AP/AR/PO receipt/costing)                   |
        --Create Accounting-->                              |
   XLA_AE_HEADERS 1:N XLA_AE_LINES --CODE_COMBINATION_ID----+
        |  GL_SL_LINK_ID + GL_SL_LINK_TABLE
        v  (roll UP, one level)
   GL_JE_BATCHES 1:N GL_JE_HEADERS 1:N GL_JE_LINES --> GL_BALANCES
        (posted journals)                  (by LEDGER_ID + CCID + CURRENCY + PERIOD)
```

## Cross-module cardinality table

| Relationship | Cardinality | Join key(s) |
|---|---|---|
| `GL_LEDGERS` → `GL_PERIOD_STATUSES` | 1:N | `LEDGER_ID` |
| `GL_PERIODS` → `GL_PERIOD_STATUSES` | 1:N | `PERIOD_NAME` (+ `PERIOD_SET_NAME`) |
| `GL_LEDGERS` → Legal Entity (via BSV) | 1:N | BSV→LE assignment |
| Legal Entity → Balancing Segment Value | 1:N | BSV assignment |
| `GL_LEDGERS` → Business Unit | 1:N | primary `LEDGER_ID` |
| `GL_CODE_COMBINATIONS` → any line/dist | 1:N | `CODE_COMBINATION_ID` |
| `GL_CODE_COMBINATIONS.SEGMENTn` → `FND_FLEX_VALUES_VL` | N:1 per segment | `FLEX_VALUE` (+ `FLEX_VALUE_SET_ID`) |
| `GL_JE_BATCHES` → `GL_JE_HEADERS` | 1:N | `JE_BATCH_ID` |
| `GL_JE_HEADERS` → `GL_JE_LINES` | 1:N | `JE_HEADER_ID` |
| `GL_JE_LINES` → `GL_BALANCES` | rolls up | `LEDGER_ID` + `CODE_COMBINATION_ID` + `CURRENCY_CODE` + `PERIOD_NAME` |
| `XLA_AE_HEADERS` → `XLA_AE_LINES` | 1:N | `AE_HEADER_ID` |
| `XLA_AE_LINES` → `GL_JE_LINES` | N:1 **roll-up** | `GL_SL_LINK_ID` + `GL_SL_LINK_TABLE` |
| `POR_REQUISITION_HEADERS_ALL` → `PO_HEADERS_ALL` | 1:N (via sourcing) | requisition/PO link |
| `PO_HEADERS_ALL` → `PO_LINES_ALL` | 1:N | `PO_HEADER_ID` |
| `PO_LINES_ALL` → `PO_LINE_LOCATIONS_ALL` | 1:N | `PO_LINE_ID` |
| `PO_LINE_LOCATIONS_ALL` → `PO_DISTRIBUTIONS_ALL` | 1:N | `LINE_LOCATION_ID` |
| `PO_DISTRIBUTIONS_ALL` → `GL_CODE_COMBINATIONS` | N:1 | `CODE_COMBINATION_ID` |
| `PO_HEADERS_ALL` → `POZ_SUPPLIERS` | N:1 | `VENDOR_ID` |

## Cross-module join keys (quick reference)

- **The universal account key:** `CODE_COMBINATION_ID` (CCID) links GL lines, GL
  balances, XLA lines, and PO distributions to `GL_CODE_COMBINATIONS`. The single most
  important cross-module join.
- **The org scope:** `LEDGER_ID` (GL/XLA) and `PRC_BU_ID`/BU (procurement `_ALL`). Never
  total a multi-org `_ALL` table without a BU/ledger filter.
- **The subledger→GL bridge:** `GL_SL_LINK_ID` **+** `GL_SL_LINK_TABLE` (join on both)
  between `XLA_AE_LINES` and `GL_JE_LINES`. One level only — never add GL + XLA.
- **The legal-entity resolution:** balancing-segment value (read off the CCID) → BSV→LE
  assignment. No raw LE column on the line.
- **The period:** `PERIOD_NAME` + `LEDGER_ID`; order chronologically by
  `PERIOD_YEAR*10000 + PERIOD_NUM`, never by the name string.
