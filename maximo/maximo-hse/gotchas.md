# Maximo HSE — Gotchas

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

When the user asks "show me active permits", they almost always mean transactional permits (`plusgpermitwork.STATUS IN ('ISSUED','ACTIVE')`), not the type catalog. Confirm if ambiguous.

## 1. `plusg*` tables may not exist

The PLUSG prefix is the Maximo Oil & Gas industry-solution extension. Customers running classic Maximo without the O&G solution **don't have these tables**. Verify before writing queries that join to them — return a clear error rather than silently returning empty results.

## 2. TRIR / LTIR hours-worked typically isn't in Maximo

The formula is `(recordable incidents × 200,000) / hours-worked`. The numerator is in `INCIDENT`. The denominator (hours-worked across the workforce) is almost always in **HR / payroll**, not Maximo. Common sources:
- Workday / SAP SuccessFactors / Oracle HCM
- Custom workforce-management system
- A Databricks-side HR dataset

The shipped `trir` UDF takes hours-worked as a parameter. The caller must source it. Don't hallucinate hours-worked from Maximo LABTRANS — LABTRANS is only labor booked to WOs, not all hours-worked.

## 3. Incident categorization is regulatory-specific

| Category | Definition | Reporting body |
|---|---|---|
| Recordable | OSHA-defined: lost time, restricted duty, medical treatment beyond first aid | OSHA |
| Lost-time | Subset of recordable: caused days away from work | OSHA + internal |
| Near-miss | Could-have-been incident with no injury | Internal + sometimes regulator |
| First aid | Minor injury treated on-site | Internal |
| Process Safety (Tier 1-4) | API RP 754 process-safety classification | API + sometimes regulator |

`INCIDENTCATEGORY` values are customer-configured. Verify via workspace glossary or ASK before computing TRIR/LTIR — different customers use different category codes.

## 4. Permit-to-work data is PII-sensitive in some jurisdictions

Permit records may include named permit-holders, isolation lockout names, etc. Some jurisdictions treat this as employment data subject to GDPR / regional privacy law. Aggregate or de-identify before sharing in any non-restricted artifact.

Same for `plusgincperson` — names of injured workers should NEVER appear in dashboards visible beyond the HSE team.

## 5. Corrective-action tracking varies by customer

Some customers use:
- A dedicated `ACTION` module
- WOs with `WOCLASS = 'ACTION'`
- Sub-tasks of an incident WO (`ISTASK=1` linked to parent)
- A custom table not in Maximo at all

Check workspace glossary. The shipped `v_moc_actions` view assumes the WOCLASS='ACTION' pattern; adapt as needed.

## 6. MOC compliance has staged deadlines

A Management of Change record typically has multiple stages: initiate → review → approve → implement → close. Each stage has its own deadline. "MoC compliance %" can mean any of:
- % of MoCs at any stage by their stage-deadline
- % of MoCs FULLY closed by their close-deadline
- % of MoCs with completed actions

Clarify which the user means.

## 7. PSM / process-safety indicators (API RP 754)

For O&G refineries / facilities, process safety reporting uses API RP 754 Tier 1-4 classifications:
- **Tier 1**: significant process safety events (high consequence)
- **Tier 2**: less severe process safety events
- **Tier 3**: challenges to safety systems (precursor indicators)
- **Tier 4**: operating discipline / management system metrics

These map to Maximo `INCIDENT` records with specific category codes — typically customer-configured. Workspace glossary should define the mapping.

## 8. Permit expiry vs permit closure

A permit can expire (`ENDDATE < current_date()` while `STATUS = 'ACTIVE'`) — this is a **compliance issue**. The status should have been moved to CLOSED before expiry. Detect this and surface it.

```sql
SELECT * FROM plusgpermitwork
WHERE status IN ('ISSUED', 'ACTIVE')
  AND enddate < current_timestamp();
-- Each row is a permit that needs investigation.
```

## 9. Near-miss reporting often has lag

Near-misses are typically reported by workers via a separate process (paper / mobile app) that batches into Maximo. There's commonly a 1-2 week lag. Trending near-miss reports near "now" will look artificially low — caveat any near-miss trend with the typical lag.
