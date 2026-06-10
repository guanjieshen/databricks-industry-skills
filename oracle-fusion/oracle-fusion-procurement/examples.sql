-- =============================================================================
-- Oracle Fusion Procurement — Gold-Standard Query Examples
-- =============================================================================
-- Each block is a parameterized template that maps to a single analytical
-- question. Bind these Databricks SQL parameters at execution time:
--   :catalog          → the customer's UC catalog
--   :silver_schema    → canonical procurement schema (PO_* tables + v_po_enriched / v_po_spend)
--   :gold_schema      → Gold/metrics schema with the Trusted UDFs (only for UDF examples)
--   :prc_bu_id        → procurement business unit scope (PO_HEADERS_ALL.PRC_BU_ID)
--   :spend_basis      → 'ordered' | 'received' | 'billed'  (gotcha 1 — pick ONE)
--   :vendor_id        → supplier (POZ_SUPPLIERS.VENDOR_ID)
-- These examples assume views.sql and metric_udfs.sql have been registered.
-- Workflow priority: if a Trusted UDF matches the question, prefer it (SKILL.md §Workflow).
--
-- THREE SPEND BASES ARE DISTINCT (gotcha 1): ORDERED ≠ RECEIVED ≠ BILLED. Every
-- "spend" query below takes a basis — never report one as another. Scope by
-- PRC_BU_ID (multi-org, gotcha 4); exclude canceled / finally-closed (gotcha 5).
-- For cross-currency totals, normalize to ledger currency via the keystone
-- convert_to_ledger_currency (oracle-fusion-ledger-coa). Account/cost-center decode
-- COMPOSES the keystone v_code_combination — never assume segment positions.
-- =============================================================================
--
-- Contents (load the block that matches the question):
--   1a. PO spend for a BU on a chosen basis (Trusted UDF)
--   1b. PO spend by supplier on a chosen basis (view-based)
--   2.  Open PO backlog by business unit
--   3.  3-way match exceptions (receipt-required schedules)
--   4.  Requisition-to-PO cycle time
--   5.  Contract vs non-contract spend (leakage)
--   6.  Spend by cost center via the keystone CCID decode
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1a. PO spend for a BU on a chosen basis (Trusted UDF — prefer this)
-- -----------------------------------------------------------------------------
-- Trigger: "total PO spend for BU X (ordered / received / billed)"
-- The po_spend UDF is the governed metric. Use for a single number for one BU on
-- one basis. For breakdowns (by supplier, category, …) fall through to 1b.
SELECT :catalog.:gold_schema.po_spend(:prc_bu_id, :spend_basis) AS po_spend;


-- -----------------------------------------------------------------------------
-- 1b. PO spend by supplier on a chosen basis (view-based)
-- -----------------------------------------------------------------------------
-- Trigger: "spend by supplier", "top suppliers by ordered/received/billed spend"
-- Distribution grain (v_po_spend) so amounts sum correctly (gotcha 2). The CASE
-- selects the basis (gotcha 1). Rolls up to the supplier, not the site (gotcha 7).
SELECT
    sp.vendor_id,
    sp.supplier_name,
    ROUND(SUM(
        CASE :spend_basis
            WHEN 'ordered'  THEN sp.ordered_amount
            WHEN 'received' THEN sp.received_amount
            WHEN 'billed'   THEN sp.billed_amount
        END
    ), 2) AS spend
FROM :catalog.:silver_schema.v_po_spend sp
WHERE sp.prc_bu_id = :prc_bu_id
  AND sp.cancel_flag = 'N'
  AND sp.approved_flag = 'Y'
GROUP BY sp.vendor_id, sp.supplier_name
ORDER BY spend DESC
LIMIT 50;


-- -----------------------------------------------------------------------------
-- 2. Open PO backlog by business unit
-- -----------------------------------------------------------------------------
-- Trigger: "open PO backlog", "open purchase orders by BU", "committed but not received"
-- Open = approved, not canceled, not finally closed, with ordered > received at the
-- schedule grain (gotcha 5). Counts distinct headers (gotcha 2) and the open
-- committed value still outstanding.
SELECT
    h.prc_bu_id,
    COUNT(DISTINCT h.po_header_id) AS open_po_count,
    ROUND(SUM((sch.quantity - COALESCE(sch.quantity_received, 0)) * ln.unit_price), 2) AS open_committed_amount
FROM :catalog.:silver_schema.PO_HEADERS_ALL h
JOIN :catalog.:silver_schema.PO_LINES_ALL ln
    ON ln.po_header_id = h.po_header_id
JOIN :catalog.:silver_schema.PO_LINE_LOCATIONS_ALL sch
    ON sch.po_line_id = ln.po_line_id
WHERE h.approved_flag = 'Y'
  AND h.cancel_flag = 'N'
  AND COALESCE(h.closed_code, 'OPEN') NOT IN ('CLOSED', 'FINALLY CLOSED')
  AND COALESCE(sch.quantity_received, 0) < sch.quantity
GROUP BY h.prc_bu_id
ORDER BY open_committed_amount DESC;


-- -----------------------------------------------------------------------------
-- 3. 3-way match exceptions (receipt-required schedules)
-- -----------------------------------------------------------------------------
-- Trigger: "3-way match exceptions", "billed more than received"
-- A 3-way exception applies ONLY where RECEIPT_REQUIRED_FLAG = 'Y' (gotcha 3) —
-- otherwise services with no receipt are false positives. Flags billed > received.
SELECT
    h.prc_bu_id,
    h.segment1 AS po_number,
    h.vendor_id,
    s.vendor_name,
    sch.line_location_id,
    sch.quantity            AS ordered_qty,
    sch.quantity_received   AS received_qty,
    sch.quantity_billed     AS billed_qty,
    (COALESCE(sch.quantity_billed, 0) - COALESCE(sch.quantity_received, 0)) AS billed_over_received
FROM :catalog.:silver_schema.PO_HEADERS_ALL h
JOIN :catalog.:silver_schema.PO_LINE_LOCATIONS_ALL sch
    ON sch.po_header_id = h.po_header_id
LEFT JOIN :catalog.:silver_schema.POZ_SUPPLIERS s
    ON s.vendor_id = h.vendor_id
WHERE h.prc_bu_id = :prc_bu_id
  AND h.cancel_flag = 'N'
  AND sch.receipt_required_flag = 'Y'
  AND COALESCE(sch.quantity_billed, 0) > COALESCE(sch.quantity_received, 0)
ORDER BY billed_over_received DESC
LIMIT 100;


-- -----------------------------------------------------------------------------
-- 4. Requisition-to-PO cycle time
-- -----------------------------------------------------------------------------
-- Trigger: "req to PO cycle time", "how long from requisition to purchase order"
-- The link is via the distribution back-reference REQ_DISTRIBUTION_ID, NOT a
-- header FK (gotcha 9). Dedup to one (requisition, PO) pair before measuring days
-- from requisition approval to PO approval.
WITH req_to_po AS (
    SELECT DISTINCT
        r.requisition_header_id,
        r.requisition_number,
        r.prc_bu_id,
        r.approved_date AS req_approved_date,
        h.po_header_id,
        h.segment1      AS po_number,
        h.approved_date AS po_approved_date
    FROM :catalog.:silver_schema.POR_REQUISITION_HEADERS_ALL r
    JOIN :catalog.:silver_schema.POR_REQ_DISTRIBUTIONS_ALL rd
        ON rd.requisition_header_id = r.requisition_header_id
    JOIN :catalog.:silver_schema.PO_DISTRIBUTIONS_ALL d
        ON d.req_distribution_id = rd.distribution_id
    JOIN :catalog.:silver_schema.PO_HEADERS_ALL h
        ON h.po_header_id = d.po_header_id
    WHERE r.prc_bu_id = :prc_bu_id
      AND r.cancel_flag = 'N'
      AND h.cancel_flag = 'N'
)
SELECT
    prc_bu_id,
    COUNT(*) AS converted_pairs,
    ROUND(AVG(datediff(DAY, req_approved_date, po_approved_date)), 1) AS avg_days_req_to_po,
    ROUND(PERCENTILE(datediff(DAY, req_approved_date, po_approved_date), 0.5), 1) AS p50_days,
    ROUND(PERCENTILE(datediff(DAY, req_approved_date, po_approved_date), 0.9), 1) AS p90_days
FROM req_to_po
WHERE po_approved_date IS NOT NULL
  AND req_approved_date IS NOT NULL
GROUP BY prc_bu_id;


-- -----------------------------------------------------------------------------
-- 5. Contract vs non-contract spend (leakage)
-- -----------------------------------------------------------------------------
-- Trigger: "contract leakage", "off-contract spend", "maverick spend"
-- Splits ordered spend into spend under an agreement (BPA releases / CONTRACT)
-- vs standalone STANDARD POs. High non-contract share = leakage. Note BPA releases
-- are their own PO rows (gotcha 6); here we classify by the PO's own TYPE_LOOKUP_CODE.
SELECT
    sp.prc_bu_id,
    CASE
        WHEN sp.po_type IN ('BLANKET', 'CONTRACT', 'PLANNED') THEN 'On-contract'
        ELSE 'Off-contract'
    END AS contract_status,
    COUNT(DISTINCT sp.po_header_id) AS po_count,
    ROUND(SUM(sp.ordered_amount), 2) AS ordered_amount,
    ROUND(100.0 * SUM(sp.ordered_amount)
          / SUM(SUM(sp.ordered_amount)) OVER (PARTITION BY sp.prc_bu_id), 1) AS pct_of_bu_spend
FROM :catalog.:silver_schema.v_po_spend sp
WHERE sp.prc_bu_id = :prc_bu_id
  AND sp.cancel_flag = 'N'
  AND sp.approved_flag = 'Y'
GROUP BY sp.prc_bu_id, contract_status
ORDER BY ordered_amount DESC;


-- -----------------------------------------------------------------------------
-- 6. Spend by cost center via the keystone CCID decode
-- -----------------------------------------------------------------------------
-- Trigger: "spend by cost center", "PO spend by account", "spend by department"
-- COMPOSES the keystone (oracle-fusion-ledger-coa): the charged account on the PO
-- distribution is a CODE_COMBINATION_ID; decode it via decode_ccid_segments to the
-- cost-center segment. SEGMENT POSITIONS ARE CUSTOMER CONFIG — resolve which segment
-- is cost center via the glossary; do NOT assume (overview gotcha 2). v_po_spend is
-- distribution grain so the account-level sum is correct (gotcha 2).
SELECT
    sp.prc_bu_id,
    :catalog.:gold_schema.decode_ccid_segments(sp.code_combination_id, 'COST_CENTER') AS cost_center,
    ROUND(SUM(sp.ordered_amount), 2) AS ordered_amount,
    ROUND(SUM(sp.billed_amount), 2)  AS billed_amount
FROM :catalog.:silver_schema.v_po_spend sp
WHERE sp.prc_bu_id = :prc_bu_id
  AND sp.cancel_flag = 'N'
  AND sp.approved_flag = 'Y'
GROUP BY sp.prc_bu_id,
    :catalog.:gold_schema.decode_ccid_segments(sp.code_combination_id, 'COST_CENTER')
ORDER BY ordered_amount DESC
LIMIT 50;
