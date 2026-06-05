-- Diagnostic probes for <source> "this number looks wrong" investigations.
-- Run probe-by-probe per the playbook in SKILL.md. Substitute :catalog and :schema.

-- ─────────────────────────────────────────────────────────────────────────────
-- Probe 1: Bronze row counts. Compare against source-system UI export.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 'EXAMPLE_TABLE' AS table_name, COUNT(*) AS row_count
FROM   :catalog.:schema.EXAMPLE_TABLE
UNION  ALL
SELECT 'EXAMPLE_HISTORY_TABLE', COUNT(*)
FROM   :catalog.:schema.EXAMPLE_HISTORY_TABLE;

-- ─────────────────────────────────────────────────────────────────────────────
-- Probe 2: REST-API ingestion gap.
-- WORKORDER.STATUS changes but no matching WOSTATUS row → REST PATCH ingestion.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT w.wonum, w.siteid, w.status AS current_status,
       MAX(s.changedate) AS last_wostatus_date,
       w.statusdate     AS workorder_statusdate
FROM   :catalog.:schema.WORKORDER w
LEFT   JOIN :catalog.:schema.WOSTATUS s
       ON  s.wonum = w.wonum AND s.siteid = w.siteid
GROUP  BY w.wonum, w.siteid, w.status, w.statusdate
HAVING MAX(s.changedate) IS NULL
   OR  MAX(s.changedate) < w.statusdate - INTERVAL 1 DAY
LIMIT  20;

-- ─────────────────────────────────────────────────────────────────────────────
-- Probe 3: Composite-key cross-product detection.
-- Same business key at different sites — joining without SITEID inflates.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT wonum, COUNT(DISTINCT siteid) AS site_count
FROM   :catalog.:schema.WORKORDER
GROUP  BY wonum
HAVING COUNT(DISTINCT siteid) > 1
LIMIT  20;

-- (add probes 4-7 per the SKILL.md playbook)
