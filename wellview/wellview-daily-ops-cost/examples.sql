-- =============================================================================
-- WellView Daily Ops & Cost — parameterized gold-standard queries
-- =============================================================================
-- Genie should prefer these patterns over generating SQL from scratch. Databricks
-- :param placeholders bind at execution. Canonical names — resolve physical names
-- + MASTER UNITS via the <customer>-wellview-glossary. Prefer the enriched views
-- (already unit-normalized + LV-decoded) over raw tables.
-- =============================================================================

-- Q: Daily drilling report readout for a well on a date.
SELECT report_date, days_from_spud, depth_md_m, job_type
FROM   :catalog.:silver_schema.v_daily_report_enriched
WHERE  well_id = :well_id
  AND  report_date = :report_date
ORDER  BY report_date;

-- Q: Time log for a report-day, NPT flagged (should reconcile to ~24 h).
SELECT time_on, time_off, hrs, phase, operation, npt_reason, is_npt
FROM   :catalog.:silver_schema.v_time_log_enriched
WHERE  report_id = :report_id
ORDER  BY time_on;

-- Q: NPT % for the last well (per job). Surface the NPT definition first.
SELECT job_id, npt_hrs, total_hrs, npt_pct
FROM   TABLE(:catalog.:silver_schema.wellview_npt_pct(:well_id))
ORDER  BY npt_pct DESC;

-- Q: NPT breakdown by reason for a job (what caused the downtime).
SELECT npt_reason, ROUND(SUM(hrs), 1) AS npt_hrs
FROM   :catalog.:silver_schema.v_time_log_enriched
WHERE  job_id = :job_id
  AND  is_npt
GROUP  BY npt_reason
ORDER  BY npt_hrs DESC;

-- Q: Cost per foot on the last N drilling jobs (confirm cost-code scope + unit).
SELECT cpf.job_id, d.well_name, cpf.total_cost, cpf.footage_m, cpf.cost_per_m
FROM   TABLE(:catalog.:silver_schema.wellview_cost_per_foot(NULL)) cpf
JOIN   (SELECT DISTINCT job_id, well_name, job_type FROM :catalog.:silver_schema.v_daily_report_enriched) d
       USING (job_id)
WHERE  d.job_type = :job_type            -- e.g. 'Drilling'
ORDER  BY cpf.cost_per_m
LIMIT  :n;

-- Q: Are we over AFE? Variance % per job for a well.
SELECT job_id, afe_amount, actual_cost, variance_pct
FROM   TABLE(:catalog.:silver_schema.wellview_afe_variance_pct(:well_id))
ORDER  BY variance_pct DESC;

-- Q: Days-vs-depth curve for a cohort (same job type; anchor = days_from_spud).
--    Plot depth_md_m (y) against days_from_spud (x); one line per well.
SELECT well_name, days_from_spud, depth_md_m
FROM   :catalog.:silver_schema.v_daily_report_enriched
WHERE  job_type = :job_type
  AND  well_id IN (:well_ids)
ORDER  BY well_name, days_from_spud;

-- Q: Cumulative cost to date for a job (recomputed; CostCum may not be stored).
SELECT report_date,
       SUM(daily_cost) OVER (ORDER BY report_date
                             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cost_cum
FROM (
  SELECT r.report_date, SUM(c.amount) AS daily_cost
  FROM   :catalog.:silver_schema.v_daily_report_enriched r
  JOIN   :catalog.:silver_schema.WVCOST c ON c.IDRECPARENT = r.report_id
  WHERE  r.job_id = :job_id
  GROUP  BY r.report_date
)
ORDER  BY report_date;

-- Q: Average ROP by hole section (phase) for a job.
SELECT phase,
       ROUND(:catalog.:silver_schema.wellview_rop(SUM(footage_m), SUM(hrs)), 2) AS rop_m_per_hr
FROM   :catalog.:silver_schema.v_time_log_enriched
WHERE  job_id = :job_id
  AND  NOT is_npt
GROUP  BY phase
ORDER  BY rop_m_per_hr DESC;
