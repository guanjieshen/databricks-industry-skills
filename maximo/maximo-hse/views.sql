-- =============================================================================
-- Maximo HSE — Gold Views
-- =============================================================================
-- Bind :catalog, :silver_schema, :gold_schema (Databricks SQL parameters) to the
-- customer's catalog / schemas at execution.
--
-- PLUSG physical column names below come from the IBM MAS Performance Wiki's
-- recommended-index DDL (IBM publishes no per-column PLUSG dictionary). CONFIRM
-- against MAXATTRIBUTE (WHERE objectname LIKE 'PLUSG%') in THIS deployment.
-- Columns flagged UNVERIFIED (e.g. plusgpermitwork.WONUM/ENDDATE/STARTDATE,
-- INCIDENTCATEGORY/SEVERITY, plusgincperson injury columns) must be verified
-- before these views compile cleanly.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_open_permits
-- Currently-issued or active permits with linked WO and asset context.
-- Permit identifier is PERMITWORKNUM; type FK is PLUSGPERTYPEID (not permitnum/permittype).
-- PTW status literals are likely customer synonyms — resolve via the PTW status
-- domain (confirm domainid in DOMAIN/SYNONYMDOMAIN; not publicly named).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_open_permits
COMMENT 'Currently active permits to work with linked WO + asset context. One row per active permit. Permit key=PERMITWORKNUM, type FK=PLUSGPERTYPEID.'
AS
SELECT
    p.permitworknum,
    p.siteid,
    p.plusgpertypeid,
    pt.pertypenum        AS permit_type_code,
    pt.description       AS permit_type_description,
    p.status,
    p.startdate,         -- UNVERIFIED on plusgpermitwork: confirm in MAXATTRIBUTE
    p.enddate,           -- UNVERIFIED on plusgpermitwork: confirm in MAXATTRIBUTE
    datediff(DAY, current_date(), p.enddate) AS days_until_expiry,
    CASE
        WHEN p.enddate < current_timestamp() THEN 'EXPIRED_STILL_OPEN'
        WHEN p.enddate <= current_timestamp() + INTERVAL 24 HOURS THEN 'EXPIRING_TODAY'
        WHEN p.enddate <= current_timestamp() + INTERVAL 7 DAYS THEN 'EXPIRING_7D'
        ELSE 'CURRENT'
    END                  AS expiry_status,
    p.wonum,             -- UNVERIFIED on plusgpermitwork: confirm in MAXATTRIBUTE
    w.description        AS wo_description,
    w.assetnum,
    a.description        AS asset_description
FROM :catalog.:silver_schema.plusgpermitwork p
LEFT JOIN :catalog.:silver_schema.plusgpertype pt
    ON pt.plusgpertypeid = p.plusgpertypeid
LEFT JOIN :catalog.:silver_schema.workorder w
    ON w.wonum = p.wonum AND w.siteid = p.siteid
LEFT JOIN :catalog.:silver_schema.asset a
    ON a.assetnum = w.assetnum AND a.siteid = w.siteid AND a.__END_AT IS NULL
WHERE p.status IN ('ISSUED', 'ACTIVE');  -- resolve via PTW status domain when synonyms exist


-- -----------------------------------------------------------------------------
-- v_incidents_enriched
-- Incidents are TICKET rows (CLASS='INCIDENT'), keyed by TICKETID.
-- Related WO, asset, location context. Aggregated injury counts from
-- plusgincperson (keyed on TICKETID), no PII exposed. HISTORYFLAG retained so the
-- caller can include/exclude closed incidents deliberately (overview F3).
-- Status holds the synonym VALUE — resolve via SYNONYMDOMAIN domainid=INCIDENTSTATUS (F2).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_incidents_enriched
COMMENT 'Enriched incidents (TICKET CLASS=INCIDENT, key TICKETID) with WO/asset/location context and injury counts. No plusgincperson PII (names) — only counts.'
AS
SELECT
    i.ticketid,
    i.siteid,
    i.reportdate,
    i.status,                            -- synonym value; resolve via SYNONYMDOMAIN (INCIDENTSTATUS)
    i.historyflag,                       -- 1 = closed/cancelled/rejected; standard views filter =0
    i.incidentcategory,                  -- UNVERIFIED stock column; often driven by CLASSSTRUCTUREID
    i.severity,                          -- UNVERIFIED stock column
    i.classstructureid   AS incident_classification,
    i.assetnum,
    a.description        AS asset_description,
    a.classstructureid   AS asset_class_id,
    i.location,
    l.description        AS location_description,
    inj.persons_count    AS persons_involved_count,
    inj.injury_count     AS injured_persons_count
FROM :catalog.:silver_schema.ticket i
LEFT JOIN :catalog.:silver_schema.asset a
    ON a.assetnum = i.assetnum AND a.siteid = i.siteid AND a.__END_AT IS NULL
LEFT JOIN :catalog.:silver_schema.locations l
    ON l.location = i.location AND l.siteid = i.siteid AND l.__END_AT IS NULL
LEFT JOIN (
    SELECT
        ticketid,
        COUNT(*)                                                AS persons_count,
        SUM(CASE WHEN injurytype IS NOT NULL THEN 1 ELSE 0 END) AS injury_count
    FROM :catalog.:silver_schema.plusgincperson
    GROUP BY ticketid
) inj ON inj.ticketid = i.ticketid
WHERE i.class = 'INCIDENT';


-- -----------------------------------------------------------------------------
-- v_moc_actions
-- MoC records and their tracking actions.
-- Assumes corrective actions are tracked as WOs with WOCLASS = 'ACTION'.
-- plusgrelatedrec source-side class column is CLASS (not recordclass).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_moc_actions
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
FROM :catalog.:silver_schema.moc moc
LEFT JOIN :catalog.:silver_schema.plusgrelatedrec rr
    ON rr.recordkey = moc.mocid
   AND rr.class = 'MOC'
   AND rr.relatedrecclass = 'WORKORDER'
LEFT JOIN :catalog.:silver_schema.workorder_all_classes act
    ON act.wonum = rr.relatedreckey
   AND act.siteid = moc.siteid
   AND act.woclass = 'ACTION';
