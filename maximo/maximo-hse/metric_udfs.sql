-- ─────────────────────────────────────────────────────────────────────────────
-- Trusted Asset functions for Genie.
-- These are UC SQL functions: register them once (CREATE FUNCTION) so Genie
-- calls them as certified, governed metrics rather than regenerating ad-hoc SQL.
-- See: https://docs.databricks.com/aws/en/genie/trusted-assets
--
-- Bind :catalog, :silver_schema, :metrics_schema (Databricks SQL parameters).
--
-- NOTES on correctness (applied below):
--  * Incidents are TICKET rows (CLASS='INCIDENT'), key TICKETID — there is no
--    standalone INCIDENT table. (gotcha 1)
--  * Recordable/Tier classification is NOT a stock column — categories are
--    PARAMETERIZED, never hardcoded. (gotcha 5)
--  * Permit key is PERMITWORKNUM; permits are NOT work orders and have NO WOSTATUS
--    rows — never join PTW to WOSTATUS. (gotcha 2)
--  * Status holds the synonym VALUE — resolve sets via SYNONYMDOMAIN where the
--    domainid is known (overview F2).
-- ─────────────────────────────────────────────────────────────────────────────


-- -----------------------------------------------------------------------------
-- trir — Total Recordable Incident Rate
-- OSHA formula: (recordable incidents * 200,000) / hours_worked
-- Hours-worked must be sourced from HR; this UDF takes it as a parameter.
-- Recordable categories are parameterized (no stock recordable column exists).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.trir(
    site_id STRING COMMENT 'SITEID. NULL for all sites.',
    recordable_categories STRING COMMENT 'Comma-separated INCIDENTCATEGORY / classification values that count as recordable (deployment-specific; e.g. "RECORDABLE,LOST_TIME")',
    hours_worked DOUBLE COMMENT 'Total workforce hours worked in the period — must be sourced from HR system, not Maximo',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: OSHA TRIR = (recordable incidents * 200000) / hours-worked. Incidents = TICKET CLASS=INCIDENT. Caller provides recordable categories + hours-worked (HR).'
RETURN (
    WITH recordable AS (
        SELECT COUNT(*) AS recordable_count
        FROM :catalog.:silver_schema.ticket
        WHERE class = 'INCIDENT'
          AND reportdate BETWEEN window_start AND window_end
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
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.ltir(
    site_id STRING COMMENT 'SITEID. NULL for all sites.',
    lost_time_categories STRING COMMENT 'Comma-separated lost-time category/classification values (deployment-specific; e.g. "LOST_TIME,DAYS_AWAY")',
    hours_worked DOUBLE,
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: Lost-Time Incident Rate (TICKET CLASS=INCIDENT) using OSHA-style 200000 constant. Categories parameterized.'
RETURN (
    WITH lt AS (
        SELECT COUNT(*) AS lt_count
        FROM :catalog.:silver_schema.ticket
        WHERE class = 'INCIDENT'
          AND reportdate BETWEEN window_start AND window_end
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
-- Permit key is PERMITWORKNUM; status literals likely synonyms (PTW domain).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.open_permit_count(
    site_id STRING COMMENT 'SITEID. NULL for all sites.',
    as_of TIMESTAMP COMMENT 'Point in time (typically current_timestamp())'
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of issued/active permits (plusgpermitwork) at a site as of a point in time.'
RETURN (
    SELECT COUNT(*)
    FROM :catalog.:silver_schema.plusgpermitwork
    WHERE (site_id IS NULL OR siteid = site_id)
      AND status IN ('ISSUED', 'ACTIVE')          -- resolve via PTW status domain when synonyms exist
      AND startdate <= as_of                        -- startdate/enddate UNVERIFIED: confirm in MAXATTRIBUTE
      AND (enddate IS NULL OR enddate >= as_of)
);


-- -----------------------------------------------------------------------------
-- permit_compliance — % of permits closed before expiry
-- CORRECTED: permits are NOT work orders — they have no WOSTATUS rows. Status
-- history comes from the PTW object's OWN status-history mechanism (analogous to
-- TKSTATUS/WOSTATUS). Verify that object's name + columns in MAXATTRIBUTE and
-- substitute below. Placeholder name :ptw_status_hist used for the PTW status
-- history object; its FK to the permit is the permit key (PERMITWORKNUM), NOT wonum.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.permit_compliance(
    site_id STRING,
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: % of permits closed BEFORE their ENDDATE within the window. Uses the PTW objects own status history (NOT WOSTATUS). Verify the PTW status-history object/columns in MAXATTRIBUTE.'
RETURN (
    WITH permits AS (
        SELECT p1.permitworknum, p1.siteid, p1.enddate,
            EXISTS (
                SELECT 1
                FROM :catalog.:silver_schema.plusgpermitwork p2
                WHERE p2.permitworknum = p1.permitworknum
                  AND p2.siteid = p1.siteid
                  AND p2.status IN ('CLOSED', 'CANCELLED')   -- resolve via PTW domain
            ) AS was_closed,
            (
                -- PTW status-history object (NOT wostatus). Confirm object name + FK
                -- column in this deployment; the permit key is PERMITWORKNUM.
                SELECT MAX(s.changedate)
                FROM :catalog.:silver_schema.ptw_status_history s
                WHERE s.permitworknum = p1.permitworknum AND s.siteid = p1.siteid
            ) AS final_change_date
        FROM :catalog.:silver_schema.plusgpermitwork p1
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
-- Incidents = TICKET CLASS=INCIDENT.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.incident_count_by_class(
    site_id STRING,
    incident_category STRING COMMENT 'INCIDENTCATEGORY / classification value (deployment-specific)',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of incidents (TICKET CLASS=INCIDENT) with a given category in a window.'
RETURN (
    SELECT COUNT(*)
    FROM :catalog.:silver_schema.ticket
    WHERE class = 'INCIDENT'
      AND reportdate BETWEEN window_start AND window_end
      AND (site_id IS NULL OR siteid = site_id)
      AND incidentcategory = incident_category
);
