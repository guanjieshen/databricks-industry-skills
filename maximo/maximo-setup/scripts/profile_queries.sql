-- =============================================================================
-- maximo-setup · Phase 0 profiling — PORTABLE SQL path
-- =============================================================================
-- Use this when Genie Code is attached to a SQL warehouse (e.g. started from the
-- Unity Catalog data page) and cannot run Python/CLI. Returns the same
-- data-provable facts as scripts/introspect_schema.py — distinct WOCLASS/STATUS/
-- WORKTYPE, sites, asset classes, custom columns, module presence + ACTIVITY
-- (recency + cross-table population), customization signals (workflows,
-- calendars, currency, criticality scheme), PLUSG, stats. Everything is
-- READ-ONLY.
--
-- BIND THESE PARAMETERS in SQL Editor before running:
--   :catalog          → customer's UC catalog (e.g. eam)
--   :silver_schema    → Silver schema with the Maximo MBOs (e.g. maximo_silver)
--
-- Tables are referenced via IDENTIFIER(...) for portable parameter binding;
-- WHERE-clause string positions use the parameter markers directly.
--
-- Maximo mirrors are often lowercase and sometimes RENAMED (WOSTATUS->wo_status,
-- LABTRANS->labor_trans). Use Section 1 to see real names, then adjust the
-- per-table sections as needed.
--
-- Probes may fail with "table not found" when the underlying MBO is not ingested
-- into this customer's Silver layer. That's expected signal (NOT_INGESTED) —
-- skip the failing probe and move on.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Section 1: Tables present (+ flag PLUSG / O&G add-on)
-- -----------------------------------------------------------------------------
SELECT table_name,
       CASE WHEN lower(table_name) LIKE 'plusg%' THEN 'PLUSG (O&G)' ELSE '' END AS note
FROM   system.information_schema.tables
WHERE  table_catalog = :catalog AND table_schema = :silver_schema
ORDER  BY table_name;


-- -----------------------------------------------------------------------------
-- Section 2: Columns of core MBOs — for CUSTOM-COLUMN detection
-- -----------------------------------------------------------------------------
-- Any column here NOT in the documented base columns (scripts/maximo_comments.json)
-- is a custom/extension column to ask about in the interview.
SELECT table_name, column_name, data_type
FROM   system.information_schema.columns
WHERE  table_catalog = :catalog AND table_schema = :silver_schema
  AND  lower(table_name) IN ('workorder', 'asset', 'locations')
ORDER  BY table_name, ordinal_position;


-- -----------------------------------------------------------------------------
-- Section 3: WORKORDER distinct dimensions
-- -----------------------------------------------------------------------------
SELECT 'WOCLASS'  AS dim, CAST(woclass  AS STRING) AS value, COUNT(*) AS n
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.workorder')
  GROUP BY woclass
UNION ALL SELECT 'STATUS',   CAST(status   AS STRING), COUNT(*)
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.workorder')
  GROUP BY status
UNION ALL SELECT 'WORKTYPE', CAST(worktype AS STRING), COUNT(*)
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.workorder')
  GROUP BY worktype
UNION ALL SELECT 'SITEID',   CAST(siteid   AS STRING), COUNT(*)
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.workorder')
  GROUP BY siteid
ORDER BY dim, n DESC;


-- -----------------------------------------------------------------------------
-- Section 3b: PROPOSED open-status set = every STATUS except COMP/CLOSE/CAN
-- -----------------------------------------------------------------------------
-- PROPOSAL only — the customer confirms the official "open" set in interview Q1.
SELECT DISTINCT status AS proposed_open_status
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.workorder')
WHERE  upper(status) NOT IN ('COMP', 'CLOSE', 'CAN')
ORDER  BY 1;


-- -----------------------------------------------------------------------------
-- Section 3c: SYNONYMDOMAIN renamings
-- -----------------------------------------------------------------------------
-- Status columns store the customer-renamable VALUE, not internal MAXVALUE
-- (see maximo-overview status-is-a-synonym-domain gotcha). Rows where
-- VALUE <> MAXVALUE are renamings to record in the glossary.
-- (Skip if SYNONYMDOMAIN was not mirrored into Silver.)
SELECT domainid, maxvalue, value
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.synonymdomain')
WHERE  upper(domainid) IN ('WOSTATUS','ASSETSTATUS','LOCSTATUS','SRSTATUS')
ORDER  BY domainid, maxvalue;


-- -----------------------------------------------------------------------------
-- Section 3d: HISTORYFLAG distribution
-- -----------------------------------------------------------------------------
-- Records at a final status get HISTORYFLAG=1 and drop out of standard List
-- views (see maximo-overview); completion/trend metrics must include them.
SELECT historyflag, COUNT(*) AS n
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.workorder')
GROUP  BY historyflag
ORDER  BY historyflag;


-- -----------------------------------------------------------------------------
-- Section 4: ASSET class distribution
-- -----------------------------------------------------------------------------
SELECT classstructureid, COUNT(*) AS n
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.asset')
GROUP  BY classstructureid
ORDER  BY n DESC;


-- -----------------------------------------------------------------------------
-- Section 5: Module presence — which indicator tables are ingested?
-- -----------------------------------------------------------------------------
SELECT lower(table_name) AS present_table
FROM   system.information_schema.tables
WHERE  table_catalog = :catalog AND table_schema = :silver_schema
  AND  lower(table_name) IN (
        'workorder','wostatus','labtrans','pm','pmsequence',
        'failurereport','failurecode',
        'inventory','invbalances','invuse','item',
        'po','poline','pr','invoice','invoiceline','companies',
        'sr','ticket','incident','problem',
        'assetmeter','meterreading',
        'wfinstance','wfassignment','wfprocess',
        'escalation','calendar','workperiod','assignment',
        'assetspec','classstructure','locancestor','assetancestor',
        'plusgpermitwork','plusgincperson','plusgrelatedrec'
       )
ORDER  BY 1;


-- -----------------------------------------------------------------------------
-- Section 6: Row counts per core table
-- -----------------------------------------------------------------------------
SELECT 'workorder' AS tbl, COUNT(*) AS n
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.workorder')
UNION ALL SELECT 'asset',     COUNT(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asset')
UNION ALL SELECT 'locations', COUNT(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.locations');


-- =============================================================================
-- MODULE ACTIVITY DETECTION (NEW IN v0.3.0)
-- =============================================================================
-- The following sections feed the 4-verdict Module Activity Heatmap
-- (ACTIVE / DORMANT / NOT_INGESTED / INSUFFICIENT_DATA). Run each one against
-- the corresponding module's primary table. Skip queries whose tables aren't
-- ingested (the absence IS the NOT_INGESTED signal).
--
-- Verdict rules:
--   ACTIVE             — table present, rows > 0, MAX(date) within 365 days,
--                        HISTORYFLAG=0 rows dominant
--   DORMANT            — table present, rows > 0, MAX(date) > 365 days OR
--                        mostly HISTORYFLAG=1
--   NOT_INGESTED       — table absent from UC (see Section 5)
--   INSUFFICIENT_DATA  — table present but no datetime column / sparse data
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Section 7: Recency MAX(date) per module's primary table (HISTORYFLAG-aware)
-- -----------------------------------------------------------------------------
-- Activity threshold: 365 days. Interpret MAX(date) in the app-server timezone
-- captured in setup Question 3.

-- 7.1 Work Management — WORKORDER
SELECT 'work_management' AS module,
       'WORKORDER.STATUSDATE' AS date_column,
       MAX(statusdate) AS most_recent,
       COUNT(*) AS rows_total,
       SUM(CASE WHEN historyflag = 0 THEN 1 ELSE 0 END) AS rows_current,
       datediff(DAY, MAX(statusdate), current_date()) AS days_since_max
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.workorder');

-- 7.2 Preventive Maintenance — PM
SELECT 'preventive_maintenance' AS module,
       'PM.LASTCOMPDATE' AS date_column,
       MAX(lastcompdate) AS most_recent,
       COUNT(*) AS rows_total,
       datediff(DAY, MAX(lastcompdate), current_date()) AS days_since_max
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.pm');

-- 7.3 Reliability / Failure — FAILUREREPORT joined to WORKORDER.ACTFINISH
SELECT 'reliability' AS module,
       'FAILUREREPORT (via WO.ACTFINISH)' AS date_column,
       MAX(w.actfinish) AS most_recent,
       COUNT(*) AS rows_total,
       datediff(DAY, MAX(w.actfinish), current_date()) AS days_since_max
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.failurereport') fr
LEFT JOIN IDENTIFIER(:catalog || '.' || :silver_schema || '.workorder') w
       ON fr.wonum = w.wonum AND fr.siteid = w.siteid;

-- 7.4 Inventory — INVUSE
SELECT 'inventory' AS module,
       'INVUSE.TRANSDATE' AS date_column,
       MAX(transdate) AS most_recent,
       COUNT(*) AS rows_total,
       datediff(DAY, MAX(transdate), current_date()) AS days_since_max
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.invuse');

-- 7.5 Procurement — PO
SELECT 'procurement' AS module,
       'PO.STATUSDATE' AS date_column,
       MAX(statusdate) AS most_recent,
       COUNT(*) AS rows_total,
       datediff(DAY, MAX(statusdate), current_date()) AS days_since_max
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.po');

-- 7.6 Service Desk — TICKET (or SR if TICKET absent)
SELECT 'service_desk' AS module,
       'TICKET.STATUSDATE' AS date_column,
       MAX(statusdate) AS most_recent,
       COUNT(*) AS rows_total,
       datediff(DAY, MAX(statusdate), current_date()) AS days_since_max
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.ticket');

-- 7.7 HSE (PLUSG) — plusgpermitwork
SELECT 'hse' AS module,
       'plusgpermitwork.REPORTDATE' AS date_column,
       MAX(reportdate) AS most_recent,
       COUNT(*) AS rows_total,
       datediff(DAY, MAX(reportdate), current_date()) AS days_since_max
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.plusgpermitwork');

-- 7.8 Asset Integrity — METERREADING
SELECT 'asset_integrity' AS module,
       'METERREADING.READINGDATE' AS date_column,
       MAX(readingdate) AS most_recent,
       COUNT(*) AS rows_total,
       datediff(DAY, MAX(readingdate), current_date()) AS days_since_max
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.meterreading');

-- 7.9 Workflow & Approvals — WFINSTANCE
SELECT 'workflow_and_approvals' AS module,
       'WFINSTANCE.STARTDATE' AS date_column,
       MAX(startdate) AS most_recent,
       COUNT(*) AS rows_total,
       datediff(DAY, MAX(startdate), current_date()) AS days_since_max
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.wfinstance');

-- 7.10 Labor Resources — LABTRANS
SELECT 'labor_resources' AS module,
       'LABTRANS.STARTDATE' AS date_column,
       MAX(startdate) AS most_recent,
       COUNT(*) AS rows_total,
       datediff(DAY, MAX(startdate), current_date()) AS days_since_max
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.labtrans');


-- -----------------------------------------------------------------------------
-- Section 8: Cross-table field-population probes
-- -----------------------------------------------------------------------------
-- Which features are exercised (not just which tables exist). Low values
-- indicate the capability is barely used — surface as glossary caveats.
SELECT
    COUNT(*) AS rows_total,
    ROUND(100.0 * SUM(CASE WHEN pmnum       IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_with_pmnum,
    ROUND(100.0 * SUM(CASE WHEN failurecode IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_with_failurecode,
    ROUND(100.0 * SUM(CASE WHEN crewid      IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_with_crewid,
    ROUND(100.0 * SUM(CASE WHEN jpnum       IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_with_jpnum,
    ROUND(100.0 * SUM(CASE WHEN assetnum    IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_with_assetnum,
    ROUND(100.0 * SUM(CASE WHEN location    IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_with_location
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.workorder');


-- -----------------------------------------------------------------------------
-- Section 9: WO assignment model — % populated for ownership fields
-- -----------------------------------------------------------------------------
-- The dominant pattern signals the customer's assignment model:
--   LEAD-heavy        → single-owner
--   CREWID-heavy      → crew-based
--   ASSIGNMENT-heavy  → pool/assignment (separate ASSIGNMENT rows per WO)
SELECT
    COUNT(*) AS rows_total,
    ROUND(100.0 * SUM(CASE WHEN lead       IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_lead,
    ROUND(100.0 * SUM(CASE WHEN supervisor IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_supervisor,
    ROUND(100.0 * SUM(CASE WHEN crewid     IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_crewid,
    ROUND(100.0 * SUM(CASE WHEN ownergroup IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_ownergroup
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.workorder');

-- ASSIGNMENT rows per WO ratio (when ASSIGNMENT table is ingested)
SELECT
    (SELECT COUNT(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.assignment')) AS assignment_rows,
    (SELECT COUNT(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.workorder'))  AS workorder_rows,
    ROUND(
      1.0 * (SELECT COUNT(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.assignment'))
          / NULLIF((SELECT COUNT(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.workorder')), 0),
      2
    ) AS assignment_per_workorder;


-- -----------------------------------------------------------------------------
-- Section 10: Asset criticality distribution (reveals the scheme)
-- -----------------------------------------------------------------------------
-- Asset criticality varies by customer: 1-5, 1-10, custom labels, or bespoke.
-- The distinct values + counts reveal the scheme to confirm in interview.
SELECT criticality, COUNT(*) AS n
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.asset')
GROUP  BY criticality
ORDER  BY criticality NULLS LAST;


-- -----------------------------------------------------------------------------
-- Section 11: Failure-code hierarchy depth + scheme usage
-- -----------------------------------------------------------------------------
-- Customers use FAILURECODE at different levels (PROBLEM-only / PROBLEM-CAUSE /
-- full PROBLEM-CAUSE-REMEDY). Hierarchy depth + TYPE distribution reveal which.
SELECT type, COUNT(*) AS n
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.failurecode')
GROUP  BY type
ORDER  BY n DESC;

-- Hierarchy depth via recursive CTE
WITH RECURSIVE fc AS (
    SELECT failurecode, parent, 0 AS depth
    FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.failurecode')
    WHERE  parent IS NULL
    UNION ALL
    SELECT c.failurecode, c.parent, fc.depth + 1
    FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.failurecode') c
    JOIN   fc ON c.parent = fc.failurecode
    WHERE  fc.depth < 20
)
SELECT MAX(depth) AS max_failure_code_depth, COUNT(*) AS total_codes
FROM   fc;


-- -----------------------------------------------------------------------------
-- Section 12: Custom workflows (WFPROCESS)
-- -----------------------------------------------------------------------------
-- Active workflow definitions + which business objects they cover.
-- Triggers the workflow-scope interview question (Tier 2).
SELECT objectname, COUNT(*) AS active_workflows
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.wfprocess')
WHERE  active = 1
GROUP  BY objectname
ORDER  BY active_workflows DESC;


-- -----------------------------------------------------------------------------
-- Section 13: Custom escalations
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS active_escalations
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.escalation')
WHERE  active = 1;


-- -----------------------------------------------------------------------------
-- Section 14: Custom calendars
-- -----------------------------------------------------------------------------
-- Drives capacity-vs-workload analytics in pm-planning and labor-resources.
SELECT COUNT(DISTINCT calnum) AS distinct_calendars,
       COUNT(*)               AS calendar_rows
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.calendar');

-- WORKPERIOD recency — confirms calendars are being maintained forward
SELECT MAX(shiftstart)                                AS most_recent_shift_start,
       datediff(DAY, MAX(shiftstart), current_date()) AS days_since_max_shift
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.workperiod');


-- -----------------------------------------------------------------------------
-- Section 15: Currency — distinct codes
-- -----------------------------------------------------------------------------
-- >1 distinct currency triggers the multi-currency interview question (Tier 1).
SELECT 'PO' AS source, COUNT(DISTINCT currencycode) AS distinct_currencies
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.po')
UNION ALL SELECT 'INVOICE',   COUNT(DISTINCT currencycode)
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.invoice')
UNION ALL SELECT 'COMPANIES', COUNT(DISTINCT currencycode)
  FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.companies');


-- -----------------------------------------------------------------------------
-- Section 16: Stockroom strategy (when inventory is in scope)
-- -----------------------------------------------------------------------------
SELECT COUNT(DISTINCT location) AS distinct_stockrooms,
       COUNT(*)                 AS invbalances_rows
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.invbalances');


-- -----------------------------------------------------------------------------
-- Section 17: Asset spec usage (PLUSC / integrity workflows)
-- -----------------------------------------------------------------------------
SELECT classstructureid, COUNT(*) AS spec_rows
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.assetspec')
GROUP  BY classstructureid
ORDER  BY spec_rows DESC;
