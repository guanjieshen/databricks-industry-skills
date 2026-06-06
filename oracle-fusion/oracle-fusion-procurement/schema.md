# Oracle Fusion Procurement — Schema Reference

Canonical reference for the Fusion Procurement purchasing chain and the supplier master. Column lists are the most commonly used columns, not exhaustive — customers carry additional descriptive flexfield (DFF) and extension columns.

**Landing-pattern note (read first).** Names below are the **canonical Oracle E-Business-Suite-style table/column names** (`PO_HEADERS_ALL`, `PO_DISTRIBUTIONS_ALL`, …) that Fusion's underlying physical model keeps almost verbatim. But Fusion Cloud is **SaaS** — what a customer actually *receives* is **BICC Public View Objects** (e.g. `PurchaseOrderHeaderExtractPVO`, `RequisitionHeaderExtractPVO`) or **Fusion Data Intelligence (FDI)** star-schema artifacts, with different physical names. **This file describes the canonical model; the physical→canonical mapping for THIS customer lives in the `<customer>-oracle-fusion-glossary`** produced by `oracle-fusion-setup`. Resolve physical names there before querying; never promise raw-table access (overview's landing-agnostic rule).

Catalog/schema is customer-specific. SQL uses Databricks-native parameter placeholders — `:catalog`, `:silver_schema` (the canonical procurement layer), `:gold_schema` (Trusted UDFs / metric views). Bind at execution / registration.

## Contents

- The procurement document chain (req → PO → line → schedule → distribution)
- `POR_REQUISITION_HEADERS_ALL` — requisition header
- `PO_HEADERS_ALL` — purchase-order header
- `PO_LINES_ALL` — PO line (item grain)
- `PO_LINE_LOCATIONS_ALL` — schedule / shipment (received-quantity grain)
- `PO_DISTRIBUTIONS_ALL` — distribution (charged-account grain)
- `POZ_SUPPLIERS` + supplier sites — supplier master
- **The grain table — which amount lives at which level**
- Composing the keystone (account decode + currency)
- Cardinality summary

## The procurement document chain (req → PO → line → schedule → distribution)

```
POR_REQUISITION_HEADERS_ALL        (requisition — the demand)
        │  (REQ_DISTRIBUTION_ID back-reference on the PO distribution)
        ▼
PO_HEADERS_ALL                     (the order — supplier, BU, currency, type, status)
        │  1:N
        ▼
PO_LINES_ALL                       (what — item / category / UOM / unit price; QUANTITY = Σ schedule qty)
        │  1:N
        ▼
PO_LINE_LOCATIONS_ALL              (when / where — schedule/shipment; QUANTITY_RECEIVED, QUANTITY_BILLED)
        │  1:N
        ▼
PO_DISTRIBUTIONS_ALL               (charged account — CODE_COMBINATION_ID; AMOUNT_BILLED, QUANTITY_ORDERED)
```

Each downward step fans out (1:N). The single most common procurement modeling error is summing a higher-grain amount after joining down (gotcha 2 — see the grain table).

## `POR_REQUISITION_HEADERS_ALL` — requisition header

The demand signal that (optionally) becomes a PO. One row per requisition.

| Column | Type | Notes |
|---|---|---|
| `REQUISITION_HEADER_ID` | BIGINT | PK |
| `REQUISITION_NUMBER` | STRING | Business key — the requisition number |
| `PRC_BU_ID` | BIGINT | Procurement (requisitioning) business unit — **multi-org scope** |
| `PREPARER_ID` | BIGINT | Who raised the requisition |
| `TYPE_LOOKUP_CODE` | STRING | `PURCHASE` / `INTERNAL` |
| `AUTHORIZATION_STATUS` | STRING | e.g. `APPROVED`, `IN PROCESS`, `REJECTED` |
| `CREATION_DATE` | TIMESTAMP | When the requisition was created — the start of req-to-PO cycle time |
| `APPROVED_DATE` | TIMESTAMP | When approved |
| `CANCEL_FLAG` | STRING (Y/N) | Canceled requisition |
| `CURRENCY_CODE` | STRING | Document currency |

Requisition lines (`POR_REQUISITION_LINES_ALL`) and distributions (`POR_REQ_DISTRIBUTIONS_ALL`) carry the line-level demand; the PO distribution links back via `REQ_DISTRIBUTION_ID`. For req-to-PO conversion, join the requisition to the PO distribution's `REQ_DISTRIBUTION_ID` (see examples.sql) — there is no direct header-to-header FK.

## `PO_HEADERS_ALL` — purchase-order header

One row per PO (or per BPA / contract / planned agreement). Holds supplier, BU, currency, type, and status.

| Column | Type | Notes |
|---|---|---|
| `PO_HEADER_ID` | BIGINT | PK |
| `SEGMENT1` | STRING | **The PO number** (the human-readable order identifier) |
| `PRC_BU_ID` | BIGINT | **Procurement business unit — the multi-org scope.** Always filter/scope on this (gotcha 3). |
| `TYPE_LOOKUP_CODE` | STRING | `STANDARD` / `BLANKET` (= **Blanket Purchase Agreement**) / `CONTRACT` / `PLANNED`. Releases against a BPA generate their own PO rows (gotcha 6). |
| `VENDOR_ID` | BIGINT | FK to `POZ_SUPPLIERS` — the supplier |
| `VENDOR_SITE_ID` | BIGINT | FK to the supplier **site** (ship-from / pay-to location) |
| `AGENT_ID` | BIGINT | **Buyer** (the procurement agent) |
| `CURRENCY_CODE` | STRING | PO (entered/document) currency. Cross-BU totals normalize to ledger currency via the keystone. |
| `APPROVED_FLAG` | STRING (Y/N) | Approved commitment |
| `CLOSED_CODE` | STRING | `OPEN` / `CLOSED` / `FINALLY CLOSED` / `CLOSED FOR RECEIVING` / `CLOSED FOR INVOICING` — header-level lifecycle (gotcha 4) |
| `CANCEL_FLAG` | STRING (Y/N) | Canceled PO — **not spend** (gotcha 4) |
| `CREATION_DATE` | TIMESTAMP | When the PO was created — end of req-to-PO cycle time |
| `APPROVED_DATE` | TIMESTAMP | When approved |

## `PO_LINES_ALL` — PO line (item grain)

One row per line. Carries *what* is being bought. `QUANTITY` here is the **sum of its schedule quantities**.

| Column | Type | Notes |
|---|---|---|
| `PO_LINE_ID` | BIGINT | PK |
| `PO_HEADER_ID` | BIGINT | FK to `PO_HEADERS_ALL` |
| `LINE_NUM` | INT | Line number on the PO |
| `ITEM_ID` | BIGINT | FK to the item master (inventory item) |
| `ITEM_DESCRIPTION` | STRING | Free-text description (for non-catalog lines) |
| `CATEGORY_ID` | BIGINT | Purchasing category (spend category) |
| `UOM_CODE` | STRING | Unit of measure |
| `UNIT_PRICE` | DECIMAL | Price per unit (document currency) |
| `QUANTITY` | DECIMAL | Line quantity = **Σ of `PO_LINE_LOCATIONS_ALL.QUANTITY`** for this line. Do not also sum schedule quantity after joining — that double-counts (gotcha 2). |

## `PO_LINE_LOCATIONS_ALL` — schedule / shipment (received-quantity grain)

One row per schedule (shipment). **This is the grain where receiving and matching live.**

| Column | Type | Notes |
|---|---|---|
| `LINE_LOCATION_ID` | BIGINT | PK |
| `PO_HEADER_ID` / `PO_LINE_ID` | BIGINT | FKs up the chain |
| `QUANTITY` | DECIMAL | **Scheduled (ordered) quantity** for this shipment |
| `QUANTITY_RECEIVED` | DECIMAL | **Received** quantity — updated by Receiving. The "received" basis (gotcha 1). |
| `QUANTITY_BILLED` | DECIMAL | **Billed** quantity — updated by Payables on invoice match. The PO-side "invoiced/billed" basis (gotcha 1; AP invoice itself is out of scope — P2P boundary). |
| `QUANTITY_ACCEPTED` | DECIMAL | Accepted (passed inspection) — the 4-way-match quantity |
| `QUANTITY_REJECTED` | DECIMAL | Rejected at inspection |
| `RECEIPT_REQUIRED_FLAG` | STRING (Y/N) | **`Y` ⇒ 3-way match applies** (compare `QUANTITY_RECEIVED`). 3-way checks on `N` schedules are false positives (gotcha 5). |
| `INSPECTION_REQUIRED_FLAG` | STRING (Y/N) | **`Y` ⇒ 4-way match applies** (compare `QUANTITY_ACCEPTED`) (gotcha 5). |
| `MATCH_OPTION` | STRING | `P` (match to PO) / `R` (match to receipt) — how Payables matches invoices |
| `NEED_BY_DATE` / `PROMISED_DATE` | TIMESTAMP | Demand date / supplier-promised date (delivery-performance analysis) |
| `CLOSED_CODE` | STRING | Schedule-level lifecycle (mirrors header `CLOSED_CODE` values) |

## `PO_DISTRIBUTIONS_ALL` — distribution (charged-account grain)

One row per distribution. **This is the grain where the charged account (CCID) and the ordered/billed *amount* live.** A schedule can split across multiple distributions (e.g. two cost centers).

| Column | Type | Notes |
|---|---|---|
| `PO_DISTRIBUTION_ID` | BIGINT | PK |
| `PO_HEADER_ID` / `PO_LINE_ID` / `LINE_LOCATION_ID` | BIGINT | FKs up the chain |
| `DISTRIBUTION_NUM` | INT | Distribution number within the schedule |
| `CODE_COMBINATION_ID` | BIGINT | **The charged account (CCID).** Join to the keystone `v_code_combination` / `decode_ccid_segments` for company / cost center / natural-account segments (gotcha — compose `oracle-fusion-ledger-coa`, never assume segment positions). |
| `REQ_DISTRIBUTION_ID` | BIGINT | Back-reference to the originating requisition distribution — the req→PO link |
| `QUANTITY_ORDERED` | DECIMAL | Ordered quantity charged to this account — the **ordered** basis at amount grain |
| `QUANTITY_DELIVERED` | DECIMAL | Delivered (received) quantity for this distribution |
| `QUANTITY_BILLED` | DECIMAL | Billed quantity for this distribution |
| `AMOUNT_BILLED` | DECIMAL | **Billed amount** (document currency) — the PO-side invoiced/billed spend amount (gotcha 1) |

## `POZ_SUPPLIERS` + supplier sites — supplier master

| Column | Type | Notes |
|---|---|---|
| `VENDOR_ID` | BIGINT | PK — the supplier. FK target of `PO_HEADERS_ALL.VENDOR_ID`. |
| `VENDOR_NAME` | STRING | Supplier name |
| `SEGMENT1` | STRING | Supplier number |
| `VENDOR_TYPE_LOOKUP_CODE` | STRING | Supplier classification |
| `ENABLED_FLAG` / `END_DATE_ACTIVE` | STRING / DATE | Active status |

Supplier **sites** (`POZ_SUPPLIER_SITES_ALL`, key `VENDOR_SITE_ID`) carry the per-site, **per-BU** purchasing/pay attributes (a supplier has many sites; sites are themselves BU-scoped). `PO_HEADERS_ALL.VENDOR_SITE_ID` joins to the site. **"Supplier spend" rolls up to `VENDOR_ID`; "site spend" stays at `VENDOR_SITE_ID`** — don't conflate (gotcha: supplier-site grain).

## The grain table — which amount lives at which level

This is the core of the skill. **Sum each measure at its native grain; never sum a higher-grain amount after joining down.**

| Measure | Native table (grain) | Column / expression | Basis |
|---|---|---|---|
| PO **line** quantity | `PO_LINES_ALL` (line) | `QUANTITY` (= Σ schedule qty) | — |
| **Ordered** quantity | `PO_LINE_LOCATIONS_ALL` (schedule) | `QUANTITY` | ordered |
| **Ordered** amount | `PO_DISTRIBUTIONS_ALL` (distribution) | `QUANTITY_ORDERED × PO_LINES_ALL.UNIT_PRICE` | ordered (commitment) |
| **Received** quantity | `PO_LINE_LOCATIONS_ALL` (schedule) | `QUANTITY_RECEIVED` | received |
| **Billed** quantity | `PO_LINE_LOCATIONS_ALL` (schedule) | `QUANTITY_BILLED` | invoiced/billed (PO-side) |
| **Billed** amount | `PO_DISTRIBUTIONS_ALL` (distribution) | `AMOUNT_BILLED` | invoiced/billed (PO-side) |
| Charged account | `PO_DISTRIBUTIONS_ALL` (distribution) | `CODE_COMBINATION_ID` | — (decode via keystone) |

The **distribution grain** is the canonical home for spend *amount* and for account/cost-center analysis — `v_po_spend` in [views.sql](views.sql) materializes ordered/received/billed there. The **schedule grain** is the home for received quantity and the match flags.

## Composing the keystone (account decode + currency)

This skill does **not** redefine accounting assets. For spend-by-account / spend-by-cost-center, join `PO_DISTRIBUTIONS_ALL.CODE_COMBINATION_ID` to the keystone `oracle-fusion-ledger-coa`'s `v_code_combination` (or call `decode_ccid_segments`) — segment meaning is customer config, resolve via the glossary, never assume `SEGMENT2` = cost center. For cross-BU totals across PO currencies, normalize to ledger currency via the keystone's `convert_to_ledger_currency`. See [views.sql](views.sql) and [examples.sql](examples.sql).

## Cardinality summary

| Relationship | Cardinality |
|---|---|
| `POR_REQUISITION_HEADERS_ALL` → `PO_DISTRIBUTIONS_ALL` | 1:N (via `REQ_DISTRIBUTION_ID`; not header-to-header) |
| `PO_HEADERS_ALL` → `PO_LINES_ALL` | 1:N |
| `PO_LINES_ALL` → `PO_LINE_LOCATIONS_ALL` | 1:N |
| `PO_LINE_LOCATIONS_ALL` → `PO_DISTRIBUTIONS_ALL` | 1:N |
| `PO_HEADERS_ALL` → `POZ_SUPPLIERS` | N:1 (via `VENDOR_ID`) |
| `PO_HEADERS_ALL` → supplier site | N:1 (via `VENDOR_SITE_ID`) |
| `POZ_SUPPLIERS` → supplier sites | 1:N |
| `PO_DISTRIBUTIONS_ALL` → `GL_CODE_COMBINATIONS` | N:1 (via `CODE_COMBINATION_ID` — keystone) |
