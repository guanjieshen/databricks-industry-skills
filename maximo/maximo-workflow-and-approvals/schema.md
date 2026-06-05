# Maximo Workflow & Approvals — Schema Reference

The four tables that drive Maximo workflow analytics. Stable from Maximo 7.6 through MAS 8.x.

> Column names below follow the documented `psdi.workflow.*` MBO attributes. Where this skill flags "verify in deployment", the column is either deployment-variable (synonym domains, custom objects) or NOT in the formal attribute domain — confirm against `MAXOBJECT`/`MAXATTRIBUTE` before keying queries on it.

## Contents

- `WFINSTANCE` — workflow runs (active and deactivated)
- `WFASSIGNMENT` — approval inbox / Task-node assignments
- `WFNODE` — workflow process definition
- `WFTRANSACTION` — workflow event log (append-only)
- OWNERID surrogate-key map (the join trap)
- Cardinality
- Universal mechanics (deferred to maximo-overview)

## `WFINSTANCE` — workflow runs

One row per workflow run for a business record. The row is **not deleted** when a record leaves workflow — it is deactivated in place: rows active in workflow have `ACTIVE = 1`, and when the record leaves workflow `ACTIVE` changes to `0` (the row is retained, so closed-workflow history queries against `ACTIVE = 0` are valid).

| Column | Type | Notes |
|---|---|---|
| `WFID` | BIGINT | Workflow instance ID — primary join key to other workflow tables |
| `PROCESSNAME` | STRING | Workflow process name (e.g. `WOAPPR`, `PRAPPR`, `POAPPR`, `INVCAPPR`) |
| `OWNERTABLE` | STRING | Business-object table name (`WORKORDER`, `PR`, `PO`, `INVOICE`, `TICKET`, etc.) |
| `OWNERID` | BIGINT | The owner object's **surrogate unique-ID column** (the recordid), NOT the displayable key. See the OWNERID map below — this is the #1 join trap |
| `ACTIVE` | INT (0/1) | `1` = currently in workflow, `0` = workflow has left the record. Does NOT mean "completed" — `0` covers completed, cancelled, or rejected. The row is retained either way |
| `STARTDATE` | TIMESTAMP | When the workflow started (app-server-local TZ — see maximo-overview) |
| `STARTBY` | STRING | User who initiated |

**Finding records currently in workflow:** `WFINSTANCE WHERE ACTIVE = 1`, joined by `OWNERTABLE`/`OWNERID`. Presence-in-workflow must be determined from `ACTIVE = 1` (or an `ACTIVE` `WFASSIGNMENT`) — it CANNOT be inferred from the business-object status: `WAPPR` is the default record status and is independent of whether a workflow is active, so a record can sit at `WAPPR` with NO active `WFINSTANCE`.

```sql
SELECT wo.wonum, wi.processname, wi.startdate
FROM WFINSTANCE wi
JOIN WORKORDER wo ON wo.workorderid = wi.ownerid
WHERE wi.ownertable = 'WORKORDER' AND wi.active = 1;
```

## `WFASSIGNMENT` — approval inbox / Task-node assignments

One row per (workflow instance, Task node, assignee). This is the table behind every approver's "inbox" in Maximo. "Current owner" and per-assignment timing analytics come from here. Rows **persist** (set `INACTIVE`) after the instance is deactivated — assignment history survives.

| Column | Type | Notes |
|---|---|---|
| `ASSIGNMENTID` | BIGINT | Surrogate primary key (confirm exact name in deployment) |
| `WFID` | BIGINT | FK to `WFINSTANCE.WFID` |
| `NODEID` | BIGINT | FK to `WFNODE.NODEID` — which workflow node this assignment is at |
| `ASSIGNCODE` | STRING | The current assignee code. Auto-reassign/escalation SETs this to the new assignee on the still-`ACTIVE` row — "who owns it now" is read from `ASSIGNCODE` on the `ACTIVE` assignment |
| `PERSONID` | STRING | The assignee person (if assigned to an individual) |
| `PERSONGROUP` | STRING | The assignee person-group (if assigned to a group; peers see the assignment but only one acts) |
| `ASSIGNSTATUS` | STRING | Formal attribute domain: `DEFAULT` (template rows only), `ACTIVE`, `COMPLETE`, `INACTIVE`. `FORWARDED` is IBM narrative language, **not** a stored value — do NOT key queries on a literal `'FORWARDED'`. See gotchas |
| `STARTDATE` | TIMESTAMP | The DATETIME the assignment became current — i.e. when it entered the assignee's inbox (set to server current date/time). Use this as the "time-in-approval" start |
| `DUEDATE` | TIMESTAMP | The SLA threshold: assignment creation date + the Escalation Time Limit on the Task Node. This is the due/escalation deadline, NOT the actual completion timestamp |
| `MEMO` | STRING | Optional note |

**Do NOT assume `ASSIGNDATE`, `COMPLETEDATE`, `COMPLETED` (yorn), or `RESULT` exist on this object** — they are not documented `WFAssignment` attributes. `STARTDATE` is the documented entry timestamp; the actual completion timestamp and the route disposition (positive vs negative) live in `WFTRANSACTION`, not on the assignment row. Status-changing methods are `complete()` → `COMPLETE`, `inactivate()` → `INACTIVE`, `cancel()`, and `escalate()`.

**Time-in-approval per assignment:** from `STARTDATE` (entry into inbox) to the completing `WFTRANSACTION`/route timestamp. Compare against `DUEDATE` to flag SLA breaches. (Both are app-server-local datetimes — see maximo-overview.)

## `WFNODE` — workflow process definition

Reference data. Defines the structure of each workflow process: nodes, their types (Start, Task, Condition, Subprocess, Wait, Stop), and the connections between them.

| Column | Type | Notes |
|---|---|---|
| `NODEID` | BIGINT | Primary key |
| `PROCESSNAME` | STRING | Which process this node belongs to |
| `NODETYPE` | STRING | `START`, `TASK`, `CONDITION`, `SUBPROCESS`, `WAIT`, `STOP` |
| `TITLE` | STRING | Display title shown in the workflow designer |

For bottleneck analytics ("which node is slowest"), join `WFASSIGNMENT`/`WFTRANSACTION` to `WFNODE` to get human-readable node titles alongside timing numbers. View Workflow History reads `WFTRANSACTION` filtered by node type (e.g. `nodetype != 'CONDITION'`).

## `WFTRANSACTION` — workflow event log (append-only)

Keeps the history of the record as it moves through the workflow process (a row or two per node). Required for retrospective analysis after a workflow leaves the record (`WFINSTANCE.ACTIVE = 0`), and the authoritative source for route disposition and termination reason.

| Column | Type | Notes |
|---|---|---|
| `WFID` | BIGINT | FK to `WFINSTANCE.WFID` |
| `TRANSID` | BIGINT | Surrogate primary key (confirm exact name in deployment) |
| `NODEID` | BIGINT | FK to `WFNODE.NODEID` |
| `NODETYPE` | STRING | Node type for the transition (e.g. `TASK`, `WAIT`) |
| `TRANSDATE` | TIMESTAMP | When the transition occurred (app-server-local TZ) |
| `TRANSTYPE` | STRING | Type of the transaction. **Value from SYNONYM domain `WFTRANSTYPE`** — stored values are customer-renamable synonyms; resolve via `SYNONYMDOMAIN` rather than hardcoding. A verified real value is `WFUSERSTOPPED` (written when a user stops a workflow) |
| `PERSONID` | STRING | User who performed the action (if applicable) |
| `MEMO` | STRING | Optional note |

Use `WFTRANSACTION` for:
- Full audit trail of a workflow that has ended (`ACTIVE = 0`)
- The actual completion timestamp of an assignment / route
- End-to-end cycle time (start → terminating transaction)
- Route disposition (positive vs negative path) and termination reason (e.g. `TRANSTYPE = 'WFUSERSTOPPED'`)

> Resolve `TRANSTYPE` via `SYNONYMDOMAIN WHERE DOMAINID = 'WFTRANSTYPE'` — treat the full enumeration as deployment-specific (enumerate it; do not assume a fixed `INITIATED`/`POSITIVE`/`NEGATIVE`/`REASSIGN` set). This is the same status-is-a-synonym-domain mechanic owned by maximo-overview.

## OWNERID surrogate-key map (the join trap)

`OWNERID` is the owner object's **unique-ID column** (the recordid) — never the displayable key. For `WORKORDER`, `OWNERID = WORKORDERID` (the WOID), NOT `WONUM`. `WFASSIGNMENT` uses the same `OWNERTABLE`/`OWNERID` pair. Per the Maximo convention that the unique column = main object name + `ID` (the ticket family being the notable exception):

| Business object | `OWNERTABLE` | `OWNERID` joins to |
|---|---|---|
| Work order | `WORKORDER` | `WORKORDER.WORKORDERID` |
| Purchase requisition | `PR` | `PR.PRID` |
| Purchase order | `PO` | `PO.POID` |
| Invoice | `INVOICE` | `INVOICE.INVOICEID` |
| Ticket / SR / Incident (ticket family) | `TICKET` (or `SR`/`INCIDENT`) | `TICKETUID` (ticket family uses `TICKETUID`, NOT `TICKETID`) |

**Confirm exact unique-column names per object via `MAXOBJECT.uniquecolumnname` (Database Configuration) in the target deployment** — MOC and custom objects vary. Do not hardcode without verifying.

## Cardinality

| Relationship | Cardinality |
|---|---|
| `WFINSTANCE` → `WFASSIGNMENT` | 1 : N |
| `WFINSTANCE` → `WFTRANSACTION` | 1 : N |
| `WFASSIGNMENT` → `WFNODE` | N : 1 |
| `WFTRANSACTION` → `WFNODE` | N : 1 |
| `WFINSTANCE` → business object (via OWNERTABLE + OWNERID) | 1 : 1 currently active, but multiple historical instances possible per record over its lifetime |

## Universal mechanics (deferred to maximo-overview)

These cross-cutting mechanics are owned by `maximo-overview` (v0.3.0+) — applied here, not re-taught:
- **Status / TRANSTYPE are synonym domains.** `WFTRANSACTION.TRANSTYPE` resolves via `SYNONYMDOMAIN` (`DOMAINID = 'WFTRANSTYPE'`); business-object status columns resolve the same way.
- **Datetimes are app-server-timezone**, not per-row UTC — don't assume UTC when bucketing cycle times across sites.
