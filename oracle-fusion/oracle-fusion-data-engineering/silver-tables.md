# Fusion Silver Tables — v1 Materialization Reference

Which canonical Oracle Fusion tables to materialize for the v1 modules (GL + procurement +
the keystone accounting foundation), with **grain**, **dedup/merge key**, and **incremental
column** notes. The module skills query these by their **canonical EBS-style names**; the
`<customer>-oracle-fusion-glossary` (from `oracle-fusion-setup`) maps each to the customer's
physical PVO/FDI/base object. Universal mechanics (`_ALL` scoping, CCID segments,
entered-vs-accounted currency, period ordering, GL↔XLA) are owned by `oracle-fusion-overview`
and `oracle-fusion-ledger-coa` — applied here, not re-taught.

## Contents
- Notes on the incremental column
- Keystone — accounting foundation
- General Ledger
- Procurement
- Deletes-not-captured note

---

## Notes on the incremental column

Fusion rows carry `LAST_UPDATE_DATE` (and `CREATION_DATE`) audit columns; BICC incremental
extracts key off `LAST_UPDATE_DATE`. Use it as the `sequence_by` for `APPLY CHANGES` where
present. If the landing pattern strips it (some FDI facts), fall back to the extract/ingest
timestamp. **BICC incremental does NOT capture hard deletes** — see the deletes note below.

---

## Keystone — accounting foundation (consumed by `oracle-fusion-ledger-coa`)

| Canonical table | Grain | Silver type | Dedup / merge key | Incremental column |
|---|---|---|---|---|
| `GL_LEDGERS` | one row per ledger (the 4 Cs) | SCD2 / MV | `LEDGER_ID` | `LAST_UPDATE_DATE` |
| `GL_CODE_COMBINATIONS` | one row per account combination (CCID) | SCD2 (or MV) | `CODE_COMBINATION_ID` | `LAST_UPDATE_DATE` |
| `GL_PERIODS` | one row per period per calendar | MV | `PERIOD_SET_NAME, PERIOD_NAME` | full refresh |
| `GL_PERIOD_STATUSES` | one row per ledger+period+application | apply-changes | `LEDGER_ID, PERIOD_NAME, APPLICATION_ID` | `LAST_UPDATE_DATE` |
| `GL_DAILY_RATES` | one row per (from, to, date, type) | append-only | `FROM_CURRENCY, TO_CURRENCY, CONVERSION_DATE, CONVERSION_TYPE` | `CONVERSION_DATE` |
| `XLA_AE_HEADERS` | one row per subledger accounting event header | append-only | `AE_HEADER_ID` | `LAST_UPDATE_DATE` |
| `XLA_AE_LINES` | one row per subledger accounting line | append-only | `AE_HEADER_ID, AE_LINE_NUM` | `LAST_UPDATE_DATE` |

`GL_PERIODS` sort key: `PERIOD_YEAR*10000 + PERIOD_NUM` — never `PERIOD_NAME` alphabetically.
`XLA_AE_LINES` carries `GL_SL_LINK_ID` linking to `GL_JE_LINES` — keep it for the subledger→GL bridge.

## General Ledger (consumed by `oracle-fusion-general-ledger`)

| Canonical table | Grain | Silver type | Dedup / merge key | Incremental column |
|---|---|---|---|---|
| `GL_JE_BATCHES` | one row per posting batch | apply-changes | `JE_BATCH_ID` | `LAST_UPDATE_DATE` |
| `GL_JE_HEADERS` | one row per journal header | apply-changes | `JE_HEADER_ID` | `LAST_UPDATE_DATE` |
| `GL_JE_LINES` | one row per journal line | apply-changes | `JE_HEADER_ID, JE_LINE_NUM` | `LAST_UPDATE_DATE` |
| `GL_BALANCES` | one row per ledger+CCID+currency+period+actual_flag | apply-changes | `LEDGER_ID, CODE_COMBINATION_ID, CURRENCY_CODE, PERIOD_NAME, ACTUAL_FLAG` | `LAST_UPDATE_DATE` |

Keep `STATUS` (`P`/`U`) and `ACTUAL_FLAG` (`A`/`B`/`E`) as columns — never filter them at Silver.
`GL_BALANCES` rows for an open period are re-extracted as the balance changes — apply-changes on
the full slice key keeps the latest without losing other slices. Pass `ENTERED_DR/CR` and
`ACCOUNTED_DR/CR` through unmodified.

## Procurement (consumed by `oracle-fusion-procurement`)

| Canonical table | Grain | Silver type | Dedup / merge key | Incremental column |
|---|---|---|---|---|
| `POR_REQUISITION_HEADERS_ALL` | one row per requisition (multi-org) | apply-changes | `REQUISITION_HEADER_ID` | `LAST_UPDATE_DATE` |
| `PO_HEADERS_ALL` | one row per PO header (multi-org) | apply-changes | `PO_HEADER_ID` | `LAST_UPDATE_DATE` |
| `PO_LINES_ALL` | one row per PO line | apply-changes | `PO_HEADER_ID, PO_LINE_ID` | `LAST_UPDATE_DATE` |
| `PO_LINE_LOCATIONS_ALL` | one row per schedule (ship-to/dates) | apply-changes | `LINE_LOCATION_ID` | `LAST_UPDATE_DATE` |
| `PO_DISTRIBUTIONS_ALL` | one row per distribution (the charged CCID) | apply-changes | `PO_DISTRIBUTION_ID` | `LAST_UPDATE_DATE` |
| `POZ_SUPPLIERS` | one row per supplier | SCD2 | `VENDOR_ID` | `LAST_UPDATE_DATE` |
| `POZ_SUPPLIER_SITES_ALL` | one row per supplier site (multi-org) | SCD2 | `VENDOR_SITE_ID` | `LAST_UPDATE_DATE` |

`_ALL` tables: keep ALL business units in Silver; scope by `PRC_BU_ID` at consumption.
`PO_LINE_LOCATIONS_ALL` carries `QUANTITY_RECEIVED` / `QUANTITY_BILLED` for 3-way-match.
`PO_DISTRIBUTIONS_ALL.CODE_COMBINATION_ID` is the join to the COA — keep it for spend-by-account.
Keep `CANCEL_FLAG` / `CLOSED_CODE` as columns; don't drop canceled/closed POs at Silver.

## Deletes-not-captured note

For every table above sourced via **BICC incremental**: hard deletes in Fusion are NOT
reflected (the row just stops appearing; it stays in Bronze/Silver). Options, in order of
preference: (1) a BICC **Deleted-Record extract** if the customer configured one — apply it as
tombstones; (2) a **periodic full reload** of the affected tables — anti-join the latest full
snapshot vs Silver and tombstone the missing keys; (3) accept the drift and surface it in
`oracle-fusion-data-quality` (the extract-gap probe). Record which applies in the glossary.
