-- =============================================================================
-- Oracle Fusion — Ledger & Chart of Accounts — Gold-Standard Query Examples
-- =============================================================================
-- Each block is a parameterized template that maps to a single analytical
-- question. Bind these Databricks SQL parameters at execution time:
--   :catalog          → the customer's UC catalog
--   :silver_schema    → canonical Silver schema (GL/XLA mirror)
--   :gold_schema      → Gold/metrics schema with Trusted UDFs
--                       — only needed for examples that call a Trusted UDF
--   :ledger_id        → target ledger (scope EVERYTHING by ledger)
--   :ccid             → a CODE_COMBINATION_ID (integer, not a string)
--   :as_of_date       → an as-of date (DATE)
--   :period_name      → a GL period name (e.g. 'Mar-25')
--   :rate_type        → GL_DAILY_RATES.CONVERSION_TYPE (Spot/Corporate/User/Fixed)
--   :target_currency  → ISO currency to convert into
-- These examples assume views.sql and metric_udfs.sql have been registered.
-- Workflow priority: if a Trusted UDF matches the question, prefer it over the
-- view/raw query (see SKILL.md §Workflow).
--
-- *** PHYSICAL NAMES & CONFIG ***
-- All table names are CANONICAL (EBS-style). Fusion is SaaS — resolve real
-- physical names (and the segment->meaning map) via the
-- `<customer>-oracle-fusion-glossary` before binding. Segment positions shown
-- (e.g. the balancing/natural-account segment) are PLACEHOLDERS — confirm via the
-- glossary (gotcha 2). CURRENCY: never sum ENTERED across currencies — use
-- ACCOUNTED, or convert with convert_to_ledger_currency (gotcha 4/5). PERIODS:
-- sort by effective_period_number, never PERIOD_NAME (gotcha 6).
-- =============================================================================
--
-- Contents (load the block that matches the question):
--   1. Decode an account (CCID) to readable segments + type (Trusted UDF)
--   2. Trial-balance-style balance by account, converted to a target currency
--   3. Which period is a date in, and is it open? (Trusted UDFs)
--   4. Last N closed periods for a ledger (chronological ordering)
--   5. Reconcile an XLA subledger total to its GL journal via GL_SL_LINK_ID
--   6. Balancing segment values by legal entity (consolidation map)
--   7. Spend/activity by natural account, postable detail accounts only
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Decode an account (CCID) to readable segments + type (Trusted UDF — prefer)
-- -----------------------------------------------------------------------------
-- Trigger: "what account is CCID 123456", "decode this code combination".
-- The decode_ccid_segments UDF is the governed metric for a single CCID. For a
-- batch / join, use the v_code_combination view instead (block 2, 7).
SELECT :catalog.:gold_schema.decode_ccid_segments(:ccid) AS account;


-- -----------------------------------------------------------------------------
-- 2. Trial-balance-style balance by account, converted to a target currency
-- -----------------------------------------------------------------------------
-- Trigger: "trial balance for <ledger>", "net balance by account in USD".
-- Sums ACCOUNTED amounts (already in ledger currency, safe to sum) from posted
-- subledger detail, grouped by decoded account. If the requested target currency
-- differs from the ledger currency, convert the net with convert_to_ledger_currency
-- at the as-of date + rate type (gotcha 5). Restrict to postable detail accounts
-- (gotcha 12). NOTE: this reads XLA detail; for the SUMMARIZED posted GL number use
-- GL_BALANCES (owned by oracle-fusion-general-ledger) — pick ONE level (gotcha 9).
WITH lines AS (
    SELECT
        xl.code_combination_id,
        SUM(COALESCE(xl.accounted_dr, 0) - COALESCE(xl.accounted_cr, 0)) AS net_accounted
    FROM :catalog.:silver_schema.XLA_AE_LINES xl
    JOIN :catalog.:silver_schema.XLA_AE_HEADERS xh
          ON xh.ae_header_id = xl.ae_header_id
    WHERE xh.ledger_id = :ledger_id
      AND xh.accounting_entry_status_code = 'F'      -- Final entries only
      AND xh.gl_transfer_status_code = 'Y'           -- transferred to GL (gotcha 10)
      AND xh.period_name = :period_name
    GROUP BY xl.code_combination_id
)
SELECT
    cc.concatenated_segments,
    cc.account_type_name,
    cc.natural_account_name,
    l.net_accounted                                  AS net_ledger_currency,
    :catalog.:gold_schema.convert_to_ledger_currency(
        CAST(l.net_accounted AS DECIMAL(38,6)),
        led.currency_code, :target_currency, :as_of_date, :rate_type
    )                                                AS net_target_currency
FROM lines l
JOIN :catalog.:silver_schema.v_code_combination cc
      ON cc.code_combination_id = l.code_combination_id
JOIN :catalog.:silver_schema.GL_LEDGERS led
      ON led.ledger_id = :ledger_id
WHERE cc.detail_posting_allowed_flag = 'Y'           -- postable detail accounts only (gotcha 12)
  AND cc.enabled_flag = 'Y'
ORDER BY cc.concatenated_segments;


-- -----------------------------------------------------------------------------
-- 3. Which period is a date in, and is it open? (Trusted UDFs — prefer)
-- -----------------------------------------------------------------------------
-- Trigger: "what period is <date> in", "is that period still open for posting".
-- Both UDFs are scoped by ledger (period status is per-ledger, gotcha 7).
SELECT
    :as_of_date                                                      AS as_of_date,
    :catalog.:gold_schema.period_for_date(:ledger_id, :as_of_date)   AS period_name,
    :catalog.:gold_schema.is_period_open(
        :ledger_id,
        :catalog.:gold_schema.period_for_date(:ledger_id, :as_of_date)
    )                                                                AS is_period_open;


-- -----------------------------------------------------------------------------
-- 4. Last N closed periods for a ledger (chronological ordering)
-- -----------------------------------------------------------------------------
-- Trigger: "show the last 6 closed periods", "most recent finalized periods".
-- Orders by effective_period_number, NOT by period_name string (gotcha 6).
SELECT
    period_name,
    period_year,
    period_num,
    effective_period_number,
    closing_status_name,
    start_date,
    end_date
FROM :catalog.:silver_schema.v_gl_period
WHERE ledger_id = :ledger_id
  AND closing_status = 'C'              -- Closed = finalized
  AND adjustment_period_flag = 'N'
ORDER BY effective_period_number DESC
LIMIT 6;


-- -----------------------------------------------------------------------------
-- 5. Reconcile an XLA subledger total to its GL journal via GL_SL_LINK_ID
-- -----------------------------------------------------------------------------
-- Trigger: "reconcile the subledger to GL", "do AP lines tie to the GL journal".
-- This COMPARES the two levels (it does NOT add them — that would double-count,
-- gotcha 9). XLA detail rolls up into GL_JE_LINES; join on BOTH gl_sl_link_id AND
-- gl_sl_link_table. GL_JE_LINES is owned by oracle-fusion-general-ledger; this
-- block shows the bridge join for a reconciliation check.
WITH xla AS (
    SELECT
        xl.gl_sl_link_id,
        xl.gl_sl_link_table,
        SUM(COALESCE(xl.accounted_dr, 0)) AS xla_dr,
        SUM(COALESCE(xl.accounted_cr, 0)) AS xla_cr
    FROM :catalog.:silver_schema.XLA_AE_LINES xl
    JOIN :catalog.:silver_schema.XLA_AE_HEADERS xh
          ON xh.ae_header_id = xl.ae_header_id
    WHERE xh.ledger_id = :ledger_id
      AND xh.period_name = :period_name
      AND xh.gl_transfer_status_code = 'Y'
    GROUP BY xl.gl_sl_link_id, xl.gl_sl_link_table
),
gl AS (
    SELECT
        jl.gl_sl_link_id,                       -- verify physical name via glossary
        jl.gl_sl_link_table,                    -- verify physical name via glossary
        SUM(COALESCE(jl.accounted_dr, 0)) AS gl_dr,
        SUM(COALESCE(jl.accounted_cr, 0)) AS gl_cr
    FROM :catalog.:silver_schema.GL_JE_LINES jl  -- owned by oracle-fusion-general-ledger
    GROUP BY jl.gl_sl_link_id, jl.gl_sl_link_table
)
SELECT
    x.gl_sl_link_id,
    x.xla_dr, x.xla_cr,
    g.gl_dr,  g.gl_cr,
    (x.xla_dr - g.gl_dr) AS dr_diff,
    (x.xla_cr - g.gl_cr) AS cr_diff
FROM xla x
JOIN gl g
      ON g.gl_sl_link_id    = x.gl_sl_link_id
     AND g.gl_sl_link_table = x.gl_sl_link_table
WHERE (x.xla_dr - g.gl_dr) <> 0
   OR (x.xla_cr - g.gl_cr) <> 0       -- show only out-of-balance bridges
ORDER BY ABS(x.xla_dr - g.gl_dr) DESC;


-- -----------------------------------------------------------------------------
-- 6. Balancing segment values by legal entity (consolidation map)
-- -----------------------------------------------------------------------------
-- Trigger: "which legal entities are in this ledger", "list BSVs per LE",
-- "how do balancing segments map to legal entities".
-- BSV->LE is THE consolidation key (gotcha 11) — there is no LE column on a
-- journal line; you resolve LE through the balancing segment value.
SELECT
    ledger_name,
    legal_entity_name,
    legal_entity_id,
    collect_set(balancing_segment_value) AS balancing_segment_values
FROM :catalog.:silver_schema.v_ledger_org
WHERE ledger_id = :ledger_id
  AND legal_entity_id IS NOT NULL
GROUP BY ledger_name, legal_entity_name, legal_entity_id
ORDER BY legal_entity_name;


-- -----------------------------------------------------------------------------
-- 7. Activity by natural account, postable detail accounts only
-- -----------------------------------------------------------------------------
-- Trigger: "spend by natural account", "expense by account for the period".
-- Groups posted XLA detail by the decoded natural-account name, restricted to
-- postable detail, enabled, expense accounts. WHICH segment is the natural
-- account = customer config (gotcha 2) — v_code_combination decodes it from the
-- glossary-bound segment. Uses ACCOUNTED amounts (ledger currency, gotcha 4).
SELECT
    cc.natural_account_value,
    cc.natural_account_name,
    SUM(COALESCE(xl.accounted_dr, 0) - COALESCE(xl.accounted_cr, 0)) AS net_accounted
FROM :catalog.:silver_schema.XLA_AE_LINES xl
JOIN :catalog.:silver_schema.XLA_AE_HEADERS xh
      ON xh.ae_header_id = xl.ae_header_id
JOIN :catalog.:silver_schema.v_code_combination cc
      ON cc.code_combination_id = xl.code_combination_id
WHERE xh.ledger_id = :ledger_id
  AND xh.period_name = :period_name
  AND xh.accounting_entry_status_code = 'F'
  AND xh.gl_transfer_status_code = 'Y'
  AND cc.detail_posting_allowed_flag = 'Y'
  AND cc.enabled_flag = 'Y'
  AND cc.account_type = 'E'             -- Expense; change per the question
GROUP BY cc.natural_account_value, cc.natural_account_name
ORDER BY net_accounted DESC
LIMIT 100;
