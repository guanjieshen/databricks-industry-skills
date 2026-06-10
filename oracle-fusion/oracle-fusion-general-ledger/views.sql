-- =============================================================================
-- Oracle Fusion General Ledger — Pre-joined Delta Views
-- =============================================================================
-- Bind :catalog and :silver_schema (Databricks SQL parameters) to the customer's
-- catalog and Silver/canonical GL schema at execution / registration.
--
-- These views encode the most-used GL joins so Genie (Code or Space) and humans
-- compose against a smaller, denormalized, ALREADY-DECODED surface — per
-- Databricks best practice "denormalize and pre-join before exposing to Genie."
--
-- LANDING-AGNOSTIC: the FROM targets below use the CANONICAL table names
-- (GL_JE_HEADERS, GL_BALANCES, …). Fusion lands as BICC PVOs or FDI artifacts
-- with DIFFERENT physical names — resolve the physical→canonical mapping via the
-- <customer>-oracle-fusion-glossary (produced by oracle-fusion-setup) and bind
-- the real names before registering. Never promise raw-table access (SaaS).
--
-- COMPOSES THE KEYSTONE: these views join oracle-fusion-ledger-coa's
-- v_code_combination (CCID + decoded segments) and v_gl_period (period + status
-- + chronological sort key). Those views MUST be registered first (via setup).
-- Do NOT redefine them here — this skill owns only v_gl_journal_enriched and
-- v_trial_balance.
--
-- UC column comments are NOT registered here — owned by oracle-fusion-setup
-- (preview-then-apply). Register these views once via setup.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_gl_journal_enriched
-- -----------------------------------------------------------------------------
-- Journal lines joined up to their header/batch, with the account DECODED via the
-- keystone v_code_combination and the period status/sort key via v_gl_period.
-- One row per journal LINE. Use for journal volume, line-level drill, and any
-- "by natural account / cost center / legal entity" journal-side analysis.
--
-- NOTE: this view does NOT pre-filter posted/unposted or balance type, so callers
-- choose deliberately. Apply STATUS = 'P' for financials (gotcha 2) and pin
-- ACTUAL_FLAG to one value (gotcha 1). The decoded-segment columns come from the
-- keystone; their exact names depend on the customer's COA — confirm via glossary.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:silver_schema.v_gl_journal_enriched
COMMENT 'Enriched GL journal lines: line + header + batch, with decoded account (keystone v_code_combination) and period status (keystone v_gl_period). One row per journal line. Not pre-filtered — apply STATUS and ACTUAL_FLAG per query.'
AS
SELECT
    -- Line grain
    jl.je_header_id,
    jl.je_line_num,
    jl.ledger_id,
    jl.code_combination_id,
    jl.period_name,
    jl.entered_dr,
    jl.entered_cr,
    jl.accounted_dr,
    jl.accounted_cr,
    (jl.accounted_dr - jl.accounted_cr)                              AS accounted_net,   -- Activity Amount, ledger ccy (gotcha 10)
    (jl.entered_dr  - jl.entered_cr)                                 AS entered_net,     -- Activity Amount, document ccy
    jl.status                                                        AS line_status,
    jl.description                                                   AS line_description,
    jl.gl_sl_link_id,                                                                    -- XLA bridge (keystone); subledger lines only
    -- Header context
    jh.je_batch_id,
    jh.name                                                          AS journal_name,
    jh.je_source,
    jh.je_category,
    jh.currency_code,
    jh.status                                                        AS header_status,
    jh.actual_flag,                                                                      -- A/B/E — pin to one (gotcha 1)
    jh.budget_version_id,
    jh.encumbrance_type_id,
    jh.default_effective_date,
    jh.posted_date,
    -- Batch context
    jb.name                                                          AS batch_name,
    jb.status                                                        AS batch_status,
    -- Decoded account (KEYSTONE v_code_combination — do not redefine)
    cc.concatenated_segments,
    cc.account_type,
    cc.balancing_segment_value,                                                          -- ties to legal entity (keystone)
    cc.natural_account_value,
    cc.cost_center_value,
    cc.detail_posting_allowed_flag,                                                      -- detail vs summary (gotcha 7)
    -- Period status + chronological sort key (KEYSTONE v_gl_period — do not redefine)
    gp.closing_status                                                                   AS period_status,
    gp.effective_period_number                                                          AS period_sort_key,                                                                  -- order by THIS, never period_name (gotcha 4)
    gp.period_year,
    gp.period_num
FROM :catalog.:silver_schema.GL_JE_LINES jl
JOIN :catalog.:silver_schema.GL_JE_HEADERS jh
       ON jh.je_header_id = jl.je_header_id
LEFT JOIN :catalog.:silver_schema.GL_JE_BATCHES jb
       ON jb.je_batch_id = jh.je_batch_id
-- Keystone views (registered by oracle-fusion-ledger-coa via setup):
LEFT JOIN :catalog.:silver_schema.v_code_combination cc
       ON cc.code_combination_id = jl.code_combination_id
LEFT JOIN :catalog.:silver_schema.v_gl_period gp
       ON gp.ledger_id   = jl.ledger_id
      AND gp.period_name = jl.period_name;


-- -----------------------------------------------------------------------------
-- v_trial_balance
-- -----------------------------------------------------------------------------
-- Posted ACTUAL balances by ledger / account / period in LEDGER currency, with
-- the account decoded and the ending balance computed. One row per
-- (ledger, ccid, period) for actuals. This is the trial-balance base surface.
--
-- Built from GL_BALANCES (NOT journal lines — see gotcha 6) and pre-filtered to
-- the trial-balance discipline:
--   actual_flag = 'A'                  → actuals only (gotcha 1)
--   detail_posting_allowed_flag = 'Y'  → detail accounts only, no summary
--                                        rollups double-counted (gotcha 7)
-- Currency basis is left as a column so the caller pins the ledger-currency rows
-- (and excludes translated rows — gotcha 8) deliberately at query time.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:silver_schema.v_trial_balance
COMMENT 'Trial-balance base: posted ACTUAL detail-account balances by ledger/account/period from GL_BALANCES, account decoded via keystone v_code_combination, ending balance computed. One row per (ledger, ccid, currency, period). Pin currency basis + period at query time.'
AS
SELECT
    gb.ledger_id,
    gb.code_combination_id,
    gb.currency_code,
    gb.period_name,
    gb.actual_flag,
    gb.translated_flag,                                                                  -- exclude/keep translated rows deliberately (gotcha 8)
    gb.begin_balance_dr,
    gb.begin_balance_cr,
    gb.period_net_dr,
    gb.period_net_cr,
    (gb.begin_balance_dr - gb.begin_balance_cr)                      AS begin_balance,   -- Dr - Cr (gotcha 10)
    (gb.period_net_dr   - gb.period_net_cr)                          AS period_activity,
    (gb.begin_balance_dr - gb.begin_balance_cr)
      + (gb.period_net_dr - gb.period_net_cr)                        AS ending_balance,  -- trial-balance amount
    -- Decoded account (KEYSTONE v_code_combination)
    cc.concatenated_segments,
    cc.account_type,
    cc.balancing_segment_value,
    cc.natural_account_value,
    cc.cost_center_value,
    -- Period status + chronological sort key (KEYSTONE v_gl_period)
    gp.closing_status                                                                   AS period_status,
    gp.effective_period_number                                                          AS period_sort_key,
    gp.period_year,
    gp.period_num
FROM :catalog.:silver_schema.GL_BALANCES gb
LEFT JOIN :catalog.:silver_schema.v_code_combination cc
       ON cc.code_combination_id = gb.code_combination_id
LEFT JOIN :catalog.:silver_schema.v_gl_period gp
       ON gp.ledger_id   = gb.ledger_id
      AND gp.period_name = gb.period_name
WHERE gb.actual_flag = 'A'                                            -- actuals only (gotcha 1)
  AND cc.detail_posting_allowed_flag = 'Y';                          -- detail accounts only (gotcha 7)
