-- =============================================================================
-- Maximo Gold Views — reusable analytical surface
-- =============================================================================
-- Contents (CROSS-DOMAIN views only — single-domain WO views are owned by
-- maximo-work-orders; see the reference note below):
--   v_failure_events            completed WOs with coded failure data
--   v_pm_schedule               PM master + next-due age
--
-- These views are the canonical consumption layer. Downstream skills
-- (maximo-work-orders, maximo-reliability, maximo-integrity, maximo-hse,
-- Genie Agents, AI/BI dashboards) all compose against these.
--
-- Parameters use Databricks-native :param placeholders, bound at execution by
-- SQL warehouses / Genie Agents / AI-BI. Set :catalog, :silver_schema,
-- :gold_schema (e.g. eam / maximo_silver / maximo_gold) before running, or
-- register via maximo-setup which substitutes the customer's values.
--
-- UNIVERSAL MECHANICS APPLIED HERE (owned by maximo-overview — see that skill):
--   * SITEID is part of every composite-key join (WONUM/ASSETNUM/LOCATION are
--     unique only within SITEID).
--   * Status sets are resolved via SYNONYMDOMAIN, never status literals —
--     WORKORDER.STATUS stores the customer-renamable synonym (VALUE), not the
--     internal MAXVALUE. (COMP <> CLOSE: "completed" keys on COMP-or-later.)
--   * HISTORYFLAG closed records are NOT filtered here; Silver keeps them so
--     completion/trend metrics work. Add HISTORYFLAG filters only per consumer.
--   * Day/week/month bucketing below uses datediff on app-server-local
--     datetimes (NOT guaranteed per-row UTC). For cross-site daily buckets,
--     confirm the deployment's app-server timezone with maximo-setup.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- WO-domain Gold views (v_workorder_enriched, v_workorder_status_history,
-- v_labor_actuals) are SINGLE-DOMAIN and OWNED by maximo-work-orders
-- (its views.sql ships the canonical DDL). This skill ships only CROSS-DOMAIN
-- Gold views that span modules (below). Do not re-define the WO views here —
-- compose against the ones maximo-work-orders owns. See that skill for their DDL.
-- -----------------------------------------------------------------------------


-- -----------------------------------------------------------------------------
-- v_failure_events
-- Completed WOs with coded failure data, joined to FAILURECODE for descriptions.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_failure_events
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
FROM :catalog.:silver_schema.failurereport fr
JOIN :catalog.:silver_schema.workorder w
    ON w.wonum = fr.wonum AND w.siteid = fr.siteid
LEFT JOIN :catalog.:silver_schema.failurecode fc
    ON fc.failurecode = fr.failurecode
LEFT JOIN :catalog.:silver_schema.asset a
    ON a.assetnum = w.assetnum AND a.siteid = w.siteid AND a.__END_AT IS NULL
-- "Completed" = the completed set COMP/CLOSE (both terminal states, not a
-- COMP-or-later range). Resolve the synonym set via SYNONYMDOMAIN instead of
-- literals, because WORKORDER.STATUS stores the customer-renamable synonym
-- (VALUE), not the internal MAXVALUE. COMP <> CLOSE (many shops never CLOSE),
-- so both MAXVALUEs are included here.
WHERE w.status IN (
    SELECT value FROM :catalog.:silver_schema.synonymdomain
    WHERE domainid = 'WOSTATUS' AND maxvalue IN ('COMP', 'CLOSE')
);


-- -----------------------------------------------------------------------------
-- v_pm_schedule
-- PM master + derived next-due age.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_pm_schedule
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
FROM :catalog.:silver_schema.pm
WHERE pm.__END_AT IS NULL;
