# Maximo HSE — Schema Reference

## Contents

- PLUSG (O&G industry solution) tables
  - `plusgpermitwork` — Permit to Work records
  - `plusgpertype` — Permit & Certificate Type catalog
  - `plusgshiftlog` / `plusgshftlogentry` — Operator Log + shift log entries
  - `plusgoperaction` — Operator-recorded actions
  - `plusgshftlogentry` / `plusgshiftlog` — Operator shift logs
  - `plusgrelatedrec` — Cross-record links
  - `plusgincperson` — Persons involved in incidents
  - `plusgoperaction` — Operator-recorded actions
- Core Maximo tables used by HSE
  - `TICKET` / Incident (CLASS='INCIDENT')
  - `INVESTIGATION`
  - LOTO (Lock Out Tag Out) Plan
  - `MOC` (Management of Change)
  - `ACTION` (sometimes `WORKORDER` with `WOCLASS = 'ACTION'`)
- Common joins
  - Open permits with their covered work
  - Incidents linked to specific WOs / assets
  - Corrective actions still open from incidents
- Cardinality summary

For the universal Maximo schema, see `maximo-overview/SKILL.md`. This skill focuses on the PLUSG O&G industry-solution tables and HSE workflows.

> **PHYSICAL COLUMN NAMES — READ FIRST.** IBM does NOT publish a per-column data dictionary for `PLUSG*` tables (the docs page only directs you to query `MAXATTRIBUTE WHERE objectname LIKE 'PLUSG%'`). The column names below are derived from the IBM MAS Performance Wiki's recommended-index DDL — the best public source — and MUST be confirmed against `MAXATTRIBUTE` in THIS deployment before shipping. Where a column was not visible in any source, it is flagged as unverified.

## PLUSG (O&G industry solution) tables

The full inventory of PLUSG tables referenced by HSE workflows (per the IBM MAS Performance Wiki's recommended-index documentation):

| Table | What it holds |
|---|---|
| `plusgpermitwork` | Permit-to-Work transactional records |
| `plusgpertype` | **Permit & Certificate Type catalog** — distinct from transactional permits |
| `plusgshiftlog` | Operator shift log header |
| `plusgshftlogentry` | Operator shift log entries (line items) |
| `plusgoperaction` | Operator-recorded actions |
| `plusgrelatedrec` | Cross-record relationship links |
| `plusgincperson` | Persons involved in incidents (**PII-sensitive**) |

> IBM recommends archiving `plusgshiftlog` / `plusgshftlogentry` / Operator Log records periodically for performance — they grow quickly in active O&G operations.

### `plusgpermitwork` — Permit to Work records

Physical columns confirmed from the MAS Performance Wiki index DDL: `PTWCLASS`, `SITEID`, `ORGID`, `PERMITWORKNUM`, `STATUS`, `PLUSGPERTYPEID`, `DESCRIPTION`.

| Column | Notes |
|---|---|
| `PERMITWORKNUM` | **Permit identifier** (verified). NOT `PERMITNUM`. |
| `SITEID` / `ORGID` | Composite with `PERMITWORKNUM` (apply overview F1). |
| `PTWCLASS` | Permit-work class discriminator (appears in multiple indexes). |
| `PLUSGPERTYPEID` | **FK to `plusgpertype`** (its surrogate PK). NOT a column named `PERMITTYPE`. |
| `STATUS` | PTW-specific status (the skill's `DRAFT/APPROVED/ISSUED/ACTIVE/CLOSED/CANCELLED` are likely customer synonyms). Resolve via the PTW status domain — confirm the exact `domainid` in `DOMAIN`/`SYNONYMDOMAIN` (was NOT publicly named; candidates like `PTWSTATUS` are inferred only). PTW also carries its own `HISTORYFLAG`. |
| `DESCRIPTION` | Free-text permit description (verified, indexed). |
| `WONUM` / `LOCATION` / `STARTDATE` / `ENDDATE` / `ISSUEDBY` / `ISSUEDDATE` | **Unverified** — these are conceptually expected (work covered, validity window, authorization audit) but were NOT in the published index DDL. Confirm against `MAXATTRIBUTE` before use. |

> PTW has its OWN `STATUS` and OWN `HISTORYFLAG`; it is a work-control object, NOT a WORKORDER. Its status HISTORY lives in the PTW object's own status-history mechanism (analogous to TKSTATUS for tickets / WOSTATUS for work orders), NOT in `WOSTATUS`. See gotchas.md.

### `plusgpertype` — Permit & Certificate Type catalog

The **type catalog** — distinct from transactional `plusgpermitwork` records. Physical key columns (from the MAS Performance Wiki index DDL): business code column `PERTYPENUM`, surrogate PK `PLUSGPERTYPEID`. The PK is `PLUSGPERTYPEID`, NOT `PERTYPE`. `plusgpermitwork` joins to this catalog via `plusgpertype.plusgpertypeid = plusgpermitwork.plusgpertypeid`.

Used by:
- Permit to Work (PTW)
- Isolation Management
- Certifications

Examples of type records: Hot Work, Cold Work, Confined Space, Excavation, Work-at-Heights, electrical-isolation certificate.

**Three-state framework** governs reuse of a type:

| State | Editable? | Applicable to new records? |
|---|---|---|
| `DRAFT` | Yes | No |
| `ACTIVE` | No (read-only) | Yes |
| `INACTIVE` | No (read-only) | No |

When a type is applied to a transactional record (PTW / Isolation / Cert), the type's `LONGDESCRIPTION` populates the record's header.

**Implication for analytics**: when asking "which permit types are in use", filter `plusgpertype` to `STATUS = 'ACTIVE'`. Inactive types may still appear on historical transactional records — that's intentional.

Reference: [IBM — Permit and Certificate Types application](https://www.ibm.com/docs/en/mfo-and-g/7.6.2?topic=module-permit-certificate-types-application)

### `plusgshiftlog` / `plusgshftlogentry` — Operator Log + shift log entries

The **Operator Log** application captures shift-by-shift operational notes — production losses, handover items, equipment status changes, observations that don't rise to the level of a formal incident. Often the first place a near-miss gets recorded before formal HSE intake.

- `plusgshiftlog` — log header per shift (one row per operator-shift)
- `plusgshftlogentry` — line items within a shift log (production-loss entries, handover notes, equipment notes, etc.)

The **Log Book** feature aggregates individual operator logs for shift handover — useful for trend analytics across shifts.

For analytics:
- Joining shift logs to incidents (via `plusgrelatedrec`) can surface "this incident was foreshadowed in three prior shift logs"
- Production-loss entries are a leading indicator for equipment-driven outages

### `plusgoperaction` — Operator-recorded actions

Field-recorded actions tied to work, permits, or incidents. Used when an operator needs to log a step taken outside of a formal WO.

### `plusgshftlogentry` / `plusgshiftlog` — Operator shift logs

Operator handover records — often used to flag issues that didn't reach the formal incident system.

### `plusgrelatedrec` — Cross-record links

Bidirectional link table for relating records across modules:
- WORKORDER ↔ INCIDENT
- INCIDENT ↔ MOC
- INCIDENT ↔ INVESTIGATION
- WORKORDER ↔ plusgpermitwork (a permit covers a WO)

Verified physical key columns (from MAS Performance Wiki indexes): `RECORDKEY`, `CLASS` (the source-side class column — NOT `RECORDCLASS`), `RELATEDRECKEY`, `RELATEDRECCLASS`. The link is keyed `(recordkey, class) <-> (relatedreckey, relatedrecclass)`, mirroring core Maximo's `RELATEDRECORD` object (system-level, no key attributes, maintains the reciprocal row). `RECORDKEY` already encodes the composite business-key value, so the link is keyed on `RECORDKEY`+`CLASS`, not a separate `siteid` join column.

A relationship/type column was NOT visible in the published indexes. Core `RELATEDRECORD` uses `RELATETYPE` (values like `FOLLOWUP`/`ORIGINATOR`/`RELATED`), NOT a column named `RELATIONSHIP`. Verify whether `plusgrelatedrec` carries an analogous `RELATETYPE` column in `MAXATTRIBUTE`; a column literally named `PLUSGRELATEDRECID` was NOT found in any source — do not assert it without deployment verification.

### `plusgincperson` — Persons involved in incidents

Links incidents to people. **PII-sensitive** — handle with care. The MAS Performance Wiki's sole recommended index for `plusgincperson` is on `TICKETID` — so the join column to the incident is **`TICKETID`**, NOT `INCIDENTID`. This is consistent with incidents being TICKET-class records (surrogate key `TICKETID`); see the TICKET/INCIDENT section below.

IBM's incident docs confirm the conceptual fields (a "Persons Impacted by Incident" table; a "Person Role" field with value `Injured/Ill`; multiple illnesses/injuries and multiple outcomes per person) but do NOT publish the physical column names. So `PERSONID`/`ROLE`/`INJURYTYPE`/`INJURYCLASSIFICATION` are **conceptual/UNVERIFIED** — read the exact attribute names (e.g. `PERSONID` vs `PERSONUID`, the role/injury columns) from `MAXATTRIBUTE` in the deployment. The only verified column is `TICKETID`.

### `plusgoperaction` — Operator-recorded actions

Field-recorded actions tied to work or incidents.

## Core Maximo tables used by HSE

### `TICKET` / Incident (CLASS='INCIDENT')

**There is no standalone `INCIDENT` table.** SR, INCIDENT, and PROBLEM all share the core `TICKET` table; the three applications are views distinguished by `TICKET.CLASS` (values `SR` / `INCIDENT` / `PROBLEM`). The "Incident Class" field is populated with the class (e.g. `Incident` or `Service Request`). The surrogate key is `TICKETID` — which is why `plusgincperson` keys on `TICKETID`. Filter `CLASS='INCIDENT'` for incident analytics.

Because incidents are TICKET records they are subject to **`HISTORYFLAG`**: at CLOSED/CANCELLED/REJECTED a ticket gets `HISTORYFLAG=1` and drops off the List tab (apply overview F3). Incident status resolves via `SYNONYMDOMAIN WHERE domainid='INCIDENTSTATUS'` — each ticket class has its OWN synonym domain (`SRSTATUS` / `INCIDENTSTATUS` / `PROBLEMSTATUS`). The stock `INCIDENTSTATUS` value set is `NEW` / `QUEUED` / `PENDING` / `INPROG` / `RESOLVED` / `CLOSED` (apply overview F2).

Common / conceptual columns:
- `TICKETID` — surrogate primary key (verified).
- `CLASS` — `SR` / `INCIDENT` / `PROBLEM`. Filter `='INCIDENT'`.
- `SITEID` / `ORGID` — composite-key participants.
- `STATUS` — synonym value; resolve via `SYNONYMDOMAIN` (domainid `INCIDENTSTATUS`). The skill's old `REPORTED/INVESTIGATING/CLOSED` literals do NOT match the stock set — treat as customer synonyms, do not hardcode.
- `HISTORYFLAG` — `1` once final-status; standard views filter `=0`.
- `REPORTDATE` — when reported (app-server TZ; apply overview F4).
- `ASSETNUM` / `LOCATION` — asset / where it happened.
- `INCIDENTCATEGORY`, `SEVERITY` — **UNVERIFIED stock column names.** Category/severity and any recordable/Tier classification are typically driven by `CLASSIFICATION` (`CLASSSTRUCTUREID`) or a configurable value list, NOT a fixed stock column. Confirm in `MAXATTRIBUTE` / the workspace glossary (see gotchas).

### `INVESTIGATION`

Per-incident investigation record. Columns: `INVESTIGATIONID`, `INCIDENTID`, root cause findings, corrective actions.

### LOTO (Lock Out Tag Out) Plan

The **Lock Out Tag Out Plan** application (part of Lock Management in the Planning module) holds reusable locking/unlocking-sequence templates applied on PTW / Isolation records. The plan record uses an **`ACTIVE`** field, NOT a `STATUS` field ("The Active field is used to identify plan records which are available for use"). See gotchas.md — there is no LOTO status nor status-history.

The exact physical table name is not published; it is a `PLUSG`-prefixed Lock/LOTO object. Verify via `MAXATTRIBUTE WHERE objectname LIKE 'PLUSG%LOCK%'` or `'PLUSG%LOTO%'` in the deployment. Lock boxes / locks / seals / keys are managed by the separate **Lock Management** application, not the LOTO Plan object.

### `MOC` (Management of Change)

Records of changes to plant / processes / assets requiring formal review. Maximo's MOC module tables vary by version. Typical: `MOCID`, `SITEID`, `REASON`, `STATUS`, `INITIATEDDATE`, `CLOSEDDATE`.

### `ACTION` (sometimes `WORKORDER` with `WOCLASS = 'ACTION'`)

Corrective actions arising from incidents. Each action has owner, due-date, status. Outstanding-actions reporting is a major HSE KPI.

## Common joins

### Open permits with their covered work

```sql
-- PERMITWORKNUM (not permitnum); join type catalog on PLUSGPERTYPEID.
-- WONUM on plusgpermitwork is unverified — confirm in MAXATTRIBUTE before relying on it.
SELECT p.permitworknum, pt.pertypenum, p.status, p.description,
       w.wonum, w.description AS wo_desc, a.assetnum, a.description AS asset_desc
FROM plusgpermitwork p
LEFT JOIN plusgpertype pt ON pt.plusgpertypeid = p.plusgpertypeid
LEFT JOIN workorder w ON w.wonum = p.wonum AND w.siteid = p.siteid
LEFT JOIN asset a ON a.assetnum = w.assetnum AND a.siteid = w.siteid AND a.__END_AT IS NULL
WHERE p.status IN ('ISSUED', 'ACTIVE');  -- resolve via PTW status domain; literals are likely synonyms
```

### Incidents linked to specific WOs / assets

```sql
-- Incidents are TICKET rows (CLASS='INCIDENT'); join plusgrelatedrec on TICKETID.
-- The source-side class column is CLASS (not recordclass).
SELECT i.ticketid, rr.recordkey AS related_wonum
FROM ticket i
JOIN plusgrelatedrec rr
    ON rr.relatedreckey = i.ticketid
   AND rr.relatedrecclass = 'INCIDENT'
   AND rr.class = 'WORKORDER'
WHERE i.class = 'INCIDENT';
```

### Corrective actions still open from incidents

```sql
SELECT a.* FROM workorder a
WHERE a.woclass = 'ACTION'
  AND a.status NOT IN ('COMP', 'CLOSE')
  AND a.parent IN (SELECT wonum FROM workorder WHERE woclass = 'ACTION' OR ...);
```
(Action tracking varies by customer; check workspace glossary.)

## Cardinality summary

| Relationship | Cardinality |
|---|---|
| `plusgpermitwork` → `WORKORDER` | N : 1 (a permit covers one primary WO) — `WONUM` on permit is unverified |
| `plusgpermitwork.plusgpertypeid` → `plusgpertype.plusgpertypeid` | N : 1 |
| `TICKET (CLASS='INCIDENT')` → `plusgincperson` (on `TICKETID`) | 1 : N |
| `TICKET (CLASS='INCIDENT')` → `INVESTIGATION` | 1 : 0..1 |
| `plusgrelatedrec` `(recordkey,class) <-> (relatedreckey,relatedrecclass)` | bidirectional link, M : N effectively |
| `TICKET (CLASS='INCIDENT')` → `ACTION` (via plusgrelatedrec) | 1 : N |
