-- =============================================================================
-- Maximo Labor & Resources — UC SQL Function (Trusted UDF) DDL
-- =============================================================================
-- Substitute :catalog.:silver_schema and :catalog.:metrics_schema.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS :catalog.:metrics_schema
COMMENT 'Trusted-asset SQL functions for Maximo labor + capacity metrics';


-- -----------------------------------------------------------------------------
-- crew_capacity_hours — total available craft-hours for a crew × week
-- -----------------------------------------------------------------------------
-- Sums WORKPERIOD scheduled hours across current crew members minus planned
-- absences (MODAVAIL non-work rows) overlapping the week. Returns 0 if
-- WORKPERIOD coverage is missing for the week — caller should probe coverage
-- separately.
--
-- TEMPLATE — PENDING COLUMN VERIFICATION. The `absent` CTE references MODAVAIL
-- ("Modify Availability"), whose exact column names are NOT publicly documented.
-- The resource key, start datetime, reason-code column (`rsncode`) and affected-
-- hours column (`hours`) below are PLACEHOLDERS, and the non-work reason-code set
-- ('VAC','SICK','PERSONAL') that isolates absences (RSNCODE synonym domain) must
-- be confirmed against MAXATTRIBUTE (object MODAVAIL) and SYNONYMDOMAIN in this
-- deployment before registering as a Trusted UDF. See gotchas.md §9.
--
-- CONTRACTOR CAVEAT: scheduled capacity is derived from each member's default
-- CALNUM/SHIFTNUM via WORKPERIOD. Contractor labor frequently has NULL
-- CALNUM/SHIFTNUM (gotcha 1), so it contributes ZERO WORKPERIOD hours here. This
-- function therefore measures CALENDAR-DRIVEN capacity only; contractor hours
-- are not represented unless the deployment populates their calendars. The
-- `scheduled` join intentionally does not gate out those members (they simply
-- contribute no rows), but be aware the returned number excludes calendar-less
-- contractors rather than erroring.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.crew_capacity_hours(
    crew_id STRING,
    org_id STRING,
    week_start TIMESTAMP,
    craft_filter STRING COMMENT 'Craft code. NULL for total across all crafts.'
)
RETURNS DOUBLE
COMMENT 'Trusted metric (TEMPLATE pending MODAVAIL column verification): calendar-driven available crew-hours in a week, net of planned absences. Aggregates current AMCREWLABOR x WORKPERIOD (hours derived from SHIFTSTART/SHIFTEND) minus MODAVAIL non-work overlap. Excludes calendar-less contractor labor.'
RETURN (
    WITH current_members AS (
        SELECT cl.laborcode, cl.orgid
        FROM :catalog.:silver_schema.amcrewlabor cl
        WHERE cl.amcrew = crew_id AND cl.orgid = org_id
          AND cl.effectivedate <= week_start
          AND (cl.enddate IS NULL OR cl.enddate > week_start)
    ),
    scheduled AS (
        -- Scheduled hours DERIVED from SHIFTSTART/SHIFTEND (no WORKPERIOD.HOURS).
        SELECT SUM((unix_timestamp(wp.shiftend) - unix_timestamp(wp.shiftstart)) / 3600.0) AS hours
        FROM current_members cm
        JOIN :catalog.:silver_schema.labor l USING (laborcode, orgid)
        JOIN :catalog.:silver_schema.workperiod wp
            ON wp.calnum = l.calnum AND wp.shiftnum = l.shiftnum
           AND wp.workdate >= week_start
           AND wp.workdate <  week_start + INTERVAL 7 DAYS
        WHERE craft_filter IS NULL OR l.craft = craft_filter
    ),
    -- absent: TEMPLATE — replace `ma.*` placeholders and the RSNCODE set with
    -- verified MODAVAIL columns / this deployment's non-work reason codes.
    absent AS (
        SELECT SUM(ma.hours) AS hours
        FROM current_members cm
        JOIN :catalog.:silver_schema.labor l USING (laborcode, orgid)
        JOIN :catalog.:silver_schema.modavail ma
            ON ma.laborcode = cm.laborcode AND ma.orgid = cm.orgid
           AND ma.rsncode IN ('VAC', 'SICK', 'PERSONAL')   -- non-work rows = absences
           AND ma.startdatetime >= week_start
           AND ma.startdatetime <  week_start + INTERVAL 7 DAYS
        WHERE craft_filter IS NULL OR l.craft = craft_filter
    )
    SELECT COALESCE(s.hours, 0) - COALESCE(a.hours, 0)
    FROM scheduled s, absent a
);


-- -----------------------------------------------------------------------------
-- qualified_labor_count — distinct labor records with a current cert
-- -----------------------------------------------------------------------------
-- For "how many people are qualified for X" — filters out expired certs.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.qualified_labor_count(
    qualification_id STRING,
    org_id STRING COMMENT 'ORGID. NULL for all orgs.'
)
RETURNS BIGINT
COMMENT 'Trusted metric: distinct ACTIVE labor records with a current (non-expired) qualification of the given type.'
RETURN (
    SELECT COUNT(DISTINCT l.laborcode)
    FROM :catalog.:silver_schema.qualperson qp
    JOIN :catalog.:silver_schema.labor l
        ON l.personid = qp.personid AND l.status = 'ACTIVE'
    WHERE qp.qualificationid = qualification_id
      AND qp.status = 'ACTIVE'
      AND (qp.expirydate IS NULL OR qp.expirydate > current_date())
      AND (org_id IS NULL OR l.orgid = org_id)
);


-- -----------------------------------------------------------------------------
-- labor_utilization_pct — booked LABTRANS hours / scheduled WORKPERIOD hours
-- -----------------------------------------------------------------------------
-- "How much of a person's scheduled time was booked to WOs in a window."
-- 100% = fully booked. >100% = booked overtime beyond schedule.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.labor_utilization_pct(
    labor_code STRING,
    org_id STRING,
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: % of scheduled WORKPERIOD hours that were booked as LABTRANS in the window. NULL if no scheduled hours.'
RETURN (
    WITH scheduled AS (
        -- Scheduled hours DERIVED from SHIFTSTART/SHIFTEND (no WORKPERIOD.HOURS).
        SELECT SUM((unix_timestamp(wp.shiftend) - unix_timestamp(wp.shiftstart)) / 3600.0) AS hours
        FROM :catalog.:silver_schema.labor l
        JOIN :catalog.:silver_schema.workperiod wp
            ON wp.calnum = l.calnum AND wp.shiftnum = l.shiftnum
        WHERE l.laborcode = labor_code AND l.orgid = org_id
          AND wp.workdate BETWEEN window_start AND window_end
    ),
    booked AS (
        SELECT SUM(lt.regularhrs + COALESCE(lt.premiumpayhours, 0)) AS hours
        FROM :catalog.:silver_schema.labtrans lt
        WHERE lt.laborcode = labor_code
          AND lt.transtype = 'WORK'
          AND lt.startdate BETWEEN window_start AND window_end
    )
    SELECT
        CASE WHEN s.hours > 0
             THEN 100.0 * COALESCE(b.hours, 0) / s.hours
             ELSE NULL
        END
    FROM scheduled s, booked b
);


-- -----------------------------------------------------------------------------
-- expired_qualifications_count — count of expired or expiring qualifications
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.expired_qualifications_count(
    org_id STRING COMMENT 'ORGID. NULL for all orgs.',
    within_days INT COMMENT 'Look ahead (e.g. 30 for "expiring or expired in next 30 days"). Pass 0 for only-already-expired.'
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of active person-qualification pairs that are expired now or within N days.'
RETURN (
    SELECT COUNT(*)
    FROM :catalog.:silver_schema.qualperson qp
    JOIN :catalog.:silver_schema.qualification q
        ON q.qualificationid = qp.qualificationid AND q.status = 'ACTIVE'
    JOIN :catalog.:silver_schema.labor l
        ON l.personid = qp.personid AND l.status = 'ACTIVE'
    WHERE qp.status = 'ACTIVE'
      AND qp.expirydate IS NOT NULL
      AND qp.expirydate <= current_date() + make_interval(0, 0, 0, within_days, 0, 0, 0)
      AND (org_id IS NULL OR l.orgid = org_id)
);


-- -----------------------------------------------------------------------------
-- vacation_impact_hours — total scheduled absence hours for a labor in window
-- -----------------------------------------------------------------------------
-- TEMPLATE — PENDING COLUMN VERIFICATION. Reads MODAVAIL ("Modify Availability")
-- non-work rows. MODAVAIL's exact columns are NOT publicly documented: the
-- resource key, start datetime, reason-code column (`rsncode`) and affected-hours
-- column (`hours`) below are PLACEHOLDERS, and the non-work reason-code set
-- ('VAC','SICK','PERSONAL') must be confirmed against MAXATTRIBUTE (object
-- MODAVAIL) and SYNONYMDOMAIN before registering. MODAVAIL holds both work and
-- non-work rows — the RSNCODE filter is what isolates planned absences. See
-- gotchas.md §9.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.vacation_impact_hours(
    labor_code STRING,
    org_id STRING,
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric (TEMPLATE pending MODAVAIL column verification): total scheduled absence hours (MODAVAIL non-work rows) for a labor record in a window.'
RETURN (
    SELECT COALESCE(SUM(ma.hours), 0)
    FROM :catalog.:silver_schema.modavail ma
    WHERE ma.laborcode = labor_code AND ma.orgid = org_id
      AND ma.rsncode IN ('VAC', 'SICK', 'PERSONAL')   -- non-work rows = absences
      AND ma.startdatetime BETWEEN window_start AND window_end
);


-- =============================================================================
-- Grants (uncomment + substitute principal)
-- =============================================================================
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.crew_capacity_hours         TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.qualified_labor_count       TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.labor_utilization_pct       TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.expired_qualifications_count TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.vacation_impact_hours       TO `:principal`;
