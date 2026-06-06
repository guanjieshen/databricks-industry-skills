-- =============================================================================
-- Maximo Procurement — Pre-joined Gold Views
-- =============================================================================
-- Bind these Databricks SQL parameters before running:
--   :catalog          customer UC catalog (e.g. eam)
--   :silver_schema    Silver schema with the MBO tables (e.g. maximo_silver)
--   :gold_schema      Gold schema for consumption views (e.g. maximo_gold)
--
-- These encode the most-used purchasing joins. Register once via maximo-setup
-- (preview-then-apply) — never run writes from the skill.
--
-- NOTE: views do NOT pre-filter status/history. Apply the active-revision rule
-- (status <> 'REVISD') and HISTORYFLAG/SYNONYMDOMAIN patterns per query
-- (see gotchas 2 and 11, and maximo-overview gotchas 5-6).
-- =============================================================================

-- Contents:
--   v_po_enriched        — active PO header + vendor, one row per current PO
--   v_po_receipt_status  — PO line ordered vs received, with a receipt bucket
--   v_invoice_match      — invoice line ↔ PO line ↔ received qty (3-way match)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_po_enriched
-- Active (non-revision-history) PO headers with vendor name and derived age.
-- One row per current PO. Filter further (status set, historyflag) per query.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_po_enriched
COMMENT 'Current purchase-order headers (revision history excluded) with vendor name and derived age. One row per active (siteid, ponum).'
AS
SELECT
    p.ponum,
    p.siteid,
    p.orgid,
    p.revisionnum,
    p.status,
    p.statusdate,
    p.potype,
    p.vendor,
    c.name                                            AS vendor_name,
    p.orderdate,
    p.totalcost,
    p.contractrefnum,
    p.historyflag,
    datediff(DAY, p.orderdate, current_date())        AS days_since_ordered
FROM :catalog.:silver_schema.po p
LEFT JOIN :catalog.:silver_schema.companies c
       ON c.company = p.vendor
      AND c.orgid   = p.orgid
WHERE p.status <> 'REVISD'   -- active revision only (gotcha 2)
QUALIFY ROW_NUMBER() OVER (PARTITION BY p.siteid, p.ponum ORDER BY p.revisionnum DESC) = 1;


-- -----------------------------------------------------------------------------
-- v_po_receipt_status
-- PO line ordered vs received quantity, with a receipt-completeness bucket.
-- Use for open/under-received backlog and fulfillment analytics.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_po_receipt_status
COMMENT 'Per PO line: ordered vs cumulative received quantity and a receipt-completeness bucket. One row per (siteid, ponum, polinenum) on the active revision.'
AS
SELECT
    pl.ponum,
    pl.siteid,
    pl.polinenum,
    pl.linetype,
    pl.itemnum,
    pl.orderqty,
    pl.receivedqty,
    pl.linecost,
    pl.loadedcost,
    pl.requireddate,
    CASE
        WHEN COALESCE(pl.receivedqty, 0) = 0                          THEN 'not received'
        WHEN pl.orderqty IS NOT NULL
         AND pl.receivedqty >= pl.orderqty                            THEN 'fully received'
        ELSE 'partial'
    END                                                       AS receipt_status
FROM :catalog.:silver_schema.poline pl
JOIN :catalog.:gold_schema.v_po_enriched p
      ON p.ponum  = pl.ponum
     AND p.siteid = pl.siteid;


-- -----------------------------------------------------------------------------
-- v_invoice_match
-- Invoice lines joined to their PO line and the received quantity, to expose
-- three-way-match gaps (received-required lines lacking matching receipts).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW :catalog.:gold_schema.v_invoice_match
COMMENT 'Invoice lines matched to PO line and cumulative received quantity. One row per invoice line; receipt_gap flags lines invoiced beyond what was received.'
AS
SELECT
    il.invoicenum,
    il.siteid,
    il.invoicelinenum,
    i.status                                          AS invoice_status,
    i.invoicetype,
    i.vendor,
    il.ponum,
    il.polinenum,
    il.quantity                                       AS invoiced_qty,
    pl.orderqty,
    pl.receivedqty,
    il.linecost                                       AS invoice_linecost,
    pl.linecost                                       AS po_linecost,
    (il.quantity > COALESCE(pl.receivedqty, 0))       AS receipt_gap
FROM :catalog.:silver_schema.invoiceline il
JOIN :catalog.:silver_schema.invoice i
      ON i.invoicenum = il.invoicenum
     AND i.siteid     = il.siteid
LEFT JOIN :catalog.:silver_schema.poline pl
      ON pl.ponum     = il.ponum
     AND pl.siteid    = il.siteid
     AND pl.polinenum = il.polinenum;
