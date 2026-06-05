# Maximo Workflow & Approvals — Gotchas

Domain-specific traps for the workflow tables. Universal mechanics (synonym-domain
resolution, app-server-timezone datetimes, composite keys) are owned by
`maximo-overview` and only *applied* here — see the last section.

## Contents

1. `ASSIGNSTATUS` has three persisted states — `FORWARDED` is narrative, not stored
2. Route disposition lives in `WFTRANSACTION`, not in `RESULT`/`COMPLETED` on the assignment
3. `WFINSTANCE.ACTIVE = 0` does NOT mean "completed" (and the row is retained)
4. `WAPPR` ≠ "in workflow" — presence-in-workflow comes from `ACTIVE = 1` only
5. `WFINSTANCE.OWNERID` is the surrogate unique-ID column, not the business key
6. Reassignment/escalation changes `ASSIGNCODE` on the same `ACTIVE` row — no new status
7. Time-in-approval: `STARTDATE` (inbox entry) → completing transaction; `DUEDATE` is only the SLA
8. Person-group peer assignments inflate counts unless filtered
9. `TRANSTYPE` is a synonym domain — resolve it, don't hardcode literals
10. Subprocess nodes don't generate parent `WFASSIGNMENT` rows
11. Audit-trail completeness can be incomplete in defective releases — validate
12. Universal mechanics applied here (deferred to maximo-overview)

## 1. `ASSIGNSTATUS` has three persisted states — `FORWARDED` is narrative, not stored

The formal `psdi.workflow.WFAssignment` attribute domain documents `ASSIGNSTATUS` literally as **`DEFAULT ACTIVE COMPLETE INACTIVE`**. `DEFAULT` applies to template rows only. So at the schema level the meaningful persisted states are:

| State | Meaning |
|---|---|
| `ACTIVE` | Currently awaiting action from the assignee |
| `COMPLETE` | Accepted / routed by this person (the assignee acted) |
| `INACTIVE` | Superseded — a person-group peer accepted, or the workflow was stopped |

IBM's narrative "inner workings of Workflow" prose describes reassignment as "Forwarded", which is the origin of an older four-state claim — but `FORWARDED` is **not** in the formal attribute domain. **Do not key queries on a literal `ASSIGNSTATUS = 'FORWARDED'`**; verify the actual domain in-deployment. Author defensively: `COMPLETE` = this person acted/routed; `INACTIVE` = superseded; the *disposition* of the route (who it went to, positive/negative) is NOT carried in `ASSIGNSTATUS` — read it from `WFTRANSACTION`.

**Implication for analytics:**
- "Who needs to act right now" → `ASSIGNSTATUS = 'ACTIVE'`
- "Who actually acted" → `ASSIGNSTATUS = 'COMPLETE'`
- Don't count `INACTIVE` rows as participants — they were superseded peers/stopped routes

## 2. Route disposition lives in `WFTRANSACTION`, not in `RESULT`/`COMPLETED` on the assignment

The documented `WFAssignment` attributes do NOT include a `COMPLETED` (yorn) column or a `RESULT` column. The disposition/route outcome (positive vs negative path) is recorded in `WFTRANSACTION`, not as a `COMPLETED + RESULT` pair on the assignment row. Status-changing methods are `complete(memo) → COMPLETE`, `inactivate() → INACTIVE`, `cancel(memo)` (writes a transaction), and `escalate()`.

**Before keying any "approval pass rate / rejection rate" query on `WFASSIGNMENT.RESULT`, verify the column exists in the target deployment** — by default it does not. Compute pass/reject from `WFTRANSACTION` route outcomes instead: `WFACCEPT` (escalation action) accepts an assignment and routes the POSITIVE path; `WFREJECT` routes the NEGATIVE path. Treat the full `TRANSTYPE` enumeration as deployment-specific (gotcha 9).

## 3. `WFINSTANCE.ACTIVE = 0` does NOT mean "completed" (and the row is retained)

A `WFINSTANCE` row is not deleted when a record leaves workflow; it is deactivated in place — `ACTIVE` flips `1 → 0`. `ACTIVE = 0` covers three outcomes:

- **Completed** — the workflow ran through to a Stop node successfully
- **Cancelled / user-stopped** — a user stopped the workflow
- **Rejected / aborted** — a Condition node routed to termination

To distinguish, read the terminating `WFTRANSACTION` for that `WFID`, resolving `TRANSTYPE` via the synonym domain. A user-stop is `TRANSTYPE = 'WFUSERSTOPPED'` (a verified real value); the documented table-level stop sequence is: `UPDATE WFINSTANCE SET ACTIVE = 0`; `UPDATE WFASSIGNMENT SET ASSIGNSTATUS = 'INACTIVE'`; `UPDATE WFCALLSTACK SET ACTIVE = 0`; `INSERT WFTRANSACTION` with `TRANSTYPE = 'WFUSERSTOPPED'`. Because the row is retained, closed-workflow history queries against `ACTIVE = 0` are valid.

## 4. `WAPPR` ≠ "in workflow" — presence-in-workflow comes from `ACTIVE = 1` only

`WAPPR` is the default record status and is **independent** of whether a workflow is active. Maximo does not require an active `WFINSTANCE` for a record sitting at `WAPPR` — a record can be `WAPPR` with NO active workflow. Determine presence-in-workflow from `WFINSTANCE.ACTIVE = 1` (or an `ACTIVE` `WFASSIGNMENT`), never inferred from `STATUS = 'WAPPR'`. `WFASSIGNMENT` rows persist (set `INACTIVE`) after the instance deactivates, so assignment history survives the instance.

## 5. `WFINSTANCE.OWNERID` is the surrogate unique-ID column, not the business key

The owner-key join is `OWNERTABLE + OWNERID`, where `OWNERID` is the object's **surrogate unique-ID column** (the recordid), never the displayable key. For `WORKORDER`, `OWNERID = WORKORDERID` (the WOID), NOT `WONUM`. There is no documented config where `OWNERID` holds the displayable key. The ticket family is the notable naming exception — it uses `TICKETUID`, not `TICKETID`. Full map and the `MAXOBJECT.uniquecolumnname` verification step are in [schema.md](schema.md). Confirm custom/MOC objects per deployment; do not hardcode.

## 6. Reassignment/escalation changes `ASSIGNCODE` on the same `ACTIVE` row — no new status

Reassignment does NOT introduce a new `ASSIGNSTATUS`. Auto-reassign is implemented as an Escalation on the `WFASSIGNMENT` object that matches `assignstatus = 'ACTIVE'` and runs an action that SETs `WFASSIGNMENT.ASSIGNCODE` to the new assignee. The row stays `ACTIVE` with a changed `ASSIGNCODE`. So:
- "Who owns it now" → read `ASSIGNCODE` (or `PERSONID`) on the `ACTIVE` assignment.
- A reassignment is NOT separately stamped on the assignment row — audit the reassignment trail via `WFTRANSACTION`.

## 7. Time-in-approval: `STARTDATE` → completing transaction; `DUEDATE` is only the SLA

For true time-in-approval, distinguish the assignment start from the due/notification timestamps:
- `WFASSIGNMENT.STARTDATE` = the DATETIME the assignment became current — when it entered the assignee's inbox (set to server current date/time).
- `WFASSIGNMENT.DUEDATE` = the date the assignment is due per the escalation time limit, computed as assignment creation date + the Escalation Time Limit on the Task Node. This is the **SLA threshold, not the actual completion**.

Compute time-in-approval from `STARTDATE` to the completing `WFTRANSACTION`/route timestamp; use `DUEDATE` only to flag SLA breaches. `ASSIGNDATE`/`COMPLETEDATE` are not documented `WFAssignment` attributes — do not assume them. (These are app-server-local datetimes — see maximo-overview.)

## 8. Person-group peer assignments inflate counts unless filtered

When a Task node is assigned to a person-group, Maximo creates an `ACTIVE` row for **every member of the group**. When one member accepts, that row goes `COMPLETE` while the other group members' rows are set `INACTIVE`. A naïve `COUNT(*)` over `WFASSIGNMENT` over-counts a 4-person-group node by 4×.

Patterns:
- "Number of approvals that occurred" → count rows with `ASSIGNSTATUS = 'COMPLETE'`
- "Number of assignment events created" → count all rows
- "Currently waiting on" → `ASSIGNSTATUS = 'ACTIVE'` (still N rows per group, but `COUNT(DISTINCT WFID, NODEID)` collapses to the node)

## 9. `TRANSTYPE` is a synonym domain — resolve it, don't hardcode literals

`WFTRANSACTION.TRANSTYPE` is "Value from synonym domain named `WFTRANSTYPE`" — stored values are the customer-renamable synonyms. Termination/audit queries should resolve through `SYNONYMDOMAIN` (`DOMAINID = 'WFTRANSTYPE'`) rather than hardcoding placeholders like `'STOP'`/`'cancel'`. A verified real value is `WFUSERSTOPPED`. Treat the full enumeration as deployment-specific — enumerate it from `SYNONYMDOMAIN`, do not assume a fixed `INITIATED`/`POSITIVE`/`NEGATIVE`/`REASSIGN` set. This is the status-is-a-synonym-domain mechanic owned by maximo-overview, applied to `TRANSTYPE`.

## 10. Subprocess nodes don't generate parent `WFASSIGNMENT` rows

When a workflow includes a Subprocess node, the **subprocess** has its own `WFINSTANCE` rows. The parent workflow doesn't create a `WFASSIGNMENT` for the subprocess invocation itself. For "all approvals on this record" queries, walk the subprocess tree by joining child `WFINSTANCE` rows back to the parent (via the configured parent-link or process-name conventions in the deployment).

## 11. Audit-trail completeness can be incomplete in defective releases — validate

IBM APARs document cases where workflow table writes were incomplete: `IV85807` (on ROUTE a workflow could fail to update tables) and `IZ88857` (the "Change Status" workflow action not adding `WORKORDER` history rows in some PM-generated cases). So `WFTRANSACTION`/status-history completeness should be **validated, not assumed**, in a given deployment before basing audit or cycle-time metrics on it.

## 12. Universal mechanics applied here (deferred to maximo-overview)

These are NOT re-taught here — `maximo-overview` (v0.3.0+) is the canonical home; apply them in your SQL:
- **Synonym domains.** `TRANSTYPE` (and any business-object status) store the synonym `VALUE`, not the internal `MAXVALUE` — resolve via `SYNONYMDOMAIN` (gotcha 9).
- **App-server-timezone datetimes.** `STARTDATE`/`DUEDATE`/`TRANSDATE` are stored in the app server's local TZ, not per-row UTC — don't assume UTC when bucketing cycle times across sites.
- **Composite keys / WOCLASS / ISTASK** for the *business object* you join to live in maximo-overview and the relevant module skill — apply them when you join `WFINSTANCE` to `WORKORDER` etc.
