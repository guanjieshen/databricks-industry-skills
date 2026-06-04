-- =============================================================================
-- Maximo HSE — Gold Views
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_open_permits
-- Currently-issued or active permits with linked WO and asset context.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_open_permits
COMMENT 'Currently active permits to work with linked WO + asset context. One row per active permit.'
AS
SELECT
    p.permitnum,
    p.siteid,
    p.permittype,
    pt.description       AS permit_type_description,
    p.status,
    p.startdate,
    p.enddate,
    datediff(DAY, current_date(), p.enddate) AS days_until_expiry,
    CASE
        WHEN p.enddate < current_timestamp() THEN 'EXPIRED_STILL_OPEN'
        WHEN p.enddate <= current_timestamp() + INTERVAL 24 HOURS THEN 'EXPIRING_TODAY'
        WHEN p.enddate <= current_timestamp() + INTERVAL 7 DAYS THEN 'EXPIRING_7D'
        ELSE 'CURRENT'
    END                  AS expiry_status,
    p.wonum,
    w.description        AS wo_description,
    w.assetnum,
    a.description        AS asset_description
FROM {{catalog}}.{{silver_schema}}.plusgpermitwork p
LEFT JOIN {{catalog}}.{{silver_schema}}.plusgpertype pt
    ON pt.pertype = p.permittype
LEFT JOIN {{catalog}}.{{silver_schema}}.workorder w
    ON w.wonum = p.wonum AND w.siteid = p.siteid
LEFT JOIN {{catalog}}.{{silver_schema}}.asset a
    ON a.assetnum = w.assetnum AND a.siteid = w.siteid AND a.__END_AT IS NULL
WHERE p.status IN ('ISSUED', 'ACTIVE');


-- -----------------------------------------------------------------------------
-- v_incidents_enriched
-- INCIDENT with related WO, asset, and location context.
-- Aggregated injury counts from plusgincperson (no PII exposed).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_incidents_enriched
COMMENT 'Enriched incidents with WO/asset/location context and injury counts. Does NOT expose plusgincperson PII (names) — only counts.'
AS
SELECT
    i.incidentid,
    i.siteid,
    i.reportdate,
    i.incidentcategory,
    i.severity,
    i.status,
    i.assetnum,
    a.description        AS asset_description,
    a.classstructureid   AS asset_class_id,
    i.location,
    l.description        AS location_description,
    inj.persons_count    AS persons_involved_count,
    inj.injury_count     AS injured_persons_count
FROM {{catalog}}.{{silver_schema}}.incident i
LEFT JOIN {{catalog}}.{{silver_schema}}.asset a
    ON a.assetnum = i.assetnum AND a.siteid = i.siteid AND a.__END_AT IS NULL
LEFT JOIN {{catalog}}.{{silver_schema}}.locations l
    ON l.location = i.location AND l.siteid = i.siteid AND l.__END_AT IS NULL
LEFT JOIN (
    SELECT
        incidentid,
        COUNT(*)                                         AS persons_count,
        SUM(CASE WHEN injurytype IS NOT NULL THEN 1 ELSE 0 END) AS injury_count
    FROM {{catalog}}.{{silver_schema}}.plusgincperson
    GROUP BY incidentid
) inj ON inj.incidentid = i.incidentid;


-- -----------------------------------------------------------------------------
-- v_moc_actions
-- MoC records and their tracking actions.
-- Assumes corrective actions are tracked as WOs with WOCLASS = 'ACTION'.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_moc_actions
COMMENT 'MoC records with their linked corrective actions (WORKORDER WOCLASS=ACTION). One row per (MoC, action) pair.'
AS
SELECT
    moc.mocid,
    moc.siteid                AS moc_siteid,
    moc.reason                AS moc_reason,
    moc.status                AS moc_status,
    moc.initiateddate         AS moc_initiated,
    moc.closeddate            AS moc_closed,
    act.wonum                 AS action_wonum,
    act.status                AS action_status,
    act.targcompdate          AS action_due_date,
    act.actfinish             AS action_finish_date,
    CASE
        WHEN act.actfinish IS NULL AND act.targcompdate < current_date() THEN 'OVERDUE'
        WHEN act.actfinish IS NULL THEN 'OPEN'
        WHEN act.actfinish > act.targcompdate THEN 'LATE_CLOSED'
        ELSE 'ON_TIME_CLOSED'
    END                       AS action_status_bucket
FROM {{catalog}}.{{silver_schema}}.moc moc
LEFT JOIN {{catalog}}.{{silver_schema}}.plusgrelatedrec rr
    ON rr.recordkey = moc.mocid
   AND rr.recordclass = 'MOC'
   AND rr.relatedrecclass = 'WORKORDER'
LEFT JOIN {{catalog}}.{{silver_schema}}.workorder_all_classes act
    ON act.wonum = rr.relatedreckey
   AND act.siteid = moc.siteid
   AND act.woclass = 'ACTION';
