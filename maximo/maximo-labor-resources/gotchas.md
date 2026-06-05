# Maximo Labor & Resources — Gotchas

## Contents

- 1. `LABOR` vs `PERSON` — different concepts
- 2. Contractor identification varies by customer
- 3. `CALENDAR` / `WORKPERIOD` coverage probe
- 4. `QUALPERSON.EXPIRYDATE` — filter to current
- 5. `LABREPHIST` vs `LABTRANS` — pick the right one for the question
- 6. `LABORCRAFTRATE` currency aggregation
- 7. Crew membership is time-bounded
- 8. Person-group nesting can loop
- 9. Employee + contractor blends in the same crew
- 10. `AVAILREFLY` doesn't always sync with `WORKPERIOD`
- 11. Status columns are synonym domains (defer to overview)

The first 5 are also inline in `SKILL.md`. Reproduced here in full with the additional gotchas (6-11) for queries that go deeper.

> **Universal mechanics live in `maximo-overview`** — don't re-derive them here. This skill's SQL must still APPLY them: `SITEID` in every cross-table join (overview gotcha 4), `SYNONYMDOMAIN` resolution for status sets (gotcha 5), `HISTORYFLAG = 0` awareness when joining to `WORKORDER`/`TICKET` (gotcha 6), and app-server-timezone datetimes when bucketing `WORKPERIOD`/`AVAILREFLY` by day/week across sites (gotcha 7).

## 1. `LABOR` ≠ `PERSON`

`LABOR` is the maintainable resource (with craft + rate + status). `PERSON` is the human. The two are joined by `LABOR.PERSONID = PERSON.PERSONID` but the relationship is **not** 1:1:

- Admin staff and office workers are in `PERSON` but not in `LABOR` (they're not assignable to maintenance work)
- Contractor labor often appears in `LABOR` with `PERSONID = NULL` (the vendor is a company, not a tracked person)

```sql
-- WRONG — misses contractor labor that has no PERSON link
SELECT l.laborcode, p.firstname, p.lastname
FROM labor l
JOIN person p ON p.personid = l.personid
WHERE l.status = 'ACTIVE';

-- RIGHT — preserves contractor labor records
SELECT l.laborcode, COALESCE(p.displayname, l.laborcode) AS display, l.vendor
FROM labor l
LEFT JOIN person p ON p.personid = l.personid
WHERE l.status = 'ACTIVE';
```

## 2. Contractor identification varies by customer

Three common patterns — workspace glossary should specify which:

| Pattern | Filter |
|---|---|
| Vendor link | `LABOR.VENDOR IS NOT NULL` (most common — labor mapped to COMPANIES vendor) |
| Outside-only flag | `LABOR.OUTSIDELABOR = 1` |
| Custom labor type | `LABOR.LABORTYPE IN ('CONTRACTOR', 'VENDOR', ...)` |

Ask before classifying. The `contractor_spend` UDF in `maximo-maintenance-cost` uses the vendor-link pattern by default.

## 3. `CALENDAR` / `WORKPERIOD` coverage probe

`WORKPERIOD` is often sparsely populated — half the customers don't maintain forward-year schedules. A capacity query that claims "we have X hours next month" can silently return zero if `WORKPERIOD` doesn't cover that window.

**Always probe coverage first:**

```sql
SELECT
    calnum,
    MIN(startdate) AS coverage_start,
    MAX(startdate) AS coverage_end,
    COUNT(*) AS work_period_count
FROM workperiod
WHERE periodtype = 'WORK'
GROUP BY calnum
ORDER BY calnum;
```

If the forecast window extends beyond `coverage_end` for a given calendar, the capacity claim is incomplete. Disclose in the response.

## 4. `QUALPERSON.EXPIRYDATE` — filter to current

```sql
-- "Who's qualified to do hot work?"
SELECT qp.personid
FROM qualperson qp
JOIN qualification q ON q.qualificationid = qp.qualificationid
WHERE q.description LIKE '%hot work%'
  AND q.status = 'ACTIVE'
  AND qp.status = 'ACTIVE'
  AND (qp.expirydate IS NULL OR qp.expirydate > current_date());
```

Without the `EXPIRYDATE` filter, you'll count people whose certs lapsed years ago.

## 5. `LABREPHIST` vs `LABTRANS`

| Use case | Source |
|---|---|
| Cost analytics | `LABTRANS` (see `maximo-work-orders`) — has `LINECOST` |
| Hours-by-WO analytics | `LABTRANS` |
| Payroll reconciliation | `LABREPHIST` — has `PAYPERIOD` and `REPORTEDHRS` |
| Productivity (booked vs reported hours) | Both — join via `LABORCODE` |

For 99% of analytics, use `LABTRANS`. The two tables can disagree because LABTRANS is per-WO transaction and LABREPHIST is per-pay-period.

## 6. `LABORCRAFTRATE` currency aggregation

`LABORCRAFTRATE.CURRENCYCODE` may vary across labor records in multi-country deployments. Summing `RATE × HOURS` across currencies produces a meaningless number.

```sql
-- WRONG — mixes currencies
SELECT SUM(rate) FROM laborcraftrate;

-- RIGHT — group by currency
SELECT currencycode, SUM(rate) FROM laborcraftrate GROUP BY currencycode;
```

For total cost analytics, see `maximo-maintenance-cost` (which has the currency-normalization gotcha and uses `LABTRANS.LINECOST` already in-currency).

## 7. Crew membership is time-bounded

`CREWLABOR` has `STARTDATE` and `ENDDATE` per (crew, labor) pair. A labor record can be on multiple crews historically or have rotated off a crew. For "current crew composition":

```sql
SELECT cl.crewid, cl.laborcode, cl.position
FROM crewlabor cl
WHERE cl.startdate <= current_date()
  AND (cl.enddate IS NULL OR cl.enddate > current_date());
```

For historical analytics ("crew X composition in 2023 Q3"), use the dates that overlap the window.

## 8. Person-group nesting can loop

`PERSONGROUP` membership can include other groups (recursive). Some customers create accidental loops in this structure that recursive CTEs can't terminate. Defensively limit recursion depth:

```sql
WITH RECURSIVE persongroup_tree (persongroup, member, depth) AS (
    SELECT persongroup, persongroup AS member, 0 FROM persongroup
    UNION ALL
    SELECT t.persongroup, pt.persongroupteam_member, t.depth + 1
    FROM persongroup_tree t
    JOIN persongroupteam pt ON pt.persongroup = t.member
    WHERE t.depth < 10   -- hard cap to prevent runaway recursion on broken data
)
SELECT * FROM persongroup_tree;
```

## 9. Employee + contractor blends in the same crew

A single crew can contain both employee and contractor labor. For "how much of this crew's hours were contractor work":

```sql
SELECT
    cl.crewid,
    SUM(CASE WHEN l.vendor IS NULL THEN lt.regularhrs + COALESCE(lt.premiumpayhours, 0) ELSE 0 END) AS employee_hours,
    SUM(CASE WHEN l.vendor IS NOT NULL THEN lt.regularhrs + COALESCE(lt.premiumpayhours, 0) ELSE 0 END) AS contractor_hours
FROM crewlabor cl
JOIN labor l USING (laborcode, orgid)
JOIN labtrans lt USING (laborcode)
WHERE lt.startdate >= current_date() - INTERVAL 30 DAYS
GROUP BY cl.crewid;
```

## 10. `AVAILREFLY` doesn't always sync with `WORKPERIOD`

Planned absences in `AVAILREFLY` (vacation, training, sick leave) should reduce the worker's `WORKPERIOD` availability — but the sync depends on customer process. Some customers update `AVAILREFLY` but not `WORKPERIOD`; some do both; some neither.

For a "true available hours" computation, combine both:

```
true_available = workperiod_hours - sum_of_overlapping_availrefly_hours
```

The shipped `vacation_impact_hours` UDF does this for a single labor over a window. Disclose to the user if `AVAILREFLY` is sparse in their data.

Also note `WORKPERIOD.STARTDATE/ENDDATE` and `AVAILREFLY.STARTDATETIME/ENDDATETIME` are stored in the app-server timezone, not per-row UTC (overview gotcha 7). When you bucket capacity or absences by week across multiple sites, confirm the deployment's app-server TZ (a `maximo-setup` fact) — don't assume UTC.

## 11. Status columns are synonym domains (defer to overview)

`LABOR.STATUS`, `ASSIGNMENT.STATUS`, `QUALPERSON.STATUS`, `QUALIFICATION.STATUS`, `CREW.STATUS`, and the `WORKORDER.STATUS` you join to all store the customer-renamable synonym (`SYNONYMDOMAIN.VALUE`), **not** the internal `MAXVALUE`. In stock Maximo internal==external so literals like `STATUS = 'ACTIVE'` work — but if the deployment added synonyms, a literal filter silently misses records. Resolve the set via `SYNONYMDOMAIN` exactly as overview gotcha 5 prescribes (labor-side domains include `LABORSTATUS`, `WOSTATUS` for the joined WO, and the assignment-status domain configured in this deployment):

```sql
WHERE l.status IN (
    SELECT value FROM :catalog.:silver_schema.synonymdomain
    WHERE domainid = 'LABORSTATUS' AND maxvalue = 'ACTIVE'
)
```

This is a universal mechanic owned by `maximo-overview` — applied here, not re-taught.
