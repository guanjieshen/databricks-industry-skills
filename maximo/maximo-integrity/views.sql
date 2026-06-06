-- =============================================================================
-- Maximo Integrity — Gold Views
-- =============================================================================
-- Substitute :catalog.:silver_schema and :catalog.:gold_schema.
-- The inspection worktype filter is parameterized via a configurable list
-- (replace WORKTYPE_FILTER with the customer's actual codes).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_inspection_schedule
-- Active regulatory-inspection PMs with due-date status.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_inspection_schedule
COMMENT 'Active regulatory-inspection PMs. One row per active inspection PM, with due-date bucket.'
AS
SELECT
    pm.pmnum,
    pm.siteid,
    pm.assetnum,
    a.description       AS asset_description,
    a.classstructureid  AS asset_class_id,
    a.criticality       AS asset_criticality,
    pm.jpnum,
    jp.worktype,
    pm.frequency,
    pm.frequnit,
    pm.nextdate,
    pm.laststartdate,
    datediff(DAY, pm.nextdate, current_date())  AS days_overdue,
    CASE
        WHEN pm.nextdate < current_date() THEN 'OVERDUE'
        WHEN pm.nextdate <= current_date() + INTERVAL 30 DAYS THEN 'DUE_30D'
        WHEN pm.nextdate <= current_date() + INTERVAL 90 DAYS THEN 'DUE_90D'
        WHEN pm.nextdate <= current_date() + INTERVAL 180 DAYS THEN 'DUE_180D'
        ELSE 'FUTURE'
    END                                          AS due_bucket
FROM :catalog.:silver_schema.pm pm
JOIN :catalog.:silver_schema.jobplan jp
    ON jp.jpnum = pm.jpnum AND jp.__END_AT IS NULL
LEFT JOIN :catalog.:silver_schema.asset a
    ON a.assetnum = pm.assetnum AND a.siteid = pm.siteid AND a.__END_AT IS NULL
WHERE pm.__END_AT IS NULL
  -- Customer-specific: replace with their inspection WORKTYPE set, ideally
  -- via a workspace-glossary lookup.
  AND jp.worktype IN ('REG', 'INSP', 'API510', 'API570', 'B31_4', 'CSA_Z662');


-- -----------------------------------------------------------------------------
-- v_corrosion_trends
-- Per-asset thickness trend with SHORT-TERM (ST) and LONG-TERM (LT) corrosion
-- rates exposed SEPARATELY (API 510/570), plus remaining life on the more
-- conservative rate. One row per (asset, thickness-meter).
--
-- METHODOLOGY (do NOT collapse to a single regression slope):
--   LT rate = (t_initial - t_actual) / years(t_initial -> t_actual)   [full history]
--   ST rate = (t_previous - t_actual) / years(t_previous -> t_actual) [two most recent]
--   remaining_life = (t_actual - t_required) / rate ; pick the SHORTER (worse) case.
--   t_required (t-min) is a per-component INPUT — substitute the customer's source
--   below. Here we use ASSETMETER.actionlimitlo as a PLACEHOLDER for t-min; confirm
--   it really equals t-min before quoting remaining life (see gotchas 1, 2, 9).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_corrosion_trends
COMMENT 'Per-asset thickness trend with short-term and long-term corrosion rates (API 510/570) and remaining life on the more conservative rate. t-min is a placeholder (ASSETMETER.actionlimitlo) — confirm per customer. One row per (asset, thickness-meter).'
AS
WITH ordered AS (
    SELECT
        mr.assetnum, mr.siteid, mr.metername, mr.reading, mr.readingdate,
        ROW_NUMBER() OVER (PARTITION BY mr.assetnum, mr.siteid, mr.metername ORDER BY mr.readingdate DESC) AS rn_desc,
        ROW_NUMBER() OVER (PARTITION BY mr.assetnum, mr.siteid, mr.metername ORDER BY mr.readingdate ASC)  AS rn_asc
    FROM :catalog.:silver_schema.meterreading mr
    JOIN :catalog.:silver_schema.assetmeter am
        ON am.assetnum = mr.assetnum AND am.siteid = mr.siteid AND am.metername = mr.metername
       AND am.__END_AT IS NULL
       AND am.metername LIKE '%THICKNESS%'
    WHERE mr.reading IS NOT NULL
),
pivoted AS (
    SELECT
        assetnum, siteid, metername,
        COUNT(*)                                              AS reading_count,
        MAX(CASE WHEN rn_desc = 1 THEN reading END)           AS t_actual,
        MAX(CASE WHEN rn_desc = 1 THEN readingdate END)       AS t_actual_date,
        MAX(CASE WHEN rn_desc = 2 THEN reading END)           AS t_previous,
        MAX(CASE WHEN rn_desc = 2 THEN readingdate END)       AS t_previous_date,
        MAX(CASE WHEN rn_asc  = 1 THEN reading END)           AS t_initial,
        MAX(CASE WHEN rn_asc  = 1 THEN readingdate END)       AS t_initial_date
    FROM ordered
    GROUP BY assetnum, siteid, metername
),
rates AS (
    SELECT
        p.*,
        -- long-term: oldest vs latest over full history
        CASE WHEN reading_count >= 2 AND datediff(DAY, t_initial_date, t_actual_date) > 0
             THEN (t_initial - t_actual) / (datediff(DAY, t_initial_date, t_actual_date) / 365.0)
             ELSE NULL END AS lt_rate_per_year,
        -- short-term: two most recent readings (catches recent acceleration)
        CASE WHEN t_previous IS NOT NULL AND datediff(DAY, t_previous_date, t_actual_date) > 0
             THEN (t_previous - t_actual) / (datediff(DAY, t_previous_date, t_actual_date) / 365.0)
             ELSE NULL END AS st_rate_per_year
    FROM pivoted p
)
SELECT
    r.assetnum,
    r.siteid,
    r.metername,
    r.reading_count,
    r.t_initial_date         AS oldest_reading_date,
    r.t_actual_date          AS latest_reading_date,
    r.t_actual               AS latest_reading,
    r.t_previous,
    r.t_initial,
    am.actionlimitlo         AS retirement_thickness,
    am.warnlimitlo           AS warning_thickness,
    am.actionlimitlo         AS t_required_placeholder,   -- PLACEHOLDER for t-min; confirm per customer
    r.lt_rate_per_year       AS corrosion_rate_lt_per_year,
    r.st_rate_per_year       AS corrosion_rate_st_per_year,
    -- the governing (more conservative = larger) thinning rate
    GREATEST(COALESCE(r.lt_rate_per_year, 0), COALESCE(r.st_rate_per_year, 0)) AS corrosion_rate_governing_per_year,
    -- remaining life on the GOVERNING rate; NULL when t-min/rate unavailable
    CASE
        WHEN am.actionlimitlo IS NOT NULL
         AND GREATEST(COALESCE(r.lt_rate_per_year, 0), COALESCE(r.st_rate_per_year, 0)) > 0
            THEN (r.t_actual - am.actionlimitlo)
                 / GREATEST(COALESCE(r.lt_rate_per_year, 0), COALESCE(r.st_rate_per_year, 0))
        ELSE NULL
    END AS remaining_life_years,
    CASE
        WHEN am.actionlimitlo IS NOT NULL AND r.t_actual <= am.actionlimitlo
            THEN 'AT_RETIREMENT'
        WHEN am.warnlimitlo IS NOT NULL AND r.t_actual <= am.warnlimitlo
            THEN 'AT_WARNING'
        ELSE 'OK'
    END AS thickness_status
FROM rates r
LEFT JOIN :catalog.:silver_schema.assetmeter am
    ON am.assetnum = r.assetnum
   AND am.siteid = r.siteid
   AND am.metername = r.metername
   AND am.__END_AT IS NULL;


-- -----------------------------------------------------------------------------
-- v_inspection_findings
-- Closed inspection WOs with O&G-linked records via PLUSGRELATEDREC.
--
-- NOTE: PLUSGRELATEDREC is the O&G add-on's OWN object, DISTINCT from base
-- RELATEDRECORD (gotcha 4). It only exists if the O&G solution is deployed —
-- guard this join behind a deployment check, and inspect the deployed object's
-- columns (they vary by version) rather than assuming base RELATEDRECORD names.
-- w.failurecode is a MAINTENANCE failure, NOT the inspection finding (gotcha 12);
-- structured findings may live in MEASUREMENT/MEASUREPOINT or custom columns.
-- Resolve status synonyms via SYNONYMDOMAIN per maximo-overview rather than
-- hard-coding 'COMP'/'CLOSE' literals.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_inspection_findings
COMMENT 'Closed inspection work orders, with O&G-linked records via PLUSGRELATEDREC (distinct from base RELATEDRECORD; only if O&G solution deployed). failurecode is a maintenance failure, not the inspection finding. One row per inspection-WO; LEFT JOIN to links.'
AS
SELECT
    w.wonum,
    w.siteid,
    w.assetnum,
    w.actstart,
    w.actfinish,
    w.failurecode,                              -- MAINTENANCE failure, not the finding
    fc.description AS failure_description,
    rr.relatedrecwonum AS linked_wonum,         -- per APAR IJ41024 PLUSGRELATEDREC attr
    rr.relatedreckey   AS linked_record_id,
    rr.relatedrecclass AS linked_record_class,
    rr.relatetype      AS linked_relate_type      -- core RELATEDRECORD uses RELATETYPE, NOT a column named RELATIONSHIP
FROM :catalog.:silver_schema.workorder w
JOIN :catalog.:silver_schema.jobplan jp
    ON jp.jpnum = w.jpnum AND jp.__END_AT IS NULL
   AND jp.worktype IN ('REG', 'INSP', 'API510', 'API570', 'B31_4', 'CSA_Z662')
LEFT JOIN :catalog.:silver_schema.failurecode fc
    ON fc.failurecode = w.failurecode
-- O&G overlay only — remove/guard if PLUSG* objects are not deployed.
-- PLUSG* column names vary by version: confirm against MAXATTRIBUTE
-- (WHERE objectname LIKE 'PLUSG%') before shipping. The source-side class
-- column is CLASS (NOT recordclass), and the relate-type is RELATETYPE.
LEFT JOIN :catalog.:silver_schema.plusgrelatedrec rr
    ON rr.recordkey = w.wonum
   AND rr.class = 'WORKORDER'
WHERE w.status IN ('COMP', 'CLOSE');
