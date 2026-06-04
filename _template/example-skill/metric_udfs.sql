-- ─────────────────────────────────────────────────────────────────────────────
-- Trusted Asset functions for Genie.
-- These are UC SQL functions: register them once (CREATE FUNCTION) so Genie
-- Spaces can call them as certified, governed metrics rather than regenerating
-- ad-hoc SQL. Substitute your catalog.schema before running.
-- See: https://docs.databricks.com/aws/en/genie/trusted-assets
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION :catalog.:schema.example_metric(p_site STRING)
RETURNS TABLE (site STRING, metric_value DOUBLE)
COMMENT 'Canonical definition of <metric>. Certified for Genie.'
RETURN
  SELECT SITEID AS site, COUNT(*)::DOUBLE AS metric_value
  FROM   :catalog.:schema.EXAMPLE_TABLE
  WHERE  deleted_at IS NULL
    AND  (p_site IS NULL OR SITEID = p_site)
  GROUP  BY SITEID;
