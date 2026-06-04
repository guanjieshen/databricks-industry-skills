# Maximo Workflow & Approvals — Gotchas

## 1. `WFINSTANCE.ACTIVE = 0` does NOT mean "completed"

`ACTIVE` is binary: `1` = workflow is currently engaged with the record, `0` = workflow has left. But "left" can mean three things:

- **Completed** — the workflow ran through to a Stop node successfully
- **Cancelled** — someone explicitly cancelled the workflow
- **Rejected / aborted** — a Condition node routed to termination

To distinguish, look at `WFTRANSACTION` for the final transaction with that `WFID`:

```sql
SELECT wt.transaction, wt.transdate, wt.memo
FROM WFTRANSACTION wt
WHERE wt.wfid = <wfid>
ORDER BY wt.transdate DESC
LIMIT 1;
```

A `STOP` transaction is "completed normally". A cancel or reject typically shows up as a different transaction type with memo context.

## 2. `WFASSIGNMENT.ASSIGNSTATUS` lifecycle has four states

The lifecycle is documented in the IBM Workflow Implementation Guide:

| State | Meaning |
|---|---|
| `ACTIVE` | Currently awaiting action from the assignee |
| `COMPLETE` | The assignee acted (approved, rejected, etc.) |
| `FORWARDED` | The assignee delegated to someone else (a new `WFASSIGNMENT` row is created for the delegate) |
| `INACTIVE` | Person-group peer who did NOT act — the assignment was claimed by another peer |

**Implication for analytics**:
- "Who needs to act right now" → `ASSIGNSTATUS = 'ACTIVE'`
- "Who actually approved" → `ASSIGNSTATUS = 'COMPLETE'`
- "Delegation chain" → walk forward through `ASSIGNSTATUS = 'FORWARDED'` rows
- Don't count `INACTIVE` rows as participants — they were potential approvers who never took action

## 3. Person-group peer assignments inflate counts unless filtered

When a Task node is assigned to a person-group, Maximo creates an `ACTIVE` row for **every member of the group**. The first peer to act gets `ASSIGNSTATUS = 'COMPLETE'`; the remaining peers get `ASSIGNSTATUS = 'INACTIVE'`.

If you `COUNT(*)` `WFASSIGNMENT` rows naïvely, you'll over-count assignments at a 4-person-group node by 4×.

Patterns:
- "Number of approval steps that occurred" → count rows with `ASSIGNSTATUS IN ('COMPLETE', 'FORWARDED')`
- "Number of assignment events created" → count all rows
- "Currently waiting on" → `ASSIGNSTATUS = 'ACTIVE'` (still has 4 rows per group, but `DISTINCT WFID, NODEID` collapses correctly)

## 4. `WFINSTANCE.OWNERID` is a surrogate key, not the business key

`WFINSTANCE.OWNERID = WORKORDER.WORKORDERID`, not `WORKORDER.WONUM`. The mapping is:

| Business object | `OWNERTABLE` | `OWNERID` joins to |
|---|---|---|
| Work order | `WORKORDER` | `WORKORDER.WORKORDERID` |
| Purchase requisition | `PR` | `PR.PRID` (typically — verify per customer) |
| Purchase order | `PO` | `PO.POID` (typically) |
| Invoice | `INVOICE` | `INVOICE.INVOICEID` |
| MOC | `MOC` | `MOC.MOCID` |
| Incident | `INCIDENT` | `INCIDENT.INCIDENTID` |
| Ticket / SR | `TICKET` | `TICKET.TICKETID` |

Always cross-reference with the customer's actual ingestion — partner connectors sometimes drop or rename surrogate columns.

## 5. Cycle time has two meanings — assignment-level vs workflow-level

| Cycle time | Definition | Source |
|---|---|---|
| **Assignment cycle time** | Time from `ASSIGNDATE` to `COMPLETEDATE` for a single assignment | `WFASSIGNMENT` |
| **Workflow cycle time** | Time from workflow start to workflow end (when `ACTIVE` flipped to `0`) | `WFINSTANCE.STARTDATE` + last `WFTRANSACTION.TRANSDATE` |

For a stuck-in-approval analysis, you usually want assignment-level. For a "how long does our PO approval take end-to-end" analysis, you want workflow-level.

Cycle time **of a still-active workflow** = `datediff(NOW, WFINSTANCE.STARTDATE)`. Cycle time of a closed workflow = `datediff(WFINSTANCE.STARTDATE, max(WFTRANSACTION.TRANSDATE))`.

## 6. E-signature requirements affect interpretation

Some transitions require e-signature (configured at the workflow node or object-level). When e-sig is required:
- The action records both an `ASSIGNSTATUS = COMPLETE` on `WFASSIGNMENT` AND an entry in `LOGINTRACKING` or `SIGOPTION`
- A failed e-sig can leave the assignment `ACTIVE` while the operator sees an error

If your analytics show "approver took 3 seconds to approve", investigate — they may have been bypassing e-sig configuration or the row may not represent what it appears to.

References:
- IBM Workflow Implementation Guide
- IBM Support — e-signature on workflow records

## 7. Subprocess nodes don't generate WFASSIGNMENT rows

When a workflow includes a Subprocess node, the **subprocess** has its own `WFINSTANCE` rows. The parent workflow doesn't create a `WFASSIGNMENT` for the subprocess invocation itself.

For "all approvals on this record" queries, walk the subprocess tree by joining child `WFINSTANCE` rows back to the parent (via `WFINSTANCE.OWNERTABLE = 'WFINSTANCE'` pattern in some configurations, or via process-name conventions).
