-- =============================================================================
-- WellView Daily Ops & Cost — pre-joined Gold views
-- =============================================================================
-- Registered ONCE by wellview-setup (preview-then-apply); never run from the
-- module skill. Canonical WellView names are used below — resolve to the
-- customer's PHYSICAL names + MASTER UNITS via the <customer>-wellview-glossary.
--
-- Conventions:
--   * Join the record tree on IDRECPARENT = parent.IDREC (NOT IDWELL).
--   * Normalize depth/footage to METRES at this layer (wellview_ft_to_m) so every
--     downstream metric is unit-safe. Swap the conversion per the glossary's
--     recorded master unit.
--   * Decode coded columns through LV lookups here, once.
--   * Bind :catalog, :silver_schema at registration.
-- =============================================================================

-- 1. Daily report enriched: one row per day per job, with job/well context.
CREATE OR REPLACE VIEW :catalog.:silver_schema.v_daily_report_enriched AS
SELECT
    r.IDREC                                   AS report_id,
    r.IDRECPARENT                             AS job_id,        -- -> WVJOB.IDREC
    r.IDWELL                                  AS well_id,
    w.WELLNAME                                AS well_name,
    j.JOBTYPE                                 AS job_type_code,
    lvj.DESCRIPTION                           AS job_type,
    r.DTTMSTART                               AS report_date,
    r.DAYSFROMSPUD                            AS days_from_spud,         -- may be NULL if calc-only
    wellview_ft_to_m(r.DEPTHMD)               AS depth_md_m,             -- normalized
    wellview_ft_to_m(r.DEPTHTVD)              AS depth_tvd_m
FROM        :catalog.:silver_schema.WVJOBREPORT  r
JOIN        :catalog.:silver_schema.WVJOB        j   ON j.IDREC    = r.IDRECPARENT
JOIN        :catalog.:silver_schema.WVWELLHEADER w   ON w.IDWELL   = r.IDWELL
LEFT JOIN   :catalog.:silver_schema.LVWVTYPEJOB  lvj ON lvj.CODE   = j.JOBTYPE;

-- 2. Time-log enriched: one row per activity, NPT-classified, footage normalized.
CREATE OR REPLACE VIEW :catalog.:silver_schema.v_time_log_enriched AS
SELECT
    op.IDREC                                  AS activity_id,
    op.IDRECPARENT                            AS report_id,    -- -> WVJOBREPORT.IDREC
    r.IDRECPARENT                             AS job_id,
    op.IDWELL                                 AS well_id,
    r.DTTMSTART                               AS report_date,
    op.DTTMSTART                              AS time_on,
    op.DTTMEND                                AS time_off,
    op.HRS                                    AS hrs,
    op.PHASE                                  AS phase_code,
    lvp.DESCRIPTION                           AS phase,
    op.CODEOP                                 AS op_code,
    lvo.DESCRIPTION                           AS operation,
    op.CODENPT                               AS npt_code,
    lvn.DESCRIPTION                           AS npt_reason,
    -- NPT rule is customer-configurable; default: non-productive flag OR an NPT code present.
    -- Confirm via wellview-setup; override here once the rule is known.
    (COALESCE(op.PRODUCTIVE, TRUE) = FALSE OR op.CODENPT IS NOT NULL) AS is_npt,
    wellview_ft_to_m(op.DEPTHEND - op.DEPTHSTART) AS footage_m
FROM        :catalog.:silver_schema.WVJOBREPORTOP op
JOIN        :catalog.:silver_schema.WVJOBREPORT   r   ON r.IDREC  = op.IDRECPARENT
LEFT JOIN   :catalog.:silver_schema.LVWVPHASE     lvp ON lvp.CODE = op.PHASE
LEFT JOIN   :catalog.:silver_schema.LVWVCODEOP    lvo ON lvo.CODE = op.CODEOP
LEFT JOIN   :catalog.:silver_schema.LVWVCODENPT   lvn ON lvn.CODE = op.CODENPT;

-- 3. Job cost rollup: cost rolled to the JOB grain (the safe roll-up unit).
--    Cost parentage (report vs job) is confirmed in wellview-setup; this view
--    resolves to job_id either way via the report->job hop.
CREATE OR REPLACE VIEW :catalog.:silver_schema.v_job_cost_rollup AS
SELECT
    j.IDREC                                   AS job_id,
    j.IDWELL                                  AS well_id,
    c.CODECOST                                AS cost_code,
    lvc.DESCRIPTION                           AS cost_desc,
    lvc.CATEGORY                              AS cost_category,   -- e.g. Tangible / Intangible
    c.CURRENCY                                AS currency,
    c.AFENUM                                  AS afe_num,
    SUM(c.AMOUNT)                             AS amount
FROM        :catalog.:silver_schema.WVCOST       c
-- cost may parent off the report or the job; the COALESCE resolves both shapes to a job_id
LEFT JOIN   :catalog.:silver_schema.WVJOBREPORT  r   ON r.IDREC = c.IDRECPARENT
JOIN        :catalog.:silver_schema.WVJOB        j   ON j.IDREC = COALESCE(r.IDRECPARENT, c.IDRECPARENT)
LEFT JOIN   :catalog.:silver_schema.LVWVCODECOST lvc ON lvc.CODE = c.CODECOST
GROUP BY    j.IDREC, j.IDWELL, c.CODECOST, lvc.DESCRIPTION, lvc.CATEGORY, c.CURRENCY, c.AFENUM;
