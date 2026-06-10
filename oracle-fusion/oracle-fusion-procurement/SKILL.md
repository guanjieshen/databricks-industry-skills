---
name: oracle-fusion-procurement
description: |
  Use for Oracle Fusion Cloud ERP / Fusion Procurement / Fusion SCM purchasing
  analytics — purchase orders, agreements, requisitions, suppliers, and spend.
  Covers the requisition→PO→schedule→distribution chain (POR_REQUISITION_HEADERS_ALL,
  PO_HEADERS_ALL, PO_LINES_ALL, PO_LINE_LOCATIONS_ALL, PO_DISTRIBUTIONS_ALL) and the
  supplier master (POZ_SUPPLIERS, supplier sites, VENDOR_ID/VENDOR_SITE_ID). Triggers
  on business phrasings: "PO spend", "purchase order spend", "supplier spend", "spend
  by supplier", "purchase order backlog", "open POs", "3-way match", "match
  exceptions", "PO cycle time", "requisition to PO", "req-to-PO conversion",
  "contract leakage", "off-contract spend", "blanket purchase agreement", "BPA
  releases", "spend by cost center", "spend by account". The central concept this
  skill encodes: ORDERED vs RECEIVED vs INVOICED/BILLED are three different numbers
  from three different grains — never conflate them. Composes the keystone
  oracle-fusion-ledger-coa for account/cost-center decode (PO_DISTRIBUTIONS_ALL
  carries CODE_COMBINATION_ID) and currency normalization. Invoice/payment facts
  (AP_INVOICES_ALL) are a future oracle-fusion-payables concern — out of scope (P2P
  boundary).
metadata:
  version: "0.1.0"
parent: oracle-fusion-overview
---

# Oracle Fusion — Procurement (purchase orders, suppliers, spend)

Help the user query, analyze, or build pipelines/dashboards/Genie agents on Oracle Fusion procurement data. This skill adds the purchasing-specific schema, gold-standard queries, reusable views, and Trusted UDFs on top of `oracle-fusion-overview`'s baseline data-model literacy, and composes the keystone `oracle-fusion-ledger-coa` for accounting dimensionality (the charged account on a PO distribution and currency normalization).

> **FIRST:** load the `oracle-fusion-overview` skill — it carries the org model (Ledger / LE / BU), the landing-pattern-agnostic rule (Fusion is SaaS; physical names are PVO/FDI and vary by customer), and the universal gotchas (`_ALL` multi-org scoping, CCID segments, currency, posted-vs-unposted, cancel/close). This skill is the procurement depth beneath it.

## When to use

Triggered by purchasing / spend / supplier operational questions:
- "What's our PO spend by supplier this quarter?"
- "Show me the open PO backlog by business unit."
- "Which schedules have 3-way-match exceptions?"
- "Average requisition-to-PO cycle time."
- "How much spend is off-contract (contract leakage)?"
- "Spend by cost center / by account" (composes the keystone for CCID decode).
- "Top suppliers by ordered amount; received vs billed."
- "Build a procurement / supplier-spend dashboard or Genie space."

**Defer to siblings when:**
- The question is about **invoices, payments, holds, or AP aging** (`AP_INVOICES_ALL`, `AP_INVOICE_DISTRIBUTIONS_ALL`) → a future `oracle-fusion-payables`. **Invoiced/billed spend as an AP fact is out of scope here** — this skill reports the *PO-side* billed quantity/amount (`QUANTITY_BILLED`, `AMOUNT_BILLED`, updated by Payables on invoice match), not the AP invoice itself. See *Composes with* (P2P boundary).
- Anything touching the **chart of accounts, segment meaning, period status, or currency conversion** → the keystone `oracle-fusion-ledger-coa`. This skill *composes* it; it does not redefine it.
- General Ledger journals/balances → `oracle-fusion-general-ledger`.

## Top gotchas

These silently produce wrong spend numbers. Read before writing any non-trivial query (full set in [gotchas.md](gotchas.md); `oracle-fusion-overview` carries the org-wide ones):

1. **ORDERED ≠ RECEIVED ≠ INVOICED/BILLED — three numbers, three grains.** This is *the* central procurement trap. **Ordered** (commitment) = schedule `QUANTITY` × price, or distribution `QUANTITY_ORDERED` × price. **Received** = `PO_LINE_LOCATIONS_ALL.QUANTITY_RECEIVED` (updated by receiving). **Invoiced/Billed** = `QUANTITY_BILLED` / `PO_DISTRIBUTIONS_ALL.AMOUNT_BILLED` (updated by Payables on invoice match). They answer different questions; **never report one as another, and always confirm which the user means** (see *Questions to surface first*).
2. **Grain mismatch — don't sum amounts across levels.** PO quantity lives at the **line** level; scheduled/received quantity at the **schedule** (`PO_LINE_LOCATIONS_ALL`) level; ordered/billed *amount* at the **distribution** (`PO_DISTRIBUTIONS_ALL`) level. A header joined to lines joined to schedules joined to distributions **fans out** — summing a line amount after that join multi-counts. Sum each measure at its native grain; the charged-account spend total lives at the distribution grain.
3. **`_ALL` tables are multi-org — scope by `PRC_BU_ID`.** `PO_HEADERS_ALL` holds every procurement business unit's POs. Summing without a `PRC_BU_ID` (procurement BU) filter mixes orgs. Always scope (overview gotcha 1).
4. **Respect `CANCEL_FLAG` and `CLOSED_CODE`.** Canceled POs (`CANCEL_FLAG = 'Y'`) are not spend. Closed/finally-closed schedules (`CLOSED_CODE` on the header and the schedule) are complete and should not be counted as open backlog. Also honor `APPROVED_FLAG` if the user wants approved commitments only.
5. **Match rule changes which quantities you compare, and the rule is per-schedule.** 2-way = ordered vs invoiced; **3-way** adds `QUANTITY_RECEIVED` and applies **only when `RECEIPT_REQUIRED_FLAG = 'Y'`**; **4-way** also adds `QUANTITY_ACCEPTED` and applies **only when `INSPECTION_REQUIRED_FLAG = 'Y'`**. Computing a 3-way exception on schedules that aren't receipt-required produces false positives. Confirm the match rule.
6. **Blanket Purchase Agreements (BPAs) and their releases.** `TYPE_LOOKUP_CODE = 'BLANKET'` is a Blanket Purchase Agreement (the negotiated agreement, not an order). **Releases against a BPA generate their own PO rows** — counting both the agreement and its releases double-counts committed spend. Decide explicitly whether the question is about agreements, releases, or standard POs (and which currency basis — gotcha in [gotchas.md](gotchas.md)).

## Questions to surface first

Surface these to the user *before* answering — there is no defensible default:

1. **Spend definition.** Ordered (commitment), received (goods in), or invoiced/billed (Payables-matched)? These are three different numbers from three grains (gotcha 1). This is the single most important question for any "spend" ask.
2. **Match rule.** 2-way (ordered vs invoiced), 3-way (also received, receipt-required only), or 4-way (also accepted, inspection-required only)? Determines which quantities a "match exception" compares (gotcha 5).
3. **Business-unit scope.** Which procurement BU(s) (`PRC_BU_ID`)? All, or a named set? `_ALL` tables mix orgs (gotcha 3).
4. **Document types.** Standard POs only, or include Blanket Purchase Agreements / Contract / Planned? Include BPA releases? (gotcha 6, `TYPE_LOOKUP_CODE`).
5. **Status filters.** Exclude canceled (`CANCEL_FLAG = 'Y'`) and closed (`CLOSED_CODE`)? Approved-only (`APPROVED_FLAG = 'Y'`)? (gotcha 4).
6. **Currency basis + which date.** Entered (PO `CURRENCY_CODE`) or ledger currency? Which date drives time bucketing (PO creation / approval / promised / need-by)? Cross-BU totals must normalize via the keystone (`convert_to_ledger_currency`).

## Pre-flight (per session)

One-time session config — cache, don't re-ask:

1. **Catalog/schema** — confirm via the workspace glossary skill if installed, or ask. Placeholders: `:catalog`, `:silver_schema`, `:gold_schema`.
2. **Glossary skill** — is a `<customer>-oracle-fusion-glossary` installed? It holds the **physical→canonical table mapping** (Fusion lands as BICC PVO / FDI; canonical EBS-style names like `PO_HEADERS_ALL` are not the physical names), the **COA segment→meaning map** (which segment is cost center / natural account), and the BU/ledger list. Prefer it over assumptions.
3. **Landing pattern** — BICC PVO vs FDI changes physical names and currency-basis columns; the glossary maps them. Never hard-code a physical table name; never promise raw-table SaaS access.

## Workflow

**Building a semantic layer / Genie Agent / dashboard (the most common ask):** start from [metric_view.yaml](metric_view.yaml) — the governed procurement semantic layer over a gold `v_po_spend` view. Its measures (`ordered_amount`, `received_amount`, `billed_amount`, `po_count`, `open_po_count`, `received_rate`, …) and **agent metadata** (synonyms like "PO spend", "supplier spend", "PO backlog") are defined once and sliceable by BU / supplier / buyer / category / PO type / date. The three spend bases are **distinct measures** — the layer never collapses them into one "spend". Defer creation/registration mechanics to [`databricks-metric-views`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-metric-views); `oracle-fusion-setup` owns registration.

**Answering an ad-hoc question:** resolve in this order:

1. **Metric view** — if a procurement metric view is registered, query it with `MEASURE(...)`; it encodes the canonical spend-basis definitions and the cancel filter.
2. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `po_spend(prc_bu_id, spend_basis)`, `supplier_spend(vendor_id, basis)`, `open_po_count(prc_bu_id)`, `three_way_match_exceptions(prc_bu_id)` — when the metric takes parameters.
3. **Parameterized example query** — check [examples.sql](examples.sql) for an existing pattern; use it with the user's parameters.
4. **Pre-joined view** — compose using `v_po_enriched` (header+line+schedule, decoded account, supplier name) and `v_po_spend` (distribution-grain ordered/received/billed) from [views.sql](views.sql).
5. **Raw canonical tables** — `PO_HEADERS_ALL` → `PO_LINES_ALL` → `PO_LINE_LOCATIONS_ALL` → `PO_DISTRIBUTIONS_ALL`, `POR_REQUISITION_HEADERS_ALL`, `POZ_SUPPLIERS` — only when the view layer doesn't cover the shape. Resolve physical names via the glossary first; explain why you're skipping the views.

## What's in this skill

- [schema.md](schema.md) — **load when** joining or selecting columns. Canonical reference for the requisition→PO→line→schedule→distribution chain and suppliers, the **grain table** (which amount lives at which level), cardinality, and the landing-pattern note.
- [gotchas.md](gotchas.md) — **load before** writing non-trivial procurement joins. The inline 6 plus the spend-definition matrix, match-rule flags, supplier-site grain, currency basis, and BPA-release double-count.
- [views.sql](views.sql) — DDL for `v_po_enriched` and `v_po_spend` (distribution-grain, with decoded account via the keystone's `v_code_combination`). Registered once via `oracle-fusion-setup`.
- [metric_udfs.sql](metric_udfs.sql) — Trusted Asset UC functions: `po_spend`, `supplier_spend`, `open_po_count`, `three_way_match_exceptions`. Registered once via `oracle-fusion-setup`.
- [metric_view.yaml](metric_view.yaml) — **load when** building/extending the procurement semantic layer, a Genie Agent, or a dashboard. Canonical measures + agent metadata over a gold `v_po_spend`, with the cancel filter baked in and the three spend bases kept distinct.
- [examples.sql](examples.sql) — **load when** the question matches a pattern (spend by supplier on a basis, open backlog by BU, 3-way-match exceptions, req-to-PO cycle time, contract leakage, spend by cost center via the keystone decode).

## What NOT to do

- Don't conflate ordered / received / invoiced-billed spend — they are three grains, three numbers (gotcha 1). Confirm which the user means.
- Don't sum amounts across grains (line + distribution) after a fan-out join — sum each measure at its native grain (gotcha 2).
- Don't sum across business units (`_ALL` tables) without a `PRC_BU_ID` scope (gotcha 3).
- Don't count canceled (`CANCEL_FLAG`) or closed (`CLOSED_CODE`) POs as open backlog or spend (gotcha 4).
- Don't flag 3-way / 4-way exceptions on schedules that aren't receipt-/inspection-required (gotcha 5).
- Don't count both a Blanket Purchase Agreement and its releases as committed spend (gotcha 6).
- Don't redefine the keystone's CCID decode or currency conversion — **compose** `oracle-fusion-ledger-coa` (`v_code_combination` / `decode_ccid_segments`, `convert_to_ledger_currency`).
- Don't compute invoiced spend from AP tables — that's the future `oracle-fusion-payables` (P2P boundary). Report the PO-side billed quantity/amount only.
- Don't hard-code a physical table name without checking the glossary; don't promise raw-table access (Fusion is SaaS — landing-agnostic rule).
- Don't write or alter UC comments / table metadata from this skill — owned by `oracle-fusion-setup` (preview-then-apply).

## Composes with

- **`oracle-fusion-overview`** — org model + universal gotchas + landing-agnostic rule. Always loaded first.
- **`oracle-fusion-ledger-coa`** (**KEYSTONE**) — for **spend-by-account / spend-by-cost-center**, `PO_DISTRIBUTIONS_ALL.CODE_COMBINATION_ID` joins to the keystone's `v_code_combination` / `decode_ccid_segments` to resolve segments to names; for **currency normalization**, cross-BU spend totals use `convert_to_ledger_currency`. This skill never redefines those assets.
- **`oracle-fusion-payables`** (future — **P2P boundary**) — Procurement owns ordering + receiving (`PO_*`). Payables owns invoicing and payment (`AP_INVOICES_ALL`, `AP_INVOICE_DISTRIBUTIONS_ALL`). Invoiced spend as an AP fact joined back to the PO is a payables concern; this skill stops at the PO-side `QUANTITY_BILLED` / `AMOUNT_BILLED` that Payables writes onto the schedule/distribution.
- **`oracle-fusion-general-ledger`** — once procurement accounting is created (via XLA), committed/received spend posts to GL; reconcile there, not in this skill.
- **`oracle-fusion-setup`** — owns the physical→canonical mapping, segment meanings, and registration of these views/UDFs/metric view. Never run those scripts from this skill.
- **`databricks-metric-views`** (platform) — the *mechanics* of creating/registering/refreshing the metric view. This skill supplies the source-specific YAML + agent metadata; that skill supplies the how.
