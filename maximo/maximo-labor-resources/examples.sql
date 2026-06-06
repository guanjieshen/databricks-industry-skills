-- =============================================================================
-- Maximo Labor & Resources — Gold-Standard Query Examples
-- =============================================================================
-- Substitute :catalog.:silver_schema, :catalog.:gold_schema,
-- :catalog.:metrics_schema before running.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Qualified labor for a specific qualification (current certs only)
-- -----------------------------------------------------------------------------
-- Trigger: "who's qualified to do hot work", "qualified labor for X"
SELECT
    l.laborcode, l.orgid, l.craft,
    COALESCE(p.displayname, l.laborcode) AS name,
    qp.expirydate                                          AS cert_expiry
FROM :catalog.:silver_schema.qualperson qp
JOIN :catalog.:silver_schema.qualification q
    ON q.qualificationid = qp.qualificationid AND q.status = 'ACTIVE'
JOIN :catalog.:silver_schema.labor l
    ON l.personid = qp.personid AND l.status = 'ACTIVE'
LEFT JOIN :catalog.:silver_schema.person p
    ON p.personid = l.personid
WHERE q.qualificationid = ':qualification_id'
  AND qp.status = 'ACTIVE'
  AND (qp.expirydate IS NULL OR qp.expirydate > current_date())
ORDER BY cert_expiry NULLS LAST;


-- -----------------------------------------------------------------------------
-- 2. Certifications expiring in the next N days
-- -----------------------------------------------------------------------------
-- Trigger: "expiring certifications", "certs lapsing soon"
SELECT
    qp.personid,
    COALESCE(p.displayname, qp.personid)                   AS name,
    q.qualificationid,
    q.description                                          AS qualification,
    qp.expirydate,
    datediff(DAY, current_date(), qp.expirydate)           AS days_until_expiry
FROM :catalog.:silver_schema.qualperson qp
JOIN :catalog.:silver_schema.qualification q
    ON q.qualificationid = qp.qualificationid
LEFT JOIN :catalog.:silver_schema.person p
    ON p.personid = qp.personid
WHERE qp.status = 'ACTIVE'
  AND qp.expirydate BETWEEN current_date() AND current_date() + INTERVAL :days_ahead DAYS
ORDER BY qp.expirydate;


-- -----------------------------------------------------------------------------
-- 3. Crew capacity for the next N weeks (composes with pm-planning)
-- -----------------------------------------------------------------------------
-- Trigger: "crew capacity next month", "how many hours can crew X work"
SELECT
    cap.crewid,
    cap.week_starting,
    cap.craft,
    cap.available_hours
FROM :catalog.:gold_schema.v_crew_capacity cap
WHERE cap.week_starting BETWEEN current_date()
                            AND current_date() + INTERVAL :weeks_ahead WEEKS
  AND cap.crewid = ':crewid'
ORDER BY week_starting, craft;


-- -----------------------------------------------------------------------------
-- 4. Workload vs capacity gap by craft × week
-- -----------------------------------------------------------------------------
-- Trigger: "are we over-scheduled", "workload vs capacity"
-- Composes maximo-pm-planning forecast (v_pm_workload_by_craft) with this
-- skill's capacity (v_crew_capacity).
SELECT
    wl.siteid,
    wl.craft,
    wl.week_starting,
    wl.planned_labor_hours                                  AS workload_hours,
    COALESCE(SUM(cap.available_hours), 0)                   AS capacity_hours,
    wl.planned_labor_hours - COALESCE(SUM(cap.available_hours), 0) AS gap_hours,
    CASE
        WHEN wl.planned_labor_hours > COALESCE(SUM(cap.available_hours), 0) THEN 'OVER'
        WHEN wl.planned_labor_hours < COALESCE(SUM(cap.available_hours), 0) * 0.6 THEN 'UNDER'
        ELSE 'OK'
    END                                                     AS status
FROM :catalog.:gold_schema.v_pm_workload_by_craft wl
LEFT JOIN :catalog.:gold_schema.v_crew_capacity cap
    ON cap.craft = wl.craft AND cap.week_starting = wl.week_starting
WHERE wl.week_starting BETWEEN current_date()
                           AND current_date() + INTERVAL 90 DAYS
GROUP BY wl.siteid, wl.craft, wl.week_starting, wl.planned_labor_hours
ORDER BY wl.week_starting, ABS(gap_hours) DESC;


-- -----------------------------------------------------------------------------
-- 5. Vacation impact in next quarter
-- -----------------------------------------------------------------------------
-- Trigger: "vacation impact", "planned absence next quarter"
-- TEMPLATE — PENDING COLUMN VERIFICATION. Planned absences are the NON-WORK rows
-- of MODAVAIL ("Modify Availability"), isolated by the reason code (RSNCODE
-- synonym domain). MODAVAIL's exact column names are NOT publicly documented:
-- the resource key, datetimes, RSNCODE column and hours column below are
-- PLACEHOLDERS — confirm against MAXATTRIBUTE (object MODAVAIL) and resolve the
-- non-work reason-code set via SYNONYMDOMAIN before running. MODAVAIL also holds
-- working-time rows, so the RSNCODE filter is required. See gotchas.md §9.
SELECT
    a.laborcode,
    COALESCE(p.displayname, a.laborcode)                   AS name,
    l.craft,
    a.rsncode                                              AS absence_reason,
    a.startdatetime, a.enddatetime,
    a.hours                                                AS absence_hours
FROM :catalog.:silver_schema.modavail a
JOIN :catalog.:silver_schema.labor l USING (laborcode, orgid)
LEFT JOIN :catalog.:silver_schema.person p ON p.personid = l.personid
WHERE a.rsncode IN ('VAC', 'SICK', 'PERSONAL')   -- non-work rows = absences (confirm codes)
  AND a.startdatetime BETWEEN current_date()
                          AND current_date() + INTERVAL 90 DAYS
ORDER BY a.startdatetime, l.craft;


-- -----------------------------------------------------------------------------
-- 6. Contractor vs employee labor mix last quarter
-- -----------------------------------------------------------------------------
-- Trigger: "contractor mix", "outside labor percentage"
SELECT
    CASE WHEN l.vendor IS NOT NULL THEN 'CONTRACTOR' ELSE 'EMPLOYEE' END AS labor_type,
    l.craft,
    SUM(lt.regularhrs + COALESCE(lt.premiumpayhours, 0))   AS total_hours,
    SUM(lt.linecost)                                       AS total_cost,
    COUNT(DISTINCT l.laborcode)                            AS distinct_resources
FROM :catalog.:silver_schema.labtrans lt
JOIN :catalog.:silver_schema.labor l USING (laborcode, orgid)
WHERE lt.transtype = 'WORK'
  AND lt.startdate >= add_months(current_date(), -3)
GROUP BY CASE WHEN l.vendor IS NOT NULL THEN 'CONTRACTOR' ELSE 'EMPLOYEE' END,
         l.craft
ORDER BY l.craft, labor_type;


-- -----------------------------------------------------------------------------
-- 7. Labor utilization — hours booked / available hours
-- -----------------------------------------------------------------------------
-- Trigger: "labor utilization", "is X overworked"
WITH booked AS (
    SELECT lt.laborcode, SUM(lt.regularhrs + COALESCE(lt.premiumpayhours, 0)) AS booked_hours
    FROM :catalog.:silver_schema.labtrans lt
    WHERE lt.startdate BETWEEN ':window_start' AND ':window_end'
      AND lt.transtype = 'WORK'
    GROUP BY lt.laborcode
),
available AS (
    -- Scheduled hours DERIVED from SHIFTSTART/SHIFTEND (no WORKPERIOD.HOURS column).
    SELECT l.laborcode,
           SUM((unix_timestamp(wp.shiftend) - unix_timestamp(wp.shiftstart)) / 3600.0) AS available_hours
    FROM :catalog.:silver_schema.labor l
    JOIN :catalog.:silver_schema.workperiod wp
        ON wp.calnum = l.calnum AND wp.shiftnum = l.shiftnum
       AND wp.workdate BETWEEN ':window_start' AND ':window_end'
    GROUP BY l.laborcode
)
SELECT
    a.laborcode,
    a.available_hours,
    COALESCE(b.booked_hours, 0)                            AS booked_hours,
    ROUND(100.0 * COALESCE(b.booked_hours, 0) / NULLIF(a.available_hours, 0), 1)
                                                            AS utilization_pct
FROM available a
LEFT JOIN booked b ON b.laborcode = a.laborcode
ORDER BY utilization_pct DESC NULLS LAST;


-- -----------------------------------------------------------------------------
-- 8. Crew composition (current)
-- -----------------------------------------------------------------------------
-- Trigger: "who's on crew X", "crew composition"
SELECT
    cl.amcrew                                              AS crewid,
    cl.laborcode,
    COALESCE(p.displayname, cl.laborcode)                  AS name,
    l.craft, l.skilllevel,
    cl.position,
    cl.effectivedate                                      AS on_crew_since
FROM :catalog.:silver_schema.amcrewlabor cl
JOIN :catalog.:silver_schema.labor l USING (laborcode, orgid)
LEFT JOIN :catalog.:silver_schema.person p ON p.personid = l.personid
WHERE cl.amcrew = ':crewid'
  AND cl.effectivedate <= current_date()
  AND (cl.enddate IS NULL OR cl.enddate > current_date())
ORDER BY cl.position, cl.effectivedate;


-- -----------------------------------------------------------------------------
-- 9. Person-group composition (immediate members only)
-- -----------------------------------------------------------------------------
-- Trigger: "who's in person group X"
SELECT
    pgt.persongroup,
    pgt.respparty                                          AS member_personid,
    COALESCE(p.displayname, pgt.respparty)                 AS member_name,
    pgt.persongroupteamid                                  AS member_type
FROM :catalog.:silver_schema.persongroupteam pgt
LEFT JOIN :catalog.:silver_schema.person p
    ON p.personid = pgt.respparty
WHERE pgt.persongroup = ':persongroup'
ORDER BY pgt.respparty;


-- -----------------------------------------------------------------------------
-- 10. Open WO assignments for a specific labor (today's backlog)
-- -----------------------------------------------------------------------------
-- Trigger: "what's X working on today", "my assignments"
-- NOTE (overview gotcha 5): WORKORDER.STATUS and ASSIGNMENT.STATUS are synonym
--   domains. The literals below work in stock Maximo (internal==external); if
--   the deployment added synonyms, resolve via SYNONYMDOMAIN, e.g.
--   w.status NOT IN (SELECT value FROM :catalog.:silver_schema.synonymdomain
--                    WHERE domainid = 'WOSTATUS' AND maxvalue IN ('COMP','CLOSE','CAN'))
-- NOTE (overview gotcha 6): WORKORDER carries HISTORYFLAG; closed/cancelled WOs
--   get HISTORYFLAG=1 and drop out of IBM-shipped views. Excluding final
--   statuses (below) already removes them, but be aware if you widen the filter.
SELECT
    a.wonum, a.siteid,
    w.description                                          AS wo_description,
    w.assetnum, w.location,
    a.scheddate, a.estdur,
    a.status                                               AS assignment_status,
    w.status                                               AS wo_status
FROM :catalog.:silver_schema.assignment a
JOIN :catalog.:silver_schema.workorder w
    ON w.wonum = a.wonum AND w.siteid = a.siteid          -- SITEID composite (gotcha 4)
WHERE a.laborcode = ':laborcode'
  AND a.status IN ('NEW', 'ASSIGNED')
  AND w.status NOT IN ('COMP', 'CLOSE', 'CAN')
ORDER BY a.scheddate;
