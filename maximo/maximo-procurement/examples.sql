-- =============================================================================
-- Maximo Procurement — Gold-Standard Query Examples
-- =============================================================================
-- Bind these Databricks SQL parameters at execution time:
--   :catalog          customer UC catalog (e.g. eam)
--   :silver_schema    Silver schema with MBO tables (e.g. maximo_silver)
--   :gold_schema      Gold schema with the views in views.sql (e.g. maximo_gold)
--   :open_po_statuses multi-value list, e.g. ('WAPPR','INPRG','APPR','HOLD')
--   :vendor, :ponum, :siteid, :orgid  per-query value parameters
--
-- COST BASIS: examples use LINECOST (pretax). Per gotcha 4, confirm whether the
-- deployment's canonical cost is LINECOST or LOADEDCOST (RECEIPLINEORLOADED MAXVAR),
-- and decide on tax (TAX1-5) and credit/debit memos. STATUS: literals assume stock
-- values — resolve via SYNONYMDOMAIN when synonyms exist (gotcha 11 / overview gotcha 5).
-- REVISIONS: filter status <> 'REVISD' so revision history doesn't double-count (gotcha 2).
-- =============================================================================

-- Contents:
--   1.  Open PO backlog by site (synonym-safe, revision-aware)
--   2.  Vendor spend (LINECOST, current POs)
--   3.  PO cycle time — order to close (p50/p90)
--   4.  Three-way-match exceptions (invoiced beyond received)
--   5.  On-time delivery rate by vendor
--   6.  Open requisitions — PR lines not yet on a PO
--   7.  Under-received / overdue PO lines
--   8.  Top vendors by spend concentration (pareto)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Open PO backlog by site (synonym-safe, revision-aware)
-- -----------------------------------------------------------------------------
-- Trigger: "open PO backlog", "how many POs are open by site"
SELECT
    siteid,
    status,
    COUNT(*) AS open_po_count,
    ROUND(SUM(totalcost), 2) AS open_value
FROM :catalog.:silver_schema.po
WHERE status <> 'REVISD'                       -- exclude revision history
  AND status IN (
        SELECT value FROM :catalog.:silver_schema.synonymdomain
        WHERE domainid = 'POSTATUS'
          AND maxvalue IN ('WAPPR','INPRG','APPR','HOLD')   -- "open" internal values
      )
GROUP BY siteid, status
ORDER BY siteid, open_po_count DESC;


-- -----------------------------------------------------------------------------
-- 2. Vendor spend (LINECOST, current POs)
-- -----------------------------------------------------------------------------
-- Trigger: "spend by vendor", "top vendors"
-- LINECOST is pretax; switch to LOADEDCOST if that's the deployment's cost basis.
-- Built on v_po_enriched, which already excludes REVISD and dedups to the active
-- revision (gotcha 2). Vendor identity is COMPANY + ORGID (gotcha 9). Roll up by
-- COMPMASTER for enterprise-wide vendor spend across orgs.
SELECT
    p.vendor,
    p.vendor_name,
    p.orgid,
    COUNT(DISTINCT p.ponum)            AS po_count,
    ROUND(SUM(pl.linecost), 2)         AS line_spend
FROM :catalog.:gold_schema.v_po_enriched p
JOIN :catalog.:silver_schema.poline pl
      ON pl.ponum = p.ponum AND pl.siteid = p.siteid
WHERE p.orderdate >= date_trunc('YEAR', current_date())
GROUP BY p.vendor, p.vendor_name, p.orgid
ORDER BY line_spend DESC
LIMIT 50;


-- -----------------------------------------------------------------------------
-- 3. PO cycle time — order to close (p50/p90)
-- -----------------------------------------------------------------------------
-- Trigger: "PO cycle time", "how long from order to close"
SELECT
    siteid,
    COUNT(*) AS closed_po_count,
    ROUND(AVG(datediff(DAY, orderdate, statusdate)), 1)            AS avg_days,
    ROUND(PERCENTILE(datediff(DAY, orderdate, statusdate), 0.5), 1) AS p50_days,
    ROUND(PERCENTILE(datediff(DAY, orderdate, statusdate), 0.9), 1) AS p90_days
FROM :catalog.:silver_schema.po
WHERE status = 'CLOSE'
  AND orderdate IS NOT NULL
  AND statusdate >= add_months(current_date(), -12)
GROUP BY siteid
ORDER BY closed_po_count DESC;


-- -----------------------------------------------------------------------------
-- 4. Three-way-match exceptions (invoiced beyond received)
-- -----------------------------------------------------------------------------
-- Trigger: "invoices that failed three-way match", "invoiced more than received"
-- Uses v_invoice_match; receipt_gap = invoiced qty exceeds cumulative received qty.
SELECT
    invoicenum, siteid, invoicelinenum, vendor,
    ponum, polinenum,
    invoiced_qty, receivedqty, orderqty,
    invoice_linecost
FROM :catalog.:gold_schema.v_invoice_match
WHERE receipt_gap = true
  AND invoicetype = 'INVOICE'        -- exclude credit/debit memos (gotcha 7)
ORDER BY (invoiced_qty - COALESCE(receivedqty, 0)) DESC
LIMIT 100;


-- -----------------------------------------------------------------------------
-- 5. On-time delivery rate by vendor
-- -----------------------------------------------------------------------------
-- Trigger: "on-time delivery", "late deliveries by vendor"
-- On-time = the LAST material receipt for a line arrived on/before REQUIREDDATE
-- (i.e. the line was fully delivered by the need-by date). Partial receipts are
-- not excluded. Service lines (SERVRECTRANS) are excluded — union them if needed.
WITH last_receipt AS (
    SELECT ponum, siteid, polinenum, MAX(actualdate) AS last_receipt_date
    FROM :catalog.:silver_schema.matrectrans
    GROUP BY ponum, siteid, polinenum
)
SELECT
    p.vendor,
    COUNT(*) AS received_lines,
    ROUND(100.0 * SUM(CASE WHEN r.last_receipt_date <= pl.requireddate THEN 1 ELSE 0 END)
          / COUNT(*), 1) AS on_time_pct
FROM :catalog.:silver_schema.poline pl
JOIN :catalog.:gold_schema.v_po_enriched p
      ON p.ponum = pl.ponum AND p.siteid = pl.siteid
JOIN last_receipt r
      ON r.ponum = pl.ponum AND r.siteid = pl.siteid AND r.polinenum = pl.polinenum
WHERE pl.requireddate IS NOT NULL
GROUP BY p.vendor
ORDER BY on_time_pct ASC;


-- -----------------------------------------------------------------------------
-- 6. Open requisitions — PR lines not yet on a PO (true unmet demand)
-- -----------------------------------------------------------------------------
-- Trigger: "open requisitions", "requisitions not yet ordered"
-- A PR closes when ALL lines are transferred to POs, so "real" open demand =
-- PR lines whose PONUM link is still null (gotcha 3). Not the same as WAPPR.
SELECT
    pr.prnum, pr.siteid, pr.status AS pr_status,
    prl.prlinenum, prl.itemnum, prl.linetype, prl.orderqty, prl.linecost,
    prl.requireddate
FROM :catalog.:silver_schema.prline prl
JOIN :catalog.:silver_schema.pr pr
      ON pr.prnum = prl.prnum AND pr.siteid = prl.siteid
WHERE prl.ponum IS NULL                 -- not yet transferred to a PO
  AND pr.status NOT IN ('CAN', 'CLOSE')
ORDER BY prl.requireddate;


-- -----------------------------------------------------------------------------
-- 7. Under-received / overdue PO lines
-- -----------------------------------------------------------------------------
-- Trigger: "overdue POs", "what hasn't been delivered", "partial receipts"
SELECT
    ponum, siteid, polinenum, linetype, itemnum,
    orderqty, receivedqty, receipt_status,
    requireddate,
    datediff(DAY, requireddate, current_date()) AS days_overdue
FROM :catalog.:gold_schema.v_po_receipt_status
WHERE receipt_status IN ('not received', 'partial')
  AND requireddate < current_date()
ORDER BY days_overdue DESC
LIMIT 100;


-- -----------------------------------------------------------------------------
-- 8. Top vendors by spend concentration (pareto)
-- -----------------------------------------------------------------------------
-- Trigger: "vendor spend concentration", "what share of spend is our top vendors"
WITH vendor_spend AS (
    SELECT p.vendor, p.orgid, ROUND(SUM(pl.linecost), 2) AS spend
    FROM :catalog.:gold_schema.v_po_enriched p          -- active revision only (gotcha 2)
    JOIN :catalog.:silver_schema.poline pl
          ON pl.ponum = p.ponum AND pl.siteid = p.siteid
    WHERE p.orderdate >= add_months(current_date(), -12)
    GROUP BY p.vendor, p.orgid                           -- vendor is org-scoped (gotcha 9)
)
SELECT
    vendor,
    orgid,
    spend,
    ROUND(100.0 * spend / SUM(spend) OVER (), 2)                                   AS pct_of_total,
    ROUND(100.0 * SUM(spend) OVER (ORDER BY spend DESC) / SUM(spend) OVER (), 2)    AS cumulative_pct
FROM vendor_spend
ORDER BY spend DESC
LIMIT 50;
