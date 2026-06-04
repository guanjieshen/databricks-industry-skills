# Maximo Workflow & Approvals — Schema Reference

The four tables that drive Maximo workflow analytics. Stable from Maximo 7.6 through MAS 8.x.

## `WFINSTANCE` — active workflow runs

One row per business record currently in workflow. When the workflow leaves a record (completed, cancelled, rejected), the row stays but `ACTIVE = 0`.

| Column | Type | Notes |
|---|---|---|
| `WFID` | BIGINT | Workflow instance ID — primary join key to other workflow tables |
| `PROCESSNAME` | STRING | Workflow process name (e.g. `WOAPPR`, `PRAPPR`, `POAPPR`, `INVCAPPR`) |
| `OWNERTABLE` | STRING | Business-object table name (`WORKORDER`, `PR`, `PO`, `INVOICE`, `MOC`, `INCIDENT`, etc.) |
| `OWNERID` | BIGINT | Surrogate key of the business record (joins to e.g. `WORKORDER.WORKORDERID`) |
| `ACTIVE` | INT (0/1) | `1` = currently in workflow, `0` = workflow has left the record. Does NOT mean "complete" — could be cancelled or rejected |
| `STARTDATE` | TIMESTAMP | When the workflow started |
| `STARTBY` | STRING | User who initiated |

**Joining to a business record**: `OWNERTABLE` tells you which table, `OWNERID` joins to that table's surrogate primary key. Example for work orders:

```sql
SELECT wo.wonum, wi.processname, wi.startdate
FROM WFINSTANCE wi
JOIN WORKORDER wo ON wo.workorderid = wi.ownerid
WHERE wi.ownertable = 'WORKORDER' AND wi.active = 1;
```

## `WFASSIGNMENT` — approval inbox / Task-node assignments

One row per (workflow instance, Task node, approver). This is the table behind every approver's "inbox" in Maximo. Cycle-time and "current owner" analytics come from here.

| Column | Type | Notes |
|---|---|---|
| `ASSIGNID` | BIGINT | Surrogate primary key |
| `WFID` | BIGINT | FK to `WFINSTANCE.WFID` |
| `NODEID` | BIGINT | FK to `WFNODE.NODEID` — which workflow node this assignment is at |
| `ASSIGNCODE` | STRING | Code identifying the role of this assignment (e.g. `APPR1`, `REVIEWER`) |
| `PERSONID` | STRING | The approver (if assigned to an individual) |
| `PERSONGROUP` | STRING | The approver person-group (if assigned to a group; peers see the assignment but only one acts) |
| `ASSIGNSTATUS` | STRING | Lifecycle: `ACTIVE` → `COMPLETE` / `FORWARDED` / `INACTIVE`. See gotchas. |
| `ASSIGNDATE` | TIMESTAMP | When the assignment was created |
| `COMPLETEDATE` | TIMESTAMP | When the assignment was acted on (NULL while ACTIVE) |
| `RESULT` | STRING | Outcome of the action (e.g. `POSITIVE`, `NEGATIVE`, `FORWARD`) |
| `MEMO` | STRING | Optional note from approver |

**Cycle time per assignment**: `datediff(SECOND, ASSIGNDATE, COMPLETEDATE) / 3600.0` (hours).

## `WFNODE` — workflow process definition

Reference data. Defines the structure of each workflow process: nodes, their types (Start, Task, Condition, Subprocess, Wait, Stop), and the connections between them.

| Column | Type | Notes |
|---|---|---|
| `NODEID` | BIGINT | Primary key |
| `PROCESSNAME` | STRING | Which process this node belongs to |
| `NODENAME` | STRING | Human-readable node name |
| `NODETYPE` | STRING | `START`, `TASK`, `CONDITION`, `SUBPROCESS`, `WAIT`, `STOP` |
| `TITLE` | STRING | Display title shown in the workflow designer |

For bottleneck analytics ("which node is slowest"), join `WFASSIGNMENT` to `WFNODE` to get human-readable node names alongside cycle-time numbers.

## `WFTRANSACTION` — workflow event log (append-only)

One row per workflow transition that occurred — node entered, action taken, workflow ended. Required for retrospective analysis after a workflow has left the record (`WFINSTANCE.ACTIVE = 0`).

| Column | Type | Notes |
|---|---|---|
| `WFID` | BIGINT | FK to `WFINSTANCE.WFID` |
| `TRANSACTIONID` | BIGINT | Surrogate primary key |
| `NODEID` | BIGINT | FK to `WFNODE.NODEID` |
| `TRANSDATE` | TIMESTAMP | When the transition occurred |
| `TRANSACTION` | STRING | Transition type (`START`, `INITIATE`, `ROUTE`, `STOP`, etc.) |
| `PERSONID` | STRING | User who performed the action (if applicable) |
| `MEMO` | STRING | Optional note |

Use `WFTRANSACTION` for:
- Full audit trail of a workflow that has ended (`ACTIVE = 0`)
- Mean cycle time across the entire workflow (START → STOP)
- Identifying which transition ended the workflow (cancel vs complete vs reject)

## Cardinality

| Relationship | Cardinality |
|---|---|
| `WFINSTANCE` → `WFASSIGNMENT` | 1 : N |
| `WFINSTANCE` → `WFTRANSACTION` | 1 : N |
| `WFASSIGNMENT` → `WFNODE` | N : 1 |
| `WFTRANSACTION` → `WFNODE` | N : 1 |
| `WFINSTANCE` → business object (via OWNERTABLE + OWNERID) | 1 : 1 currently, but multiple historical instances possible per record over its lifetime |
