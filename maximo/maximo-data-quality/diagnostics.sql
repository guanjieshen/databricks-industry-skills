-- =============================================================================
-- Maximo Data Quality — Diagnostic Probes
-- =============================================================================
-- Run individually based on the symptom. See common_issues.md for what each
-- finding means and the remediation pattern.
-- Substitute {{maximo_catalog}}.{{maximo_schema}} with the customer's Silver schema.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Probe 1 — WOSTATUS coverage
-- Symptom: WOSTATUS sparse / current status doesn't match latest WOSTATUS row
-- -----------------------------------------------------------------------------
-- For each WO, count status-history rows. WOs with zero history are suspicious.
-- Compare current WORKORDER.STATUS to the most recent WOSTATUS row.
SELECT
    w.wonum, w.siteid,
    w.status                                AS workorder_current,
    w.statusdate                            AS workorder_status_date,
    s.latest_status                         AS wostatus_latest,
    s.latest_changedate                     AS wostatus_latest_date,
    s.history_count
FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER w
LEFT JOIN (
    SELECT
        wonum, siteid,
        COUNT(*)                          AS history_count,
        MAX(changedate)                   AS latest_changedate,
        MAX_BY(status, changedate)        AS latest_status
    FROM {{maximo_catalog}}.{{maximo_schema}}.WOSTATUS
    GROUP BY wonum, siteid
) s ON s.wonum = w.wonum AND s.siteid = w.siteid
WHERE w.woclass = 'WORKORDER'
  AND (s.history_count IS NULL OR s.latest_status != w.status)
LIMIT 50;
-- If many rows return with history_count = NULL: REST-API ingestion isn't capturing history (see common_issues.md #1).
-- If latest_status != workorder_current: latest transition didn't replicate or status was changed via REST without writing WOSTATUS.


-- -----------------------------------------------------------------------------
-- Probe 2 — WONUM uniqueness within SITEID
-- Symptom: Same WONUM appears twice
-- -----------------------------------------------------------------------------
SELECT wonum, siteid, COUNT(*) AS dup_count
FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER
GROUP BY wonum, siteid
HAVING COUNT(*) > 1
ORDER BY dup_count DESC
LIMIT 20;
-- WORKORDER (WONUM, SITEID) should be unique. Duplicates indicate ingestion idempotency bug.


-- -----------------------------------------------------------------------------
-- Probe 3 — ISTASK / PARENT roll-up integrity
-- Symptom: Labor / cost totals double-counted
-- -----------------------------------------------------------------------------
-- Tasks (ISTASK=1) should have a PARENT pointing at a real header (ISTASK=0).
-- Orphan tasks indicate broken hierarchy or filtering bug.
SELECT
    COUNT(*)                                                AS total_rows,
    SUM(CASE WHEN istask = 1 THEN 1 ELSE 0 END)             AS task_rows,
    SUM(CASE WHEN istask = 0 THEN 1 ELSE 0 END)             AS header_rows,
    SUM(CASE WHEN istask = 1
              AND parent IS NULL THEN 1 ELSE 0 END)         AS task_without_parent,
    SUM(CASE WHEN istask = 1
              AND parent NOT IN (
                  SELECT wonum
                  FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER w2
                  WHERE w2.siteid = w.siteid
              ) THEN 1 ELSE 0 END)                          AS task_orphan_parent
FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER w
WHERE woclass = 'WORKORDER';


-- -----------------------------------------------------------------------------
-- Probe 4 — WOCLASS filter sanity
-- Symptom: WO counts feel inflated
-- -----------------------------------------------------------------------------
-- WORKORDER table holds multiple classes. If a query forgets WOCLASS, totals balloon.
SELECT woclass, COUNT(*) AS row_count
FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER
GROUP BY woclass
ORDER BY row_count DESC;
-- Expect 'WORKORDER' to dominate. PM, CHANGE, RELEASE, ACTIVITY each non-zero.


-- -----------------------------------------------------------------------------
-- Probe 5 — Orphan check (LABTRANS / WPLABOR / WPMATERIAL)
-- Symptom: Labor or material lines without a matching WO
-- -----------------------------------------------------------------------------
SELECT
    'LABTRANS' AS source_table,
    COUNT(*) AS orphan_count
FROM {{maximo_catalog}}.{{maximo_schema}}.LABTRANS lt
LEFT JOIN {{maximo_catalog}}.{{maximo_schema}}.WORKORDER w
    ON w.wonum = lt.wonum AND w.siteid = lt.siteid
WHERE w.wonum IS NULL

UNION ALL

SELECT 'WPLABOR', COUNT(*)
FROM {{maximo_catalog}}.{{maximo_schema}}.WPLABOR wp
LEFT JOIN {{maximo_catalog}}.{{maximo_schema}}.WORKORDER w
    ON w.wonum = wp.wonum AND w.siteid = wp.siteid
WHERE w.wonum IS NULL

UNION ALL

SELECT 'WPMATERIAL', COUNT(*)
FROM {{maximo_catalog}}.{{maximo_schema}}.WPMATERIAL wp
LEFT JOIN {{maximo_catalog}}.{{maximo_schema}}.WORKORDER w
    ON w.wonum = wp.wonum AND w.siteid = wp.siteid
WHERE w.wonum IS NULL;


-- -----------------------------------------------------------------------------
-- Probe 6 — Hierarchy orphans (ASSET / LOCATIONS)
-- Symptom: Asset rolls up to a parent that doesn't exist
-- -----------------------------------------------------------------------------
SELECT
    a.assetnum, a.siteid, a.parent
FROM {{maximo_catalog}}.{{maximo_schema}}.ASSET a
LEFT JOIN {{maximo_catalog}}.{{maximo_schema}}.ASSET p
    ON p.assetnum = a.parent AND p.siteid = a.siteid
WHERE a.parent IS NOT NULL
  AND p.assetnum IS NULL
LIMIT 50;


-- -----------------------------------------------------------------------------
-- Probe 7 — Cross-site duplicates (master-data drift)
-- Symptom: Same asset/location name on multiple sites — intended or not?
-- -----------------------------------------------------------------------------
SELECT
    description,
    COUNT(DISTINCT siteid) AS site_count,
    array_agg(DISTINCT siteid) AS sites,
    array_agg(DISTINCT assetnum) AS assetnums
FROM {{maximo_catalog}}.{{maximo_schema}}.ASSET
WHERE description IS NOT NULL
GROUP BY description
HAVING COUNT(DISTINCT siteid) > 1
ORDER BY site_count DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- Probe 8 — Date sanity
-- Symptom: Time-based analytics looking off
-- -----------------------------------------------------------------------------
SELECT
    'ACTFINISH before REPORTDATE'                       AS issue,
    COUNT(*)                                            AS row_count
FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER
WHERE actfinish IS NOT NULL AND reportdate IS NOT NULL
  AND actfinish < reportdate

UNION ALL

SELECT 'STATUSDATE before REPORTDATE',
       COUNT(*)
FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER
WHERE statusdate < reportdate

UNION ALL

SELECT 'REPORTDATE in the future',
       COUNT(*)
FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER
WHERE reportdate > current_timestamp();


-- -----------------------------------------------------------------------------
-- Probe 9 — PM generation health
-- Symptom: PM compliance suddenly dropped
-- -----------------------------------------------------------------------------
-- Are PMs generating WOs? Look for PMs that are due but have no recent WO.
SELECT
    pm.pmnum, pm.siteid, pm.nextdate, pm.laststartdate,
    COUNT(w.wonum) AS recent_wo_count
FROM {{maximo_catalog}}.{{maximo_schema}}.PM pm
LEFT JOIN {{maximo_catalog}}.{{maximo_schema}}.WORKORDER w
    ON w.pmnum = pm.pmnum AND w.siteid = pm.siteid
   AND w.reportdate >= current_date() - INTERVAL 90 DAYS
WHERE pm.nextdate < current_date()
GROUP BY pm.pmnum, pm.siteid, pm.nextdate, pm.laststartdate
HAVING COUNT(w.wonum) = 0
ORDER BY pm.nextdate
LIMIT 50;


-- -----------------------------------------------------------------------------
-- Probe 10 — Custom column population
-- Symptom: Custom column unexpectedly NULL for many rows
-- -----------------------------------------------------------------------------
-- Substitute the column you're checking.
SELECT
    COUNT(*)                                                AS total_rows,
    SUM(CASE WHEN {{custom_column}} IS NULL
             THEN 1 ELSE 0 END)                             AS null_count,
    SUM(CASE WHEN {{custom_column}} IS NULL
             THEN 1 ELSE 0 END) * 100.0 / COUNT(*)          AS null_pct
FROM {{maximo_catalog}}.{{maximo_schema}}.WORKORDER
WHERE woclass = 'WORKORDER'
  AND reportdate >= current_date() - INTERVAL 365 DAYS;
