# Maximo Labor & Resources — Schema Reference

## Contents

- `LABOR` — labor master
- `PERSON` — person master
- `CRAFT` + `LABORCRAFTRATE` — crafts and rates
- Qualifications — `QUALIFICATION`, `CERTIFICATION`, `QUALPERSON`
- Crews — `AMCREW`, `AMCREWLABOR`, `AMCREWT`
- Person groups — `PERSONGROUP`, `PERSONGROUPTEAM`
- Capacity — `CALENDAR`, `WORKPERIOD`, `MODAVAIL`
- Assignment & reporting — `ASSIGNMENT` (labor actuals live in `LABTRANS`, owned by `maximo-work-orders`)
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

There is **no** `LABOR.OUTSIDELABOR` column. Inside-vs-outside (employee vs contractor) labor is determined by `LABOR.VENDOR` (FK to `COMPANIES`, most common) or by whether the labor's `CRAFT` (via `LABORCRAFTRATE`) has a `VENDOR` populated — a contractor-craft convention. See gotchas §2.

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

The crew master is `AMCREW` (NOT a `CREW` table). The crew identifier value on transactional records is a column named `CREWID` (e.g. `WORKORDER.CREWID` is a real column — the crew field on the work order), but the **master** table is keyed `(ORGID, AMCREW)` and its identifier column is `AMCREW`. Join transactional crew references to the master via `AMCREW.AMCREW = <txn>.CREWID`.

### `AMCREW` — crew master

| Column | Notes |
|---|---|
| `AMCREW` | Crew identifier (PK component; the master's crew code). Referenced as the value `CREWID` on transactional records like `WORKORDER.CREWID` |
| `ORGID` | Composite — keyed `(ORGID, AMCREW)` |
| `AMCREWTYPE` | FK to `AMCREWT` (crew type) |
| `STATUS` | `ACTIVE` / `INACTIVE` |
| `WORKGROUP` | Attribute on `AMCREW` referencing a Person Group — there is **no** separate crew-workgroup binding table |

### `AMCREWLABOR` — crew composition (labor ↔ crew)

| Column | Notes |
|---|---|
| `AMCREW` / `ORGID` | FK to AMCREW |
| `LABORCODE` | FK to LABOR — one row per labor member |
| `CRAFT` | Craft the member fills on the crew |
| `SKILLLEVEL` | Skill level on the crew |
| `EFFECTIVEDATE` / `ENDDATE` | Membership period (NOTE: `EFFECTIVEDATE`, not `STARTDATE`) |
| `POSITION` | Crew position (lead, member, etc.) |

For "current crew" filter `EFFECTIVEDATE <= current_date() AND (ENDDATE IS NULL OR ENDDATE > current_date())`.

### `AMCREWT` — crew type

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

Specific work periods within a calendar — one row per working day per shift.

| Column | Notes |
|---|---|
| `CALNUM` / `ORGID` | FK to CALENDAR |
| `SITEID` | Site scope |
| `SHIFTNUM` | Shift identifier |
| `WORKDATE` | The working day (date) |
| `SHIFTSTART` | Shift start time |
| `SHIFTEND` | Shift end time |

There is **no** `WORKPERIOD.HOURS`, `WORKPERIOD.PERIODTYPE`, or `WORKPERIOD.STARTDATE` column. Scheduled hours must be **DERIVED** from the `SHIFTSTART`/`SHIFTEND` time difference. Working vs non-working time is handled via the calendar / `MODAVAIL`, not a `WORKPERIOD.PERIODTYPE` filter.

**Coverage check** before using for capacity claims:

```sql
SELECT MIN(workdate), MAX(workdate), COUNT(*)
FROM workperiod
WHERE calnum = '<your-calendar>';
```

### `MODAVAIL` — availability modifications ("Modify Availability")

Per-resource (labor/crew) availability modifications, defined separately from the shared `CALENDAR` / `SHIFT` / `WORKPERIOD`. Holds **both** working-time and non-working-time rows. **Planned absences (vacation / sick / personal / training) are the NON-WORK rows**, identified by a reason code (`RSNCODE` synonym domain — e.g. `VAC` / `SICK` / `PERSONAL`). Filter to the non-work reason codes to isolate absences; do not treat every row as an absence.

> **MODAVAIL's exact column names are NOT publicly documented.** The columns below are the *expected* semantics, not verified physical names — **confirm against `MAXATTRIBUTE` (object `MODAVAIL`) in this deployment before use.** Do not assert these as canonical.

| Column (confirm in deployment) | Expected semantics |
|---|---|
| labor / crew + `ORGID` key | FK to LABOR (or CREW) — resource whose availability is modified |
| start / end datetime | When the modification applies |
| `RSNCODE` | Reason code (synonym domain) — distinguishes work vs non-work; absence reasons (VAC/SICK/PERSONAL) are the non-work rows |
| affected hours | Hours added/removed by the modification |

Treat the absence-aware UDFs/views shipped in this skill as **templates pending column verification**, not canonical SQL.

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

### Labor reporting / actuals → `LABTRANS` (not a separate history table)

The Maximo Labor Reporting application writes to **`LABTRANS`** — the cost-bearing per-WO transaction. There is **no** separate Maximo labor-reporting-history table. For reported/actual hours and cost analytics, use `LABTRANS` (owned by `maximo-work-orders`, consumed by `maximo-maintenance-cost`). Payroll/timekeeping reconciliation typically happens in an **external timekeeping system**, not inside Maximo.

## Cardinality summary

| Relationship | Cardinality |
|---|---|
| `LABOR` → `PERSON` | N : 0..1 (contractor labor has no person) |
| `LABOR` → `LABORCRAFTRATE` | 1 : N (multiple craft rates per labor) |
| `PERSON` → `QUALPERSON` | 1 : N |
| `QUALIFICATION` → `QUALPERSON` | 1 : N |
| `AMCREW` → `AMCREWLABOR` | 1 : N |
| `AMCREW` → `PERSONGROUP` (via `WORKGROUP` attribute) | N : 0..1 |
| `LABOR` → `AMCREWLABOR` | 1 : N (labor can be on multiple crews over time) |
| `LABOR` → `MODAVAIL` | 1 : N (availability modifications; non-work rows = absences) |
| `CALENDAR` → `WORKPERIOD` | 1 : N |
| `WORKORDER` → `ASSIGNMENT` | 1 : N |
| `LABOR` → `LABTRANS` (labor actuals; referenced from `maximo-work-orders`) | 1 : N |
| `LABOR` → `COMPANIES` (via VENDOR, for contractors) | N : 1 |
