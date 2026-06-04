-- =============================================================================
-- Maximo HSE — UC SQL Function (Metric UDF) DDL
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} and {{catalog}}.{{metrics_schema}}.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- trir — Total Recordable Incident Rate
-- -----------------------------------------------------------------------------
-- OSHA formula: (recordable incidents * 200,000) / hours_worked
-- Hours-worked must be sourced from HR; this UDF takes it as a parameter.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.trir(
    site_id STRING COMMENT 'SITEID. NULL for all sites.',
    recordable_categories STRING COMMENT 'Comma-separated INCIDENTCATEGORY values that count as recordable (e.g. "RECORDABLE,LOST_TIME")',
    hours_worked DOUBLE COMMENT 'Total workforce hours worked in the period — must be sourced from HR system',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: OSHA TRIR = (recordable incidents * 200000) / hours-worked. Caller must provide hours-worked from HR/payroll.'
RETURN (
    WITH recordable AS (
        SELECT COUNT(*) AS recordable_count
        FROM {{catalog}}.{{silver_schema}}.incident
        WHERE reportdate BETWEEN window_start AND window_end
          AND (site_id IS NULL OR siteid = site_id)
          AND array_contains(split(recordable_categories, ','), incidentcategory)
    )
    SELECT
        CASE WHEN hours_worked > 0
             THEN (recordable_count * 200000.0) / hours_worked
             ELSE NULL
        END
    FROM recordable
);


-- -----------------------------------------------------------------------------
-- ltir — Lost-Time Incident Rate (subset of recordable)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.ltir(
    site_id STRING COMMENT 'SITEID. NULL for all sites.',
    lost_time_categories STRING COMMENT 'Comma-separated INCIDENTCATEGORY values for lost-time (e.g. "LOST_TIME,DAYS_AWAY")',
    hours_worked DOUBLE,
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: Lost-Time Incident Rate using OSHA-style 200000 constant.'
RETURN (
    WITH lt AS (
        SELECT COUNT(*) AS lt_count
        FROM {{catalog}}.{{silver_schema}}.incident
        WHERE reportdate BETWEEN window_start AND window_end
          AND (site_id IS NULL OR siteid = site_id)
          AND array_contains(split(lost_time_categories, ','), incidentcategory)
    )
    SELECT
        CASE WHEN hours_worked > 0
             THEN (lt_count * 200000.0) / hours_worked
             ELSE NULL
        END
    FROM lt
);


-- -----------------------------------------------------------------------------
-- open_permit_count — currently active permits at a site
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.open_permit_count(
    site_id STRING COMMENT 'SITEID. NULL for all sites.',
    as_of TIMESTAMP COMMENT 'Point in time (typically current_timestamp())'
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of issued/active permits at a site as of a point in time.'
RETURN (
    SELECT COUNT(*)
    FROM {{catalog}}.{{silver_schema}}.plusgpermitwork
    WHERE (site_id IS NULL OR siteid = site_id)
      AND status IN ('ISSUED', 'ACTIVE')
      AND startdate <= as_of
      AND (enddate IS NULL OR enddate >= as_of)
);


-- -----------------------------------------------------------------------------
-- permit_compliance — % of permits closed before expiry
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.permit_compliance(
    site_id STRING,
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: % of permits closed BEFORE their ENDDATE within the window. Lower values indicate compliance gaps.'
RETURN (
    WITH permits AS (
        SELECT permitnum, siteid, enddate,
            EXISTS (
                SELECT 1
                FROM {{catalog}}.{{silver_schema}}.plusgpermitwork p2
                WHERE p2.permitnum = p1.permitnum
                  AND p2.siteid = p1.siteid
                  AND p2.status IN ('CLOSED', 'CANCELLED')
            ) AS was_closed,
            (
                SELECT MAX(s.changedate)
                FROM {{catalog}}.{{silver_schema}}.wostatus s
                WHERE s.wonum = p1.permitnum AND s.siteid = p1.siteid
            ) AS final_change_date
        FROM {{catalog}}.{{silver_schema}}.plusgpermitwork p1
        WHERE p1.enddate BETWEEN window_start AND window_end
          AND (site_id IS NULL OR p1.siteid = site_id)
    )
    SELECT
        CASE WHEN COUNT(*) > 0
             THEN 100.0 * SUM(CASE WHEN was_closed
                                    AND (final_change_date IS NULL OR final_change_date <= enddate)
                                  THEN 1 ELSE 0 END) / COUNT(*)
             ELSE NULL
        END
    FROM permits
);


-- -----------------------------------------------------------------------------
-- incident_count_by_class — for a given category and window
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.incident_count_by_class(
    site_id STRING,
    incident_category STRING,
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of incidents with a given category in a window.'
RETURN (
    SELECT COUNT(*)
    FROM {{catalog}}.{{silver_schema}}.incident
    WHERE reportdate BETWEEN window_start AND window_end
      AND (site_id IS NULL OR siteid = site_id)
      AND incidentcategory = incident_category
);
