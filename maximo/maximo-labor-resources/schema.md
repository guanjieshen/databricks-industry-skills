# Maximo Labor & Resources — Schema Reference

## Contents

- `LABOR` — labor master
- `PERSON` — person master
- `CRAFT` + `LABORCRAFTRATE` — crafts and rates
- Qualifications — `QUALIFICATION`, `CERTIFICATION`, `QUALPERSON`
- Crews — `CREW`, `CREWLABOR`, `CREWWORKGROUP`, `CREWTYPE`
- Person groups — `PERSONGROUP`, `PERSONGROUPTEAM`
- Capacity — `CALENDAR`, `WORKPERIOD`, `AVAILREFLY`
- Assignment & reporting — `ASSIGNMENT`, `LABREPHIST`
- Cardinality summary

For the universal Maximo schema, see `maximo-overview`. This skill focuses on labor + capacity tables.

## `LABOR` — labor master

One row per maintainable resource (employee or contractor). Has craft + rate + status.

| Column | Notes |
|---|---|
| `LABORCODE` | Business key — unique per org. Used as FK from `LABTRANS`, `ASSIGNMENT`, `WORKORDER.LEAD`, etc. |
| `ORGID` | Composite with LABORCODE |
| `PERSONID` | FK to `PERSON` (NULL for contractor records without a person link) |
| `CRAFT` | Default craft for the resource |
| `SKILLLEVEL` | Default skill level |
| `STATUS` | `ACTIVE`, `INACTIVE`. Only ACTIVE can be assigned new work |
| `VENDOR` | FK to `COMPANIES` — populated for contractor labor (most common contractor flag) |
| `LABORTYPE` | Customer-configured (some use `EMPLOYEE` / `CONTRACTOR`) |
| `CALNUM` | Default calendar for this labor (FK to `CALENDAR`) |
| `SHIFTNUM` | Default shift |
| `PERSONGROUP` | Default person group |
| `OUTSIDELABOR` | `1` if outside (vendor) labor — alternate contractor flag |

## `PERSON` — person master

| Column | Notes |
|---|---|
| `PERSONID` | Business key — unique globally (not org-scoped) |
| `DISPLAYNAME` / `FIRSTNAME` / `LASTNAME` | Names (**PII-sensitive**) |
| `STATUS` | `ACTIVE`, `INACTIVE` |
| `JOBCODE` | Job classification |
| `SUPERVISOR` | FK to PERSON.PERSONID — chain of supervision |
| `DEPARTMENT` / `LOCATIONORG` | Organizational placement |

PII: name + email + phone live here. De-identify or aggregate before exposing in non-restricted reports.

## `CRAFT` — craft master

| Column | Notes |
|---|---|
| `CRAFT` | Craft code (`ELEC`, `MECH`, `INST`, etc.) |
| `ORGID` | Composite |
| `DESCRIPTION` | Free text |
| `OUTSIDEONLY` | `1` if craft is contractor-only |

## `LABORCRAFTRATE` — pay rates per craft per labor

One row per (labor, craft, skill level). Same labor may have rates for multiple crafts.

| Column | Notes |
|---|---|
| `LABORCODE` / `ORGID` | FK to LABOR |
| `CRAFT` / `SKILLLEVEL` | FK to CRAFT (skill level granularity) |
| `RATE` | Pay rate |
| `RATETYPE` | Rate basis |
| `PREMIUMRATETYPE` | Premium / overtime rate type |
| `CURRENCYCODE` | Currency — **be careful aggregating across currencies** |

## Qualifications

### `QUALIFICATION` — qualification catalog

| Column | Notes |
|---|---|
| `QUALIFICATIONID` | Qualification code |
| `ORGID` | Composite |
| `DESCRIPTION` | Free text |
| `STATUS` | `ACTIVE` / `INACTIVE` |
| `CRAFT` | Optional — qualification tied to a craft |
| `REQUIREDFORWORK` | `1` if the qualification is mandatory for matched work |

### `CERTIFICATION`

Specific certifications a person may hold (often a subset of `QUALIFICATION` in some customer models).

### `QUALPERSON` — person ↔ qualification

| Column | Notes |
|---|---|
| `PERSONID` | FK to PERSON |
| `QUALIFICATIONID` | FK to QUALIFICATION |
| `EFFECTIVEDATE` | When the person earned it |
| `EXPIRYDATE` | When it lapses (NULL = never) |
| `STATUS` | `ACTIVE`, `EXPIRED`, etc. |
| `CERTIFICATEID` | Optional cert identifier |
| `ISSUEDBY` | Who issued |

For "qualified labor", filter `(EXPIRYDATE IS NULL OR EXPIRYDATE > current_date()) AND STATUS = 'ACTIVE'`.

## Crews

### `CREW`

| Column | Notes |
|---|---|
| `CREWID` | Crew identifier |
| `ORGID` | Composite |
| `CREWTYPE` | FK to `CREWTYPE` |
| `STATUS` | `ACTIVE` / `INACTIVE` |
| `BASELOCATION` | Home location |

### `CREWLABOR` — crew composition (labor ↔ crew)

| Column | Notes |
|---|---|
| `CREWID` / `ORGID` | FK to CREW |
| `LABORCODE` | FK to LABOR — one row per labor member |
| `STARTDATE` / `ENDDATE` | Membership period |
| `POSITION` | Crew position (lead, member, etc.) |

For "current crew" filter `STARTDATE <= current_date() AND (ENDDATE IS NULL OR ENDDATE > current_date())`.

### `CREWWORKGROUP` — crew ↔ workgroup binding

Crews can be assigned to multiple work groups; this is the binding.

### `CREWTYPE`

Defines the type of crew (e.g. Electrical Distribution Crew, Field Operations Crew) and the **required** craft mix per crew — drives "is this crew valid" checks.

## Person groups

### `PERSONGROUP` + `PERSONGROUPTEAM`

`PERSONGROUP` defines a named group; `PERSONGROUPTEAM` lists members and their roles. Used by workflow assignment, paging, on-call rotation. Nesting possible — handle carefully.

## Capacity

### `CALENDAR`

| Column | Notes |
|---|---|
| `CALNUM` / `ORGID` | Calendar identifier |
| `DESCRIPTION` | Free text |
| `STARTDATE` / `ENDDATE` | Calendar validity range |

### `WORKPERIOD`

Specific work periods within a calendar — shifts, days off, holidays.

| Column | Notes |
|---|---|
| `CALNUM` / `ORGID` | FK to CALENDAR |
| `SHIFTNUM` | Shift identifier |
| `STARTDATE` | Period start (date + time) |
| `ENDDATE` | Period end |
| `HOURS` | Available hours in the period |
| `PERIODTYPE` | `WORK`, `HOLIDAY`, `EXCEPTION`, etc. |

**Coverage check** before using for capacity claims:

```sql
SELECT MIN(startdate), MAX(startdate), COUNT(*)
FROM workperiod
WHERE calnum = '<your-calendar>' AND periodtype = 'WORK';
```

### `AVAILREFLY` — planned absences (vacation / leave / training)

One row per planned non-availability event.

| Column | Notes |
|---|---|
| `LABORCODE` / `ORGID` | FK to LABOR |
| `STARTDATETIME` / `ENDDATETIME` | When the absence is scheduled |
| `REFTYPE` | Reason (vacation, sick, training, etc.) |
| `HOURS` | Affected hours |

## Assignment & reporting

### `ASSIGNMENT`

WO ↔ labor assignment (labor scheduled to do specific WO work).

| Column | Notes |
|---|---|
| `WONUM` / `SITEID` | FK to WORKORDER |
| `LABORCODE` / `ORGID` | FK to LABOR (or `CRAFT` only if assigned to a craft, not a specific person) |
| `CRAFT` | Craft assigned |
| `SCHEDDATE` | Scheduled start |
| `ESTDUR` | Estimated duration |
| `STATUS` | `NEW`, `ASSIGNED`, `COMPLETE` |

### `LABREPHIST` — labor reporting history

Audit log of labor reporting per pay period. Used by payroll. **For cost / hours analytics use `LABTRANS`** (see `maximo-work-orders`).

| Column | Notes |
|---|---|
| `LABORCODE` / `ORGID` | FK to LABOR |
| `PAYPERIOD` | Pay-period identifier |
| `REPORTEDHRS` | Reported hours |
| `STATUS` | `WAPPR`, `APPR`, `PROCESSED` |

## Cardinality summary

| Relationship | Cardinality |
|---|---|
| `LABOR` → `PERSON` | N : 0..1 (contractor labor has no person) |
| `LABOR` → `LABORCRAFTRATE` | 1 : N (multiple craft rates per labor) |
| `PERSON` → `QUALPERSON` | 1 : N |
| `QUALIFICATION` → `QUALPERSON` | 1 : N |
| `CREW` → `CREWLABOR` | 1 : N |
| `CREW` → `CREWWORKGROUP` | 1 : N |
| `LABOR` → `CREWLABOR` | 1 : N (labor can be on multiple crews over time) |
| `LABOR` → `AVAILREFLY` | 1 : N |
| `CALENDAR` → `WORKPERIOD` | 1 : N |
| `WORKORDER` → `ASSIGNMENT` | 1 : N |
| `LABOR` → `LABREPHIST` | 1 : N |
| `LABOR` → `LABTRANS` (referenced from `maximo-work-orders`) | 1 : N |
| `LABOR` → `COMPANIES` (via VENDOR, for contractors) | N : 1 |
