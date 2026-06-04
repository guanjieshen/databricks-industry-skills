-- =============================================================================
-- Maximo Integrity — Gold-Standard Query Examples
-- =============================================================================
-- Substitute {{catalog}}.{{gold_schema}}, {{catalog}}.{{silver_schema}},
-- {{catalog}}.{{metrics_schema}} before running.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Pressure vessels with inspection due in next 6 months
-- -----------------------------------------------------------------------------
-- Trigger: "vessels due for inspection in 6 months", "API 510 due"
SELECT
    pmnum, siteid, assetnum, asset_description, asset_criticality,
    worktype, nextdate, days_overdue, due_bucket
FROM {{catalog}}.{{gold_schema}}.v_inspection_schedule
WHERE asset_class_id IN ({{vessel_class_ids}})   -- e.g. 7100, 7101, 7102 — from workspace glossary
  AND nextdate <= current_date() + INTERVAL 180 DAYS
ORDER BY nextdate
LIMIT 100;


-- -----------------------------------------------------------------------------
-- 2. Corrosion rate for a single asset
-- -----------------------------------------------------------------------------
-- Trigger: "corrosion rate on asset X"
SELECT
    {{catalog}}.{{metrics_schema}}.corrosion_rate(
        '{{assetnum}}',
        '{{siteid}}',
        'UT_THICKNESS',
        1095   -- 3-year window
    ) AS corrosion_rate_per_year;


-- -----------------------------------------------------------------------------
-- 3. Assets approaching retirement thickness
-- -----------------------------------------------------------------------------
-- Trigger: "which assets are near retirement thickness", "thinning assets"
SELECT
    assetnum, siteid, metername,
    latest_reading, latest_reading_date,
    retirement_thickness,
    warning_thickness,
    corrosion_rate_per_year,
    thickness_status
FROM {{catalog}}.{{gold_schema}}.v_corrosion_trends
WHERE thickness_status IN ('AT_WARNING', 'AT_RETIREMENT')
ORDER BY
    CASE thickness_status WHEN 'AT_RETIREMENT' THEN 1 ELSE 2 END,
    corrosion_rate_per_year DESC;


-- -----------------------------------------------------------------------------
-- 4. Inspection on-time compliance by site, last year
-- -----------------------------------------------------------------------------
-- Trigger: "inspection compliance", "regulatory compliance rate"
SELECT
    siteid,
    {{catalog}}.{{metrics_schema}}.inspection_on_time_compliance(
        siteid,
        'REG,INSP,API510,API570',   -- customer's worktype filter from glossary
        current_timestamp() - INTERVAL 365 DAYS,
        current_timestamp()
    ) AS on_time_compliance_pct
FROM (SELECT DISTINCT siteid FROM {{catalog}}.{{gold_schema}}.v_inspection_schedule)
ORDER BY on_time_compliance_pct;


-- -----------------------------------------------------------------------------
-- 5. RBI risk-ranked asset list
-- -----------------------------------------------------------------------------
-- Trigger: "RBI score", "risk-based inspection priorities"
SELECT
    a.assetnum, a.siteid, a.description, a.criticality,
    {{catalog}}.{{metrics_schema}}.rbi_score(a.assetnum, a.siteid) AS rbi_score
FROM {{catalog}}.{{silver_schema}}.asset a
WHERE a.__END_AT IS NULL
  AND a.classstructureid IN ({{vessel_class_ids}})
ORDER BY rbi_score DESC NULLS LAST
LIMIT 50;


-- -----------------------------------------------------------------------------
-- 6. Inspection findings linked to incidents (last year)
-- -----------------------------------------------------------------------------
-- Trigger: "inspections tied to incidents", "did a missed inspection cause incident X"
SELECT
    wonum, siteid, assetnum,
    actstart, actfinish,
    failure_description,
    linked_incident_id,
    relationship
FROM {{catalog}}.{{gold_schema}}.v_inspection_findings
WHERE actfinish >= add_months(current_date(), -12)
  AND linked_incident_id IS NOT NULL
ORDER BY actfinish DESC;


-- -----------------------------------------------------------------------------
-- 7. Audit prep: all inspection records for a site in a year (with audit trail)
-- -----------------------------------------------------------------------------
-- Trigger: "audit prep for site X", "pull all inspection records"
SELECT
    w.wonum, w.siteid, w.assetnum, w.jpnum, jp.worktype,
    w.reportdate, w.actstart, w.actfinish, w.status,
    s.status                                      AS final_transition_status,
    s.changedate                                  AS final_transition_date,
    s.changeby                                    AS final_transition_user,
    fr.failurecode, fr.recordkey                  AS failurereport_id
FROM {{catalog}}.{{silver_schema}}.workorder w
JOIN {{catalog}}.{{silver_schema}}.jobplan jp ON jp.jpnum = w.jpnum AND jp.__END_AT IS NULL
LEFT JOIN (
    SELECT wonum, siteid,
           MAX_BY(status, changedate) AS status,
           MAX(changedate)            AS changedate,
           MAX_BY(changeby, changedate) AS changeby
    FROM {{catalog}}.{{silver_schema}}.wostatus
    GROUP BY wonum, siteid
) s ON s.wonum = w.wonum AND s.siteid = w.siteid
LEFT JOIN {{catalog}}.{{silver_schema}}.failurereport fr
    ON fr.wonum = w.wonum AND fr.siteid = w.siteid
WHERE w.siteid = '{{audit_site_id}}'
  AND jp.worktype IN ('REG', 'INSP', 'API510', 'API570')
  AND w.reportdate >= '{{audit_year_start}}'
  AND w.reportdate < '{{audit_year_end}}'
ORDER BY w.reportdate;
