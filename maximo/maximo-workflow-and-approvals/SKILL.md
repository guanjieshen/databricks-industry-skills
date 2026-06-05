---
name: maximo-workflow-and-approvals
description: |
  Use for IBM Maximo / Maximo / EAM / CMMS workflow & approval analytics:
  who currently owns an approval, time-in-approval / cycle time, stuck-in-approval
  records, approval bottlenecks by node, and approval/routing activity for ANY
  Maximo business object (WORKORDER, PR, PO, INVOICE, TICKET/SR, INCIDENT, CHANGE,
  MOC). Built on the WFINSTANCE / WFASSIGNMENT / WFNODE / WFTRANSACTION tables.
  Triggers on: "stuck in approval", "approval workflow", "approval cycle time",
  "time in approval", "who needs to approve", "who owns this approval",
  "WFINSTANCE", "WFASSIGNMENT", "ASSIGNSTATUS", "WFTRANSACTION", "approval
  bottleneck", "where is this PO in the workflow", "open approvals", "my inbox",
  "pending tasks", "rejection rate", "workflow history". Foundation-tier skill
  that composes with every Maximo module — any record can be in a workflow.
  Compose with maximo-overview for baseline data-model and synonym-domain literacy.
metadata:
  version: "0.2.0"
parent: maximo-overview
---

# Maximo Workflow & Approvals

Help users query and analyze Maximo's workflow engine — the system that drives approvals, assignments, and routing for every business object in Maximo (work orders, POs, invoices, tickets, incidents, MoCs, etc.). When someone asks "where is this WO in approval?" or "show me stuck POs", the workflow tables are the answer, not the business-object table.

This is a **foundation skill** — it composes with every module skill, because any record can be in a workflow.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas (SITEID composite keys, status-is-a-synonym-domain / `SYNONYMDOMAIN` resolution, app-server-timezone datetimes, `WOCLASS`, `ISTASK`). This skill builds on that foundation and applies those mechanics to the workflow tables.

## When to use

- "Where is this WO / PO / invoice / ticket in the approval flow?"
- "Show me records stuck in approval > N days"
- "Time in approval / cycle time by node / approver / record type"
- "Who currently owns this approval?"
- "What's in my approval inbox?"
- "Approval bottlenecks — which workflow node is slowest?"
- "What % of POs get approved / rejection rate?"
- Any analysis crossing workflow + a business object (WO, PO, INVOICE, TICKET, INCIDENT)

**Defer to siblings when:** the question is about a *specific business object* without touching approval/workflow concepts (backlog, cost, reliability) → the relevant module skill (`maximo-work-orders`, `maximo-maintenance-cost`, etc.).

## Top gotchas

These traps silently produce wrong numbers. Read before writing any non-trivial query (full set of 11 in [gotchas.md](gotchas.md); `maximo-overview` carries the universal ones — synonym domains, app-server-timezone datetimes):

1. **`ASSIGNSTATUS` has three persisted states — `FORWARDED` is narrative, not stored.** The formal `WFAssignment` domain is `DEFAULT / ACTIVE / COMPLETE / INACTIVE` (`DEFAULT` = template rows only). `FORWARDED` is IBM prose, **not** a stored value — do NOT key queries on a literal `'FORWARDED'`. `COMPLETE` = this person acted/routed; `INACTIVE` = superseded (group peer accepted, or workflow stopped).
2. **Route disposition (approved vs rejected) lives in `WFTRANSACTION`, not in `RESULT`/`COMPLETED` on the assignment.** `WFAssignment` has no documented `RESULT` or `COMPLETED` column — verify before keying a pass/rejection-rate query on `WFASSIGNMENT.RESULT`. Compute outcomes from `WFTRANSACTION` route types instead.
3. **`WFINSTANCE.ACTIVE = 0` ≠ "completed", and the row is retained.** `0` covers completed, cancelled/user-stopped, or rejected. The row is deactivated in place (not deleted), so `ACTIVE = 0` history is valid. Read the terminating `WFTRANSACTION.TRANSTYPE` (e.g. `WFUSERSTOPPED`) for the real reason.
4. **`WAPPR` ≠ "in workflow".** `WAPPR` is the default record status and is independent of whether a workflow is active — a record can be `WAPPR` with NO active `WFINSTANCE`. Determine presence-in-workflow from `WFINSTANCE.ACTIVE = 1` (or an `ACTIVE` `WFASSIGNMENT`), never from `STATUS = 'WAPPR'`.
5. **`WFINSTANCE.OWNERID` is the surrogate unique-ID column, not the business key.** `OWNERID = WORKORDER.WORKORDERID`, NOT `WONUM`. The ticket family is the naming exception — it uses `TICKETUID`, not `TICKETID`. Confirm custom objects via `MAXOBJECT.uniquecolumnname` ([schema.md](schema.md)).

## Questions to surface first

Surface these to the user *before* answering — there is no defensible default:

1. **What is "the approval cycle"?** Per-assignment time-in-approval (`WFASSIGNMENT.STARTDATE` → completing `WFTRANSACTION`) and end-to-end workflow time (`WFINSTANCE.STARTDATE` → terminating transaction) give different numbers. For "stuck in approval" you usually want per-assignment; for "how long does PO approval take end-to-end" you want workflow-level. Confirm which.
2. **What counts as "approved" vs "rejected"?** Disposition is not on the assignment row by default — it is in `WFTRANSACTION` route types, which are synonym-domain values (`WFTRANSTYPE`) that customers rename. Confirm which `TRANSTYPE` values represent positive (e.g. `WFACCEPT`) vs negative (e.g. `WFREJECT`) outcomes in this deployment before computing a rejection rate; enumerate them from `SYNONYMDOMAIN`.
3. **Which workflow process(es)?** Customers typically have `WOAPPR`, `PRAPPR`, `POAPPR`, `INVCAPPR`, etc. Confirm the `PROCESSNAME`(s) of interest, or whether the analysis spans all processes.
4. **Is the deployment's audit trail trusted?** Some defective releases drop `WFTRANSACTION`/status-history rows (APARs `IV85807`, `IZ88857`). Before basing audit or cycle-time metrics on the transaction log, confirm it is complete in this deployment.

## Pre-flight (per session)

One-time session config — cache, don't re-ask:

1. **Silver catalog/schema** — confirm via the customer's workspace glossary skill if installed, or ask.
2. **Glossary skill** — is a `<customer>-maximo-glossary` workspace skill installed? Prefer it for business-term and process-name resolution.
3. **`WFTRANSTYPE` synonym set** — enumerate `SYNONYMDOMAIN WHERE DOMAINID = 'WFTRANSTYPE'` once; cache the positive/negative/stop values for outcome queries.

## Workflow

For any new question, resolve in this order:

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `current_approval_age`, `mean_cycle_time`, `open_approvals_count`. If a UDF matches, call it.
2. **Pre-joined views** in [views.sql](views.sql) — `v_open_approvals` (in flight), `v_workflow_history` (transaction log enriched), `v_workflow_cycle_times` (closed-workflow cycle times).
3. **Parameterized examples** in [examples.sql](examples.sql).
4. **Raw tables** — last resort; explain why the view layer doesn't cover the shape.

## What's in this skill

- [schema.md](schema.md) — load when joining or selecting columns. `WFINSTANCE`, `WFASSIGNMENT`, `WFNODE`, `WFTRANSACTION`, the OWNERID surrogate-key map, and cardinality.
- [gotchas.md](gotchas.md) — load before writing non-trivial queries. 11 gotchas: `ASSIGNSTATUS` states, disposition-in-`WFTRANSACTION`, `ACTIVE=0` semantics, `WAPPR`≠in-workflow, OWNERID join trap, reassignment-via-`ASSIGNCODE`, `STARTDATE`/`DUEDATE` time-in-approval, person-group peers, `TRANSTYPE` synonym resolution, subprocess nodes, audit-completeness APARs.
- [examples.sql](examples.sql) — load when the user's question matches a pattern (inbox, stuck-in-approval, cycle time by node, end-to-end cycle time, current owner, audit trail, top approvers, termination outcomes).
- [views.sql](views.sql) — DDL for `v_open_approvals`, `v_workflow_history`, `v_workflow_cycle_times`. Register once via `maximo-setup`.
- [metric_udfs.sql](metric_udfs.sql) — Trusted Asset UC SQL functions Genie Code calls as governed metrics instead of regenerating ad-hoc SQL. Register once via `maximo-setup`.

## What NOT to do

- **Don't infer approval state from the business-object `STATUS` alone.** `WAPPR` does not imply an active workflow (gotcha 4); the who/what-node/since-when detail lives in `WFINSTANCE`/`WFASSIGNMENT`.
- **Don't key queries on `ASSIGNSTATUS = 'FORWARDED'` or on `WFASSIGNMENT.RESULT`/`COMPLETED`** — none are documented persisted values/columns (gotchas 1–2). Read disposition from `WFTRANSACTION`.
- **Don't treat `WFASSIGNMENT` rows as "approvers" without checking `ASSIGNSTATUS`** — `INACTIVE` rows are superseded peers/stopped routes and inflate participation metrics.
- **Don't hardcode `TRANSTYPE` literals** (`'STOP'`, `'cancel'`) — resolve via `SYNONYMDOMAIN` (`DOMAINID = 'WFTRANSTYPE'`); a verified real value is `WFUSERSTOPPED` (gotcha 9).
- **Don't measure cycle time from `WFINSTANCE.STARTDATE` to `current_timestamp()` for closed workflows** — use the terminating `WFTRANSACTION.TRANSDATE`.
- **Don't write or alter UC comments / table metadata from this skill** — UC comments are owned by `maximo-setup` (preview-then-apply, gated on explicit user approval). Defer to it.

## Composes with

When a question crosses both workflow and a module, both skills should load and compose.

- **`maximo-work-orders`** — WO approval flows (`WOAPPR`). Join `WFINSTANCE.OWNERID = WORKORDER.WORKORDERID` (with `OWNERTABLE = 'WORKORDER'`); apply that skill's `WOCLASS`/`ISTASK`/`SITEID` gotchas to the WO side of the join.
- **`maximo-maintenance-cost`** — for PR/PO/INVOICE approval analyses that touch cost/spend (e.g. value-weighted approval cycle time), defer cost methodology and multi-currency normalization there; this skill owns only the workflow/routing side.
- **`maximo-hse`** — MoC approvals and incident-investigation routing; this skill provides the workflow tables, that skill owns MoC/incident semantics.
- **`maximo-overview`** — universal mechanics: `WFTRANSACTION.TRANSTYPE` synonym-domain resolution and app-server-timezone datetimes are applied here but owned and taught there (don't re-teach).
- **`maximo-setup`** — to register the views in [views.sql](views.sql) and the Trusted UDFs in [metric_udfs.sql](metric_udfs.sql). Never run those scripts from this skill — defer to setup's preview-then-apply workflow.

## References

- IBM Workflow Implementation Guide (PDF): https://www.ibm.com/docs/en/SSLKT6_7.6.0/com.ibm.mbs.doc/pdf_mbs_workflow.pdf
- IBM Support — Inner Workings of Workflow: https://www.ibm.com/support/pages/inner-workings-workflow
- Maximo 7.6 Java API — `psdi.workflow.WFAssignment`, `psdi.workflow.WFTransaction`
