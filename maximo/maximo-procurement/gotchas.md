# Maximo Procurement — Gotchas

## Contents

- 1. PO is a SITE-level record — key on `SITEID` + `PONUM`
- 2. PO revisions: `REVISD` rows are historical copies
- 3. PR closes when its lines hit POs — "open PR" ≠ unmet demand
- 4. `LINECOST` (pretax) vs `LOADEDCOST` (freight) vs `TAX1`–`TAX5`
- 5. Partial receipts accumulate; received = accepted + rejected
- 6. Three-way match is per PO line, gated by a receipt-required flag
- 7. Credit / debit invoices distort quantity-based receipt rollups
- 8. Material vs service receipts live in different tables
- 9. Vendor identity is org-scoped (`COMPANY` + `ORGID`)
- 10. Multi-currency — transaction vs base currency
- 11. Status synonyms & `HISTORYFLAG` (apply overview's patterns to all three docs)

The traps that will silently produce wrong numbers. Read before writing any query.

## 1. PO is a SITE-level record — key on `SITEID` + `PONUM`

`PONUM` is unique only within a **site**. Autonumbering can be configured at system/org/site level, but the PO record's scope is the site, and every `POLINE` inherits the header's `SITEID`/`ORGID`. Join PO ↔ POLINE ↔ receipts ↔ invoice lines on `SITEID` + `PONUM` (never `PONUM` alone, and not `ORGID` + `PONUM`). This is the purchasing-specific instance of the universal `SITEID` composite-key gotcha (see `maximo-overview` gotcha 4).

## 2. PO revisions: `REVISD` rows are historical copies — exclude or you double-count

When a PO is revised, Maximo keeps the prior version as a `REVISD` history row and the in-flight edit as `PNDREV` (only one `PNDREV` at a time, reachable from `APPR`/`INPRG`). So a single logical PO can have several physical rows differing by `REVISIONNUM`.

For current-state PO counts, spend, and backlog, take the **active** revision only:

```sql
-- current version of each PO (exclude revision history)
WHERE status <> 'REVISD'
-- or, if multiple non-REVISD rows exist, the max revision per PO:
QUALIFY ROW_NUMBER() OVER (PARTITION BY siteid, ponum ORDER BY revisionnum DESC) = 1
```

Counting raw `PO` rows without this double-counts every revised PO.

## 3. PR closes when its lines hit POs — "open PR" ≠ unmet demand

A purchase requisition auto-`CLOSE`s once **all** its line items are transferred to POs (an admin option). So a closed PR is "fully ordered," not "rejected." And **PR approval is OFF by default** — `WAPPR` PRs are the *creation* state, not necessarily an approval bottleneck. Before reporting "pending requisitions" or "requisition backlog," confirm (a) whether approval is enabled and (b) whether you mean PRs with un-transferred lines (real unmet demand) vs `WAPPR` status. See *Questions to surface first* in SKILL.md.

## 4. `LINECOST` (pretax) vs `LOADEDCOST` (freight) vs `TAX1`–`TAX5`

Three different "costs":
- `LINECOST` — **pretax** extended cost.
- `LOADEDCOST` — `LINECOST` + prorated freight/handling.
- `TAX1`…`TAX5` — tax, tracked **separately** (not in `LINECOST`).
- `POLINE.RECEIVEDTOTALCOST` = SUM of receipt `LINECOST` — **excludes tax and freight**.

Which field is the canonical "cost" is a per-Org MAXVAR (`RECEIPLINEORLOADED` for receiving, `CONTRALINEORLOADED` for contracts), so the same "spend" question yields different numbers across deployments. Confirm the cost basis (a `maximo-setup` fact) and state it. For cost **rolled up to assets/WOs** or **multi-currency** normalization, defer to `maximo-maintenance-cost`.

## 5. Partial receipts accumulate; received = accepted + rejected

A PO line is received over multiple `MATRECTRANS`/`SERVRECTRANS` rows; `POLINE.RECEIVEDQTY` is the cumulative total. On each receipt, **received quantity = `ACCEPTEDQTY` + `REJECTEDQTY`** — inspection can reject part of a delivery (`STATUS` flows `WINSP` → `WASSET`/`COMP`). For "fully received" use `RECEIVEDQTY >= ORDERQTY` on the PO line; for "accepted into stock" sum `ACCEPTEDQTY` (rejected qty was delivered but not accepted). Don't treat a single receipt row as the full delivery.

## 6. Three-way match is per PO line, gated by a receipt-required flag

Maximo enforces the PO ↔ receipt ↔ invoice match at **invoice approval**, per PO line: if a line requires receipts and none match, approval fails (error `BMXAA1993E`). So "three-way-match exceptions" = invoice lines whose `(PONUM, POLINENUM)` has no (or insufficient) matching receipt quantity — *for receipt-required lines*. Lines flagged receipt-not-required won't error, so don't count them as exceptions.

## 7. Credit / debit invoices distort quantity-based receipt rollups

`INVOICETYPE` includes `CREDIT` and `DEBIT` memos (adjustments / returns), which carry negative or corrective amounts. A documented Maximo behavior even recorded a credit service receipt with a *positive* quantity despite a negative line cost. When rolling up spend or matched quantities, decide explicitly whether to include credit/debit memos — summing them naively with standard invoices misstates both spend and match quantities.

## 8. Material vs service receipts live in different tables

`MATRECTRANS` holds **material** PO receipts; `SERVRECTRANS` holds **service** receipts. Which one applies is driven by `POLINE.LINETYPE` (`ITEM`/`MATERIAL` → MATRECTRANS; `SERVICE`/`STDSERVICE` → SERVRECTRANS). A receipt query that hits only `MATRECTRANS` silently omits all service spend (often a large share — contractors, rentals). Union both (or use the `MXRECEIPT` structure) for total received value.

## 9. Vendor identity is org-scoped (`COMPANY` + `ORGID`)

The vendor master `COMPANIES` is **organization-scoped**: the same real-world supplier has a separate row per org it's enabled in. Always join `doc.VENDOR = COMPANIES.COMPANY AND doc.ORGID = COMPANIES.ORGID`. For **enterprise-wide** vendor spend (one number per supplier across orgs), roll up via `COMPMASTER` (the company-set master) — grouping by `COMPANY` alone can split or collide vendors across orgs.

## 10. Multi-currency — transaction vs base currency

PO/receipt/invoice cost fields exist in both the **transaction** currency (`CURRENCYLINECOST` and friends) and the org's **base** currency. Summing `LINECOST` across vendors in different currencies is meaningless. Choose the field deliberately; for cross-currency normalization (exchange rates, reporting currency) defer to `maximo-maintenance-cost`.

## 11. Status synonyms & `HISTORYFLAG` — apply overview's patterns to all three docs

`PRSTATUS`, `POSTATUS`, and `INVOICESTATUS` are **synonym domains**: the column stores the renamable synonym `VALUE`, not the internal `MAXVALUE`. Resolve status sets via `SYNONYMDOMAIN` (don't hard-code literals when synonyms exist). And closed POs/invoices get `HISTORYFLAG = 1` and drop out of standard List views — confirm closed docs are present before completion/spend-trend metrics. These are universal mechanics — see `maximo-overview` gotchas 5–6; this gotcha just notes they apply to **all three** purchasing status columns.
