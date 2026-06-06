# Oracle Fusion Procurement — Gotchas

## Contents

- 1. ORDERED ≠ RECEIVED ≠ INVOICED/BILLED — three numbers, three grains
- 2. Grain mismatch — don't sum amounts across levels
- 3. Match rule (2/3/4-way) is conditional on per-schedule flags
- 4. `_ALL` tables are multi-org — scope by `PRC_BU_ID`
- 5. Canceled and closed POs are not open backlog or spend
- 6. Blanket Purchase Agreements vs their releases — double-count trap
- 7. Supplier vs supplier site — different grains
- 8. Currency basis — entered vs ledger; which date
- 9. Requisition → PO is via the distribution back-reference, not a header FK
- 10. Invoiced spend as an AP fact is out of scope (P2P boundary)

The traps that will silently produce wrong procurement numbers. Read before writing any query. The org-wide gotchas (multi-org `_ALL`, CCID segments, currency, posted-vs-unposted, landing-pattern) live in `oracle-fusion-overview`; this file adds the purchasing-specific mechanics.

## 1. ORDERED ≠ RECEIVED ≠ INVOICED/BILLED — three numbers, three grains

This is **the** central procurement concept. "Spend" is ambiguous — there are three distinct measures, each from a different table grain, and they are rarely equal:

| Basis | What it means | Where it lives |
|---|---|---|
| **Ordered** (committed) | What we agreed to buy | schedule `PO_LINE_LOCATIONS_ALL.QUANTITY × price`, or distribution `PO_DISTRIBUTIONS_ALL.QUANTITY_ORDERED × price` |
| **Received** (goods in) | What the supplier has delivered | `PO_LINE_LOCATIONS_ALL.QUANTITY_RECEIVED` (updated by Receiving) |
| **Invoiced / Billed** | What Payables has matched to an invoice | `PO_LINE_LOCATIONS_ALL.QUANTITY_BILLED` / `PO_DISTRIBUTIONS_ALL.AMOUNT_BILLED` (updated by Payables on match) |

A PO can be **ordered but not received** (open commitment), **received but not billed** (accrued / GR-IR), or **billed beyond received** (an exception). Ordered ≥ received ≥ billed is the *normal* progression but not guaranteed.

**Action:** never answer a "spend" question without confirming the basis (SKILL.md *Questions to surface first*, Q1). Default to **ordered** for "PO spend / commitment", but say so. Report the basis in any output. The `po_spend` / `supplier_spend` Trusted UDFs take a `spend_basis` parameter precisely so the choice is explicit.

## 2. Grain mismatch — don't sum amounts across levels

The chain `PO_HEADERS_ALL → PO_LINES_ALL → PO_LINE_LOCATIONS_ALL → PO_DISTRIBUTIONS_ALL` fans out 1:N at every step. Once you join header→line→schedule→distribution, **each higher-grain row is repeated** once per distribution. Summing `PO_LINES_ALL.QUANTITY` or a line amount after that join multi-counts.

| If you want… | Aggregate at this grain | Don't also sum |
|---|---|---|
| Line quantity | `PO_LINES_ALL` (line) | schedule `QUANTITY` after joining to schedules |
| Received quantity | `PO_LINE_LOCATIONS_ALL` (schedule) | distribution rows after joining down |
| Ordered/billed **amount**, spend by account | `PO_DISTRIBUTIONS_ALL` (distribution) | line quantity × price after the fan-out |

**Action:** pick the grain that owns the measure (see schema.md's grain table) and aggregate there. `v_po_spend` materializes spend at the **distribution grain** so a `SUM` over it is correct. Note that `PO_LINES_ALL.QUANTITY` is already the sum of its schedule quantities — re-summing schedules double-counts the line.

## 3. Match rule (2/3/4-way) is conditional on per-schedule flags

The "match" compares ordered vs invoiced vs received vs accepted — but **which quantities apply depends on per-schedule flags**:

| Match | Compares | Applies when |
|---|---|---|
| **2-way** | ordered vs invoiced | always |
| **3-way** | + received (`QUANTITY_RECEIVED`) | `RECEIPT_REQUIRED_FLAG = 'Y'` |
| **4-way** | + accepted (`QUANTITY_ACCEPTED`) | `INSPECTION_REQUIRED_FLAG = 'Y'` |

A "3-way match exception" is meaningful **only on receipt-required schedules**. Computing received-vs-billed variance on schedules where `RECEIPT_REQUIRED_FLAG = 'N'` (e.g. services that don't go through receiving) produces false positives — there's no expectation of a receipt.

**Action:** filter on the flags before flagging exceptions. The `three_way_match_exceptions` UDF gates on `RECEIPT_REQUIRED_FLAG = 'Y'`. Confirm the customer's match policy (SKILL.md Q2) — the rule can vary by supplier/category.

## 4. `_ALL` tables are multi-org — scope by `PRC_BU_ID`

Every transactional procurement table carries the `_ALL` suffix and holds **every procurement business unit's** rows. Summing without a BU filter mixes orgs. The procurement BU column is **`PRC_BU_ID`** (the multi-org scope; Fusion's BU ≈ E-Business-Suite Operating Unit). This is overview gotcha 1 applied to procurement — always scope.

## 5. Canceled and closed POs are not open backlog or spend

- **`CANCEL_FLAG = 'Y'`** (header and line) — canceled. **Never count as spend.**
- **`CLOSED_CODE`** (header and schedule) — `OPEN` / `CLOSED` / `FINALLY CLOSED` / `CLOSED FOR RECEIVING` / `CLOSED FOR INVOICING`. A fully/finally-closed PO is complete and should **not** appear in open-backlog counts. A schedule "closed for receiving" won't receive more even if ordered > received.
- **`APPROVED_FLAG = 'Y'`** — if the user wants *approved* commitments only (most "committed spend" asks do), filter on it; otherwise drafts/incomplete POs inflate the number.

**Action:** confirm status filters (SKILL.md Q5). Open backlog = approved, not canceled, not finally-closed, with ordered > received (or > billed, depending on the basis).

## 6. Blanket Purchase Agreements vs their releases — double-count trap

`TYPE_LOOKUP_CODE` values: `STANDARD`, `BLANKET` (a **Blanket Purchase Agreement** — a negotiated price/terms agreement, *not* an order to fulfill), `CONTRACT`, `PLANNED`.

A BPA itself usually carries **no committed quantity to receive** — actual ordering happens through **releases** against the agreement, and **each release is its own PO row** (referencing the agreement). **Counting both the BPA and its releases double-counts committed spend.** Conversely, summing only standard POs misses all BPA-release spend.

**Action:** confirm document-type scope (SKILL.md Q4). For "committed/ordered spend", count standard POs **and** BPA releases, but **exclude the BPA agreements themselves**. For "agreements negotiated", count BPAs. Never sum the two together.

## 7. Supplier vs supplier site — different grains

A supplier (`POZ_SUPPLIERS`, `VENDOR_ID`) has many **sites** (`VENDOR_SITE_ID`), and sites are themselves **BU-scoped** (purchasing/pay attributes live at the site). A PO references both (`VENDOR_ID` + `VENDOR_SITE_ID`).

**Action:** "supplier spend" rolls up to `VENDOR_ID`; "spend by ship-from / pay site" stays at `VENDOR_SITE_ID`. Don't report site-level spend as supplier spend or vice versa. Joining supplier-site without the BU context can also fan out.

## 8. Currency basis — entered vs ledger; which date

PO amounts are in the PO's **entered/document currency** (`PO_HEADERS_ALL.CURRENCY_CODE`). **Never sum entered amounts across different currencies** (overview gotcha 5). Cross-BU or multi-currency spend totals must **normalize to ledger currency** via the keystone's `convert_to_ledger_currency` (`oracle-fusion-ledger-coa`).

Also confirm **which date** drives time bucketing — PO `CREATION_DATE`, `APPROVED_DATE`, schedule `NEED_BY_DATE`, or `PROMISED_DATE` give different trends. There is no defensible default (SKILL.md Q6).

## 9. Requisition → PO is via the distribution back-reference, not a header FK

There is **no direct header-to-header FK** from a requisition to a PO. The link is at the distribution grain: `PO_DISTRIBUTIONS_ALL.REQ_DISTRIBUTION_ID` points back to the originating requisition distribution. **Requisition-to-PO conversion / cycle time** must be computed through this link (requisition `CREATION_DATE`/`APPROVED_DATE` → PO `CREATION_DATE`/`APPROVED_DATE`), then deduplicated up to the requisition or PO grain as the question requires — a requisition can split across multiple POs and vice versa.

## 10. Invoiced spend as an AP fact is out of scope (P2P boundary)

Procurement owns **ordering and receiving** (`PO_*`). **Payables** owns the invoice and payment (`AP_INVOICES_ALL`, `AP_INVOICE_DISTRIBUTIONS_ALL`). This skill reports the **PO-side** billed quantity/amount (`QUANTITY_BILLED`, `AMOUNT_BILLED`) that Payables writes back onto the schedule/distribution on match — that is enough for 2-way/3-way exceptions and "how much of the PO has been invoiced". But **the AP invoice itself — invoice date, hold, payment, aging — is a future `oracle-fusion-payables` concern.** Don't pull AP tables here; flag it as the payables boundary and defer.
