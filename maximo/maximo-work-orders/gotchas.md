# Maximo Work Orders — Gotchas

## Contents

- 1. Status history is in `WOSTATUS`, not `WORKORDER`
- 2. `WORKORDER` is a multi-purpose table — filter by `WOCLASS`
- 3. `ISTASK = 1` rows are child tasks — deduplicate to parent
- 4. REST-API ingestion may have incomplete status history
- 5. Open-status set is customer-configurable
- 6. Always include `SITEID` in joins
- 7. Dates: which one means what
- 8. `WPLABOR` / `WPMATERIAL` are PLANNED — not actual
- 9. Failure-code aggregation is hierarchical
- 10. `WORKORDER.WORKTYPE` is customer-configured

The traps that will silently produce wrong numbers. Read before writing any query.

## 1. Status history is in `WOSTATUS`, not `WORKORDER`

`WORKORDER.STATUS` holds the *current* status. To get the *history* (every transition with timestamps), you must query `WOSTATUS`.

```sql
-- Current status only:
SELECT WONUM, SITEID, STATUS, STATUSDATE
FROM WORKORDER
WHERE WONUM = 'WO12345' AND SITEID = 'BEDFORD';

-- Full transition history:
SELECT WONUM, SITEID, STATUS, CHANGEDATE, CHANGEBY, MEMO
FROM WOSTATUS
WHERE WONUM = 'WO12345' AND SITEID = 'BEDFORD'
ORDER BY CHANGEDATE;
```

When the user asks "what's the status of WO X" (singular, current), use `WORKORDER`. When they ask "show me the status history" or "how long was it in INPRG", use `WOSTATUS`.

## 2. `WORKORDER` is a multi-purpose table — filter by `WOCLASS`

The `WORKORDER` table also holds:

| `WOCLASS` value | What it represents |
|---|---|
| `WORKORDER` | Normal work orders (this is what 95% of analytics want) |
| `PM` | Preventive-maintenance-generated work records |
| `CHANGE` | Change records (Change Management) |
| `RELEASE` | Release records |
| `ACTIVITY` | Activity records (project work) |

**Almost every WO query should start with `WHERE WOCLASS = 'WORKORDER'`.** Without it, backlog counts, labor totals, and aging metrics are inflated.

## 3. `ISTASK = 1` rows are child tasks — deduplicate to parent

A WO can have a parent header (`ISTASK = 0`) and N child tasks (`ISTASK = 1`, each pointing to the parent via the `PARENT` column). Counting all rows double-counts the parent's work.

For most analytics:
- Backlog **counts** → use only `ISTASK = 0` rows (parents).
- Labor / material **totals** → roll up by `PARENT`, or sum child rows but exclude the parent header.

If the user explicitly wants task-level detail, use child tasks; otherwise default to parent-only.

## 4. REST-API ingestion may have incomplete status history

When customers ingest via Maximo REST API endpoints that PATCH the WORKORDER record directly, the `STATUS` field on `WORKORDER` updates but **no new row is written to `WOSTATUS`**. Only changes that go through the Object Structure (OS) API or the application (which uses MBOs) write to `WOSTATUS`.

**Symptom**: `WOSTATUS` has far fewer rows than you'd expect, or "most recent" status in `WOSTATUS` doesn't match `WORKORDER.STATUS`.

**Action**: ask the user how their data is ingested. If REST-direct, `WOSTATUS` is unreliable for full history; document the limitation in any report you produce.

Reference: [IBM APAR IJ17261 — STATUS CHANGE IS NOT REGISTERED IN WOSTATUS TABLE](https://www.ibm.com/support/pages/apar/IJ17261).

## 5. Open-status set is customer-configurable

Maximo ships defaults but every customer can extend the WOSTATUS domain. Common defaults:

| Status | Meaning |
|---|---|
| `WAPPR` | Waiting on approval |
| `APPR` | Approved |
| `WSCH` | Waiting to be scheduled |
| `WMATL` | Waiting on materials |
| `WPCOND` | Waiting on plant conditions |
| `INPRG` | In progress |
| `COMP` | Completed (work done, awaiting closeout) |
| `CLOSE` | Closed (no further changes allowed) |
| `CAN` | Cancelled |

"Open" typically means everything **except** `COMP`, `CLOSE`, and `CAN`, but check with the user. The canonical place to look up a customer's set is `SYNONYMDOMAIN` filtered to `DOMAINID = 'WOSTATUS'` — each row has `MAXVALUE` (the status) and `VALUE` (its synonym/category).

## 6. Always include `SITEID` in joins

`WONUM`, `ASSETNUM`, `LOCATION` are unique only within a site. Multi-site customers have the same `WONUM` value at different sites, and joining without `SITEID` produces a cross product. Always:

```sql
-- WRONG
JOIN ASSET A ON A.ASSETNUM = WO.ASSETNUM

-- RIGHT
JOIN ASSET A ON A.ASSETNUM = WO.ASSETNUM AND A.SITEID = WO.SITEID
```

## 7. Dates: which one means what

| Column | Meaning |
|---|---|
| `REPORTDATE` | When the WO was created/reported |
| `STATUSDATE` | When the current `STATUS` was set (not the original create) |
| `TARGCOMPDATE` | Target / desired completion |
| `SCHEDSTART` / `SCHEDFINISH` | Scheduled window |
| `ACTSTART` / `ACTFINISH` | Actual execution window |
| `STATUSCHANGEDATE` (on PM-generated WOs) | When PM evaluated this slot |

"Backlog age" usually = `current_date() - REPORTDATE` for open WOs. Some customers prefer `current_date() - STATUSDATE` ("days in current status"). Confirm which.

## 8. `WPLABOR` / `WPMATERIAL` are PLANNED — not actual

Easy to confuse:

- **Planned labor** on a WO → `WPLABOR` (or the job-plan templates `JPLABOR`).
- **Actual labor** booked to a WO → `LABTRANS`.

For "actual vs planned" variance analysis, you need both: sum `LABTRANS.REGULARHRS + PREMIUMPAYHOURS` per WO vs sum `WPLABOR.LABORHRS` per WO.

## 9. Failure-code aggregation is hierarchical

`FAILURECODE` is a tree with three node types (`TYPE = 'PROBLEM'`, `'CAUSE'`, `'REMEDY'`). A `FAILUREREPORT` row may reference codes at any level. To aggregate "by failure class", you need to flatten the tree to the level the user asked for — don't just `GROUP BY FAILURECODE`.

## 10. `WORKORDER.WORKTYPE` is customer-configured

Standard codes are advisory only. Most customers customize:
- `CM` = Corrective Maintenance
- `PM` = Preventive Maintenance
- `EM` = Emergency Maintenance
- `PROJ` = Project work

But some customers have 10+ work types or use entirely different codes. Ask if a question depends on the corrective-vs-preventive split.
