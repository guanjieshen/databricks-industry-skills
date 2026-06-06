-- =============================================================================
-- Oracle Fusion Procurement — Pre-joined Delta Views
-- =============================================================================
-- Bind :catalog and :silver_schema (Databricks SQL parameters) to the customer's
-- catalog and Silver/canonical procurement schema at execution.
--
-- LANDING-AGNOSTIC: the table names below are the CANONICAL EBS-style names
-- (PO_HEADERS_ALL, PO_DISTRIBUTIONS_ALL, …). Fusion lands as BICC PVO extracts or
-- FDI artifacts with DIFFERENT physical names — resolve the physical→canonical
-- mapping via the <customer>-oracle-fusion-glossary (produced by
-- oracle-fusion-setup) before registering these. Never hard-code a physical name
-- here without checking the glossary; Fusion Cloud is SaaS (no raw-table access).
--
-- COMPOSES THE KEYSTONE: v_po_spend joins PO_DISTRIBUTIONS_ALL.CODE_COMBINATION_ID
-- to oracle-fusion-ledger-coa's v_code_combination for the decoded charged account
-- (company / cost center / natural account). This skill does NOT redefine that view.
--
-- These views encode the most-used joins so Genie and humans compose against a
-- smaller, denormalized surface (Databricks best practice: pre-join before Genie).
-- Register once via oracle-fusion-setup (preview-then-apply). UC column comments
-- are NOT set here — they are owned by oracle-fusion-setup.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_po_enriched
-- -----------------------------------------------------------------------------
-- Header + line + schedule joined, with supplier name and the decoded charged
-- account. SCHEDULE GRAIN (one row per PO_LINE_LOCATIONS_ALL schedule), with a
-- representative distribution's account decoded via the keystone. Use this for
-- "current state" / received-quantity / match-flag questions.
--
-- NOTE: this view does NOT pre-filter. Apply PRC_BU_ID scope, CANCEL_FLAG, and
-- CLOSED_CODE filters yourself per query (gotchas 4, 5). For spend AMOUNT totals
-- use v_po_spend (distribution grain) — summing amounts off this schedule-grain
-- view after the account join can fan out (gotcha 2).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:silver_schema.v_po_enriched
COMMENT 'Enriched Fusion PO schedule: header + line + schedule + supplier + decoded charged account. One row per schedule (PO_LINE_LOCATIONS_ALL).'
AS
SELECT
    h.po_header_id,
    h.segment1                                          AS po_number,
    h.prc_bu_id,
    h.type_lookup_code                                  AS po_type,
    h.agent_id                                          AS buyer_id,
    h.currency_code,
    h.approved_flag,
    h.cancel_flag                                       AS header_cancel_flag,
    h.closed_code                                       AS header_closed_code,
    h.creation_date                                     AS po_creation_date,
    h.approved_date                                     AS po_approved_date,
    -- Supplier
    h.vendor_id,
    s.vendor_name                                       AS supplier_name,
    h.vendor_site_id,
    -- Line (item grain)
    ln.po_line_id,
    ln.line_num,
    ln.item_id,
    ln.item_description,
    ln.category_id,
    ln.uom_code,
    ln.unit_price,
    ln.quantity                                         AS line_quantity,
    -- Schedule (received / match grain)
    sch.line_location_id,
    sch.quantity                                        AS scheduled_quantity,
    sch.quantity_received,
    sch.quantity_billed                                 AS schedule_quantity_billed,
    sch.quantity_accepted,
    sch.quantity_rejected,
    sch.receipt_required_flag,
    sch.inspection_required_flag,
    sch.match_option,
    sch.need_by_date,
    sch.promised_date,
    sch.closed_code                                     AS schedule_closed_code,
    -- Decoded charged account via the KEYSTONE (representative distribution).
    -- For multi-distribution splits, query v_po_spend at the distribution grain.
    cc.code_combination_id,
    cc.concatenated_segments                            AS account,
    cc.account_type
FROM :catalog.:silver_schema.PO_HEADERS_ALL h
LEFT JOIN :catalog.:silver_schema.POZ_SUPPLIERS s
       ON s.vendor_id = h.vendor_id
JOIN :catalog.:silver_schema.PO_LINES_ALL ln
       ON ln.po_header_id = h.po_header_id
JOIN :catalog.:silver_schema.PO_LINE_LOCATIONS_ALL sch
       ON sch.po_line_id = ln.po_line_id
LEFT JOIN :catalog.:silver_schema.PO_DISTRIBUTIONS_ALL d
       ON d.line_location_id = sch.line_location_id
      AND d.distribution_num = 1
-- KEYSTONE compose: decode the CCID to readable segments (oracle-fusion-ledger-coa)
LEFT JOIN :catalog.:silver_schema.v_code_combination cc
       ON cc.code_combination_id = d.code_combination_id;


-- -----------------------------------------------------------------------------
-- v_po_spend
-- -----------------------------------------------------------------------------
-- DISTRIBUTION GRAIN — the canonical home for spend AMOUNT and account analysis.
-- One row per PO_DISTRIBUTIONS_ALL distribution, carrying the three spend bases
-- side by side: ORDERED, RECEIVED, BILLED (gotcha 1 — distinct numbers, never
-- conflate). SUM over this view is correct because it is at the amount grain
-- (gotcha 2). Decoded account joined from the keystone v_code_combination.
--
-- ordered_amount  = QUANTITY_ORDERED  × line unit_price   (commitment)
-- received_amount = QUANTITY_DELIVERED × line unit_price   (goods in)
-- billed_amount   = AMOUNT_BILLED                          (Payables-matched, PO-side)
--
-- NOTE: no pre-filter. Apply PRC_BU_ID scope and CANCEL_FLAG / CLOSED_CODE per
-- query (gotchas 4, 5). For multi-currency totals, normalize to ledger currency
-- via the keystone convert_to_ledger_currency.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:silver_schema.v_po_spend
COMMENT 'PO spend at distribution grain with three distinct bases (ordered/received/billed) and decoded charged account. One row per PO_DISTRIBUTIONS_ALL. Never conflate the bases (gotcha 1).'
AS
SELECT
    d.po_distribution_id,
    d.po_header_id,
    d.po_line_id,
    d.line_location_id,
    d.distribution_num,
    d.req_distribution_id,
    -- Scope / slice columns
    h.prc_bu_id,
    h.segment1                                          AS po_number,
    h.type_lookup_code                                  AS po_type,
    h.agent_id                                          AS buyer_id,
    h.vendor_id,
    s.vendor_name                                       AS supplier_name,
    h.vendor_site_id,
    h.currency_code,
    h.approved_flag,
    h.cancel_flag,
    h.closed_code,
    h.creation_date                                     AS po_creation_date,
    h.approved_date                                     AS po_approved_date,
    ln.category_id,
    ln.unit_price,
    -- Decoded charged account via the KEYSTONE (oracle-fusion-ledger-coa)
    d.code_combination_id,
    cc.concatenated_segments                            AS account,
    cc.account_type,
    -- THE THREE SPEND BASES — distinct, never sum together (gotcha 1)
    d.quantity_ordered,
    d.quantity_delivered,
    d.quantity_billed,
    ROUND(d.quantity_ordered   * ln.unit_price, 2)      AS ordered_amount,
    ROUND(d.quantity_delivered * ln.unit_price, 2)      AS received_amount,
    ROUND(d.amount_billed, 2)                           AS billed_amount
FROM :catalog.:silver_schema.PO_DISTRIBUTIONS_ALL d
JOIN :catalog.:silver_schema.PO_HEADERS_ALL h
       ON h.po_header_id = d.po_header_id
JOIN :catalog.:silver_schema.PO_LINES_ALL ln
       ON ln.po_line_id = d.po_line_id
LEFT JOIN :catalog.:silver_schema.POZ_SUPPLIERS s
       ON s.vendor_id = h.vendor_id
-- KEYSTONE compose: decode the charged account (oracle-fusion-ledger-coa)
LEFT JOIN :catalog.:silver_schema.v_code_combination cc
       ON cc.code_combination_id = d.code_combination_id;

-- UC column comments on these views are NOT registered here. They are owned by
-- oracle-fusion-setup (which carries the canonical comment content and applies it
-- via the preview-then-apply script). Add comments there, not in this skill.
