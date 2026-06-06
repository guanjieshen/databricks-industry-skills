-- =============================================================================
-- WellView Daily Ops & Cost — Trusted Asset UC functions
-- =============================================================================
-- Register ONCE via wellview-setup (preview-then-apply). Genie calls these as
-- governed, parameterized metrics instead of regenerating ad-hoc SQL. They are
-- the callable form of the same definitions the metric view exposes sliceably.
-- See: https://docs.databricks.com/aws/en/genie/trusted-assets
--
-- Bind :catalog, :silver_schema at registration. Canonical names below — resolve
-- to physical names + MASTER UNITS via the <customer>-wellview-glossary.
-- =============================================================================

-- Unit helper: feet -> metres. Normalize EVERYTHING to one unit before math.
-- (If the glossary says depth is already metres, make this an identity function.)
CREATE OR REPLACE FUNCTION :catalog.:silver_schema.wellview_ft_to_m(p_ft DOUBLE)
RETURNS DOUBLE
COMMENT 'Convert feet to metres. Canonical unit normalizer for WellView depth/footage.'
RETURN p_ft * 0.3048;

-- ROP (rate of penetration) = footage / on-bottom hours. Unit follows the inputs.
CREATE OR REPLACE FUNCTION :catalog.:silver_schema.wellview_rop(p_footage DOUBLE, p_hours DOUBLE)
RETURNS DOUBLE
COMMENT 'Rate of penetration = footage / on-bottom hours. Pass footage and hours in consistent units.'
RETURN CASE WHEN p_hours IS NULL OR p_hours = 0 THEN NULL ELSE p_footage / p_hours END;

-- NPT % for a well's jobs = NPT hours / total activity hours * 100, per job.
-- The is_npt rule is encoded in v_time_log_enriched (confirm it in wellview-setup).
CREATE OR REPLACE FUNCTION :catalog.:silver_schema.wellview_npt_pct(p_well_id STRING)
RETURNS TABLE (job_id STRING, npt_hrs DOUBLE, total_hrs DOUBLE, npt_pct DOUBLE)
COMMENT 'Non-productive time percentage per job for a well. NPT classification per v_time_log_enriched.'
RETURN
  SELECT job_id,
         SUM(CASE WHEN is_npt THEN hrs ELSE 0 END)                          AS npt_hrs,
         SUM(hrs)                                                            AS total_hrs,
         ROUND(100.0 * SUM(CASE WHEN is_npt THEN hrs ELSE 0 END)
               / NULLIF(SUM(hrs), 0), 1)                                     AS npt_pct
  FROM   :catalog.:silver_schema.v_time_log_enriched
  WHERE  (p_well_id IS NULL OR well_id = p_well_id)
  GROUP  BY job_id;

-- Cost per foot per job = total cost / total footage (both normalized).
-- p_categories optional filter on cost_category (e.g. array('Tangible','Intangible')).
CREATE OR REPLACE FUNCTION :catalog.:silver_schema.wellview_cost_per_foot(p_well_id STRING)
RETURNS TABLE (job_id STRING, total_cost DOUBLE, footage_m DOUBLE, cost_per_m DOUBLE)
COMMENT 'Cost per metre drilled per job. Total cost / total footage. Confirm cost-code scope with the user.'
RETURN
  WITH cost AS (
    SELECT job_id, SUM(amount) AS total_cost
    FROM   :catalog.:silver_schema.v_job_cost_rollup
    WHERE  (p_well_id IS NULL OR well_id = p_well_id)
    GROUP  BY job_id
  ),
  foot AS (
    SELECT job_id, SUM(footage_m) AS footage_m
    FROM   :catalog.:silver_schema.v_time_log_enriched
    WHERE  (p_well_id IS NULL OR well_id = p_well_id)
    GROUP  BY job_id
  )
  SELECT c.job_id, c.total_cost, f.footage_m,
         c.total_cost / NULLIF(f.footage_m, 0) AS cost_per_m
  FROM   cost c LEFT JOIN foot f USING (job_id);

-- AFE variance % per job = (actual - AFE) / AFE * 100.
-- NOTE: AFEs allocate many-to-many; this assumes AFE is attributed to the job.
-- Confirm AFE baseline (original vs supplement) + allocation in wellview-setup.
CREATE OR REPLACE FUNCTION :catalog.:silver_schema.wellview_afe_variance_pct(p_well_id STRING)
RETURNS TABLE (job_id STRING, afe_amount DOUBLE, actual_cost DOUBLE, variance_pct DOUBLE)
COMMENT 'AFE variance % per job = (actual - AFE)/AFE*100. Confirm AFE baseline and shared-AFE allocation.'
RETURN
  WITH actual AS (
    SELECT job_id, SUM(amount) AS actual_cost
    FROM   :catalog.:silver_schema.v_job_cost_rollup
    WHERE  (p_well_id IS NULL OR well_id = p_well_id)
    GROUP  BY job_id
  ),
  afe AS (
    SELECT IDRECPARENT AS job_id, SUM(AFEAMOUNT) AS afe_amount
    FROM   :catalog.:silver_schema.WVAFE
    GROUP  BY IDRECPARENT
  )
  SELECT a.job_id, f.afe_amount, a.actual_cost,
         ROUND(100.0 * (a.actual_cost - f.afe_amount) / NULLIF(f.afe_amount, 0), 1) AS variance_pct
  FROM   actual a LEFT JOIN afe f USING (job_id);
