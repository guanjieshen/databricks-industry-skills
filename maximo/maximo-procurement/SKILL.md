---
name: maximo-procurement
description: |
  Use for IBM Maximo / Maximo / EAM / CMMS procurement & purchasing analytics —
  the purchase-requisition, purchase-order, receipt, and vendor-invoice layer.
  Covers PR / PRLINE, PO / POLINE, INVOICE / INVOICELINE, receipts
  (MATRECTRANS / SERVRECTRANS), the vendor master (COMPANIES), and contracts.
  Answers "open PO backlog", "vendor spend", "spend by vendor", "PO cycle time",
  "requisition to PO conversion", "on-time delivery", "three-way match
  exceptions", "under-received POs", "price variance", "maverick / off-contract
  spend", "top vendors". Triggers on: "purchase order", "PO", "PONUM",
  "purchase requisition", "PR", "requisition", "invoice", "vendor", "supplier",
  "procurement", "purchasing", "POLINE", "receipt", "3-way match", "MATRECTRANS".
  Compose with maximo-overview. For PO/PR/invoice approval routing use
  maximo-workflow-and-approvals; for cost rollup to assets / multi-currency use
  maximo-maintenance-cost; for stock receipts / reorder use maximo-inventory.
metadata:
  version: "0.1.0"
parent: maximo-overview
---

# Maximo Procurement

Help the user query, analyze, or build pipelines on IBM Maximo purchasing data — purchase requisitions, purchase orders, receipts, and vendor invoices, plus the vendor master. This skill adds the purchasing-specific schema, gold-standard queries, reusable views, and Trusted UDFs on top of `maximo-overview`'s baseline data-model literacy and universal gotchas.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas (SITEID composite keys, status-is-a-synonym-domain / `SYNONYMDOMAIN`, `HISTORYFLAG`, app-server-timezone datetimes). This skill builds on that foundation.

## When to use

Triggered by purchasing / procurement questions:
- "What's our open PO backlog?"
- "Spend by vendor last quarter" / "top vendors"
- "PO cycle time — requisition to order to receipt"
- "Which invoices failed three-way match?"
- "Under-received or overdue POs"
- "Requisition-to-PO conversion / open requisitions"
- "On-time delivery rate by vendor"
- "Off-contract / maverick spend"

**Defer to siblings when:**
- Where a PR/PO/invoice sits in **approval** (current approver, time-in-approval, stuck approvals) → `maximo-workflow-and-approvals`
- Cost **rolled up to an asset/location/WO**, budget-vs-actual, or **multi-currency normalization** → `maximo-maintenance-cost`
- **Stock** receipts feeding inventory balances, reorder, item availability for WOs → `maximo-inventory`

## Top gotchas

These traps silently produce wrong numbers. Read before writing any non-trivial query (full set in [gotchas.md](gotchas.md)):

1. **PO is a SITE-level record — key on `SITEID` + `PONUM`.** `PONUM` is unique only within a site (autonumbering can be system/org/site-level, but the record's scope is the site). `POLINE` inherits the header's `SITEID`/`ORGID`. Join PO↔POLINE↔receipts↔invoice on `SITEID` + `PONUM`, never `PONUM` alone or `ORGID` + `PONUM`.
2. **PO revisions: `REVISD` rows are historical copies — exclude them or you double-count.** A revised PO keeps the prior version as a `REVISD` history row and the in-flight edit as `PNDREV` (one at a time). For current-state PO counts/spend, filter to the active revision (`STATUS <> 'REVISD'`, highest `REVISIONNUM` per `SITEID`+`PONUM`).
3. **PR closes when its lines are assigned to POs — "open PR" ≠ unmet demand.** A PR auto-`CLOSE`s once all its line items are transferred to POs. PR approval is **OFF by default**, so `WAPPR` PRs may not represent a real approval bottleneck. Confirm before reporting "pending requisitions."
4. **`LINECOST` is PRETAX; `LOADEDCOST` adds freight/proration; tax is in `TAX1`–`TAX5`.** Which field counts as "cost" is a configurable Org MAXVAR (`RECEIPLINEORLOADED` / `CONTRALINEORLOADED`). `POLINE.RECEIVEDTOTALCOST` = SUM of receipt `LINECOST` and excludes tax/freight. Pick the cost basis deliberately — and defer rollup/multi-currency to `maximo-maintenance-cost` (gotcha: cost).
5. **Status is a synonym domain & `HISTORYFLAG` hides closed docs.** `POSTATUS`/`PRSTATUS`/`INVOICESTATUS` store the synonym `VALUE`, not the internal `MAXVALUE`; closed POs/invoices get `HISTORYFLAG = 1`. Apply the resolution + presence patterns from `maximo-overview` (gotchas 5–6) to *all three* status columns.

## Questions to surface first

Surface these to the user *before* answering — there is no defensible default:

1. **Cost basis & spend date.** Does "spend" mean `LINECOST` (pretax), `LOADEDCOST` (incl. freight), or `TOTALCOST`? And which date — PO order/approval date, receipt date, or invoice date? Each gives a different number (gotcha 4). The deployment's `RECEIPLINEORLOADED` MAXVAR (a `maximo-setup` fact) says which cost field is canonical.
2. **Approval reality.** Is PR/PO approval enabled in this deployment? PR approval is off by default, and `WAPPR` may not mean "awaiting a human." (Approval routing/time-in-approval itself → `maximo-workflow-and-approvals`.)
3. **Revisions.** Include historical PO revisions (`REVISD` rows) or only the current version of each PO? (gotcha 2)
4. **Vendor identity.** Roll up spend by `COMPANY` + `ORGID` (a vendor exists per organization) or enterprise-wide by the `COMPMASTER` company set? Confirm before aggregating vendor spend across orgs.

## Pre-flight (per session)

One-time session config — cache, don't re-ask:

1. **Catalog/schema** — confirm via the customer's workspace glossary skill if installed, or ask.
2. **Glossary skill** — is a `<customer>-maximo-glossary` workspace skill installed? Prefer it for business-term resolution.
3. **Cost-basis MAXVAR** — if cost questions are in play, confirm whether `RECEIPLINEORLOADED` is set to `LINECOST` or `LOADEDCOST` (a `maximo-setup` deployment fact).

If a business term is ambiguous and no glossary covers it, **ask before guessing**.

## Workflow

For any new question, resolve in this order:

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `open_po_count`, `po_line_received_pct`, `po_cycle_time_days`. If a UDF matches, call it.
2. **Parameterized example query** — check [examples.sql](examples.sql) for an existing pattern; use it with the user's parameters.
3. **Pre-joined view** — compose using `v_po_enriched` / `v_po_receipt_status` / `v_invoice_match` from [views.sql](views.sql).
4. **Raw tables** — only when the view layer doesn't cover the join shape. Explain why you're skipping the views.

## What's in this skill

- [schema.md](schema.md) — load when joining or selecting columns. Reference for `PR`/`PRLINE`, `PO`/`POLINE`, `INVOICE`/`INVOICELINE`, `MATRECTRANS`/`SERVRECTRANS`, `COMPANIES`, `CONTRACT`.
- [gotchas.md](gotchas.md) — load before writing non-trivial joins. Site-level PO key, PO revisions, PR-close semantics, cost basis (LINECOST/LOADEDCOST/tax), partial receipts, three-way match, credit/debit invoices, multi-currency, status synonyms.
- [examples.sql](examples.sql) — load when the user's question matches a pattern (vendor spend, open backlog, PO cycle time, 3-way-match exceptions, on-time delivery, requisition conversion, under-received POs).
- [views.sql](views.sql) — DDL for `v_po_enriched`, `v_po_receipt_status`, `v_invoice_match`. Register once via `maximo-setup`.
- [metric_udfs.sql](metric_udfs.sql) — Trusted Asset UC SQL functions Genie calls as governed metrics. Register once via `maximo-setup`.

## What NOT to do

- Don't author approval routing / current-approver / time-in-approval — that's `maximo-workflow-and-approvals` (it owns `WFINSTANCE`/`WFASSIGNMENT` across PR/PO/INVOICE).
- Don't roll PO/invoice cost up to assets/locations/WOs or normalize multi-currency — that's `maximo-maintenance-cost`. This skill stops at procurement-document analytics.
- Don't author inventory reorder / stock balance / item-availability logic — that's `maximo-inventory`. This skill owns PO/PR/INVOICE headers + lines and vendor analytics, not stock.
- Don't re-teach the universal mechanics (synonym domains, `HISTORYFLAG`, timezone, `SITEID`) — apply them and reference `maximo-overview`.
- Don't fabricate columns not in [schema.md](schema.md). If the user mentions a custom field, check the workspace glossary or ask.
- Don't write or alter UC comments / table metadata from this skill — those are owned by `maximo-setup` (preview-then-apply, gated on explicit approval).

## Composes with

- **`maximo-workflow-and-approvals`** — for the approval lifecycle of PRs/POs/invoices (where it is in the flow, who owns it, time-in-approval). This skill provides the procurement-document data; that skill provides the workflow engine.
- **`maximo-maintenance-cost`** — for cost rolled up to assets/locations/WOs, budget-vs-actual, PM-vs-CM, and multi-currency (`WOCURRENCY`/`EXCHANGERATE`) normalization. This skill passes `LINECOST`/`LOADEDCOST` through but doesn't own cost methodology.
- **`maximo-inventory`** — for the stock side: `MATRECTRANS` feeding `INVBALANCES`, reorder, ABC, item availability for WOs. Shared table `MATRECTRANS` — procurement reads it as PO receipts; inventory reads it as stock movement.
- **`maximo-setup`** to register the views in [views.sql](views.sql) and the Trusted UDFs in [metric_udfs.sql](metric_udfs.sql). Never run those scripts from this skill — defer to setup's preview-then-apply workflow.
