# Maximo HSE — Gotchas

> Universal Maximo mechanics (SITEID composite keys, status-is-a-synonym-domain / `SYNONYMDOMAIN`, `HISTORYFLAG`, app-server-timezone datetimes, current-status-vs-status-history) are owned by `maximo-overview`. They are APPLIED throughout this skill; they are not re-taught here. The gotchas below are HSE-domain-specific depth.

## Contents

- 0. LOTO Plans have no STATUS — use the `ACTIVE` flag
- 0a. Permit/Certificate Type catalog vs transactional permits
- 1. Incidents are TICKET records (CLASS='INCIDENT'), not their own table
- 2. Permit-to-Work has its OWN status + history — never use WOSTATUS
- 3. `plusg*` tables may not exist
- 4. TRIR / LTIR hours-worked typically isn't in Maximo
- 5. No stock OSHA-recordable / API RP 754 Tier column
- 6. Incident categorization is regulatory-specific
- 7. PII handling (plusgincperson, permit-holders)
- 8. Corrective-action tracking varies by customer
- 9. MOC compliance has staged deadlines
- 10. Permit expiry vs permit closure
- 11. Near-miss reporting lag

## 0. LOTO Plans don't have a STATUS field — filter by `ACTIVE` boolean instead

The single most surprising HSE gotcha. Most Maximo records have a `STATUS` field with history; **Lock Out / Tag Out plans do not**. From the IBM Maximo for O&G docs (verbatim):

> "Lock Out/Tag Out Plan does not status. The Active field is used to identify plan records which are available for use."

```sql
-- WRONG (LOTO has no STATUS column at all)
WHERE l.status = 'ACTIVE'

-- RIGHT
WHERE l.active = 1
```

There's also no LOTO status-history table. If you need to audit "when did this LOTO plan become active", you have to fall back to the audit-log infrastructure (`A_LOTO` or similar customer-specific audit tables), not a domain-modeled history.

Reference: IBM Maximo for O&G — LOTO Plan documentation.

## 0a. Permit/Certificate Type catalog vs transactional permits

These are two distinct tables that customers often conflate:

| `plusgpertype` (type catalog) | `plusgpermitwork` (transactional) |
|---|---|
| Reusable type definition (Hot Work, Confined Space, etc.) | One row per actual permit issued |
| Three-state framework: `DRAFT` / `ACTIVE` / `INACTIVE` | Status flow: `DRAFT` / `APPROVED` / `ISSUED` / `ACTIVE` / `CLOSED` / `CANCELLED` |
| Used to validate "which types do we offer" | Used to track actual operational permits |
| Long descriptions populate the header on transactional records | Joins to WORKORDER, INCIDENT, MOC, etc. |

When the user asks "show me active permits", they almost always mean transactional permits (`plusgpermitwork.STATUS IN ('ISSUED','ACTIVE')`), not the type catalog. Confirm if ambiguous. Note: the PTW status literals are likely customer synonyms — resolve via the PTW status domain (gotcha 2). The join is `plusgpertype.plusgpertypeid = plusgpermitwork.plusgpertypeid` (NOT `pertype = permittype`).

## 1. Incidents are TICKET records (CLASS='INCIDENT'), not their own table

There is no standalone `INCIDENT` table. SR, INCIDENT, and PROBLEM all share the core `TICKET` table; the applications are distinguished by `TICKET.CLASS` (`SR` / `INCIDENT` / `PROBLEM`). The surrogate key is `TICKETID` — which is exactly why `plusgincperson` keys on `TICKETID`, not `INCIDENTID`.

```sql
-- WRONG
FROM incident i ... GROUP BY i.incidentid
-- RIGHT
FROM ticket i WHERE i.class = 'INCIDENT' ... GROUP BY i.ticketid
```

Consequences (apply overview gotchas):
- **Status:** each ticket class has its OWN synonym domain (`SRSTATUS` / `INCIDENTSTATUS` / `PROBLEMSTATUS`). Resolve incident status via `SYNONYMDOMAIN WHERE domainid='INCIDENTSTATUS'`. The stock set is `NEW/QUEUED/PENDING/INPROG/RESOLVED/CLOSED`. The old `REPORTED/INVESTIGATING/CLOSED` literals do NOT match stock — treat them as customer synonyms, not hardcoded values (overview F2).
- **History:** at CLOSED/CANCELLED/REJECTED a ticket gets `HISTORYFLAG=1` and drops off the List tab. Confirm closed incidents are present before trend/closure metrics (overview F3).

## 2. Permit-to-Work has its OWN status + history — never use WOSTATUS

`plusgpermitwork` is a work-control object with its OWN `STATUS` column AND its OWN `HISTORYFLAG`. It is NOT a `WORKORDER`, so:

- It has **no `WOSTATUS` rows**. Its status HISTORY lives in the PTW object's own status-history mechanism (analogous to TKSTATUS for tickets / WOSTATUS for work orders). Verify the exact object name in the deployment, or fall back to the audit log.
- The permit key column is `PERMITWORKNUM`, not `PERMITNUM`.

```sql
-- WRONG (two bugs: permits have no WOSTATUS rows; key is not permitnum)
JOIN wostatus s ON s.wonum = p.permitnum
-- RIGHT: use the PTW object's own status-history table (confirm its name in MAXATTRIBUTE)
```

Resolve the PTW status set via its own `domainid` (confirm the exact id in `DOMAIN`/`SYNONYMDOMAIN`; it was not publicly named — `PTWSTATUS` is an inferred candidate only). Apply overview F2 once the domainid is confirmed.

## 3. `plusg*` tables may not exist

The PLUSG prefix is the Maximo Oil & Gas industry-solution extension. Customers running classic Maximo without the O&G solution **don't have these tables**. Verify before writing queries that join to them — return a clear error rather than silently returning empty results.

## 4. TRIR / LTIR hours-worked typically isn't in Maximo

The formula is `(recordable incidents × 200,000) / hours-worked`. The numerator is in `INCIDENT`. The denominator (hours-worked across the workforce) is almost always in **HR / payroll**, not Maximo. Common sources:
- Workday / SAP SuccessFactors / Oracle HCM
- Custom workforce-management system
- A Databricks-side HR dataset

The shipped `trir` UDF takes hours-worked as a parameter. The caller must source it. Don't hallucinate hours-worked from Maximo LABTRANS — LABTRANS is only labor booked to WOs, not all hours-worked.

## 5. No stock OSHA-recordable / API RP 754 Tier column — classification is configurable

There is **no dedicated, publicly-documented stock column or domain** that stores OSHA-recordable status or API RP 754 Tier 1-4 classification in stock Maximo for O&G. IBM publishes no fixed mapping. These are typically implemented per-deployment via:

- incident `CLASSIFICATION` (`CLASSSTRUCTUREID`),
- an `INCIDENTCATEGORY` / severity value list (note: `INCIDENTCATEGORY` is itself UNVERIFIED as a stock column name — confirm against `MAXATTRIBUTE`), or
- customer-added attributes / specifications.

API RP 754 tiers (for reference): **Tier 1** = high-consequence loss of primary containment (LOPC); **Tier 2** = lesser LOPC; **Tier 3** = challenges to safety systems / precursors; **Tier 4** = operating-discipline / management-system metrics.

**ACTION:** never assert a hardcoded recordable/Tier column. The `trir`/`ltir` UDFs correctly *parameterize* recordable categories rather than hardcoding — keep that pattern. Frame OSHA/754 classification as "driven by the deployment's incident classification/domain — confirm in the workspace glossary."

## 6. Incident categorization is regulatory-specific

| Category | Definition | Reporting body |
|---|---|---|
| Recordable | OSHA-defined: lost time, restricted duty, medical treatment beyond first aid | OSHA |
| Lost-time | Subset of recordable: caused days away from work | OSHA + internal |
| Near-miss | Could-have-been incident with no injury | Internal + sometimes regulator |
| First aid | Minor injury treated on-site | Internal |
| Process Safety (Tier 1-4) | API RP 754 process-safety classification | API + sometimes regulator |

`INCIDENTCATEGORY` values are customer-configured. Verify via workspace glossary or ASK before computing TRIR/LTIR — different customers use different category codes.

## 7. Permit-to-work data is PII-sensitive in some jurisdictions

Permit records may include named permit-holders, isolation lockout names, etc. Some jurisdictions treat this as employment data subject to GDPR / regional privacy law. Aggregate or de-identify before sharing in any non-restricted artifact.

Same for `plusgincperson` — names of injured workers should NEVER appear in dashboards visible beyond the HSE team.

## 8. Corrective-action tracking varies by customer

Some customers use:
- A dedicated `ACTION` module
- WOs with `WOCLASS = 'ACTION'`
- Sub-tasks of an incident WO (`ISTASK=1` linked to parent)
- A custom table not in Maximo at all

Check workspace glossary. The shipped `v_moc_actions` view assumes the WOCLASS='ACTION' pattern; adapt as needed.

## 9. MOC compliance has staged deadlines

A Management of Change record typically has multiple stages: initiate → review → approve → implement → close. Each stage has its own deadline. "MoC compliance %" can mean any of:
- % of MoCs at any stage by their stage-deadline
- % of MoCs FULLY closed by their close-deadline
- % of MoCs with completed actions

Clarify which the user means.

## 10. Permit expiry vs permit closure

A permit can expire (`ENDDATE < current_date()` while still `ISSUED`/`ACTIVE`) — this is a **compliance issue**. The status should have been moved to CLOSED before expiry. Detect this and surface it.

```sql
-- PERMITWORKNUM is the identifier; status literals are likely synonyms (resolve via PTW domain).
-- ENDDATE is unverified on plusgpermitwork — confirm against MAXATTRIBUTE before relying on it.
SELECT permitworknum, siteid, enddate FROM plusgpermitwork
WHERE status IN ('ISSUED', 'ACTIVE')
  AND enddate < current_timestamp();
-- Each row is a permit that needs investigation.
```

## 11. Near-miss reporting often has lag

Near-misses are typically reported by workers via a separate process (paper / mobile app) that batches into Maximo. There's commonly a 1-2 week lag. Trending near-miss reports near "now" will look artificially low — caveat any near-miss trend with the typical lag.
