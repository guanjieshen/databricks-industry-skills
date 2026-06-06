-- =============================================================================
-- Oracle Fusion General Ledger — Gold-Standard Query Examples
-- =============================================================================
-- Each block is a parameterized template that maps to a single analytical
-- question. Bind these Databricks SQL parameters at execution time:
--   :catalog          → the customer's UC catalog
--   :silver_schema    → canonical GL schema (GL_* tables + the keystone views)
--   :gold_schema      → Gold/metrics schema with Trusted UDFs (only for UDF examples)
--   :ledger_id, :period_name, :prior_period_name, :ccid, :budget_version_id,
--   :rate_type        → per-query value parameters
-- These examples assume views.sql and metric_udfs.sql (this skill) AND the
-- keystone's views/UDFs (v_code_combination, v_gl_period, convert_to_ledger_currency)
-- have been registered via oracle-fusion-setup.
--
-- Workflow priority (see SKILL.md §Workflow): metric view → Trusted UDF →
-- parameterized example → pre-joined view → raw tables. If a Trusted UDF matches,
-- prefer it over the view-based query.
--
-- GL DISCIPLINE in every block: pin ACTUAL_FLAG to one value (gotcha 1), posted
-- only for financials (gotcha 2), accounted/ledger currency for cross-account
-- totals (gotcha 3), order periods by the keystone sort key not PERIOD_NAME
-- (gotcha 4), and decode the account via the keystone, never the raw CCID (gotcha 5).
-- LANDING-AGNOSTIC: bind canonical names to the customer's physical PVO/FDI names
-- via the glossary first.
-- =============================================================================
--
-- Contents (load the block that matches the question):
--   1a. Trial balance total for a period (Trusted UDF)
--   1b. Trial balance by account for a period (view-based, decoded)
--   2.  Actual vs budget variance by cost center
--   3.  Top accounts by net activity this quarter
--   4.  Journal volume by source (entry-header count)
--   5.  Account balance converted to ledger currency (keystone UDF)
--   6.  Journal lines behind an account balance (drill-down)
--   7.  Period-over-period net activity by natural account (trend)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1a. Trial balance total for a period (Trusted UDF — prefer this for the number)
-- -----------------------------------------------------------------------------
-- Trigger: "trial balance total for ledger X in OCT-25", "does the TB net to zero"
-- The trial_balance UDF is the governed metric (posted actuals, detail accounts,
-- ledger currency). A fully-posted ledger nets toward zero (gotcha 10).
SELECT :catalog.:gold_schema.trial_balance(:ledger_id, :period_name) AS trial_balance_net;


-- -----------------------------------------------------------------------------
-- 1b. Trial balance BY ACCOUNT for a period (view-based, decoded)
-- -----------------------------------------------------------------------------
-- Trigger: "give me the trial balance", "balances by account for the period"
-- v_trial_balance is already actuals-only + detail-only (gotchas 1, 7). Pin the
-- ledger-currency basis by excluding translated rows (gotcha 8). Decoded segments
-- come from the keystone — no raw CCID grouping (gotcha 5).
SELECT
    tb.concatenated_segments,
    tb.account_type,
    tb.natural_account_value,
    tb.cost_center_value,
    tb.currency_code,
    tb.begin_balance,
    tb.period_activity,
    tb.ending_balance
FROM :catalog.:silver_schema.v_trial_balance tb
WHERE tb.ledger_id   = :ledger_id
  AND tb.period_name = :period_name
  AND (tb.translated_flag IS NULL OR tb.translated_flag = 'N')
ORDER BY tb.natural_account_value, tb.cost_center_value;


-- -----------------------------------------------------------------------------
-- 2. Actual vs budget variance by cost center
-- -----------------------------------------------------------------------------
-- Trigger: "actual vs budget", "budget variance by cost center / department"
-- Actual (A) and Budget (B) are SEPARATE populations for the same accounts/periods
-- — compare, never sum across ACTUAL_FLAG (gotcha 1). Budget needs a version
-- (gotcha 1). Both pulled from GL_BALANCES, decoded via the keystone.
WITH actual AS (
    SELECT gb.code_combination_id,
           SUM((gb.begin_balance_dr - gb.begin_balance_cr)
             + (gb.period_net_dr   - gb.period_net_cr)) AS actual_amt
    FROM :catalog.:silver_schema.GL_BALANCES gb
    WHERE gb.ledger_id   = :ledger_id
      AND gb.period_name = :period_name
      AND gb.actual_flag = 'A'
      AND (gb.translated_flag IS NULL OR gb.translated_flag = 'N')
    GROUP BY gb.code_combination_id
),
budget AS (
    SELECT gb.code_combination_id,
           SUM((gb.begin_balance_dr - gb.begin_balance_cr)
             + (gb.period_net_dr   - gb.period_net_cr)) AS budget_amt
    FROM :catalog.:silver_schema.GL_BALANCES gb
    WHERE gb.ledger_id         = :ledger_id
      AND gb.period_name       = :period_name
      AND gb.actual_flag       = 'B'
      AND gb.budget_version_id = :budget_version_id          -- which budget (gotcha 1)
    GROUP BY gb.code_combination_id
)
SELECT
    cc.cost_center_value,
    cc.natural_account_value,
    COALESCE(a.actual_amt, 0)                          AS actual_amt,
    COALESCE(b.budget_amt, 0)                          AS budget_amt,
    COALESCE(a.actual_amt, 0) - COALESCE(b.budget_amt, 0) AS variance_amt,
    CASE WHEN b.budget_amt <> 0
         THEN ROUND(100.0 * (COALESCE(a.actual_amt,0) - b.budget_amt) / b.budget_amt, 1)
         ELSE NULL END                                 AS variance_pct
FROM actual a
FULL OUTER JOIN budget b ON b.code_combination_id = a.code_combination_id
LEFT JOIN :catalog.:silver_schema.v_code_combination cc
       ON cc.code_combination_id = COALESCE(a.code_combination_id, b.code_combination_id)
ORDER BY ABS(COALESCE(a.actual_amt,0) - COALESCE(b.budget_amt,0)) DESC
LIMIT 100;


-- -----------------------------------------------------------------------------
-- 3. Top accounts by net activity this quarter
-- -----------------------------------------------------------------------------
-- Trigger: "biggest accounts this quarter", "top movement by account"
-- Net activity = accounted Dr - Cr (gotcha 10), actuals + posted only, decoded
-- account. Uses the enriched journal view; multiple periods so order by the
-- keystone sort key, never PERIOD_NAME (gotcha 4).
SELECT
    je.natural_account_value,
    je.concatenated_segments,
    je.account_type,
    SUM(je.accounted_net) AS net_activity
FROM :catalog.:silver_schema.v_gl_journal_enriched je
WHERE je.ledger_id    = :ledger_id
  AND je.actual_flag  = 'A'
  AND je.header_status = 'P'
  AND je.line_status   = 'P'
  AND je.period_sort_key >= (
        SELECT MIN(gp.effective_period_number)             -- keystone v_gl_period column name
        FROM :catalog.:silver_schema.v_gl_period gp
        WHERE gp.ledger_id = :ledger_id AND gp.period_name = :period_name
      ) - 2                                              -- this period + prior 2 (a quarter)
GROUP BY je.natural_account_value, je.concatenated_segments, je.account_type
ORDER BY ABS(SUM(je.accounted_net)) DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- 4. Journal volume by source (entry-header count)
-- -----------------------------------------------------------------------------
-- Trigger: "how many journals by source", "journal volume by Payables/Manual"
-- Count GL_JE_HEADERS (entry grain, NOT lines), posted actuals only (gotcha 2).
-- Compare with the journal_count UDF for a single-source/period scalar.
SELECT
    jh.je_source,
    jh.je_category,
    COUNT(*)                              AS journal_count,
    SUM(jh.running_total_accounted_dr)    AS total_accounted_dr
FROM :catalog.:silver_schema.GL_JE_HEADERS jh
WHERE jh.ledger_id   = :ledger_id
  AND jh.period_name = :period_name
  AND jh.actual_flag = 'A'
  AND jh.status      = 'P'
GROUP BY jh.je_source, jh.je_category
ORDER BY journal_count DESC;


-- -----------------------------------------------------------------------------
-- 5. Account balance converted to ledger currency (keystone UDF)
-- -----------------------------------------------------------------------------
-- Trigger: "this foreign-currency balance in our ledger currency"
-- For an entered-currency balance row, normalize to ledger currency via the
-- KEYSTONE convert_to_ledger_currency UDF — do NOT hand-roll GL_DAILY_RATES
-- (gotcha 3). The function owns rate-type + conversion-date selection.
SELECT
    gb.code_combination_id,
    gb.currency_code                                                   AS entered_currency,
    (gb.begin_balance_dr - gb.begin_balance_cr)
      + (gb.period_net_dr - gb.period_net_cr)                          AS entered_balance,
    :catalog.:gold_schema.convert_to_ledger_currency(
        (gb.begin_balance_dr - gb.begin_balance_cr)
          + (gb.period_net_dr - gb.period_net_cr),
        gb.currency_code,
        :ledger_id,
        :period_name,
        :rate_type
    )                                                                  AS ledger_currency_balance
FROM :catalog.:silver_schema.GL_BALANCES gb
WHERE gb.ledger_id           = :ledger_id
  AND gb.code_combination_id = :ccid
  AND gb.period_name         = :period_name
  AND gb.actual_flag         = 'A'
  AND gb.currency_code      <> 'USD';                  -- foreign-currency rows; adjust to ledger ccy


-- -----------------------------------------------------------------------------
-- 6. Journal lines behind an account balance (drill-down)
-- -----------------------------------------------------------------------------
-- Trigger: "show me the entries that make up this balance", "drill into account X"
-- Drops from the balance (point-in-time) to the journal LINES (detail) for one
-- account/period — different grains, don't add them together (gotcha 6). Posted
-- actuals only; decoded account + source from the enriched view.
SELECT
    je.posted_date,
    je.je_source,
    je.je_category,
    je.journal_name,
    je.line_description,
    je.accounted_dr,
    je.accounted_cr,
    je.accounted_net
FROM :catalog.:silver_schema.v_gl_journal_enriched je
WHERE je.ledger_id            = :ledger_id
  AND je.code_combination_id  = :ccid
  AND je.period_name          = :period_name
  AND je.actual_flag          = 'A'
  AND je.header_status        = 'P'
  AND je.line_status          = 'P'
ORDER BY je.posted_date, je.je_header_id, je.je_line_num;


-- -----------------------------------------------------------------------------
-- 7. Period-over-period net activity by natural account (trend)
-- -----------------------------------------------------------------------------
-- Trigger: "monthly trend by account", "net activity over the last periods"
-- Multi-period trend: GROUP BY the period but ORDER BY the keystone sort key so
-- periods are chronological, never alphabetical (gotcha 4). Actuals + posted only.
SELECT
    je.period_name,
    je.period_sort_key,
    je.natural_account_value,
    SUM(je.accounted_net) AS net_activity
FROM :catalog.:silver_schema.v_gl_journal_enriched je
WHERE je.ledger_id     = :ledger_id
  AND je.actual_flag   = 'A'
  AND je.header_status = 'P'
  AND je.line_status   = 'P'
GROUP BY je.period_name, je.period_sort_key, je.natural_account_value
ORDER BY je.period_sort_key, je.natural_account_value;
