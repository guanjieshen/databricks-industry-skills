-- =============================================================================
-- Maximo Integrity — UC SQL Function (Metric UDF) DDL
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} and {{catalog}}.{{metrics_schema}}.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- corrosion_rate — linear regression on UT thickness readings
-- -----------------------------------------------------------------------------
-- Returns the corrosion rate in (units-per-year) for a given asset+meter+window.
-- NULL if fewer than 2 readings.
-- Units depend on the meter (mils/year, mm/year, etc.) — check ASSETMETER.UOM.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.corrosion_rate(
    assetnum_param STRING,
    siteid_param STRING,
    metername_param STRING,
    window_days INT COMMENT 'Look-back window for the regression (recommend >= 730 days for reliable rates)'
)
RETURNS DOUBLE
COMMENT 'Trusted metric: corrosion rate (units per year) via linear regression of METERREADING on time. NULL if <2 readings.'
RETURN (
    WITH readings AS (
        SELECT
            CAST(readingdate AS DOUBLE) / 86400.0  AS day_of_year_double,
            reading
        FROM {{catalog}}.{{silver_schema}}.meterreading
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
        CASE WHEN n >= 2 AND (xx_bar - x_bar * x_bar) <> 0
             THEN ((xy_bar - x_bar * y_bar) / (xx_bar - x_bar * x_bar)) * 365.0
             ELSE NULL
        END
    FROM stats
);


-- -----------------------------------------------------------------------------
-- next_inspection_due — for a given asset
-- -----------------------------------------------------------------------------
-- Returns the next NEXTDATE from PM records flagged as regulatory inspections.
-- The "inspection" filter is parameterized via the worktype_filter input — pass
-- a comma-separated list of WORKTYPE values that count as inspections at this customer.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.next_inspection_due(
    assetnum_param STRING,
    siteid_param STRING,
    worktype_filter STRING COMMENT 'Comma-separated WORKTYPE values that count as inspections (e.g. "REG,API510,API570")'
)
RETURNS TIMESTAMP
COMMENT 'Trusted metric: next regulatory-inspection due date for an asset (MIN NEXTDATE across active inspection PMs).'
RETURN (
    SELECT MIN(pm.nextdate)
    FROM {{catalog}}.{{silver_schema}}.pm pm
    JOIN {{catalog}}.{{silver_schema}}.jobplan jp
        ON jp.jpnum = pm.jpnum
    WHERE pm.assetnum = assetnum_param
      AND pm.siteid = siteid_param
      AND pm.__END_AT IS NULL
      AND array_contains(split(worktype_filter, ','), jp.worktype)
);


-- -----------------------------------------------------------------------------
-- inspection_on_time_compliance — regulatory definition (binary, statutory deadline)
-- -----------------------------------------------------------------------------
-- Per-asset, was the asset inspected by its NEXTDATE? Aggregate to a site / class.
-- This is DIFFERENT from SMRP PM compliance (which uses tolerance windows).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.inspection_on_time_compliance(
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
        FROM {{catalog}}.{{silver_schema}}.pm pm
        JOIN {{catalog}}.{{silver_schema}}.jobplan jp ON jp.jpnum = pm.jpnum
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
                FROM {{catalog}}.{{silver_schema}}.workorder w
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
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.rbi_score(
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
                FROM {{catalog}}.{{silver_schema}}.workorder w
                JOIN {{catalog}}.{{silver_schema}}.jobplan jp ON jp.jpnum = w.jpnum
                WHERE w.assetnum = a.assetnum AND w.siteid = a.siteid
                  AND jp.worktype IN ('REG', 'INSP', 'API510', 'API570')
                  AND w.status IN ('COMP', 'CLOSE')
            ) AS years_since_inspection,
            (
                SELECT MAX(ABS({{catalog}}.{{metrics_schema}}.corrosion_rate(
                    a.assetnum, a.siteid, am.metername, 1095
                )))
                FROM {{catalog}}.{{silver_schema}}.assetmeter am
                WHERE am.assetnum = a.assetnum AND am.siteid = a.siteid AND am.__END_AT IS NULL
                  AND am.metername LIKE '%THICKNESS%'
            ) AS max_corrosion_rate
        FROM {{catalog}}.{{silver_schema}}.asset a
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
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.corrosion_rate              TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.next_inspection_due         TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.inspection_on_time_compliance TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.rbi_score                   TO `{{principal}}`;
