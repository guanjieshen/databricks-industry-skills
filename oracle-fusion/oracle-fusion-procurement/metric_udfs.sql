-- =============================================================================
-- Oracle Fusion Procurement — UC SQL Function (Metric UDF) DDL
-- =============================================================================
-- Trusted Asset functions for Genie. Register once (CREATE FUNCTION) so Genie
-- Code and Genie Agents call them as certified, governed metrics rather than
-- regenerating ad-hoc SQL. Ref: https://docs.databricks.com/aws/en/genie/trusted-assets
--
-- Bind these Databricks SQL parameters at registration time:
--   :catalog        → customer UC catalog
--   :silver_schema  → canonical procurement schema (PO_* tables, v_po_spend)
--   :gold_schema    → Gold/metrics schema where these functions live
--   :principal      → grant target (a group preferred, e.g. genie-users)
--
-- Each function is a single SQL statement (no procedural logic) so it can be
-- inlined into Genie's generated queries.
--
-- THE THREE SPEND BASES ARE DISTINCT (gotcha 1): ORDERED (commitment) vs RECEIVED
-- (goods in) vs BILLED (Payables-matched, PO-side). po_spend / supplier_spend take
-- a basis parameter so the choice is ALWAYS explicit — never collapse them into one
-- "spend". These read v_po_spend (distribution grain) so amounts sum correctly
-- (gotcha 2). Scope is by PRC_BU_ID (multi-org, gotcha 4); canceled POs excluded.
-- Currency is the PO entered currency — for cross-currency totals normalize via the
-- keystone convert_to_ledger_currency (oracle-fusion-ledger-coa); these UDFs do NOT.
-- =============================================================================

-- Ensure the metrics schema exists
CREATE SCHEMA IF NOT EXISTS :catalog.:gold_schema
COMMENT 'Trusted-asset SQL functions for Oracle Fusion procurement metrics';


-- -----------------------------------------------------------------------------
-- po_spend
-- -----------------------------------------------------------------------------
-- Trigger: "PO spend for BU X on a <basis> basis", "total committed spend"
-- Returns spend for a procurement BU on the chosen basis. spend_basis must be one
-- of 'ordered' / 'received' / 'billed' (gotcha 1) — the three are different numbers.
-- Excludes canceled POs (gotcha 5). Approved-only via APPROVED_FLAG.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:gold_schema.po_spend(
    prc_bu_id BIGINT COMMENT 'Procurement business unit (PO_HEADERS_ALL.PRC_BU_ID) — multi-org scope',
    spend_basis STRING COMMENT "Spend basis: one of 'ordered' (commitment), 'received' (goods in), 'billed' (Payables-matched). The three are DISTINCT (gotcha 1)."
)
RETURNS DECIMAL(38, 2)
COMMENT 'Trusted metric: approved, non-canceled PO spend for a procurement BU on the chosen basis (ordered/received/billed). Entered currency — normalize cross-currency via the keystone.'
RETURN (
    SELECT ROUND(SUM(
        CASE lower(spend_basis)
            WHEN 'ordered'  THEN sp.ordered_amount
            WHEN 'received' THEN sp.received_amount
            WHEN 'billed'   THEN sp.billed_amount
        END
    ), 2)
    FROM :catalog.:silver_schema.v_po_spend sp
    WHERE sp.prc_bu_id = prc_bu_id
      AND sp.cancel_flag = 'N'
      AND sp.approved_flag = 'Y'
);


-- -----------------------------------------------------------------------------
-- supplier_spend
-- -----------------------------------------------------------------------------
-- Trigger: "spend with supplier X", "how much have we spent with <vendor>"
-- Returns spend for one supplier (VENDOR_ID, all BUs) on the chosen basis.
-- Rolls up to the supplier, not the site (gotcha 7). Excludes canceled POs.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:gold_schema.supplier_spend(
    vendor_id BIGINT COMMENT 'Supplier (POZ_SUPPLIERS.VENDOR_ID). Rolls up the supplier, not the site (gotcha 7).',
    basis STRING COMMENT "Spend basis: one of 'ordered' / 'received' / 'billed' (gotcha 1)."
)
RETURNS DECIMAL(38, 2)
COMMENT 'Trusted metric: approved, non-canceled spend with one supplier on the chosen basis (ordered/received/billed). Entered currency — normalize cross-currency via the keystone.'
RETURN (
    SELECT ROUND(SUM(
        CASE lower(basis)
            WHEN 'ordered'  THEN sp.ordered_amount
            WHEN 'received' THEN sp.received_amount
            WHEN 'billed'   THEN sp.billed_amount
        END
    ), 2)
    FROM :catalog.:silver_schema.v_po_spend sp
    WHERE sp.vendor_id = vendor_id
      AND sp.cancel_flag = 'N'
      AND sp.approved_flag = 'Y'
);


-- -----------------------------------------------------------------------------
-- open_po_count
-- -----------------------------------------------------------------------------
-- Trigger: "how many open POs at BU X", "open purchase order backlog count"
-- Counts DISTINCT approved, non-canceled, not-finally-closed POs at a BU that
-- still have an open commitment (ordered > received). Counts headers (gotcha 2).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:gold_schema.open_po_count(
    prc_bu_id BIGINT COMMENT 'Procurement business unit (PO_HEADERS_ALL.PRC_BU_ID)'
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of open purchase orders (approved, not canceled, not finally closed, ordered > received) at a procurement BU.'
RETURN (
    SELECT COUNT(DISTINCT sch.po_header_id)
    FROM :catalog.:silver_schema.PO_HEADERS_ALL h
    JOIN :catalog.:silver_schema.PO_LINE_LOCATIONS_ALL sch
        ON sch.po_header_id = h.po_header_id
    WHERE h.prc_bu_id = prc_bu_id
      AND h.approved_flag = 'Y'
      AND h.cancel_flag = 'N'
      AND COALESCE(h.closed_code, 'OPEN') NOT IN ('CLOSED', 'FINALLY CLOSED')
      AND COALESCE(sch.quantity_received, 0) < sch.quantity
);


-- -----------------------------------------------------------------------------
-- three_way_match_exceptions
-- -----------------------------------------------------------------------------
-- Trigger: "3-way match exceptions for BU X", "billed-without-receipt count"
-- Counts receipt-required schedules where billed quantity exceeds received
-- quantity — the classic 3-way exception. Gated on RECEIPT_REQUIRED_FLAG = 'Y'
-- so non-receipt schedules are NOT false positives (gotcha 3).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:gold_schema.three_way_match_exceptions(
    prc_bu_id BIGINT COMMENT 'Procurement business unit (PO_HEADERS_ALL.PRC_BU_ID)'
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of receipt-required schedules (RECEIPT_REQUIRED_FLAG=Y) where QUANTITY_BILLED > QUANTITY_RECEIVED — a 3-way match exception (gotcha 3).'
RETURN (
    SELECT COUNT(*)
    FROM :catalog.:silver_schema.PO_HEADERS_ALL h
    JOIN :catalog.:silver_schema.PO_LINE_LOCATIONS_ALL sch
        ON sch.po_header_id = h.po_header_id
    WHERE h.prc_bu_id = prc_bu_id
      AND h.cancel_flag = 'N'
      AND sch.receipt_required_flag = 'Y'
      AND COALESCE(sch.quantity_billed, 0) > COALESCE(sch.quantity_received, 0)
);


-- =============================================================================
-- Grants — required for Genie to register these as Trusted assets.
-- Substitute :principal — a group is preferred (e.g. genie-users).
-- =============================================================================

-- GRANT USAGE ON SCHEMA :catalog.:gold_schema TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:gold_schema.po_spend                   TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:gold_schema.supplier_spend             TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:gold_schema.open_po_count              TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:gold_schema.three_way_match_exceptions TO `:principal`;
