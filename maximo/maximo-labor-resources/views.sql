-- =============================================================================
-- Maximo Labor & Resources — Gold Views
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} and {{catalog}}.{{gold_schema}}.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_labor_position
-- Per-labor enriched view: person link, craft, default rate, current
-- qualification count, contractor flag, default calendar/shift.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_labor_position
COMMENT 'Per-labor enriched position. One row per LABOR. Joins person, default craft rate, and current qualification count. Use for any labor-master report.'
AS
WITH default_rate AS (
    SELECT
        laborcode, orgid, craft, skilllevel,
        ROW_NUMBER() OVER (PARTITION BY laborcode, orgid ORDER BY craft) AS rn,
        rate, currencycode
    FROM {{catalog}}.{{silver_schema}}.laborcraftrate
),
current_quals AS (
    SELECT personid, COUNT(*) AS current_qualification_count
    FROM {{catalog}}.{{silver_schema}}.qualperson
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
    l.calnum                                               AS default_calendar,
    l.shiftnum                                             AS default_shift,
    l.persongroup                                          AS default_persongroup,
    l.vendor                                               AS contractor_vendor,
    CASE
        WHEN l.vendor IS NOT NULL THEN 'CONTRACTOR'
        WHEN l.outsidelabor = 1 THEN 'CONTRACTOR'
        ELSE 'EMPLOYEE'
    END                                                    AS labor_type,
    COALESCE(cq.current_qualification_count, 0)           AS current_qualifications,
    p.supervisor                                          AS supervisor_personid,
    p.department,
    l.labortype                                           AS custom_labor_type
FROM {{catalog}}.{{silver_schema}}.labor l
LEFT JOIN {{catalog}}.{{silver_schema}}.person p
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
-- current crew members, broken down by their craft. The capacity side of the
-- workload-vs-capacity composition with pm-planning.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_crew_capacity
COMMENT 'Per-(crew, week, craft) available work hours. Sums WORKPERIOD across current crew members. Composes with v_pm_workload_by_craft for workload-vs-capacity analytics.'
AS
WITH current_members AS (
    SELECT cl.crewid, cl.orgid, cl.laborcode
    FROM {{catalog}}.{{silver_schema}}.crewlabor cl
    WHERE cl.startdate <= current_date()
      AND (cl.enddate IS NULL OR cl.enddate > current_date())
),
member_periods AS (
    SELECT
        cm.crewid,
        cm.orgid,
        cm.laborcode,
        l.craft,
        date_trunc('WEEK', wp.startdate)                  AS week_starting,
        SUM(wp.hours)                                      AS scheduled_hours
    FROM current_members cm
    JOIN {{catalog}}.{{silver_schema}}.labor l
        ON l.laborcode = cm.laborcode AND l.orgid = cm.orgid
    JOIN {{catalog}}.{{silver_schema}}.workperiod wp
        ON wp.calnum = l.calnum AND wp.shiftnum = l.shiftnum
       AND wp.periodtype = 'WORK'
    GROUP BY cm.crewid, cm.orgid, cm.laborcode, l.craft, date_trunc('WEEK', wp.startdate)
),
member_absences AS (
    SELECT
        cm.crewid,
        cm.orgid,
        l.craft,
        date_trunc('WEEK', ar.startdatetime)              AS week_starting,
        SUM(ar.hours)                                      AS absence_hours
    FROM current_members cm
    JOIN {{catalog}}.{{silver_schema}}.labor l
        ON l.laborcode = cm.laborcode AND l.orgid = cm.orgid
    JOIN {{catalog}}.{{silver_schema}}.availrefly ar
        ON ar.laborcode = cm.laborcode AND ar.orgid = cm.orgid
    GROUP BY cm.crewid, cm.orgid, l.craft, date_trunc('WEEK', ar.startdatetime)
)
SELECT
    p.crewid,
    p.orgid,
    p.craft,
    p.week_starting,
    SUM(p.scheduled_hours)                                 AS scheduled_hours,
    COALESCE(MAX(a.absence_hours), 0)                      AS absence_hours,
    SUM(p.scheduled_hours) - COALESCE(MAX(a.absence_hours), 0) AS available_hours
FROM member_periods p
LEFT JOIN member_absences a
    ON a.crewid = p.crewid
   AND a.orgid  = p.orgid
   AND a.craft  = p.craft
   AND a.week_starting = p.week_starting
GROUP BY p.crewid, p.orgid, p.craft, p.week_starting;


-- -----------------------------------------------------------------------------
-- v_qualification_expiry
-- Active qualifications with days-to-expiry. One row per (person, qualification)
-- with non-null EXPIRYDATE.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_qualification_expiry
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
FROM {{catalog}}.{{silver_schema}}.qualperson qp
JOIN {{catalog}}.{{silver_schema}}.qualification q
    ON q.qualificationid = qp.qualificationid
LEFT JOIN {{catalog}}.{{silver_schema}}.person p
    ON p.personid = qp.personid
WHERE qp.status = 'ACTIVE'
  AND q.status = 'ACTIVE';
