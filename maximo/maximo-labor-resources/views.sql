-- =============================================================================
-- Maximo Labor & Resources — Gold Views
-- =============================================================================
-- Substitute :catalog.:silver_schema and :catalog.:gold_schema.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_labor_position
-- Per-labor enriched view: person link, craft, default rate, current
-- qualification count, contractor flag, default calendar/shift.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_labor_position
COMMENT 'Per-labor enriched position. One row per LABOR. Joins person, default craft rate, and current qualification count. Use for any labor-master report.'
AS
WITH default_rate AS (
    SELECT
        laborcode, orgid, craft, skilllevel,
        ROW_NUMBER() OVER (PARTITION BY laborcode, orgid ORDER BY craft) AS rn,
        rate, currencycode, vendor
    FROM :catalog.:silver_schema.laborcraftrate
),
current_quals AS (
    SELECT personid, COUNT(*) AS current_qualification_count
    FROM :catalog.:silver_schema.qualperson
    WHERE status = 'ACTIVE'
      AND (expirydate IS NULL OR expirydate > current_date())
    GROUP BY personid
)
SELECT
    l.laborcode, l.orgid, l.status,
    l.personid,
    COALESCE(p.displayname, l.laborcode)                  AS display_name,
    p.firstname, p.lastname,
    l.craft                                                AS default_craft,
    l.skilllevel                                           AS default_skill_level,
    dr.rate                                                AS default_rate,
    dr.currencycode                                        AS rate_currency,
    dr.vendor                                              AS craft_rate_vendor,
    l.calnum                                               AS default_calendar,
    l.shiftnum                                             AS default_shift,
    l.persongroup                                          AS default_persongroup,
    l.vendor                                               AS contractor_vendor,
    CASE
        -- Inside-vs-outside labor: LABOR.VENDOR (most common), or the associated
        -- CRAFT rate (via LABORCRAFTRATE) carrying a VENDOR. There is no
        -- LABOR.OUTSIDELABOR column (gotcha 2).
        WHEN l.vendor IS NOT NULL THEN 'CONTRACTOR'
        WHEN dr.vendor IS NOT NULL THEN 'CONTRACTOR'
        ELSE 'EMPLOYEE'
    END                                                    AS labor_type,
    COALESCE(cq.current_qualification_count, 0)           AS current_qualifications,
    p.supervisor                                          AS supervisor_personid,
    p.department,
    l.labortype                                           AS custom_labor_type
FROM :catalog.:silver_schema.labor l
LEFT JOIN :catalog.:silver_schema.person p
    ON p.personid = l.personid
LEFT JOIN default_rate dr
    ON dr.laborcode = l.laborcode AND dr.orgid = l.orgid
   AND dr.craft = l.craft AND dr.skilllevel = l.skilllevel
   AND dr.rn = 1
LEFT JOIN current_quals cq
    ON cq.personid = l.personid;


-- -----------------------------------------------------------------------------
-- v_crew_capacity
-- Per-(crew, week, craft) available hours. Aggregates WORKPERIOD across all
-- current crew members (AMCREWLABOR), broken down by their craft, net of
-- MODAVAIL non-work (absence) rows. Scheduled hours are DERIVED from
-- WORKPERIOD.SHIFTSTART/SHIFTEND (there is no WORKPERIOD.HOURS column). The
-- capacity side of the workload-vs-capacity composition with pm-planning.
-- The output `crewid` column carries the AMCREW identifier value.
--
-- TEMPLATE — PENDING COLUMN VERIFICATION. The absence CTE references the
-- MODAVAIL ("Modify Availability") object, whose exact column names are NOT
-- publicly documented. The resource key, start datetime, reason-code column,
-- affected-hours column, and the non-work reason-code set used to isolate
-- absences (RSNCODE synonym domain — e.g. VAC/SICK/PERSONAL) below are
-- PLACEHOLDERS — confirm each against MAXATTRIBUTE (object MODAVAIL) in this
-- deployment before registering. See gotchas.md §9.
--
-- CONTRACTOR CAVEAT: capacity is driven by WORKPERIOD via the member's default
-- CALNUM/SHIFTNUM. Contractor labor often has NULL CALNUM/SHIFTNUM (gotcha 1) —
-- such members have no derivable WORKPERIOD capacity. We LEFT JOIN WORKPERIOD so
-- those members are NOT silently dropped from the crew/craft grain; they surface
-- with NULL/zero scheduled hours rather than vanishing. Supply an explicit
-- contractor capacity convention if you need to count their hours.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_crew_capacity
COMMENT 'Per-(crew, week, craft) available work hours. Sums WORKPERIOD across current crew members, net of MODAVAIL non-work (absence) rows. TEMPLATE: MODAVAIL columns are unverified — confirm against MAXATTRIBUTE. Composes with v_pm_workload_by_craft.'
AS
WITH current_members AS (
    SELECT cl.amcrew, cl.orgid, cl.laborcode
    FROM :catalog.:silver_schema.amcrewlabor cl
    WHERE cl.effectivedate <= current_date()
      AND (cl.enddate IS NULL OR cl.enddate > current_date())
),
member_periods AS (
    SELECT
        cm.amcrew,
        cm.orgid,
        cm.laborcode,
        l.craft,
        date_trunc('WEEK', wp.workdate)                   AS week_starting,
        -- Scheduled hours are DERIVED from SHIFTSTART/SHIFTEND (no WORKPERIOD.HOURS
        -- column). Time difference in seconds / 3600 = hours per working day.
        -- NULL for members with no WORKPERIOD match (e.g. contractors with NULL
        -- CALNUM/SHIFTNUM) — kept, not dropped.
        SUM((unix_timestamp(wp.shiftend) - unix_timestamp(wp.shiftstart)) / 3600.0)
                                                           AS scheduled_hours
    FROM current_members cm
    JOIN :catalog.:silver_schema.labor l
        ON l.laborcode = cm.laborcode AND l.orgid = cm.orgid
    LEFT JOIN :catalog.:silver_schema.workperiod wp
        ON wp.calnum = l.calnum AND wp.shiftnum = l.shiftnum
    GROUP BY cm.amcrew, cm.orgid, cm.laborcode, l.craft, date_trunc('WEEK', wp.workdate)
),
-- member_absences: TEMPLATE. Replace `ma.*` placeholder columns with the
-- verified MODAVAIL physical names, and replace the non-work RSNCODE set with
-- this deployment's absence reason codes (resolve via SYNONYMDOMAIN if renamed).
member_absences AS (
    SELECT
        cm.amcrew,
        cm.orgid,
        l.craft,
        date_trunc('WEEK', ma.startdatetime)              AS week_starting,
        SUM(ma.hours)                                      AS absence_hours
    FROM current_members cm
    JOIN :catalog.:silver_schema.labor l
        ON l.laborcode = cm.laborcode AND l.orgid = cm.orgid
    JOIN :catalog.:silver_schema.modavail ma
        ON ma.laborcode = cm.laborcode AND ma.orgid = cm.orgid
       -- non-work rows only = planned absences (confirm reason codes / column)
       AND ma.rsncode IN ('VAC', 'SICK', 'PERSONAL')
    GROUP BY cm.amcrew, cm.orgid, l.craft, date_trunc('WEEK', ma.startdatetime)
)
SELECT
    p.amcrew                                               AS crewid,
    p.orgid,
    p.craft,
    p.week_starting,
    SUM(p.scheduled_hours)                                 AS scheduled_hours,
    -- Absence is summed ACROSS crew members inside member_absences (it groups by
    -- crew/craft/week, NOT by laborcode) — so when several members of the same
    -- craft are absent in one week their hours add up. That yields exactly one
    -- absence row per (crew, craft, week); MAX here just reads that single
    -- pre-summed value (it is the grain key, so MAX/MIN/ANY_VALUE are equal).
    -- Do NOT push the join to per-member grain with an outer SUM — that would
    -- multiply the absence by the number of members and overcount.
    COALESCE(MAX(a.absence_hours), 0)                      AS absence_hours,
    COALESCE(SUM(p.scheduled_hours), 0) - COALESCE(MAX(a.absence_hours), 0) AS available_hours
FROM member_periods p
LEFT JOIN member_absences a
    ON a.amcrew = p.amcrew
   AND a.orgid  = p.orgid
   AND a.craft  = p.craft
   AND a.week_starting = p.week_starting
GROUP BY p.amcrew, p.orgid, p.craft, p.week_starting;


-- -----------------------------------------------------------------------------
-- v_qualification_expiry
-- Active qualifications with days-to-expiry. One row per (person, qualification)
-- with non-null EXPIRYDATE.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_qualification_expiry
COMMENT 'Active person-qualification holdings with days-to-expiry. One row per (personid, qualificationid). Use for compliance / renewal reporting.'
AS
SELECT
    qp.personid,
    COALESCE(p.displayname, qp.personid)                   AS person_name,
    qp.qualificationid,
    q.description                                          AS qualification_description,
    q.craft                                                AS qualification_craft,
    qp.effectivedate,
    qp.expirydate,
    datediff(DAY, current_date(), qp.expirydate)           AS days_to_expiry,
    CASE
        WHEN qp.expirydate IS NULL                       THEN 'NO_EXPIRY'
        WHEN qp.expirydate < current_date()              THEN 'EXPIRED'
        WHEN qp.expirydate <= current_date() + INTERVAL 30 DAYS THEN 'DUE_30D'
        WHEN qp.expirydate <= current_date() + INTERVAL 90 DAYS THEN 'DUE_90D'
        ELSE 'CURRENT'
    END                                                    AS expiry_bucket
FROM :catalog.:silver_schema.qualperson qp
JOIN :catalog.:silver_schema.qualification q
    ON q.qualificationid = qp.qualificationid
LEFT JOIN :catalog.:silver_schema.person p
    ON p.personid = qp.personid
WHERE qp.status = 'ACTIVE'
  AND q.status = 'ACTIVE';
