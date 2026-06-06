-- =============================================================================
-- Maximo Procurement — UC SQL Function (Metric UDF) DDL
-- =============================================================================
-- Trusted Asset functions for Genie. Register once (CREATE FUNCTION) so Genie
-- calls them as certified, governed metrics rather than regenerating ad-hoc SQL.
-- Ref: https://docs.databricks.com/aws/en/genie/trusted-assets
--
-- Bind these Databricks SQL parameters at registration time:
--   :catalog        customer UC catalog (e.g. eam)
--   :silver_schema  Silver schema with MBO tables (e.g. maximo_silver)
--   :metrics_schema Gold/metrics schema where these functions live (e.g. maximo_metrics)
--   :principal      grant target (a group preferred, e.g. genie-users)
--
-- STATUS FILTERS use literal values, which are the STOCK Maximo internal values.
-- If the deployment has custom status synonyms, POSTATUS stores the synonym, not
-- the internal value — resolve via SYNONYMDOMAIN before registering, or counts
-- under-report (see maximo-overview gotcha 5). These do NOT filter HISTORYFLAG.
-- Each function is a single SQL statement so it inlines into Genie's queries.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS :catalog.:metrics_schema
COMMENT 'Trusted-asset SQL functions for Maximo procurement metrics';


-- -----------------------------------------------------------------------------
-- open_po_count
-- Trigger: "how many open purchase orders at <site>"
-- Active POs (not completed/closed/cancelled, excluding revision history) at a site.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.open_po_count(
    site STRING COMMENT 'SITEID'
)
RETURNS BIGINT
COMMENT 'Trusted metric: count of open purchase orders at a site (excludes CLOSE/CAN and REVISD revision-history rows). Status literals assume stock values — see maximo-overview gotcha 5.'
RETURN (
    SELECT COUNT(*)
    FROM :catalog.:silver_schema.po p
    WHERE p.siteid = site
      AND p.status NOT IN ('CLOSE', 'CAN', 'REVISD')
);


-- -----------------------------------------------------------------------------
-- po_line_received_pct
-- Trigger: "how much of this PO line has been received"
-- Cumulative received quantity as a percent of ordered quantity.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.po_line_received_pct(
    po STRING COMMENT 'PONUM',
    site STRING COMMENT 'SITEID',
    line INT COMMENT 'POLINENUM'
)
RETURNS DOUBLE
COMMENT 'Trusted metric: received quantity as a percent of ordered quantity for a PO line (POLINE.RECEIVEDQTY / ORDERQTY * 100).'
RETURN (
    SELECT CASE WHEN MAX(pl.orderqty) > 0
                THEN ROUND(100.0 * COALESCE(MAX(pl.receivedqty), 0) / MAX(pl.orderqty), 1)
                ELSE NULL END
    FROM :catalog.:silver_schema.poline pl
    WHERE pl.ponum = po AND pl.siteid = site AND pl.polinenum = line
);


-- -----------------------------------------------------------------------------
-- po_cycle_days
-- Trigger: "PO cycle time", "how long from order to close"
-- Elapsed days from PO order date to close (uses STATUSDATE for closed POs).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :catalog.:metrics_schema.po_cycle_days(
    po STRING COMMENT 'PONUM',
    site STRING COMMENT 'SITEID'
)
RETURNS INT
COMMENT 'Trusted metric: days from PO ORDERDATE to close (STATUSDATE while CLOSE). NULL if the PO is not yet closed. Excludes revision-history rows.'
RETURN (
    SELECT datediff(DAY, MAX(p.orderdate), MAX(p.statusdate))
    FROM :catalog.:silver_schema.po p
    WHERE p.ponum = po AND p.siteid = site
      AND p.status = 'CLOSE'
);


-- =============================================================================
-- Grants — required for Genie to register these as Trusted assets.
-- =============================================================================
-- GRANT USAGE   ON SCHEMA   :catalog.:metrics_schema TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.open_po_count       TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.po_line_received_pct TO `:principal`;
-- GRANT EXECUTE ON FUNCTION :catalog.:metrics_schema.po_cycle_days        TO `:principal`;
