-- =============================================================================
-- Maximo Gold Views — reusable analytical surface
-- =============================================================================
-- These views are the canonical consumption layer. Downstream skills
-- (maximo-work-orders, maximo-reliability, maximo-integrity, maximo-hse,
-- Genie Spaces, AI/BI dashboards) all compose against these.
--
-- Substitute {{catalog}}.{{silver_schema}} (e.g. eam.maximo_silver) and
-- {{catalog}}.{{gold_schema}} (e.g. eam.maximo_gold) before running.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_workorder_enriched
-- The workhorse view. WORKORDER + ASSET (current) + LOCATIONS (current) +
-- derived backlog age and aging buckets.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_workorder_enriched
COMMENT 'Enriched work-order header with current asset, location, and derived age. One row per WO (already filtered to WOCLASS = WORKORDER at silver).'
AS
SELECT
    w.workorderid, w.wonum, w.siteid, w.orgid,
    w.status, w.statusdate,
    w.worktype, w.istask, w.parent,
    w.wopriority, w.lead, w.supervisor, w.crewid, w.ownergroup,
    w.reportdate, w.schedstart, w.schedfinish, w.actstart, w.actfinish,
    w.targcompdate,
    w.estlabcost, w.estmatcost, w.actlabcost, w.actmatcost,
    w.failurecode, w.problemcode,
    w.assetnum,
    a.description       AS asset_description,
    a.classstructureid  AS asset_class_id,
    a.criticality       AS asset_criticality,
    w.location,
    l.description       AS location_description,
    l.type              AS location_type,
    w.jpnum, w.pmnum,
    datediff(DAY, w.reportdate, current_date())  AS days_since_reported,
    datediff(DAY, w.statusdate, current_date())  AS days_in_current_status,
    CASE
        WHEN datediff(DAY, w.reportdate, current_date()) <= 30 THEN '0-30 days'
        WHEN datediff(DAY, w.reportdate, current_date()) <= 60 THEN '31-60 days'
        WHEN datediff(DAY, w.reportdate, current_date()) <= 90 THEN '61-90 days'
        ELSE '90+ days'
    END                                          AS age_bucket
FROM {{catalog}}.{{silver_schema}}.workorder w
LEFT JOIN {{catalog}}.{{silver_schema}}.asset a
       ON a.assetnum = w.assetnum
      AND a.siteid   = w.siteid
      AND a.__END_AT IS NULL       -- current SCD2 row
LEFT JOIN {{catalog}}.{{silver_schema}}.locations l
       ON l.location = w.location
      AND l.siteid   = w.siteid
      AND l.__END_AT IS NULL;


-- -----------------------------------------------------------------------------
-- v_workorder_status_history
-- WOSTATUS unpacked with LEAD() for time-in-state.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_workorder_status_history
COMMENT 'Work-order status transitions with time-in-state. One row per WOSTATUS row.'
AS
SELECT
    s.wonum, s.siteid,
    s.status,
    s.changedate                                           AS status_start,
    LEAD(s.changedate) OVER (PARTITION BY s.wonum, s.siteid ORDER BY s.changedate) AS status_end,
    s.changeby, s.memo,
    datediff(SECOND, s.changedate,
        LEAD(s.changedate) OVER (PARTITION BY s.wonum, s.siteid ORDER BY s.changedate)
    ) / 3600.0                                             AS hours_in_status,
    ROW_NUMBER() OVER (PARTITION BY s.wonum, s.siteid ORDER BY s.changedate) AS transition_seq
FROM {{catalog}}.{{silver_schema}}.wostatus s;


-- -----------------------------------------------------------------------------
-- v_labor_actuals
-- LABTRANS aggregated to WO grain with craft breakdown as a map.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_labor_actuals
COMMENT 'Labor transactions aggregated to WO grain. One row per (wonum, siteid). Craft breakdown in hours_by_craft map.'
AS
SELECT
    lt.wonum, lt.siteid,
    COUNT(*)                                       AS labor_transaction_count,
    ROUND(SUM(lt.regularhrs), 2)                   AS total_regular_hours,
    ROUND(SUM(COALESCE(lt.premiumpayhours, 0)), 2) AS total_premium_hours,
    ROUND(SUM(lt.regularhrs + COALESCE(lt.premiumpayhours, 0)), 2) AS total_hours,
    ROUND(SUM(lt.linecost), 2)                     AS total_labor_cost,
    MIN(lt.startdate)                              AS first_labor_date,
    MAX(lt.finishdate)                             AS last_labor_date,
    map_from_entries(
        collect_list(named_struct(
            'craft', lt.craft,
            'hours', ROUND(lt.regularhrs + COALESCE(lt.premiumpayhours, 0), 2)
        ))
    )                                              AS hours_by_craft
FROM {{catalog}}.{{silver_schema}}.labtrans lt
WHERE lt.transtype = 'WORK'
GROUP BY lt.wonum, lt.siteid;


-- -----------------------------------------------------------------------------
-- v_failure_events
-- Completed WOs with coded failure data, joined to FAILURECODE for descriptions.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_failure_events
COMMENT 'Completed work orders with coded failure data. One row per FAILUREREPORT, with WO context and FAILURECODE description.'
AS
SELECT
    fr.wonum, fr.siteid,
    fr.failurecode,
    fc.description                                 AS failure_description,
    fc.type                                        AS failure_type,
    w.assetnum,
    a.classstructureid                             AS asset_class_id,
    w.actstart                                     AS event_start,
    w.actfinish                                    AS event_end,
    datediff(MINUTE, w.actstart, w.actfinish)      AS event_duration_minutes
FROM {{catalog}}.{{silver_schema}}.failurereport fr
JOIN {{catalog}}.{{silver_schema}}.workorder w
    ON w.wonum = fr.wonum AND w.siteid = fr.siteid
LEFT JOIN {{catalog}}.{{silver_schema}}.failurecode fc
    ON fc.failurecode = fr.failurecode
LEFT JOIN {{catalog}}.{{silver_schema}}.asset a
    ON a.assetnum = w.assetnum AND a.siteid = w.siteid AND a.__END_AT IS NULL
WHERE w.status IN ('COMP', 'CLOSE');


-- -----------------------------------------------------------------------------
-- v_pm_schedule
-- PM master + derived next-due age.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_pm_schedule
COMMENT 'Preventive maintenance schedule with next-due age. One row per active PM.'
AS
SELECT
    pm.pmnum, pm.siteid,
    pm.assetnum,
    pm.jpnum,
    pm.frequency, pm.frequnit,
    pm.nextdate,
    pm.laststartdate,
    datediff(DAY, pm.nextdate, current_date())     AS days_overdue,
    CASE
        WHEN pm.nextdate < current_date() THEN 'OVERDUE'
        WHEN pm.nextdate <= current_date() + INTERVAL 30 DAYS THEN 'DUE_30D'
        WHEN pm.nextdate <= current_date() + INTERVAL 90 DAYS THEN 'DUE_90D'
        ELSE 'FUTURE'
    END                                            AS due_bucket
FROM {{catalog}}.{{silver_schema}}.pm
WHERE pm.__END_AT IS NULL;
