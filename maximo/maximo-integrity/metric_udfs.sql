-- ─────────────────────────────────────────────────────────────────────────────
-- Trusted Asset functions for Genie.
-- These are UC SQL functions: register them once (CREATE FUNCTION) so Genie
-- Spaces can call them as certified, governed metrics rather than regenerating
-- ad-hoc SQL. Substitute your catalog.schema before running.
-- See: https://docs.databricks.com/aws/en/genie/trusted-assets
-- ─────────────────────────────────────────────────────────────────────────────

-- =============================================================================
-- Maximo Integrity — UC SQL Function (Metric UDF) DDL
-- =============================================================================
-- Substitute :catalog.:silver_schema and :catalog.:metrics_schema.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- corrosion_rate — LONG-TERM (trend) rate via regression on UT thickness
-- -----------------------------------------------------------------------------
-- Returns a LONG-TERM-style corrosion rate (units-per-year) for an asset+meter
-- over the window, as the regression slope of thinning over time.
-- NULL if fewer than 2 readings. Units depend on the meter — check ASSETMETER.UOM.
--
-- METHODOLOGY CAVEAT (API 510/570; see gotcha 1): engineers use TWO rates and
-- pick the one giving the SHORTER remaining life:
--   * LONG-TERM (this UDF) = trend over full history.
--   * SHORT-TERM = (t_previous - t_actual) / years over the TWO MOST RECENT
--     readings — catches a recently-accelerated mechanism that a regression slope
--     masks. Use corrosion_rate_short_term() for that, and remaining_life() to
--     combine them. Do NOT quote remaining life from this trend rate alone.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.corrosion_rate(
    assetnum_param STRING,
    siteid_param STRING,
    metername_param STRING,
    window_days INT COMMENT 'Look-back window for the regression (recommend >= 730 days for reliable rates)'
)
RETURNS DOUBLE
COMMENT 'Trusted metric: LONG-TERM corrosion rate (units per year) via regression of METERREADING on time. NULL if <2 readings. For recent acceleration use corrosion_rate_short_term; for remaining life use remaining_life (picks the more conservative rate).'
RETURN (
    WITH readings AS (
        SELECT
            CAST(readingdate AS DOUBLE) / 86400.0  AS day_of_year_double,
            reading
        FROM :catalog.:silver_schema.meterreading
        WHERE assetnum = assetnum_param
          AND siteid = siteid_param
          AND metername = metername_param
          AND readingdate >= current_date() - make_interval(0, 0, 0, window_days, 0, 0, 0)
          AND reading IS NOT NULL
    ),
    stats AS (
        SELECT
            COUNT(*)                                          AS n,
            AVG(day_of_year_double)                           AS x_bar,
            AVG(reading)                                      AS y_bar,
            AVG(day_of_year_double * reading)                 AS xy_bar,
            AVG(day_of_year_double * day_of_year_double)      AS xx_bar
        FROM readings
    )
    SELECT
        -- negate the slope so a THINNING trend yields a POSITIVE corrosion rate
        CASE WHEN n >= 2 AND (xx_bar - x_bar * x_bar) <> 0
             THEN -1.0 * ((xy_bar - x_bar * y_bar) / (xx_bar - x_bar * x_bar)) * 365.0
             ELSE NULL
        END
    FROM stats
);


-- -----------------------------------------------------------------------------
-- corrosion_rate_short_term — ST rate from the two most recent readings
-- -----------------------------------------------------------------------------
-- API 510/570 SHORT-TERM rate = (t_previous - t_actual) / years between them,
-- using the TWO MOST RECENT readings. Positive = thinning. NULL if <2 readings.
-- Catches a recently-accelerated damage mechanism a regression slope would mask.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.corrosion_rate_short_term(
    assetnum_param STRING,
    siteid_param STRING,
    metername_param STRING
)
RETURNS DOUBLE
COMMENT 'Trusted metric: SHORT-TERM corrosion rate (units per year) from the two most recent thickness readings (API 510/570). Positive = thinning. NULL if <2 readings.'
RETURN (
    WITH recent AS (
        SELECT reading, readingdate,
               ROW_NUMBER() OVER (ORDER BY readingdate DESC) AS rn
        FROM :catalog.:silver_schema.meterreading
        WHERE assetnum = assetnum_param
          AND siteid = siteid_param
          AND metername = metername_param
          AND reading IS NOT NULL
    ),
    pair AS (
        SELECT
            MAX(CASE WHEN rn = 1 THEN reading END)     AS t_actual,
            MAX(CASE WHEN rn = 1 THEN readingdate END) AS t_actual_date,
            MAX(CASE WHEN rn = 2 THEN reading END)     AS t_previous,
            MAX(CASE WHEN rn = 2 THEN readingdate END) AS t_previous_date
        FROM recent WHERE rn <= 2
    )
    SELECT CASE
        WHEN t_previous IS NOT NULL AND datediff(DAY, t_previous_date, t_actual_date) > 0
            THEN (t_previous - t_actual) / (datediff(DAY, t_previous_date, t_actual_date) / 365.0)
        ELSE NULL
    END
    FROM pair
);


-- -----------------------------------------------------------------------------
-- remaining_life — conservative remaining life (API 510/570)
-- -----------------------------------------------------------------------------
-- remaining_life (years) = (t_actual - t_required) / corrosion_rate, where the
-- corrosion_rate is the MORE CONSERVATIVE (larger) of LT and ST — yielding the
-- SHORTER (worse-case) remaining life. t_required (t-min) is a per-component
-- INPUT supplied by the caller; NULL t_required -> NULL result (do not guess).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.remaining_life(
    assetnum_param STRING,
    siteid_param STRING,
    metername_param STRING,
    t_required DOUBLE COMMENT 'Minimum safe thickness (t-min) for the component — a per-component design INPUT, not derived from readings',
    window_days INT COMMENT 'Look-back window for the long-term rate (recommend >= 730 days)'
)
RETURNS DOUBLE
COMMENT 'Trusted metric: remaining life (years) = (t_actual - t_required) / governing corrosion rate, using the more conservative of long-term and short-term rates. NULL if t_required unknown or no positive thinning rate.'
RETURN (
    WITH t AS (
        SELECT reading AS t_actual
        FROM :catalog.:silver_schema.meterreading
        WHERE assetnum = assetnum_param AND siteid = siteid_param
          AND metername = metername_param AND reading IS NOT NULL
        ORDER BY readingdate DESC LIMIT 1
    ),
    r AS (
        SELECT GREATEST(
            COALESCE(:catalog.:metrics_schema.corrosion_rate(assetnum_param, siteid_param, metername_param, window_days), 0),
            COALESCE(:catalog.:metrics_schema.corrosion_rate_short_term(assetnum_param, siteid_param, metername_param), 0)
        ) AS governing_rate
    )
    SELECT CASE
        WHEN t_required IS NOT NULL AND r.governing_rate > 0
            THEN (t.t_actual - t_required) / r.governing_rate
        ELSE NULL
    END
    FROM t CROSS JOIN r
);


-- -----------------------------------------------------------------------------
-- next_inspection_due — flat PM NEXTDATE (fallback only)
-- -----------------------------------------------------------------------------
-- Returns the next NEXTDATE from PM records flagged as regulatory inspections.
-- The "inspection" filter is parameterized via the worktype_filter input — pass
-- a comma-separated list of WORKTYPE values that count as inspections at this customer.
--
-- CAVEAT (gotcha 3): a FLAT PM cadence is NOT the code-correct due date. Per API
-- 510/570 the due date is min(statutory_max_interval, 0.5 * remaining_life) from
-- the last inspection, which tightens as the asset ages. Use this UDF only when
-- you have no thickness data; otherwise prefer next_inspection_due_code below.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.next_inspection_due(
    assetnum_param STRING,
    siteid_param STRING,
    worktype_filter STRING COMMENT 'Comma-separated WORKTYPE values that count as inspections (e.g. "REG,API510,API570")'
)
RETURNS TIMESTAMP
COMMENT 'Trusted metric: flat PM-driven next inspection date (MIN NEXTDATE across active inspection PMs). FALLBACK only — for code-correct cadence use next_inspection_due_code (min of statutory max and half remaining life).'
RETURN (
    SELECT MIN(pm.nextdate)
    FROM :catalog.:silver_schema.pm pm
    JOIN :catalog.:silver_schema.jobplan jp
        ON jp.jpnum = pm.jpnum
    WHERE pm.assetnum = assetnum_param
      AND pm.siteid = siteid_param
      AND pm.__END_AT IS NULL
      AND array_contains(split(worktype_filter, ','), jp.worktype)
);


-- -----------------------------------------------------------------------------
-- next_inspection_due_code — condition-based, code-correct cadence (API 510/570)
-- -----------------------------------------------------------------------------
-- next due = last_inspection_date + min(statutory_max_years, 0.5 * remaining_life)
-- The half-life term tightens the cadence as remaining life shrinks; the
-- statutory maximum is the absolute ceiling (e.g. API 570 Class 1 = 5 yr;
-- Class 2/3 / API 510 = 10 yr). Pass the governing statutory_max_years and the
-- remaining_life (e.g. from the remaining_life UDF). NULL last_inspection -> NULL.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.next_inspection_due_code(
    last_inspection_date TIMESTAMP,
    statutory_max_years DOUBLE COMMENT 'Code maximum interval in years for the regime/class (e.g. 5 for API 570 Class 1, 10 for Class 2/3 or API 510)',
    remaining_life_years DOUBLE COMMENT 'Calculated remaining life in years (e.g. from remaining_life UDF)'
)
RETURNS TIMESTAMP
COMMENT 'Trusted metric: code-correct next inspection date = last_inspection + min(statutory_max, 0.5 * remaining_life) per API 510/570 (half-life principle, capped by statutory max).'
RETURN (
    SELECT CASE
        WHEN last_inspection_date IS NULL THEN NULL
        ELSE last_inspection_date + make_interval(
            0, 0, 0,
            CAST(365.0 * LEAST(
                statutory_max_years,
                COALESCE(0.5 * remaining_life_years, statutory_max_years)
            ) AS INT),
            0, 0, 0)
    END
);


-- -----------------------------------------------------------------------------
-- inspection_on_time_compliance — regulatory definition (binary, statutory deadline)
-- -----------------------------------------------------------------------------
-- Per-asset, was the asset inspected by its NEXTDATE? Aggregate to a site / class.
-- This is DIFFERENT from SMRP PM compliance (which uses tolerance windows).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.inspection_on_time_compliance(
    site_id STRING COMMENT 'SITEID. NULL for all sites.',
    worktype_filter STRING COMMENT 'Comma-separated WORKTYPE values for inspections',
    window_start TIMESTAMP,
    window_end TIMESTAMP
)
RETURNS DOUBLE
COMMENT 'Trusted metric: % of regulatory inspections completed on or before their statutory deadline. Stricter than SMRP PM compliance.'
RETURN (
    WITH inspection_pms AS (
        SELECT pm.pmnum, pm.siteid, pm.assetnum, pm.nextdate
        FROM :catalog.:silver_schema.pm pm
        JOIN :catalog.:silver_schema.jobplan jp ON jp.jpnum = pm.jpnum
        WHERE pm.__END_AT IS NULL
          AND (site_id IS NULL OR pm.siteid = site_id)
          AND array_contains(split(worktype_filter, ','), jp.worktype)
          AND pm.nextdate BETWEEN window_start AND window_end
    ),
    on_time AS (
        SELECT
            ip.pmnum, ip.siteid,
            EXISTS (
                SELECT 1
                FROM :catalog.:silver_schema.workorder w
                WHERE w.pmnum = ip.pmnum
                  AND w.siteid = ip.siteid
                  AND w.status IN ('COMP', 'CLOSE')
                  AND w.actfinish IS NOT NULL
                  AND w.actfinish <= ip.nextdate
            ) AS was_on_time
        FROM inspection_pms ip
    )
    SELECT
        CASE WHEN COUNT(*) > 0
             THEN 100.0 * SUM(CASE WHEN was_on_time THEN 1 ELSE 0 END) / COUNT(*)
             ELSE NULL
        END
    FROM on_time
);


-- -----------------------------------------------------------------------------
-- rbi_score — Risk-Based Inspection score (default formulation)
-- -----------------------------------------------------------------------------
-- Defensible default: criticality × normalized-time-since-last-inspection × corrosion-rate-severity
-- Customer-specific variants should be registered as separate UDFs.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.rbi_score(
    assetnum_param STRING,
    siteid_param STRING
)
RETURNS DOUBLE
COMMENT 'Trusted metric: default Risk-Based Inspection score (criticality × time-since-inspection × corrosion-severity). Customer-specific RBI methodologies should be registered alongside as separate UDFs.'
RETURN (
    WITH base AS (
        SELECT
            a.assetnum, a.siteid,
            COALESCE(a.criticality, 5) AS criticality,
            (
                SELECT datediff(DAY, MAX(w.actfinish), current_date()) / 365.0
                FROM :catalog.:silver_schema.workorder w
                JOIN :catalog.:silver_schema.jobplan jp ON jp.jpnum = w.jpnum
                WHERE w.assetnum = a.assetnum AND w.siteid = a.siteid
                  AND jp.worktype IN ('REG', 'INSP', 'API510', 'API570')
                  AND w.status IN ('COMP', 'CLOSE')
            ) AS years_since_inspection,
            (
                SELECT MAX(ABS(:catalog.:metrics_schema.corrosion_rate(
                    a.assetnum, a.siteid, am.metername, 1095
                )))
                FROM :catalog.:silver_schema.assetmeter am
                WHERE am.assetnum = a.assetnum AND am.siteid = a.siteid AND am.__END_AT IS NULL
                  AND am.metername LIKE '%THICKNESS%'
            ) AS max_corrosion_rate
        FROM :catalog.:silver_schema.asset a
        WHERE a.assetnum = assetnum_param AND a.siteid = siteid_param AND a.__END_AT IS NULL
    )
    SELECT
        criticality
        * COALESCE(years_since_inspection, 1)
        * COALESCE(max_corrosion_rate, 0.1)
    FROM base
);


-- =============================================================================
-- Grants (uncomment + substitute principal)
-- =============================================================================
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.corrosion_rate              TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.corrosion_rate_short_term   TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.remaining_life              TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.next_inspection_due         TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.next_inspection_due_code    TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.inspection_on_time_compliance TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.rbi_score                   TO `:principal`;
