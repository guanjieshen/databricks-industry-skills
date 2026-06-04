-- =============================================================================
-- Maximo Reliability — Gold Views
-- =============================================================================
-- Most reliability queries compose against v_failure_events, v_pm_schedule
-- (already shipped by maximo-data-engineering's gold_views.sql) and the
-- meter-excursion view added here.
--
-- Substitute {{catalog}}.{{silver_schema}} and {{catalog}}.{{gold_schema}}.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_meter_excursions
-- Meter readings that breached configured action thresholds.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_meter_excursions
COMMENT 'Meter readings that exceeded an ASSETMETER action threshold. One row per excursion. Use for condition-monitoring exception analytics.'
AS
SELECT
    mr.assetnum,
    mr.siteid,
    mr.metername,
    mr.readingdate,
    mr.reading,
    am.actionlimitlo,
    am.actionlimithi,
    CASE
        WHEN am.actionlimithi IS NOT NULL AND mr.reading > am.actionlimithi
            THEN 'ABOVE_HIGH'
        WHEN am.actionlimitlo IS NOT NULL AND mr.reading < am.actionlimitlo
            THEN 'BELOW_LOW'
    END AS excursion_type
FROM {{catalog}}.{{silver_schema}}.meterreading mr
JOIN {{catalog}}.{{silver_schema}}.assetmeter am
    ON am.assetnum = mr.assetnum
   AND am.siteid   = mr.siteid
   AND am.metername = mr.metername
   AND am.__END_AT IS NULL
WHERE
    (am.actionlimithi IS NOT NULL AND mr.reading > am.actionlimithi)
 OR (am.actionlimitlo IS NOT NULL AND mr.reading < am.actionlimitlo);


-- -----------------------------------------------------------------------------
-- v_asset_reliability_summary
-- Per-asset rollup of failure rate, time-since-last-failure, criticality.
-- Useful as a feature input or for bad-actor analysis.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_asset_reliability_summary
COMMENT 'Per-asset reliability summary — failure count last 12 months, time since last failure, criticality. One row per active asset.'
AS
SELECT
    a.assetnum,
    a.siteid,
    a.description,
    a.classstructureid,
    a.criticality,
    a.installdate,
    f.failure_count_12mo,
    f.last_failure_date,
    datediff(DAY, f.last_failure_date, current_date()) AS days_since_last_failure,
    p.last_pm_date,
    datediff(DAY, p.last_pm_date, current_date())      AS days_since_last_pm
FROM {{catalog}}.{{silver_schema}}.asset a
LEFT JOIN (
    SELECT assetnum, siteid,
           COUNT(*) AS failure_count_12mo,
           MAX(event_start) AS last_failure_date
    FROM {{catalog}}.{{gold_schema}}.v_failure_events
    WHERE event_start >= add_months(current_date(), -12)
    GROUP BY assetnum, siteid
) f ON f.assetnum = a.assetnum AND f.siteid = a.siteid
LEFT JOIN (
    SELECT assetnum, siteid, MAX(actfinish) AS last_pm_date
    FROM {{catalog}}.{{silver_schema}}.workorder
    WHERE pmnum IS NOT NULL
      AND status IN ('COMP', 'CLOSE')
    GROUP BY assetnum, siteid
) p ON p.assetnum = a.assetnum AND p.siteid = a.siteid
WHERE a.__END_AT IS NULL;
