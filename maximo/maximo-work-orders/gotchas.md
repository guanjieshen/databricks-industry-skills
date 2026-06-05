# Maximo Work Orders — Gotchas

## Contents

- 1. Status history is in `WOSTATUS`, not `WORKORDER`
- 2. `WORKORDER` is a multi-purpose table — filter by `WOCLASS`
- 3. Tasks vs child work orders — deduplicate before counting
- 4. REST-API ingestion may have incomplete status history
- 5. `STATUS` is a synonym domain — filter on the synonym, resolve via `SYNONYMDOMAIN`
- 6. Always include `SITEID` in joins
- 7. Dates: which one means what
- 8. `WPLABOR` / `WPMATERIAL` are PLANNED — not actual
- 9. Failure-code aggregation is hierarchical
- 10. `WORKORDER.WORKTYPE` is customer-configured
- 11. `COMP` ≠ `CLOSE`, and `HISTORYFLAG` hides closed work
- 12. Follow-up work orders live in *separate* hierarchies
- 13. Datetimes are stored in the app-server timezone, not per-row UTC
- 14. "Corrective" work type ≠ "reactive" maintenance
- 15. WO cost columns are per-record — not auto-rolled-up

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

## 3. Tasks vs child work orders — deduplicate before counting

A work order can have **two distinct kinds of children**, and they are not the same thing:

| Kind | `ISTASK` | `PARENT` | What it is |
|---|---|---|---|
| Parent header | `0` | null | The WO itself |
| **Task** | `1` | set | A step *within* the parent — not an independent WO |
| **Child work order** | `0` | set | A full, independently-tracked WO hung under a parent |

Counting all rows double-counts work. For most analytics:
- Backlog / WO **counts** → count `ISTASK = 0` rows (this includes both standalone parents and child work orders, but excludes tasks). If you only want top-level headers, add `PARENT IS NULL`.
- Labor / material **totals** → roll up by `PARENT`, or sum leaf rows; don't add a parent header's rolled-up figure to its own children (see gotcha 15).

**`PARENT` is mutable.** The *Create Work Package* action regroups existing WOs under a brand-new parent — non-task WOs become child work orders and standalone tasks become tasks of the new parent. So a WO's place in the hierarchy can change after creation; don't assume `PARENT` is stable over time.

If the user explicitly wants task-level detail, use `ISTASK = 1`; otherwise default to `ISTASK = 0`.

## 4. REST-API ingestion may have incomplete status history

When customers ingest via Maximo REST API endpoints that PATCH the WORKORDER record directly, the `STATUS` field on `WORKORDER` updates but **no new row is written to `WOSTATUS`**. Only changes that go through the Object Structure (OS) API or the application (which uses MBOs) write to `WOSTATUS`.

**Symptom**: `WOSTATUS` has far fewer rows than you'd expect, or "most recent" status in `WOSTATUS` doesn't match `WORKORDER.STATUS`.

**Action**: ask the user how their data is ingested. If REST-direct, `WOSTATUS` is unreliable for full history; document the limitation in any report you produce.

Reference: [IBM APAR IJ17261 — STATUS CHANGE IS NOT REGISTERED IN WOSTATUS TABLE](https://www.ibm.com/support/pages/apar/IJ17261).

## 5. `STATUS` is a synonym domain — filter on the synonym, resolve via `SYNONYMDOMAIN`

`WOSTATUS` is a **synonym domain**. Each status has an **internal value** (`MAXVALUE` — what Maximo business logic is written against, e.g. `COMP`) and one or more **synonyms** (`VALUE` — the customer-renamable label actually stored in the row). **`WORKORDER.STATUS` stores the synonym (`VALUE`), not the internal value.**

In a stock deployment internal value and synonym are identical, so `STATUS = 'COMP'` works. **The trap bites when a customer has added synonyms** — e.g. a synonym `WAITREV` mapped to internal `COMP`. A literal filter `STATUS IN ('COMP','CLOSE')` then silently misses every WO sitting under a custom synonym.

The robust pattern is the one IBM ships in the built-in `WORKVIEW` — filter on the synonym set resolved from the internal value:

```sql
-- "Completed" work, synonym-safe (resolves every synonym of COMP / CLOSE):
WHERE w.status IN (
  SELECT value FROM {{maximo_catalog}}.{{maximo_schema}}.SYNONYMDOMAIN
  WHERE domainid = 'WOSTATUS' AND maxvalue IN ('COMP','CLOSE')
)
```

The standard `WOSTATUS` internal values:

| Internal value | Meaning | Default in… |
|---|---|---|
| `WAPPR` | Waiting on approval | Work Order Tracking, Changes, Releases, Activities |
| `APPR` | Approved — work can begin | |
| `WSCH` | Waiting to be scheduled | PM-generated WOs |
| `WMATL` | Waiting on materials | |
| `WPCOND` | Waiting on plant conditions (e.g. shutdown required) | |
| `INPRG` | In progress | Quick Reporting; default Flow Start |
| `COMP` | Completed — physical work done | default Flow Complete |
| `CLOSE` | Closed — finalized, becomes a history record | |
| `CAN` | Cancelled (can't cancel once in progress or actuals exist) | |
| `HISTEDIT` | Edited in history (set by *Edit History Work Order* on a closed WO) | |

**"Open"** typically means every status *except* `COMP`, `CLOSE`, `CAN` — but the exact set is customer-configurable, so confirm it (see SKILL.md *Questions to surface first*). The Flow Start / Flow Complete defaults (`INPRG` / `COMP`) are themselves configurable per work type in *Organizations → Work Order Options → Work Type*.

(`maximo-overview` owns the baseline "open-status set is customer-configurable" universal gotcha; this gotcha adds the synonym-resolution mechanics that keep a status filter correct when synonyms exist.)

References: [IBM Maximo REST API filtering — `domaininternalwhere` vs `oslc.where`](https://ibm-maximo-dev.github.io/maximo-restapi-documentation/query/filtering/) · [IBM Manage — Work order statuses](https://www.ibm.com/docs/en/masv-and-l/maximo-manage/cd?topic=tracking-work-orders-overview) · [Maximo Secrets — Domains](https://maximosecrets.com/2023/07/25/domains/).

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

"Backlog age" usually = `current_date() - REPORTDATE` for open WOs. Some customers prefer `current_date() - STATUSDATE` ("days in current status"). Confirm which (also surfaced in SKILL.md's *Questions to surface first*). See gotcha 13 for the timezone caveat on all of these.

## 8. `WPLABOR` / `WPMATERIAL` are PLANNED — not actual

Easy to confuse:

- **Planned labor** on a WO → `WPLABOR` (or the job-plan templates `JPLABOR`).
- **Actual labor** booked to a WO → `LABTRANS`.

For "actual vs planned" variance analysis, you need both: sum `LABTRANS.REGULARHRS + PREMIUMPAYHOURS` per WO vs sum `WPLABOR.LABORHRS` per WO.

Note: via the *Edit History Work Order* action, **actual labor and failure reports can be booked to a WO *after* it is closed** — so `LABTRANS` rows can postdate `ACTFINISH`/the close date, and a labor total keyed strictly on the close period can drift. Planned items, by contrast, cannot be changed once the WO is closed.

## 9. Failure-code aggregation is hierarchical

`FAILURECODE` is a tree with three node types (`TYPE = 'PROBLEM'`, `'CAUSE'`, `'REMEDY'`). A `FAILUREREPORT` row may reference codes at any level. To aggregate "by failure class", you need to flatten the tree to the level the user asked for — don't just `GROUP BY FAILURECODE`. The default failure class on a WO comes from the asset's or location's associated failure class.

## 10. `WORKORDER.WORKTYPE` is customer-configured

Standard codes are advisory only. Most customers customize:
- `CM` = Corrective Maintenance
- `PM` = Preventive Maintenance
- `EM` = Emergency Maintenance
- `PROJ` = Project work

But some customers have 10+ work types or use entirely different codes. Ask if a question depends on the corrective-vs-preventive split. See gotcha 14 — work type is *not* a clean proxy for reactive-vs-proactive.

## 11. `COMP` ≠ `CLOSE`, and `HISTORYFLAG` hides closed work

These are two distinct steps with very different analytics meaning:

- **`COMP` (Complete)** — the physical work is finished. This is the event most "completed work / throughput / MTTC" analytics actually want.
- **`CLOSE` (Closed)** — a separate *finalization* step. It removes inventory reservations for unused items and turns the record into a **history record**. Closing is frequently deferred for days/weeks — and **many shops never CLOSE at all**, leaving completed work parked at `COMP` indefinitely.

So **key "completed work" on `COMP`-or-later, not on `CLOSE`** (synonym-resolved per gotcha 5), or you'll undercount in any shop with a closeout backlog.

**`HISTORYFLAG`**: when a WO reaches a *final* status (`CLOSE` or `CAN`) Maximo sets `HISTORYFLAG = 1`, and the record drops out of the standard application List views. The IBM-shipped `WORKVIEW` filters `historyflag = 0 AND istask = 0`. **If your silver tables mirror that filter, closed work may be missing** — confirm whether closed WOs are present before computing completion or trend metrics. Completed-but-unclosed (`COMP`) WOs keep `HISTORYFLAG = 0`.

Also: a WO can transition to `COMP`/`CLOSE` **automatically** when its last labor assignment is completed (governed by the `WOSTATUSONASNTCOMP` maxvar). So a completion timestamp isn't always a deliberate manual closeout event.

References: [IBM Manage — Work order statuses & archived-WO rules](https://www.ibm.com/docs/en/masv-and-l/maximo-manage/cd?topic=tracking-work-orders-overview) · [IBM — WOs completed after all assignments complete](https://www.ibm.com/support/pages/work-orders-are-completed-after-all-assignments-are-completed).

## 12. Follow-up work orders live in *separate* hierarchies

When someone finishes a job and finds more work on the same asset, they create a **follow-up** WO/ticket. The new record gets status `Follow-up`; the original becomes `Originator`. **Follow-ups are kept in separate hierarchies — their costs and labor do NOT roll up to the originating parent.**

Implications:
- "Repeat work / rework on the same asset" cannot be found via `PARENT` (parent/child) — you must trace the **originator → follow-up** link: `ORIGRECORDID` + `ORIGRECORDCLASS` on the follow-up point back to the originating record (the relationship is also recorded in `RELATEDRECORD` with type `FOLLOWUP`/`ORIGINATOR`).
- A cost or labor rollup over a parent hierarchy will *exclude* follow-up work that is conceptually part of the same job.

Rework *rate* as a reliability KPI belongs to `maximo-reliability`; this skill provides the structural join only.

References: [IBM Manage — Record relationships & follow-up work orders](https://www.ibm.com/docs/en/masv-and-l/maximo-manage/cd?topic=tracking-work-orders-overview) · [IBM APAR IV75923 — related WO and SR records](https://www.ibm.com/support/pages/apar/IV75923).

## 13. Datetimes are stored in the app-server timezone, not per-row UTC

Maximo does **not** persist a single canonical UTC instant per row. Datetimes are stored in the **application server's local timezone** (often UTC, but that is a deployment config choice, not a guarantee), and the UI converts to each user's profile timezone for display. On MIF/MEA inbound integration, a supplied UTC (`Z`) or offset timestamp is adjusted by the delta to the app-server timezone before storage; a value with no offset is stored as-is as app-server-local time.

Implication for analytics: **do not assume the raw datetime columns are UTC** when bucketing by day/week/month or computing time-in-status across sites in different timezones. Confirm the deployment's app-server timezone, and if sites span timezones, decide explicitly whether buckets should be app-server-local or converted to site-local.

References: [IBM — MEA/MIF local time format](https://www.ibm.com/support/pages/does-meamif-support-local-time-format) · [IBM APAR IJ28306](https://www.ibm.com/support/pages/apar/IJ28306).

## 14. "Corrective" work type ≠ "reactive" maintenance

A common analytics error is equating `WORKTYPE = 'CM'` (corrective) with "reactive maintenance." In SMRP terms these are **orthogonal**: *corrective* work (done after a failure, or when failure is imminent) can be either **proactive** or **reactive** — corrective work identified *before* functional failure from a PM/PdM inspection counts as **proactive**. So a "reactive vs proactive" split built purely on work type will be wrong.

Two further cautions, if the user asks for a reactive/proactive or planned/unplanned ratio:
- **Measure it on labor hours (`LABTRANS`), not WO counts.** One emergency WO can consume far more craft-hours than a routine PM, so counting by WO row materially understates reactive load (a documented plant case: 12% reactive by count vs 28% by hours).
- These are **reliability KPIs** — defer the actual metric definition and UDF to `maximo-reliability`. This skill should surface the caveat, not invent the ratio.

Reference: [SMRP Best Practices Metrics Workshop](https://pemac.org/sites/default/files/2018_SMRP_BPMW_Full_Day.pdf).

## 15. WO cost columns are per-record — defer cost analysis to `maximo-maintenance-cost`

This skill's `v_workorder_enriched` and examples pass `ACTLABCOST` / `ACTMATCOST` through for convenience, but **cost rollup, variance, contractor spend, and multi-currency are owned by `maximo-maintenance-cost`** — use it for anything beyond a single-record cost readout.

Two things to know so you don't produce a wrong number from this skill's surface:
- `ACTLABCOST` / `ACTMATCOST` are **per-record** — a charge posts to the specific WO/task where it's incurred and does **not** roll up into the parent automatically. (See `maximo-maintenance-cost` gotcha *"Parent / child WO cost rollup is NOT automatic"* for the recursive-rollup pattern, and its `WOCURRENCY` multi-currency gotcha.)
- `ACTTOTALCOST` is a **non-persistent, computed** attribute — it may be absent or stale in a silver mirror; don't treat it as a stored column.

Reference: [IBM APAR IV13319 — costs posted to task vs parent](https://www.ibm.com/support/pages/apar/IV13319).
