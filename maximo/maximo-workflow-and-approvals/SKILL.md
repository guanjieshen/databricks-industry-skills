---
name: maximo-workflow-and-approvals
description: |
  Use for Maximo Workflow & Approval analytics — finding who currently owns an
  approval, computing cycle time, surfacing stuck-in-approval records, analyzing
  approval bottlenecks across nodes, and reporting on approval activity for
  ANY Maximo business object (WORKORDER, PR, PO, INVOICE, MOC, INCIDENT,
  CHANGE, etc.). Triggers on: "stuck in approval", "approval workflow",
  "approval cycle time", "who needs to approve", "WFINSTANCE", "WFASSIGNMENT",
  "approval bottleneck", "where is this PO in the workflow", "open approvals",
  "my inbox", "pending tasks". This is a foundation-tier skill that composes
  with every other Maximo module skill — any record can be in a workflow.
metadata:
  version: "0.1.0"
parent: maximo-overview
---

# Maximo Workflow & Approvals

Help users query and analyze Maximo's workflow engine — the system that drives approvals, assignments, and routing for every business object in Maximo (work orders, POs, invoices, MoCs, tickets, incidents, etc.).

This is a **foundation skill** — it composes with every module skill. When someone asks "where is this WO in approval?" or "show me stuck POs", the workflow tables are the answer, not the business-object table.

> **FIRST:** load the `maximo-overview` skill — it carries the baseline Maximo data model, the module map, and the universal gotchas (SITEID composite keys, `WOCLASS` filtering, `ISTASK` dedup, WOSTATUS-vs-WORKORDER history). This skill builds on that foundation.

## When to use

- "Where is this WO / PO / invoice in the approval flow?"
- "Show me records stuck in approval > N days"
- "Approval cycle time by node / approver / record type"
- "Who currently owns this approval?"
- "What's in my approval inbox?"
- "Approval bottlenecks — which workflow node is slowest?"
- "How long did the last approval cycle take for this record?"
- Any analysis crossing workflow + a business object (WO, PO, INVOICE, MOC, INCIDENT)

If the user's question is about a *specific business object* without touching approval/workflow concepts, defer to the module skill (work-orders, procurement, hse, etc.).

## Pre-flight (per session)

1. **Silver catalog/schema**: confirm via workspace glossary or ask.
2. **Workflow process names of interest**: Maximo customers typically have processes like `WOAPPR`, `PRAPPR`, `POAPPR`, `INVCAPPR`, etc. Confirm if focusing on a specific process.
3. **E-signature requirement**: some workflows require e-signature on certain transitions. Affects audit interpretation.

## The four core tables

| Table | What it holds | Grain |
|---|---|---|
| `WFINSTANCE` | Active workflow runs (one per business record currently in workflow) | One row per (record, process) currently active |
| `WFASSIGNMENT` | Approval inbox — assignments created at Task nodes | One row per (instance, node, approver) |
| `WFNODE` | Workflow process definition — nodes and their types | Reference / metadata |
| `WFTRANSACTION` | Workflow event log — every transition that happened | Append-only history |

See [schema.md](schema.md) for full column reference.

## Workflow priority

For any new question, resolve in this order:

1. **Trusted UDFs** in [metric_udfs.sql](metric_udfs.sql) — `current_approval_age`, `mean_cycle_time`, `open_approvals_count`
2. **Pre-joined views** in [views.sql](views.sql) — `v_open_approvals` (currently in flight), `v_workflow_history` (transaction log enriched)
3. **Parameterized examples** in [examples.sql](examples.sql)
4. **Raw tables** — last resort

## What's in this skill

- [schema.md](schema.md) — WFINSTANCE, WFASSIGNMENT, WFNODE, WFTRANSACTION with key columns, joins, cardinality
- [gotchas.md](gotchas.md) — `ASSIGNSTATUS` lifecycle, `ACTIVE=1` vs leaves-workflow, person-group peer rules, e-signature, completed vs forwarded
- [examples.sql](examples.sql) — parameterized queries: current owner, cycle time, stuck-in-approval, bottlenecks
- [views.sql](views.sql) — `v_open_approvals`, `v_workflow_history`
- [metric_udfs.sql](metric_udfs.sql) — **Trusted Asset functions**: UC SQL functions you register once so Genie Spaces call them as *certified, governed metrics* instead of regenerating ad-hoc SQL. Register via `maximo-setup` or by running the file, then reference the functions by name.

## What NOT to do

- **Don't infer approval state from the business-object STATUS field alone.** A WO can be in `WAPPR` (waiting approval) but the workflow detail (who, what node, since when) lives in `WFINSTANCE`/`WFASSIGNMENT`.
- **Don't assume `WFINSTANCE.ACTIVE = 0` means "completed".** It means the workflow has left the record — could be completed, cancelled, or rejected. Cross-reference with `WFTRANSACTION` for the actual termination reason.
- **Don't treat `WFASSIGNMENT` rows as "approvers" without checking `ASSIGNSTATUS`.** A row with `ASSIGNSTATUS = 'INACTIVE'` is a person-group peer who didn't take action — counting them as approvers inflates participation metrics.
- **Don't measure cycle time using `WFINSTANCE.STARTDATE` to `current_timestamp()` for closed workflows.** Use `WFTRANSACTION` for the actual termination event.

## Composes with

- `maximo-work-orders` — WO approval flows (`WOAPPR`)
- `maximo-procurement` (planned v3) — PR / PO / invoice approvals
- `maximo-hse` — MoC approvals, incident-investigation routing
- `maximo-service-desk` (planned v3) — SR/ticket assignment workflows

When a question crosses both workflow and a module, both skills should load and compose.

## References

- [schema.md](schema.md)
- [gotchas.md](gotchas.md)
- [examples.sql](examples.sql)
- [views.sql](views.sql)
- [metric_udfs.sql](metric_udfs.sql)
- IBM Workflow Implementation Guide (PDF): https://www.ibm.com/docs/en/SSLKT6_7.6.0/com.ibm.mbs.doc/pdf_mbs_workflow.pdf
- IBM Support — Inner Workings of Workflow: https://www.ibm.com/support/pages/inner-workings-workflow
