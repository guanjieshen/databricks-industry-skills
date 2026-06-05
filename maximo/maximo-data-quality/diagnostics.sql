-- =============================================================================
-- Maximo Data Quality — Diagnostic Probes
-- =============================================================================
-- Run individually based on the symptom. See common_issues.md for what each
-- finding means and the remediation pattern.
--
-- Parameters (Databricks-native :param syntax; bound at execution time):
--   :catalog        Unity Catalog catalog holding the Maximo Silver layer
--   :schema         Silver schema (probes assume a single Silver schema)
--   :custom_column  (Probe 10 only) the column being checked
--
-- Universal mechanics applied below (canonical home: maximo-overview):
--   SITEID composite keys, WOCLASS filtering, ISTASK tasks-vs-child-WOs,
--   status-is-a-synonym-domain (SYNONYMDOMAIN), HISTORYFLAG hiding closed
--   records, app-server-timezone datetimes. This file APPLIES them; it does
--   not re-teach them.
-- =============================================================================

-- Contents
--   Probe 1  — WOSTATUS coverage (current status vs history; HISTORYFLAG-aware)
--   Probe 2  — WONUM uniqueness within SITEID
--   Probe 3  — ISTASK / PARENT roll-up integrity
--   Probe 4  — WOCLASS filter sanity (+ status synonym resolution)
--   Probe 5  — Orphan check (LABTRANS / WPLABOR / WPMATERIAL)
--   Probe 6  — Hierarchy orphans (ASSET / LOCATIONS)
--   Probe 7  — Cross-site duplicates (master-data drift)
--   Probe 8  — Date sanity (timezone-aware caveat)
--   Probe 9  — PM generation health
--   Probe 10 — Custom column population
--   Probe 11 — Labor master integrity (composes with maximo-labor-resources)
--   Probe 12 — Closure-table integrity (composes with maximo-asset-hierarchy)
--   Probe 13 — Qualification expiry gaps (composes with maximo-labor-resources)


-- -----------------------------------------------------------------------------
-- Probe 1 — WOSTATUS coverage
-- Symptom: WOSTATUS sparse / current status doesn't match latest WOSTATUS row
-- -----------------------------------------------------------------------------
-- For each WO, count status-history rows. WOs with zero history are suspicious.
-- Compare current WORKORDER.STATUS to the most recent WOSTATUS row.
-- NOTE: include HISTORYFLAG so a closed (HISTORYFLAG=1) WO isn't mistaken for a
-- "missing" record — closed WOs are expected to drop out of standard List views
-- (see maximo-overview HISTORYFLAG gotcha). STATUS/latest_status are synonym
-- values (SYNONYMDOMAIN.VALUE), so a difference can be a rename, not a defect.
SELECT
    w.wonum, w.siteid,
    w.historyflag,
    w.status                                AS workorder_current,
    w.statusdate                            AS workorder_status_date,
    s.latest_status                         AS wostatus_latest,
    s.latest_changedate                     AS wostatus_latest_date,
    s.history_count
FROM :catalog.:schema.WORKORDER w
LEFT JOIN (
    SELECT
        wonum, siteid,
        COUNT(*)                          AS history_count,
        MAX(changedate)                   AS latest_changedate,
        MAX_BY(status, changedate)        AS latest_status
    FROM :catalog.:schema.WOSTATUS
    GROUP BY wonum, siteid
) s ON s.wonum = w.wonum AND s.siteid = w.siteid
WHERE w.woclass = 'WORKORDER'
  AND (s.history_count IS NULL OR s.latest_status != w.status)
LIMIT 50;
-- If many rows return with history_count = NULL: REST-API ingestion isn't capturing history (see common_issues.md #1).
-- If latest_status != workorder_current: latest transition didn't replicate, status was changed via REST without writing WOSTATUS, OR the two columns use different synonyms — resolve both via SYNONYMDOMAIN before concluding a defect.


-- -----------------------------------------------------------------------------
-- Probe 2 — WONUM uniqueness within SITEID
-- Symptom: Same WONUM appears twice
-- -----------------------------------------------------------------------------
SELECT wonum, siteid, COUNT(*) AS dup_count
FROM :catalog.:schema.WORKORDER
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
-- Orphan tasks indicate broken hierarchy or filtering bug. PARENT is mutable
-- (work packages regroup WOs), so a changed parent isn't itself a defect.
SELECT
    COUNT(*)                                                AS total_rows,
    SUM(CASE WHEN istask = 1 THEN 1 ELSE 0 END)             AS task_rows,
    SUM(CASE WHEN istask = 0 THEN 1 ELSE 0 END)             AS header_rows,
    SUM(CASE WHEN istask = 1
              AND parent IS NULL THEN 1 ELSE 0 END)         AS task_without_parent,
    SUM(CASE WHEN istask = 1
              AND parent NOT IN (
                  SELECT wonum
                  FROM :catalog.:schema.WORKORDER w2
                  WHERE w2.siteid = w.siteid
              ) THEN 1 ELSE 0 END)                          AS task_orphan_parent
FROM :catalog.:schema.WORKORDER w
WHERE woclass = 'WORKORDER';


-- -----------------------------------------------------------------------------
-- Probe 4 — WOCLASS filter sanity
-- Symptom: WO counts feel inflated
-- -----------------------------------------------------------------------------
-- WORKORDER table holds multiple classes. If a query forgets WOCLASS, totals balloon.
SELECT woclass, COUNT(*) AS row_count
FROM :catalog.:schema.WORKORDER
GROUP BY woclass
ORDER BY row_count DESC;
-- Expect 'WORKORDER' to dominate. PM, CHANGE, RELEASE, ACTIVITY each non-zero.
-- If a count is inflated even WITH the WOCLASS filter, check whether the user's
-- "open"/"closed" status set was built from literals that don't match this
-- deployment's synonyms — resolve the intended set via SYNONYMDOMAIN
-- (DOMAINID='WOSTATUS') rather than hard-coded status strings.


-- -----------------------------------------------------------------------------
-- Probe 5 — Orphan check (LABTRANS / WPLABOR / WPMATERIAL)
-- Symptom: Labor or material lines without a matching WO
-- -----------------------------------------------------------------------------
SELECT
    'LABTRANS' AS source_table,
    COUNT(*) AS orphan_count
FROM :catalog.:schema.LABTRANS lt
LEFT JOIN :catalog.:schema.WORKORDER w
    ON w.wonum = lt.wonum AND w.siteid = lt.siteid
WHERE w.wonum IS NULL

UNION ALL

SELECT 'WPLABOR', COUNT(*)
FROM :catalog.:schema.WPLABOR wp
LEFT JOIN :catalog.:schema.WORKORDER w
    ON w.wonum = wp.wonum AND w.siteid = wp.siteid
WHERE w.wonum IS NULL

UNION ALL

SELECT 'WPMATERIAL', COUNT(*)
FROM :catalog.:schema.WPMATERIAL wp
LEFT JOIN :catalog.:schema.WORKORDER w
    ON w.wonum = wp.wonum AND w.siteid = wp.siteid
WHERE w.wonum IS NULL;
-- Before calling these orphans, confirm the WORKORDER load includes closed WOs
-- (HISTORYFLAG=1). If the WORKORDER feed silently drops history records, live
-- LABTRANS rows will look orphaned when their WO simply moved to history.


-- -----------------------------------------------------------------------------
-- Probe 6 — Hierarchy orphans (ASSET / LOCATIONS)
-- Symptom: Asset rolls up to a parent that doesn't exist
-- -----------------------------------------------------------------------------
SELECT
    a.assetnum, a.siteid, a.parent
FROM :catalog.:schema.ASSET a
LEFT JOIN :catalog.:schema.ASSET p
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
FROM :catalog.:schema.ASSET
WHERE description IS NOT NULL
GROUP BY description
HAVING COUNT(DISTINCT siteid) > 1
ORDER BY site_count DESC
LIMIT 20;
-- Same name across SITEIDs is often intentional (shared asset designs). Confirm
-- with the customer; maximo-setup's workspace glossary should record exceptions.


-- -----------------------------------------------------------------------------
-- Probe 8 — Date sanity
-- Symptom: Time-based analytics looking off
-- -----------------------------------------------------------------------------
-- CAUTION: Maximo datetimes are stored in the APP-SERVER timezone (often UTC,
-- but that is a config choice — not guaranteed) and displayed in the user TZ.
-- A "wrong" date is frequently a TZ-display difference, not corruption. Confirm
-- the deployment's app-server TZ (maximo-setup fact) before flagging rows.
SELECT
    'ACTFINISH before REPORTDATE'                       AS issue,
    COUNT(*)                                            AS row_count
FROM :catalog.:schema.WORKORDER
WHERE actfinish IS NOT NULL AND reportdate IS NOT NULL
  AND actfinish < reportdate

UNION ALL

SELECT 'STATUSDATE before REPORTDATE',
       COUNT(*)
FROM :catalog.:schema.WORKORDER
WHERE statusdate < reportdate

UNION ALL

SELECT 'REPORTDATE in the future',
       COUNT(*)
FROM :catalog.:schema.WORKORDER
WHERE reportdate > current_timestamp();


-- -----------------------------------------------------------------------------
-- Probe 9 — PM generation health
-- Symptom: PM compliance suddenly dropped
-- -----------------------------------------------------------------------------
-- Are PMs generating WOs? Look for PMs that are due but have no recent WO.
-- (Whether a missing-WO gap means non-compliance is a maximo-reliability call;
-- this probe only detects the generation gap, not the compliance metric.)
SELECT
    pm.pmnum, pm.siteid, pm.nextdate, pm.laststartdate,
    COUNT(w.wonum) AS recent_wo_count
FROM :catalog.:schema.PM pm
LEFT JOIN :catalog.:schema.WORKORDER w
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
-- Bind :custom_column to the column you're checking.
SELECT
    COUNT(*)                                                AS total_rows,
    SUM(CASE WHEN :custom_column IS NULL
             THEN 1 ELSE 0 END)                             AS null_count,
    SUM(CASE WHEN :custom_column IS NULL
             THEN 1 ELSE 0 END) * 100.0 / COUNT(*)          AS null_pct
FROM :catalog.:schema.WORKORDER
WHERE woclass = 'WORKORDER'
  AND reportdate >= current_date() - INTERVAL 365 DAYS;


-- -----------------------------------------------------------------------------
-- Probe 11 — Labor master integrity (composes with maximo-labor-resources)
-- Symptom: LABTRANS references LABORCODE that doesn't exist in LABOR
-- -----------------------------------------------------------------------------
SELECT
    'LABTRANS orphans (missing LABOR)' AS issue,
    COUNT(*) AS orphan_count
FROM :catalog.:schema.LABTRANS lt
LEFT JOIN :catalog.:schema.LABOR l
    ON l.laborcode = lt.laborcode AND l.orgid = lt.orgid
WHERE l.laborcode IS NULL;
-- Orphans inflate labor-cost totals against assets that didn't really have those resources.


-- -----------------------------------------------------------------------------
-- Probe 12 — Closure-table integrity (composes with maximo-asset-hierarchy)
-- Symptom: LOCATIONS has a multi-level parent chain but LOCANCESTOR doesn't reflect it
-- -----------------------------------------------------------------------------
-- Builds the 2-hop reachable set via two LOCHIERARCHY hops and compares to
-- LOCANCESTOR. A meaningful difference means the closure table is stale or
-- missing rows; fall back to recursive CTEs in queries until ingestion is fixed.
WITH two_hop AS (
    SELECT DISTINCT g.location, lh.parent AS ancestor, g.siteid, g.systemid
    FROM :catalog.:schema.LOCHIERARCHY g
    JOIN :catalog.:schema.LOCHIERARCHY lh
        ON lh.location = g.parent AND lh.siteid = g.siteid AND lh.systemid = g.systemid
    WHERE g.systemid = 'PRIMARY'
)
SELECT
    'LOCANCESTOR missing 2-hop ancestor rows' AS issue,
    COUNT(*) AS missing_count
FROM two_hop t
LEFT JOIN :catalog.:schema.LOCANCESTOR la
    ON la.location = t.location AND la.ancestor = t.ancestor
   AND la.siteid = t.siteid AND la.systemid = t.systemid
WHERE la.location IS NULL;


-- -----------------------------------------------------------------------------
-- Probe 13 — Qualification expiry gaps
-- Symptom: Qualifications attached to ACTIVE labor are expired but still marked ACTIVE
-- -----------------------------------------------------------------------------
SELECT
    qp.personid, qp.qualificationid,
    qp.expirydate,
    datediff(DAY, qp.expirydate, current_date()) AS days_past_expiry
FROM :catalog.:schema.QUALPERSON qp
JOIN :catalog.:schema.LABOR l
    ON l.personid = qp.personid AND l.status = 'ACTIVE'
WHERE qp.status = 'ACTIVE'
  AND qp.expirydate < current_date()
ORDER BY days_past_expiry DESC
LIMIT 100;
-- Rows here mean the qualification status isn't being maintained — the labor
-- record still shows the cert as ACTIVE even though it's lapsed. Filter
-- EXPIRYDATE in every "qualified labor" query to avoid trusting these rows.
