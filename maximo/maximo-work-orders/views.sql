-- =============================================================================
-- Maximo Work Orders — Pre-joined Delta Views
-- =============================================================================
-- Substitute {{maximo_catalog}}.{{maximo_schema}} with the customer's silver
-- catalog/schema (e.g. eam.maximo_silver) before running.
--
-- These views encode the most-used joins so Genie (Code or Space) and humans
-- both compose against a smaller, denormalized surface — per Databricks
-- best practice "denormalize and pre-join before exposing to Genie."
--
-- Recommended: register these as views in a dedicated Gold-layer schema with
-- TABLE and COLUMN comments (helps Genie pick the right table/column).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_workorder_enriched
-- -----------------------------------------------------------------------------
-- The workhorse view. Joins WORKORDER + ASSET + LOCATIONS + computes derived
-- columns. Use this for almost any "current state" question.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{maximo_catalog}}.{{maximo_schema}}.v_workorder_enriched
COMMENT 'Enriched Maximo work-order header with current asset, location, and derived age. One row per WO.'
AS
SELECT
    w.workorderid,
    w.wonum,
    w.siteid,
    w.orgid,
    w.status                                                         AS status,
    w.statusdate,
    w.woclass,
    w.worktype,
    w.istask,
    w.parent,
    w.wopriority,
    w.lead,
    w.supervisor,
    w.crewid,
    w.ownergroup,
    w.reportdate,
    w.schedstart,
    w.schedfinish,
    w.actstart,
    w.actfinish,
    w.targcompdate,
    w.estlabcost,
    w.estmatcost,
    w.actlabcost,
    w.actmatcost,
    w.failurecode,
    w.problemcode,
    -- Asset context
    w.assetnum,
    a.description                                                    AS asset_description,
    a.assettype                                                      AS asset_type,
    a.classstructureid                                               AS asset_class_id,
    a.criticality                                                    AS asset_criticality,
    -- Location context
    w.location,
    l.description                                                    AS location_description,
    l.type                                                           AS location_type,
    -- Job plan context
    w.jpnum,
    -- PM origin
    w.pmnum,
    -- Derived columns
    datediff(DAY, w.reportdate, current_date())                      AS days_since_reported,
    datediff(DAY, w.statusdate, current_date())                      AS days_in_current_status,
    CASE
        WHEN datediff(DAY, w.reportdate, current_date()) <= 30 THEN '0-30 days'
        WHEN datediff(DAY, w.reportdate, current_date()) <= 60 THEN '31-60 days'
        WHEN datediff(DAY, w.reportdate, current_date()) <= 90 THEN '61-90 days'
        ELSE '90+ days'
    END                                                              AS age_bucket
FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER w
LEFT JOIN {{maximo_catalog}}.{{maximo_schema}}.ASSET a
       ON a.assetnum = w.assetnum
      AND a.siteid   = w.siteid
LEFT JOIN {{maximo_catalog}}.{{maximo_schema}}.LOCATIONS l
       ON l.location = w.location
      AND l.siteid   = w.siteid;


-- -----------------------------------------------------------------------------
-- v_workorder_status_history
-- -----------------------------------------------------------------------------
-- WOSTATUS unpacked with time-in-state derived. One row per status transition
-- per WO. Use for any "how long was X in INPRG" / "transition path" question.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{maximo_catalog}}.{{maximo_schema}}.v_workorder_status_history
COMMENT 'Work-order status transition history with time-in-state. One row per WOSTATUS transition.'
AS
SELECT
    s.wonum,
    s.siteid,
    s.status,
    s.changedate                                                     AS status_start,
    LEAD(s.changedate) OVER (
        PARTITION BY s.wonum, s.siteid
        ORDER BY s.changedate
    )                                                                AS status_end,
    s.changeby,
    s.memo,
    datediff(SECOND, s.changedate,
        LEAD(s.changedate) OVER (
            PARTITION BY s.wonum, s.siteid
            ORDER BY s.changedate
        )) / 3600.0                                                  AS hours_in_status,
    ROW_NUMBER() OVER (
        PARTITION BY s.wonum, s.siteid
        ORDER BY s.changedate
    )                                                                AS transition_seq
FROM {{maximo_catalog}}.{{maximo_schema}}.WOSTATUS s;


-- -----------------------------------------------------------------------------
-- v_labor_actuals
-- -----------------------------------------------------------------------------
-- LABTRANS aggregated to the WO grain, with craft breakdown materialized as
-- a map so a single row gives total + craft-level detail.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{maximo_catalog}}.{{maximo_schema}}.v_labor_actuals
COMMENT 'Labor transactions aggregated to WO grain. One row per (wonum, siteid). Craft breakdown in hours_by_craft map.'
AS
SELECT
    lt.wonum,
    lt.siteid,
    COUNT(*)                                                AS labor_transaction_count,
    ROUND(SUM(lt.regularhrs), 2)                            AS total_regular_hours,
    ROUND(SUM(COALESCE(lt.premiumpayhours, 0)), 2)          AS total_premium_hours,
    ROUND(SUM(lt.regularhrs + COALESCE(lt.premiumpayhours, 0)), 2) AS total_hours,
    ROUND(SUM(lt.linecost), 2)                              AS total_labor_cost,
    MIN(lt.startdate)                                       AS first_labor_date,
    MAX(lt.finishdate)                                      AS last_labor_date,
    map_from_entries(
        collect_list(named_struct(
            'craft', lt.craft,
            'hours', ROUND(lt.regularhrs + COALESCE(lt.premiumpayhours, 0), 2)
        ))
    )                                                       AS hours_by_craft
FROM {{maximo_catalog}}.{{maximo_schema}}.LABTRANS lt
WHERE lt.transtype = 'WORK'
GROUP BY lt.wonum, lt.siteid;

-- UC column comments on these views are NOT registered here. They are owned by
-- maximo-setup (which carries the canonical comment content in maximo_comments.json
-- and applies it via the preview-then-apply script). If you want comments on the
-- view columns, add them to maximo_comments.json and run the setup workflow.
