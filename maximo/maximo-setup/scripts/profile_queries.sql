-- maximo-setup · Phase 0 profiling — PORTABLE SQL path.
-- Use this when Genie Code is attached to a SQL warehouse (e.g. started from the
-- Unity Catalog data page) and cannot run Python/CLI. It returns the same
-- data-provable facts as scripts/introspect_schema.py — distinct WOCLASS/STATUS/
-- WORKTYPE, sites, asset classes, custom columns, module presence, PLUSG, stats.
-- Everything here is READ-ONLY. Substitute the two placeholders:
--   {{catalog}}.{{schema}}   e.g. classic_stable_ccu63h.cmms_silver
-- Maximo mirrors are often lowercase and sometimes RENAMED (WOSTATUS->wo_status,
-- LABTRANS->labor_trans). Use query 1 to see real names, then adjust 3-6 if needed.

-- 1) Tables present (+ flag whether the O&G PLUSG add-on is installed)
SELECT table_name,
       CASE WHEN lower(table_name) LIKE 'plusg%' THEN 'PLUSG (O&G)' ELSE '' END AS note
FROM   system.information_schema.tables
WHERE  table_catalog = '{{catalog}}' AND table_schema = '{{schema}}'
ORDER  BY table_name;

-- 2) Columns of the core MBOs — for CUSTOM-COLUMN detection.
--    Any column here NOT in the documented base columns (scripts/maximo_comments.json)
--    is a custom/extension column to ask about in the interview.
SELECT table_name, column_name, data_type
FROM   system.information_schema.columns
WHERE  table_catalog = '{{catalog}}' AND table_schema = '{{schema}}'
  AND  lower(table_name) IN ('workorder', 'asset', 'locations')
ORDER  BY table_name, ordinal_position;

-- 3) WORKORDER distinct dimensions (adjust table name if renamed)
SELECT 'WOCLASS'  AS dim, CAST(woclass  AS STRING) AS value, COUNT(*) AS n FROM {{catalog}}.{{schema}}.workorder GROUP BY woclass
UNION ALL SELECT 'STATUS',   CAST(status   AS STRING), COUNT(*) FROM {{catalog}}.{{schema}}.workorder GROUP BY status
UNION ALL SELECT 'WORKTYPE', CAST(worktype AS STRING), COUNT(*) FROM {{catalog}}.{{schema}}.workorder GROUP BY worktype
UNION ALL SELECT 'SITEID',   CAST(siteid   AS STRING), COUNT(*) FROM {{catalog}}.{{schema}}.workorder GROUP BY siteid
ORDER BY dim, n DESC;

-- 3b) PROPOSED open-status set = every STATUS except COMP/CLOSE/CAN.
--     This is only a PROPOSAL — the customer confirms the official "open" set.
SELECT DISTINCT status AS proposed_open_status
FROM   {{catalog}}.{{schema}}.workorder
WHERE  upper(status) NOT IN ('COMP', 'CLOSE', 'CAN')
ORDER  BY 1;

-- 4) ASSET class list (map to business names in the interview)
SELECT classstructureid, COUNT(*) AS n
FROM   {{catalog}}.{{schema}}.asset
GROUP  BY classstructureid
ORDER  BY n DESC;

-- 5) Module presence — which indicator tables exist (and PLUSG).
--    work_management=WORKORDER, preventive_maintenance=PM, inventory=INVENTORY/INVBALANCES,
--    procurement=PO/PR/INVOICE, service_desk=SR/TICKET, asset_integrity=ASSETMETER/METERREADING,
--    hse=INCIDENT/PLUSGPERMITWORK. Absent indicator tables usually mean "owned by another system".
SELECT lower(table_name) AS present_table
FROM   system.information_schema.tables
WHERE  table_catalog = '{{catalog}}' AND table_schema = '{{schema}}'
  AND  lower(table_name) IN ('workorder','pm','inventory','invbalances','po','pr','invoice',
                             'sr','ticket','assetmeter','meterreading','incident','plusgpermitwork')
ORDER  BY 1;

-- 6) Row count + sparsity check per core table (e.g. is FAILUREREPORT/failure coding usable?)
SELECT 'workorder' AS tbl, COUNT(*) AS rows FROM {{catalog}}.{{schema}}.workorder
UNION ALL SELECT 'asset', COUNT(*) FROM {{catalog}}.{{schema}}.asset
UNION ALL SELECT 'locations', COUNT(*) FROM {{catalog}}.{{schema}}.locations;
