-- =============================================================================
-- Oracle Fusion General Ledger — UC SQL Function (Metric UDF) DDL
-- =============================================================================
-- Trusted Asset functions for Genie. Register once (CREATE FUNCTION) so Genie
-- Code and Genie Agents call them as certified, governed metrics rather than
-- regenerating ad-hoc SQL. Ref: https://docs.databricks.com/aws/en/genie/trusted-assets
--
-- Bind these Databricks SQL parameters at registration time:
--   :catalog        → customer UC catalog
--   :silver_schema  → canonical GL schema (GL_BALANCES, GL_JE_HEADERS, + keystone views)
--   :gold_schema    → Gold/metrics schema where these functions live
--   :principal      → grant target (a group preferred, e.g. genie-users)
--
-- Each function is a SINGLE SQL statement (no procedural logic) so it can be
-- inlined into Genie's generated queries.
--
-- GL DISCIPLINE baked in (see gotchas.md):
--   * Every metric pins ACTUAL_FLAG to one value — actual/budget/encumbrance are
--     different balance types and must never be summed together (gotcha 1).
--   * Balance metrics read GL_BALANCES (posted by construction) and detail
--     accounts only (gotcha 7); journal_count reads GL_JE_HEADERS and filters
--     STATUS = 'P' unless the caller asks for unposted (gotcha 2).
--   * CCID decode / currency conversion / period mapping are the KEYSTONE's job
--     (v_code_combination, convert_to_ledger_currency, v_gl_period). These UDFs
--     do not redefine them; for cross-currency normalization, wrap results with
--     convert_to_ledger_currency at the call site.
-- LANDING-AGNOSTIC: bind canonical names to the customer's physical PVO/FDI names
-- via the glossary before registering.
-- =============================================================================

-- Ensure the metrics schema exists
CREATE SCHEMA IF NOT EXISTS :catalog.:gold_schema
COMMENT 'Trusted-asset SQL functions for Oracle Fusion General Ledger metrics';


-- -----------------------------------------------------------------------------
-- trial_balance
-- -----------------------------------------------------------------------------
-- Trigger: "trial balance total for <ledger> in <period>"
-- Returns the net ending balance (Dr - Cr) of all POSTED ACTUAL detail accounts
-- for one ledger + period, in the ledger-currency rows. For a fully-posted ledger
-- this nets toward zero (gotcha 10); for a single account use account_balance.
-- Reads v_trial_balance (already actuals-only + detail-only). Caller pins the
-- ledger-currency basis by excluding translated rows.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:gold_schema.trial_balance(
    ledger_id BIGINT COMMENT 'GL_LEDGERS.LEDGER_ID — the ledger to scope to',
    period_name STRING COMMENT 'Accounting period, e.g. OCT-25'
)
RETURNS DECIMAL(28,2)
COMMENT 'Trusted metric: net ending balance (Dr - Cr) of posted ACTUAL detail accounts for a ledger + period, ledger-currency (untranslated) rows. Sums v_trial_balance.ending_balance.'
RETURN (
    SELECT SUM(tb.ending_balance)
    FROM :catalog.:silver_schema.v_trial_balance tb
    WHERE tb.ledger_id   = ledger_id
      AND tb.period_name = period_name
      AND (tb.translated_flag IS NULL OR tb.translated_flag = 'N')   -- ledger-currency basis (gotcha 8)
);


-- -----------------------------------------------------------------------------
-- account_balance
-- -----------------------------------------------------------------------------
-- Trigger: "balance of account <ccid> in <period>", "budget for this account"
-- Ending balance (Dr - Cr) for ONE code combination in one ledger + period for a
-- given balance type. ACTUAL_FLAG is a parameter, but the function pins exactly
-- one value (gotcha 1). Reads GL_BALANCES directly so all balance types are
-- reachable (v_trial_balance is actuals-only).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:gold_schema.account_balance(
    ledger_id BIGINT COMMENT 'GL_LEDGERS.LEDGER_ID',
    ccid BIGINT COMMENT 'GL_CODE_COMBINATIONS.CODE_COMBINATION_ID — decode display via keystone v_code_combination',
    period_name STRING COMMENT 'Accounting period, e.g. OCT-25',
    balance_type STRING COMMENT "ACTUAL_FLAG: 'A' Actual, 'B' Budget, 'E' Encumbrance — exactly one (gotcha 1)"
)
RETURNS DECIMAL(28,2)
COMMENT 'Trusted metric: ending balance (begin + period net, Dr - Cr) for one account/ledger/period and one balance type, ledger-currency (untranslated) rows.'
RETURN (
    SELECT SUM(
             (gb.begin_balance_dr - gb.begin_balance_cr)
           + (gb.period_net_dr   - gb.period_net_cr)
           )
    FROM :catalog.:silver_schema.GL_BALANCES gb
    WHERE gb.ledger_id            = ledger_id
      AND gb.code_combination_id  = ccid
      AND gb.period_name          = period_name
      AND gb.actual_flag          = balance_type                     -- pin one balance type (gotcha 1)
      AND (gb.translated_flag IS NULL OR gb.translated_flag = 'N')   -- ledger-currency basis (gotcha 8)
);


-- -----------------------------------------------------------------------------
-- journal_count
-- -----------------------------------------------------------------------------
-- Trigger: "how many journals in <period>", "journal volume for <ledger>"
-- Counts GL_JE_HEADERS (one row per journal entry) for a ledger + period. When
-- posted_only is TRUE (the default for financials), filters STATUS = 'P'
-- (gotcha 2); pass FALSE for a pre-close "pending posting" review. Actuals only.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:gold_schema.journal_count(
    ledger_id BIGINT COMMENT 'GL_LEDGERS.LEDGER_ID',
    period_name STRING COMMENT 'Accounting period, e.g. OCT-25',
    posted_only BOOLEAN COMMENT 'TRUE = posted journals only (STATUS = P); FALSE = include unposted'
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of ACTUAL journal entry headers for a ledger + period. posted_only=TRUE restricts to STATUS = P (gotcha 2).'
RETURN (
    SELECT COUNT(*)
    FROM :catalog.:silver_schema.GL_JE_HEADERS jh
    WHERE jh.ledger_id   = ledger_id
      AND jh.period_name = period_name
      AND jh.actual_flag = 'A'
      AND (NOT posted_only OR jh.status = 'P')
);


-- =============================================================================
-- Grants — required for Genie to register these as Trusted assets.
-- Substitute :principal — a group is preferred (e.g. genie-users).
-- =============================================================================

-- GRANT USAGE ON SCHEMA :catalog.:gold_schema TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:gold_schema.trial_balance     TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:gold_schema.account_balance   TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:gold_schema.journal_count     TO `:principal`;
