-- =============================================================================
-- Oracle Fusion — Ledger & Chart of Accounts — UC SQL Function (Metric UDF) DDL
-- =============================================================================
-- Trusted Asset functions for Genie. Register once (CREATE FUNCTION) so Genie
-- Code and Genie Agents call them as certified, governed metrics rather than
-- regenerating ad-hoc accounting SQL. Ref: https://docs.databricks.com/aws/en/genie/trusted-assets
--
-- These functions are the CANONICAL CONTRACT the module skills depend on:
--   decode_ccid_segments, convert_to_ledger_currency, period_for_date, is_period_open
--
-- Bind these Databricks SQL parameters at registration time:
--   :catalog        → customer UC catalog
--   :silver_schema  → canonical Silver schema (GL/XLA mirror)
--   :gold_schema    → Gold/metrics schema where these functions live
--   :principal      → grant target (a group preferred, e.g. genie-users)
--
-- *** REGISTRATION & PHYSICAL NAMES ***
-- Registered ONCE via `oracle-fusion-setup`, not from this skill. Fusion is SaaS:
-- the table names referenced below are CANONICAL (EBS-style); the customer lands
-- BICC PVO / FDI artifacts under different names. `oracle-fusion-setup` substitutes
-- the real physical names from the `<customer>-oracle-fusion-glossary` at register
-- time. Lines marked `-- verify physical name via glossary` are inferred.
--
-- Each function is a single SQL statement (no procedural logic) so it can be
-- inlined into Genie's generated queries.
-- =============================================================================

-- Ensure the metrics schema exists
CREATE SCHEMA IF NOT EXISTS :catalog.:gold_schema
COMMENT 'Trusted-asset SQL functions for Oracle Fusion ledger / chart-of-accounts metrics';


-- -----------------------------------------------------------------------------
-- decode_ccid_segments
-- -----------------------------------------------------------------------------
-- Trigger: "what account is this CCID", "decode code combination", "show the
-- segments for combination N".
-- Returns the human-readable account breakdown for a CODE_COMBINATION_ID: the
-- concatenated segments, the account type, and the postable/summary flags as a
-- struct. Per-segment MEANING (which is cost center, etc.) is customer config —
-- resolve names via the glossary / FND_FLEX_VALUES_VL where needed.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:gold_schema.decode_ccid_segments(
    ccid BIGINT COMMENT 'GL_CODE_COMBINATIONS.CODE_COMBINATION_ID (integer key, not a string)'
)
RETURNS STRUCT<
    concatenated_segments: STRING,
    account_type: STRING,
    detail_posting_allowed_flag: STRING,
    summary_flag: STRING,
    enabled_flag: STRING
>
COMMENT 'Trusted metric: decode a CCID to its concatenated segments, account type (A/L/O/R/E), and postable/summary/enabled flags.'
RETURN (
    SELECT named_struct(
        'concatenated_segments',        cc.concatenated_segments,
        'account_type',                 cc.account_type,
        'detail_posting_allowed_flag',  cc.detail_posting_allowed_flag,
        'summary_flag',                 cc.summary_flag,
        'enabled_flag',                 cc.enabled_flag
    )
    FROM :catalog.:silver_schema.GL_CODE_COMBINATIONS cc
    WHERE cc.code_combination_id = ccid
);


-- -----------------------------------------------------------------------------
-- convert_to_ledger_currency
-- -----------------------------------------------------------------------------
-- Trigger: "convert this amount to <currency>", "what is X EUR in USD on <date>".
-- Converts an amount from one currency to another using GL_DAILY_RATES, keyed on
-- (from, to, conversion_date, rate_type). Returns the converted amount, or NULL
-- if no rate exists for that (date, type) — DON'T treat NULL as zero (gotcha 5).
-- NOTE: prefer pre-computed ACCOUNTED_* amounts when the target IS the ledger
-- currency; use this only to convert to a DIFFERENT target currency.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:gold_schema.convert_to_ledger_currency(
    amount DECIMAL(38, 6) COMMENT 'Source amount in from_ccy',
    from_ccy STRING       COMMENT 'ISO source currency (e.g. EUR)',
    to_ccy STRING         COMMENT 'ISO target currency (e.g. USD)',
    conv_date DATE        COMMENT 'Conversion / accounting date to match the rate',
    rate_type STRING      COMMENT 'GL_DAILY_RATES.CONVERSION_TYPE — Spot / Corporate / User / Fixed'
)
RETURNS DECIMAL(38, 6)
COMMENT 'Trusted metric: convert an amount between currencies via GL_DAILY_RATES for a given date and rate type. Returns NULL if no rate row exists (do not coalesce to 0).'
RETURN (
    SELECT CASE
        WHEN from_ccy = to_ccy THEN amount
        ELSE amount * r.conversion_rate
    END
    FROM :catalog.:silver_schema.GL_DAILY_RATES r
    WHERE r.from_currency  = from_ccy
      AND r.to_currency    = to_ccy
      AND r.conversion_date = conv_date
      AND r.conversion_type = rate_type
);


-- -----------------------------------------------------------------------------
-- period_for_date
-- -----------------------------------------------------------------------------
-- Trigger: "which period is <date> in", "what GL period does this fall in".
-- Returns the PERIOD_NAME whose START_DATE..END_DATE contains the given date for
-- the ledger's calendar. Excludes adjustment periods by default so a normal date
-- maps to its normal month, not an overlapping Adj period (gotcha 8).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:gold_schema.period_for_date(
    p_ledger_id BIGINT COMMENT 'GL_LEDGERS.LEDGER_ID — selects the calendar',
    p_date DATE        COMMENT 'Date to map to a period'
)
RETURNS STRING
COMMENT 'Trusted metric: the GL PERIOD_NAME containing a date for a ledger calendar. Excludes adjustment periods (returns the normal period).'
RETURN (
    SELECT p.period_name
    FROM :catalog.:silver_schema.GL_PERIODS p
    JOIN :catalog.:silver_schema.GL_LEDGERS l
          ON l.period_set_name = p.period_set_name
    WHERE l.ledger_id = p_ledger_id
      AND p_date BETWEEN p.start_date AND p.end_date
      AND p.adjustment_period_flag = 'N'
    -- Defensive: if calendars overlap, take the chronologically-first match
    ORDER BY (p.period_year * 10000 + p.period_num)
    LIMIT 1
);


-- -----------------------------------------------------------------------------
-- is_period_open
-- -----------------------------------------------------------------------------
-- Trigger: "is <period> open", "can we still post to <period>".
-- TRUE only when the per-ledger CLOSING_STATUS is 'O' (Open). Status is per
-- ledger + period (gotcha 7), so both args are required.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:gold_schema.is_period_open(
    p_ledger_id BIGINT  COMMENT 'GL_LEDGERS.LEDGER_ID',
    p_period_name STRING COMMENT 'GL_PERIODS.PERIOD_NAME'
)
RETURNS BOOLEAN
COMMENT 'Trusted metric: TRUE when the period is Open (CLOSING_STATUS = O) for the given ledger, else FALSE. Status is per-ledger.'
RETURN (
    SELECT MAX(ps.closing_status = 'O')
    FROM :catalog.:silver_schema.GL_PERIOD_STATUSES ps
    WHERE ps.ledger_id = p_ledger_id
      AND ps.period_name = p_period_name
      AND ps.application_id = 101   -- GL application; verify physical id via glossary
);


-- =============================================================================
-- Grants — required for Genie to register these as Trusted assets.
-- Substitute :principal — a group is preferred (e.g. genie-users).
-- =============================================================================

-- GRANT USAGE ON SCHEMA :catalog.:gold_schema TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:gold_schema.decode_ccid_segments        TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:gold_schema.convert_to_ledger_currency  TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:gold_schema.period_for_date             TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:gold_schema.is_period_open              TO `:principal`;
