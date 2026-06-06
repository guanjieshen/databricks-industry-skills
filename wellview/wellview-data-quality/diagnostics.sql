-- =============================================================================
-- WellView Data Quality — diagnostic probes
-- =============================================================================
-- Load PROBE-BY-PROBE as you walk the playbook in SKILL.md; don't run all at once.
-- Canonical names — resolve physical names + master units via the glossary.
-- Bind :catalog, :silver_schema (and :well_id where used).
-- =============================================================================

-- Probe 1: Unit inconsistency. Profile depth/footage/cost ranges to spot mixed units.
--   A depth column maxing in the tens of thousands is likely feet; thousands likely metres.
SELECT 'depth_md' AS col, MIN(DEPTHMD) lo, MAX(DEPTHMD) hi, COUNT(*) n
FROM   :catalog.:silver_schema.WVJOBREPORT
UNION ALL
SELECT 'cost_currencies', NULL, COUNT(DISTINCT CURRENCY), COUNT(*)
FROM   :catalog.:silver_schema.WVCOST;

-- Probe 2: Well/job double-count. Wells with multiple jobs (roll-ups must group by job).
SELECT IDWELL, COUNT(*) AS job_count
FROM   :catalog.:silver_schema.WVJOB
GROUP  BY IDWELL
HAVING COUNT(*) > 1
ORDER  BY job_count DESC;

-- Probe 3 & 4: Orphan IDRECPARENT — reports whose parent job is missing.
SELECT r.IDREC AS report_id, r.IDRECPARENT AS missing_job_idrec
FROM   :catalog.:silver_schema.WVJOBREPORT r
LEFT   JOIN :catalog.:silver_schema.WVJOB j ON j.IDREC = r.IDRECPARENT
WHERE  j.IDREC IS NULL;
-- (repeat for time-log -> report, cost -> report/job)

-- Probe 5: Calc-vs-stored. Are calc fields present, or null/absent?
SELECT COUNT(*) AS reports,
       COUNT(DAYSFROMSPUD) AS has_days_from_spud,
       COUNT(COSTCUM)      AS has_cost_cum
FROM   :catalog.:silver_schema.WVJOBREPORT;

-- Probe 6: Undecoded LV codes. NPT codes on activities with no LV label.
SELECT op.CODENPT, COUNT(*) AS n
FROM   :catalog.:silver_schema.WVJOBREPORTOP op
LEFT   JOIN :catalog.:silver_schema.LVWVCODENPT lv ON lv.CODE = op.CODENPT
WHERE  op.CODENPT IS NOT NULL AND lv.CODE IS NULL
GROUP  BY op.CODENPT
ORDER  BY n DESC;

-- Probe 7: 24-hour reconciliation. Report-days whose time-log hours don't sum to ~24.
SELECT op.IDRECPARENT AS report_id, ROUND(SUM(op.HRS), 1) AS sum_hrs
FROM   :catalog.:silver_schema.WVJOBREPORTOP op
GROUP  BY op.IDRECPARENT
HAVING ABS(SUM(op.HRS) - 24.0) > 1.0
ORDER  BY sum_hrs;

-- Probe 8: AFE over-allocation. AFEs whose detail allocation exceeds 100%.
SELECT IDRECPARENT AS afe_id, ROUND(SUM(ALLOCATIONPCT), 1) AS total_pct
FROM   :catalog.:silver_schema.WVAFEDETAIL
GROUP  BY IDRECPARENT
HAVING SUM(ALLOCATIONPCT) > 100.0
ORDER  BY total_pct DESC;
