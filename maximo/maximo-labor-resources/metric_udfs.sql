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
-- absences (AVAILREFLY) overlapping the week. Returns 0 if WORKPERIOD coverage
-- is missing for the week — caller should probe coverage separately.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.crew_capacity_hours(
    crew_id STRING,
    org_id STRING,
    week_start TIMESTAMP,
    craft_filter STRING COMMENT 'Craft code. NULL for total across all crafts.'
)
RETURNS DOUBLE
COMMENT 'Trusted metric: available crew-hours in a week, net of planned absences. Aggregates current CREWLABOR × WORKPERIOD minus AVAILREFLY overlap.'
RETURN (
    WITH current_members AS (
        SELECT cl.laborcode, cl.orgid
        FROM :catalog.:silver_schema.crewlabor cl
        WHERE cl.crewid = crew_id AND cl.orgid = org_id
          AND cl.startdate <= week_start
          AND (cl.enddate IS NULL OR cl.enddate > week_start)
    ),
    scheduled AS (
        SELECT SUM(wp.hours) AS hours
        FROM current_members cm
        JOIN :catalog.:silver_schema.labor l USING (laborcode, orgid)
        JOIN :catalog.:silver_schema.workperiod wp
            ON wp.calnum = l.calnum AND wp.shiftnum = l.shiftnum
           AND wp.periodtype = 'WORK'
           AND wp.startdate >= week_start
           AND wp.startdate <  week_start + INTERVAL 7 DAYS
        WHERE craft_filter IS NULL OR l.craft = craft_filter
    ),
    absent AS (
        SELECT SUM(ar.hours) AS hours
        FROM current_members cm
        JOIN :catalog.:silver_schema.labor l USING (laborcode, orgid)
        JOIN :catalog.:silver_schema.availrefly ar
            ON ar.laborcode = cm.laborcode AND ar.orgid = cm.orgid
           AND ar.startdatetime >= week_start
           AND ar.startdatetime <  week_start + INTERVAL 7 DAYS
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
        SELECT SUM(wp.hours) AS hours
        FROM :catalog.:silver_schema.labor l
        JOIN :catalog.:silver_schema.workperiod wp
            ON wp.calnum = l.calnum AND wp.shiftnum = l.shiftnum
           AND wp.periodtype = 'WORK'
        WHERE l.laborcode = labor_code AND l.orgid = org_id
          AND wp.startdate BETWEEN window_start AND window_end
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
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.vacation_impact_hours(
    labor_code STRING,
    org_id STRING,
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: total scheduled absence hours (AVAILREFLY) for a labor record in a window.'
RETURN (
    SELECT COALESCE(SUM(ar.hours), 0)
    FROM :catalog.:silver_schema.availrefly ar
    WHERE ar.laborcode = labor_code AND ar.orgid = org_id
      AND ar.startdatetime BETWEEN window_start AND window_end
);


-- =============================================================================
-- Grants (uncomment + substitute principal)
-- =============================================================================
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.crew_capacity_hours         TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.qualified_labor_count       TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.labor_utilization_pct       TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.expired_qualifications_count TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.vacation_impact_hours       TO `:principal`;
