# Maximo HSE — Schema Reference

For the universal Maximo schema, see `maximo-overview/SKILL.md`. This skill focuses on the PLUSG O&G industry-solution tables and HSE workflows.

## PLUSG (O&G industry solution) tables

### `plusgpermitwork` — Permit to Work records

| Column | Notes |
|---|---|
| `PERMITNUM` | Permit identifier |
| `SITEID` | Composite with PERMITNUM |
| `PERMITTYPE` | FK to `plusgpertype` |
| `STATUS` | DRAFT, APPROVED, ISSUED, ACTIVE, CLOSED, CANCELLED |
| `STARTDATE` | Permit validity start |
| `ENDDATE` | Permit validity end (statutory deadline) |
| `WONUM` | FK to WORKORDER (the work this permit covers) |
| `SITEID` | Composite with WONUM |
| `LOCATION` | Where the permitted work happens |
| `ISSUEDBY` / `ISSUEDDATE` | Authorization audit trail |

### `plusgpertype` — Permit types

Permit-type catalog: Hot Work, Cold Work, Confined Space, Excavation, Work-at-Heights, etc. Each type has different requirements and approval workflows.

### `plusgshftlogentry` / `plusgshiftlog` — Operator shift logs

Operator handover records — often used to flag issues that didn't reach the formal incident system.

### `plusgrelatedrec` — Cross-record links

Bidirectional link table for relating records across modules:
- WORKORDER ↔ INCIDENT
- INCIDENT ↔ MOC
- INCIDENT ↔ INVESTIGATION
- WORKORDER ↔ plusgpermitwork (a permit covers a WO)

Schema: `RECORDKEY`, `RECORDCLASS`, `RELATEDRECKEY`, `RELATEDRECCLASS`, `RELATIONSHIP`.

### `plusgincperson` — Persons involved in incidents

Links incidents to people. **PII-sensitive** — handle with care. Schema typically: `INCIDENTID`, `PERSONID`, `ROLE` (witness, injured-party, supervisor), `INJURYTYPE`, `INJURYCLASSIFICATION`.

### `plusgoperaction` — Operator-recorded actions

Field-recorded actions tied to work or incidents.

## Core Maximo tables used by HSE

### `INCIDENT`

The incident master table. Columns vary by Maximo version; common ones:
- `INCIDENTID` — primary key
- `SITEID` — composite
- `REPORTDATE` — when reported
- `INCIDENTCATEGORY` — recordable, near-miss, first-aid, etc.
- `STATUS` — REPORTED, INVESTIGATING, CLOSED
- `SEVERITY` — severity classification
- `ASSETNUM` — asset involved (if any)
- `LOCATION` — where it happened

### `INVESTIGATION`

Per-incident investigation record. Columns: `INVESTIGATIONID`, `INCIDENTID`, root cause findings, corrective actions.

### `MOC` (Management of Change)

Records of changes to plant / processes / assets requiring formal review. Maximo's MOC module tables vary by version. Typical: `MOCID`, `SITEID`, `REASON`, `STATUS`, `INITIATEDDATE`, `CLOSEDDATE`.

### `ACTION` (sometimes `WORKORDER` with `WOCLASS = 'ACTION'`)

Corrective actions arising from incidents. Each action has owner, due-date, status. Outstanding-actions reporting is a major HSE KPI.

## Common joins

### Open permits with their covered work

```sql
SELECT p.permitnum, p.permittype, p.status, p.enddate,
       w.wonum, w.description, a.assetnum, a.description AS asset_desc
FROM plusgpermitwork p
LEFT JOIN workorder w ON w.wonum = p.wonum AND w.siteid = p.siteid
LEFT JOIN asset a ON a.assetnum = w.assetnum AND a.siteid = w.siteid AND a.__END_AT IS NULL
WHERE p.status IN ('ISSUED', 'ACTIVE');
```

### Incidents linked to specific WOs / assets

```sql
SELECT i.*, rr.recordkey AS related_wonum
FROM incident i
JOIN plusgrelatedrec rr
    ON rr.relatedreckey = i.incidentid
   AND rr.relatedrecclass = 'INCIDENT'
   AND rr.recordclass = 'WORKORDER';
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
| `plusgpermitwork` → `WORKORDER` | N : 1 (a permit covers one primary WO) |
| `plusgpermitwork` → `plusgpertype` | N : 1 |
| `INCIDENT` → `plusgincperson` | 1 : N |
| `INCIDENT` → `INVESTIGATION` | 1 : 0..1 |
| `plusgrelatedrec` | bidirectional link, M : N effectively |
| `INCIDENT` → `ACTION` (via parent or plusgrelatedrec) | 1 : N |
