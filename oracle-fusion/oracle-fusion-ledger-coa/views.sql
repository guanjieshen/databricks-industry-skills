-- =============================================================================
-- Oracle Fusion — Ledger & Chart of Accounts — Pre-joined Delta Views
-- =============================================================================
-- Bind :catalog and :silver_schema (Databricks SQL parameters) to the customer's
-- catalog and canonical Silver schema (the GL/XLA mirror) at execution.
--
-- These views encode the most-used accounting-foundation joins so Genie (Code or
-- Space) and humans compose against a smaller, denormalized surface — per the
-- Databricks best practice "denormalize and pre-join before exposing to Genie."
--
-- *** REGISTRATION & PHYSICAL NAMES ***
-- These views are registered ONCE via `oracle-fusion-setup`, not from this skill.
-- The FROM/JOIN names below are the CANONICAL Fusion (EBS-style) physical names.
-- Fusion Cloud is SaaS — the customer actually receives BICC PVO extracts or FDI
-- star-schema artifacts with DIFFERENT physical names. The physical->canonical
-- mapping for THIS customer lives in the `<customer>-oracle-fusion-glossary` skill.
-- `oracle-fusion-setup` substitutes the real physical names when it registers
-- these. Do not hard-code a physical name without checking the glossary.
-- Lines marked `-- verify physical name via glossary` are inferred, not verified.
--
-- UC column comments on these views are NOT registered here — they are owned by
-- `oracle-fusion-setup` (preview-then-apply). Add comment content there.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_code_combination
-- -----------------------------------------------------------------------------
-- The account-decode view. One row per CODE_COMBINATION_ID (CCID): the raw
-- segments, the human-readable concatenation, the account type, the postable/
-- summary flags, and the decoded NATURAL-ACCOUNT name.
--
-- NOTE: WHICH segment is the natural account is CUSTOMER CONFIG (gotcha 2). The
-- `:natural_account_segment` placeholder and `:natural_account_value_set_id` below
-- MUST be bound from the glossary at registration; the literal SEGMENT4 reference
-- is a PLACEHOLDER example only. Deeper per-segment name decode (cost center,
-- company, etc.) composes FND_FLEX_VALUES_VL the same way per segment.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:silver_schema.v_code_combination
COMMENT 'Chart-of-accounts code combinations with decoded natural-account name, account type, and postable/summary flags. One row per CCID. Segment->meaning is customer config (glossary).'
AS
SELECT
    cc.code_combination_id,
    cc.chart_of_accounts_id,
    cc.concatenated_segments,
    cc.segment1,
    cc.segment2,
    cc.segment3,
    cc.segment4,
    cc.segment5,
    -- ... SEGMENT6..SEGMENT30 pass through as needed; trimmed for readability
    cc.account_type,                                  -- A/L/O/R/E
    CASE cc.account_type
        WHEN 'A' THEN 'Asset'
        WHEN 'L' THEN 'Liability'
        WHEN 'O' THEN 'Owners Equity'
        WHEN 'R' THEN 'Revenue'
        WHEN 'E' THEN 'Expense'
        ELSE cc.account_type
    END                                               AS account_type_name,
    cc.enabled_flag,
    cc.detail_posting_allowed_flag,                   -- 'Y' = postable detail account
    cc.summary_flag,                                  -- 'Y' = rollup/summary account (don't mix, gotcha 12)
    cc.start_date_active,
    cc.end_date_active,
    -- Decoded SEMANTIC segments. The SEGMENTn positions below are PLACEHOLDERS —
    -- which segment is the natural account / balancing segment / cost center is
    -- CUSTOMER CONFIG (gotcha 2); bind the real positions from the glossary at
    -- registration. This view is the ONE place segment->meaning is resolved, so
    -- the rest of the family consumes semantic columns (balancing_segment_value,
    -- natural_account_value, cost_center_value), never raw SEGMENTn positions.
    cc.segment1                                       AS balancing_segment_value,  -- bind balancing-segment position via glossary
    fv.flex_value                                     AS natural_account_value,    -- SEGMENT4 placeholder — bind via glossary
    fv.description                                    AS natural_account_name,
    cc.segment3                                       AS cost_center_value         -- bind cost-center position via glossary
FROM :catalog.:silver_schema.GL_CODE_COMBINATIONS cc
LEFT JOIN :catalog.:silver_schema.FND_FLEX_VALUES_VL fv          -- verify physical name via glossary
       ON fv.flex_value = cc.segment4                            -- verify natural-account segment via glossary
      AND fv.flex_value_set_id = :natural_account_value_set_id;  -- bind from glossary


-- -----------------------------------------------------------------------------
-- v_gl_period
-- -----------------------------------------------------------------------------
-- The period view. One row per (ledger, period): the calendar definition joined
-- to the per-ledger open/close status, plus the chronological sort key. ALWAYS
-- sort/range by effective_period_number, never by period_name (gotcha 6). Status
-- is per-ledger, so this view is keyed on ledger_id (gotcha 7).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:silver_schema.v_gl_period
COMMENT 'Accounting periods joined to per-ledger open/close status with a chronological sort key. One row per (ledger_id, period_name). Sort by effective_period_number, not period_name.'
AS
SELECT
    ps.ledger_id,
    p.period_set_name,
    p.period_name,
    p.period_type,
    p.period_year,
    p.period_num,
    p.quarter_num,
    p.start_date,
    p.end_date,
    p.adjustment_period_flag,                          -- 'Y' overlaps normal-period dates (gotcha 8)
    (p.period_year * 10000 + p.period_num)  AS effective_period_number,  -- chronological sort key
    ps.closing_status,                                 -- O/C/F/N/P/W
    CASE ps.closing_status
        WHEN 'O' THEN 'Open'
        WHEN 'C' THEN 'Closed'
        WHEN 'F' THEN 'Future Enterable'
        WHEN 'N' THEN 'Never Opened'
        WHEN 'P' THEN 'Permanently Closed'
        WHEN 'W' THEN 'Close Pending'
        ELSE ps.closing_status
    END                                     AS closing_status_name,
    (ps.closing_status = 'O')               AS is_open
FROM :catalog.:silver_schema.GL_PERIODS p
JOIN :catalog.:silver_schema.GL_PERIOD_STATUSES ps
      ON ps.period_name = p.period_name
     AND ps.application_id = 101            -- GL application; verify physical id via glossary
-- The period status calendar is shared via the ledger's PERIOD_SET_NAME; join
-- GL_LEDGERS to constrain to a single calendar if a customer has multiple.
JOIN :catalog.:silver_schema.GL_LEDGERS l
      ON l.ledger_id = ps.ledger_id
     AND l.period_set_name = p.period_set_name;


-- -----------------------------------------------------------------------------
-- v_ledger_org
-- -----------------------------------------------------------------------------
-- The org-resolution view. Maps a ledger to its legal entities (via balancing
-- segment value assignment) and business units. Use to resolve "by legal entity"
-- and "which BU" questions. BSV->LE is the consolidation link (gotcha 11); there
-- is no raw LE column on a journal line.
--
-- The LE / BU / BSV assignment tables are the names that vary MOST by landing
-- pattern — every source table here is glossary-resolved.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:silver_schema.v_ledger_org
COMMENT 'Ledger to legal-entity (via balancing segment value) and business-unit resolution. One row per (ledger, balancing_segment_value, business_unit). BSV->LE is the consolidation key.'
AS
SELECT
    l.ledger_id,
    l.name                                  AS ledger_name,
    l.ledger_category_code,                 -- PRIMARY / SECONDARY / ALC (gotcha 13)
    l.chart_of_accounts_id,
    l.currency_code                         AS ledger_currency_code,
    l.period_set_name,
    l.sla_accounting_method_code,
    bsv.balancing_segment_value,            -- the BSV (read off the balancing segment of the CCID)
    le.legal_entity_id,
    le.name                                 AS legal_entity_name,
    bu.bu_id                                AS business_unit_id,
    bu.bu_name                              AS business_unit_name
FROM :catalog.:silver_schema.GL_LEDGERS l
LEFT JOIN :catalog.:silver_schema.GL_LEGAL_ENTITIES_BSV bsv      -- verify physical name via glossary
       ON bsv.ledger_id = l.ledger_id
LEFT JOIN :catalog.:silver_schema.XLE_ENTITY_PROFILES le         -- verify physical name via glossary
       ON le.legal_entity_id = bsv.legal_entity_id
LEFT JOIN :catalog.:silver_schema.FUN_ALL_BUSINESS_UNITS_V bu    -- verify physical name via glossary
       ON bu.primary_ledger_id = l.ledger_id;
