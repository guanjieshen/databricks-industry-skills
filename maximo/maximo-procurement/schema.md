# Maximo Procurement — Schema Reference

For the universal Maximo schema and mechanics (`SITEID` composite keys, status-is-a-synonym-domain / `SYNONYMDOMAIN`, `HISTORYFLAG`, app-server-timezone datetimes), see `maximo-overview`. This file focuses on the purchasing module.

Column lists below are the most commonly used columns, not exhaustive — customers often add extension columns. All tables follow the IBM Maximo MBO model.

## Contents

- `PR` / `PRLINE` — purchase requisition
- `PO` / `POLINE` — purchase order
- `INVOICE` / `INVOICELINE` — vendor invoice
- `MATRECTRANS` / `SERVRECTRANS` — receipts
- `COMPANIES` / `COMPMASTER` — vendor master
- `CONTRACT` — purchase contracts (brief)
- Cost columns: LINECOST vs LOADEDCOST vs tax
- Cardinality summary

## `PR` / `PRLINE` — purchase requisition

`PR` is the internal request to buy. One header, N lines.

| `PR` column | Type | Notes |
|---|---|---|
| `PRNUM` | STRING | Business key — unique within `SITEID` |
| `SITEID` / `ORGID` | STRING | Site / org scope |
| `STATUS` | STRING | `PRSTATUS` synonym domain: `WAPPR` (default at creation), `APPR` (only if approvals enabled — **off by default**), `CLOSE` (all lines assigned to POs), `CAN`. Stores the synonym `VALUE` — resolve via `SYNONYMDOMAIN` (see `maximo-overview`). |
| `STATUSDATE` | TIMESTAMP | When current status was set |
| `REQUIREDDATE` | TIMESTAMP | When the requestor needs it |
| `TOTALCOST` | DECIMAL | Header total |
| `HISTORYFLAG` | INT (0/1) | `1` once final (closed/cancelled) — drops from List views (see `maximo-overview`) |

`PRLINE`: `PRNUM`, `SITEID`, `PRLINENUM`, `ITEMNUM`, `LINETYPE` (`ITEM`/`MATERIAL`/`SERVICE`/`STDSERVICE`), `ORDERQTY`, `ORDERUNIT`, `UNITCOST`, `LINECOST`, `STORELOC`, `GLDEBITACCT`. A PR line that has been transferred to a PO carries the link back to its `PONUM`/`POLINENUM`.

## `PO` / `POLINE` — purchase order

**PO is a SITE-level record** — key is `SITEID` + `PONUM` (+ `REVISIONNUM` for the revision flow). `POLINE` inherits the header `SITEID`/`ORGID`.

| `PO` column | Type | Notes |
|---|---|---|
| `PONUM` | STRING | Business key — **unique within `SITEID`** (gotcha 1) |
| `SITEID` / `ORGID` | STRING | Site / org (org denormalized onto every line) |
| `REVISIONNUM` | INT | Revision number; with `STATUS` drives the revision flow (gotcha 2) |
| `STATUS` | STRING | `POSTATUS` synonym domain: `WAPPR`, `INPRG`, `APPR`, `HOLD`, `PNDREV` (pending revision — active edit), `REVISD` (historical prior version), `CLOSE` (all lines received → history), `CAN`. Resolve via `SYNONYMDOMAIN`. |
| `STATUSDATE` | TIMESTAMP | When current status was set |
| `POTYPE` | STRING | Purchase-order type (values are deployment-configured — confirm; common ones relate to standard vs contract-release POs) |
| `VENDOR` | STRING | FK to `COMPANIES.COMPANY` — **composite with `ORGID`** (gotcha: vendor) |
| `ORDERDATE` | TIMESTAMP | When the PO was issued |
| `TOTALCOST` | DECIMAL | Header total (cost basis per MAXVAR — see cost section) |
| `CONTRACTREFNUM` | STRING | Source contract if this PO is a release |
| `HISTORYFLAG` | INT (0/1) | `1` once closed/cancelled |

| `POLINE` column | Type | Notes |
|---|---|---|
| `PONUM` / `SITEID` | STRING | Composite FK to PO header |
| `POLINENUM` | INT | Line number |
| `ITEMNUM` | STRING | Item (null for services / specially-ordered) |
| `LINETYPE` | STRING | `ITEM` / `MATERIAL` / `SERVICE` / `STDSERVICE` — determines material vs service receipt table |
| `ORDERQTY` | DECIMAL | Quantity ordered |
| `RECEIVEDQTY` | DECIMAL | Cumulative quantity received (accumulates across partial receipts) |
| `UNITCOST` | DECIMAL | Unit cost |
| `LINECOST` | DECIMAL | **Pretax** extended line cost |
| `LOADEDCOST` | DECIMAL | `LINECOST` + prorated freight/handling (see cost section) |
| `CURRENCYLINECOST` | DECIMAL | Line cost in the PO transaction currency (vs base) |
| `TAX1`…`TAX5` | DECIMAL | Tax components (separate from `LINECOST`) |
| `RECEIVEDTOTALCOST` | DECIMAL | SUM of receipt `LINECOST`; **excludes tax/freight** |
| `PRNUM` / `PRLINENUM` | STRING/INT | Link back to the originating requisition line |
| `STORELOC` | STRING | Destination storeroom (for stock items) |
| `REQUIREDDATE` | TIMESTAMP | Need-by date (feeds on-time-delivery analytics) |

## `INVOICE` / `INVOICELINE` — vendor invoice

| `INVOICE` column | Type | Notes |
|---|---|---|
| `INVOICENUM` | STRING | Business key — within `SITEID` |
| `SITEID` / `ORGID` | STRING | Scope |
| `STATUS` | STRING | `INVOICESTATUS` synonym domain — common values `ENTERED`, `WAPPR`, `HOLD`, `APPR` (→ history record), `PAID` (confirm the full set via `SYNONYMDOMAIN(DOMAINID='INVOICESTATUS')`; deployments vary). Resolve via `SYNONYMDOMAIN`. |
| `INVOICETYPE` | STRING | `INVOICE`, `CREDIT` (credit memo), `DEBIT` (debit memo) — credit/debit carry negative/adjustment amounts (gotcha) |
| `VENDOR` | STRING | FK to `COMPANIES.COMPANY` (+ `ORGID`) |
| `PONUM` | STRING | Source PO (may be null for non-PO invoices) |
| `INVOICEDATE` | TIMESTAMP | Vendor invoice date |
| `TOTALCOST` / `TOTALTAX` | DECIMAL | Header totals |
| `HISTORYFLAG` | INT (0/1) | `1` once approved/paid (history) |

`INVOICELINE`: `INVOICENUM`, `SITEID`, `INVOICELINENUM`, `PONUM`, `POLINENUM` (match back to the PO line), `ITEMNUM`, `QUANTITY`, `LINECOST`, `LOADEDCOST`, `TAX1`…`TAX5`, `GLDEBITACCT`.

## `MATRECTRANS` / `SERVRECTRANS` — receipts

Receipts split by line type: **`MATRECTRANS` = material receipts, `SERVRECTRANS` = service receipts** (determined by `POLINE.LINETYPE`; the `MXRECEIPT` object structure unifies both).

| Column (MATRECTRANS) | Notes |
|---|---|
| `PONUM` / `SITEID` / `POLINENUM` | The PO line being received against |
| `ITEMNUM` | Item received |
| `ACCEPTEDQTY` / `REJECTEDQTY` | Inspection split — **received quantity = `ACCEPTEDQTY` + `REJECTEDQTY`** |
| `STATUS` | Receipt lifecycle: `WINSP` (waiting inspection) → `WASSET` (rotating, waiting to become asset) / `COMP` (complete) |
| `LINECOST` / `LOADEDCOST` | Receipt cost (pretax / loaded) |
| `TOSTORELOC` | Destination storeroom (for stock) |
| `ACTUALDATE` / `TRANSDATE` | Receipt date (feeds on-time-delivery; app-server-timezone — see overview) |

`SERVRECTRANS` mirrors this for service lines (hours/amount received against a service `POLINE`).

## `COMPANIES` / `COMPMASTER` — vendor master

- **`COMPANIES`** — **organization-scoped** vendor/manufacturer master. Key columns: `COMPANY` (code), `ORGID`, `NAME`, `TYPE` (`V` vendor, `M` manufacturer, `C` courier), `CURRENCYCODE`, `DISABLED`. Join from any document: `doc.VENDOR = COMPANIES.COMPANY AND doc.ORGID = COMPANIES.ORGID`.
- **`COMPMASTER`** — company-set-level master that propagates to org-specific `COMPANIES` rows. Use it to roll up vendor spend **enterprise-wide** across orgs (the same physical vendor may have several `COMPANIES` rows).

## `CONTRACT` — purchase contracts (brief)

Purchase/blanket/price contracts (`CONTRACT`, `CONTRACTNUM`, `VENDOR`) generate POs as **releases** (`PO.CONTRACTREFNUM` links back). Contract-release/blanket-utilization mechanics are deployment-specific — confirm `POTYPE`/contract usage before reporting on-/off-contract spend. (For deep contract analytics, treat as a future `maximo-contracts` concern.)

## Cost columns: LINECOST vs LOADEDCOST vs tax

- `LINECOST` = **pretax** extended cost.
- `LOADEDCOST` = `LINECOST` + prorated freight/handling.
- `TAX1`…`TAX5` = tax components, tracked **separately**.
- `RECEIVEDTOTALCOST` (POLINE) = SUM of receipt `LINECOST` — **excludes tax/freight**.
- Which field is the canonical "cost" is an Org MAXVAR (`RECEIPLINEORLOADED` for receiving, `CONTRALINEORLOADED` for contracts) — confirm per deployment.
- Multi-currency: `CURRENCYLINECOST` is the transaction currency; base-currency fields are separate. Defer cross-currency normalization to `maximo-maintenance-cost`.

## Cardinality summary

| Relationship | Cardinality |
|---|---|
| `PR` → `PRLINE` | 1 : N |
| `PRLINE` → `POLINE` | 1 : 0..N (a PR line can become one or more PO lines) |
| `PO` → `POLINE` | 1 : N (within `SITEID` + `PONUM`) |
| `PO` → `PO` (revisions) | 1 active + N `REVISD` history rows per `SITEID` + `PONUM` |
| `POLINE` → `MATRECTRANS` / `SERVRECTRANS` | 1 : N (partial receipts accumulate) |
| `POLINE` → `INVOICELINE` | 1 : N (three-way match) |
| `PO` / `INVOICE` → `COMPANIES` | N : 1 (via `VENDOR` + `ORGID`) |
| `COMPANIES` → `COMPMASTER` | N : 1 (org rows → company set) |
| `CONTRACT` → `PO` | 1 : N (releases via `CONTRACTREFNUM`) |
