-- =============================================================================
-- Maximo Integrity — Gold Views
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} and {{catalog}}.{{gold_schema}}.
-- The inspection worktype filter is parameterized via a configurable list
-- (replace WORKTYPE_FILTER with the customer's actual codes).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_inspection_schedule
-- Active regulatory-inspection PMs with due-date status.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_inspection_schedule
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
FROM {{catalog}}.{{silver_schema}}.pm pm
JOIN {{catalog}}.{{silver_schema}}.jobplan jp
    ON jp.jpnum = pm.jpnum AND jp.__END_AT IS NULL
LEFT JOIN {{catalog}}.{{silver_schema}}.asset a
    ON a.assetnum = pm.assetnum AND a.siteid = pm.siteid AND a.__END_AT IS NULL
WHERE pm.__END_AT IS NULL
  -- Customer-specific: replace with their inspection WORKTYPE set, ideally
  -- via a workspace-glossary lookup.
  AND jp.worktype IN ('REG', 'INSP', 'API510', 'API570', 'B31_4', 'CSA_Z662');


-- -----------------------------------------------------------------------------
-- v_corrosion_trends
-- Per-asset corrosion rate (3-year window) and current thickness vs limits.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_corrosion_trends
COMMENT 'Per-asset corrosion rate and latest thickness reading vs configured limits. One row per (asset, thickness-meter).'
AS
WITH latest_readings AS (
    SELECT
        mr.assetnum, mr.siteid, mr.metername,
        ROW_NUMBER() OVER (PARTITION BY mr.assetnum, mr.siteid, mr.metername ORDER BY mr.readingdate DESC) AS rn,
        mr.reading, mr.readingdate
    FROM {{catalog}}.{{silver_schema}}.meterreading mr
    JOIN {{catalog}}.{{silver_schema}}.assetmeter am
        ON am.assetnum = mr.assetnum AND am.siteid = mr.siteid AND am.metername = mr.metername
       AND am.__END_AT IS NULL
       AND am.metername LIKE '%THICKNESS%'
),
reading_counts AS (
    SELECT
        mr.assetnum, mr.siteid, mr.metername,
        COUNT(*) AS reading_count_3yr,
        MIN(mr.readingdate) AS oldest_reading_3yr,
        MAX(mr.readingdate) AS newest_reading_3yr,
        MIN(mr.reading) AS min_reading_3yr,
        MAX(mr.reading) AS max_reading_3yr
    FROM {{catalog}}.{{silver_schema}}.meterreading mr
    JOIN {{catalog}}.{{silver_schema}}.assetmeter am
        ON am.assetnum = mr.assetnum AND am.siteid = mr.siteid AND am.metername = mr.metername
       AND am.__END_AT IS NULL
       AND am.metername LIKE '%THICKNESS%'
    WHERE mr.readingdate >= current_date() - INTERVAL 1095 DAYS
    GROUP BY mr.assetnum, mr.siteid, mr.metername
)
SELECT
    rc.assetnum,
    rc.siteid,
    rc.metername,
    rc.reading_count_3yr,
    rc.oldest_reading_3yr,
    rc.newest_reading_3yr,
    lr.reading       AS latest_reading,
    lr.readingdate   AS latest_reading_date,
    am.actionlimitlo AS retirement_thickness,
    am.warnlimitlo   AS warning_thickness,
    (
        SELECT {{catalog}}.{{metrics_schema}}.corrosion_rate(
            rc.assetnum, rc.siteid, rc.metername, 1095
        )
    ) AS corrosion_rate_per_year,
    CASE
        WHEN am.actionlimitlo IS NOT NULL AND lr.reading <= am.actionlimitlo
            THEN 'AT_RETIREMENT'
        WHEN am.warnlimitlo IS NOT NULL AND lr.reading <= am.warnlimitlo
            THEN 'AT_WARNING'
        ELSE 'OK'
    END AS thickness_status
FROM reading_counts rc
JOIN latest_readings lr
    ON lr.assetnum = rc.assetnum
   AND lr.siteid = rc.siteid
   AND lr.metername = rc.metername
   AND lr.rn = 1
LEFT JOIN {{catalog}}.{{silver_schema}}.assetmeter am
    ON am.assetnum = rc.assetnum
   AND am.siteid = rc.siteid
   AND am.metername = rc.metername
   AND am.__END_AT IS NULL;


-- -----------------------------------------------------------------------------
-- v_inspection_findings
-- Closed inspection WOs with linked incidents via plusgrelatedrec.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_inspection_findings
COMMENT 'Closed inspection work orders, with any linked incidents via plusgrelatedrec. One row per inspection-WO; LEFT JOIN to incidents.'
AS
SELECT
    w.wonum,
    w.siteid,
    w.assetnum,
    w.actstart,
    w.actfinish,
    w.failurecode,
    fc.description AS failure_description,
    rr.relatedreckey  AS linked_incident_id,
    rr.relatedrecclass AS linked_record_class,
    rr.relationship
FROM {{catalog}}.{{silver_schema}}.workorder w
JOIN {{catalog}}.{{silver_schema}}.jobplan jp
    ON jp.jpnum = w.jpnum AND jp.__END_AT IS NULL
   AND jp.worktype IN ('REG', 'INSP', 'API510', 'API570', 'B31_4', 'CSA_Z662')
LEFT JOIN {{catalog}}.{{silver_schema}}.failurecode fc
    ON fc.failurecode = w.failurecode
LEFT JOIN {{catalog}}.{{silver_schema}}.plusgrelatedrec rr
    ON rr.recordkey = w.wonum
   AND rr.recordclass = 'WORKORDER'
   AND rr.relatedrecclass = 'INCIDENT'
WHERE w.status IN ('COMP', 'CLOSE');
