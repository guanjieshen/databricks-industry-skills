-- =============================================================================
-- Maximo Maintenance Cost — Gold Views
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} and {{catalog}}.{{gold_schema}}.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_wo_cost_enriched
-- WORKORDER + asset + location + derived total cost + variance flags.
-- One row per WO (already filtered to WOCLASS = WORKORDER at Silver).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_wo_cost_enriched
COMMENT 'Per-WO cost view with asset/location context, total/labor/material split, variance vs estimate. One row per WO.'
AS
SELECT
    w.wonum, w.siteid, w.orgid,
    w.status, w.worktype,
    w.pmnum,
    CASE WHEN w.pmnum IS NOT NULL THEN 'PM_GENERATED' ELSE 'NOT_PM' END AS pm_source,
    w.reportdate, w.actstart, w.actfinish,
    w.assetnum,
    a.description                                AS asset_description,
    a.classstructureid                           AS asset_class_id,
    a.criticality                                AS asset_criticality,
    w.location,
    l.description                                AS location_description,
    w.wocurrency                                 AS currency,
    -- Estimate side
    COALESCE(w.estlabcost, 0)                    AS est_labor_cost,
    COALESCE(w.estmatcost, 0)                    AS est_material_cost,
    COALESCE(w.estservcost, 0)                   AS est_service_cost,
    COALESCE(w.esttoolcost, 0)                   AS est_tool_cost,
    (COALESCE(w.estlabcost, 0) + COALESCE(w.estmatcost, 0)
     + COALESCE(w.estservcost, 0) + COALESCE(w.esttoolcost, 0))
                                                  AS estimated_cost,
    -- Actual side
    COALESCE(w.actlabcost, 0)                    AS actual_labor_cost,
    COALESCE(w.actmatcost, 0)                    AS actual_material_cost,
    COALESCE(w.actservcost, 0)                   AS actual_service_cost,
    COALESCE(w.acttoolcost, 0)                   AS actual_tool_cost,
    (COALESCE(w.actlabcost, 0) + COALESCE(w.actmatcost, 0)
     + COALESCE(w.actservcost, 0) + COALESCE(w.acttoolcost, 0))
                                                  AS actual_cost,
    -- Variance
    ((COALESCE(w.actlabcost, 0) + COALESCE(w.actmatcost, 0)
      + COALESCE(w.actservcost, 0) + COALESCE(w.acttoolcost, 0))
     - (COALESCE(w.estlabcost, 0) + COALESCE(w.estmatcost, 0)
        + COALESCE(w.estservcost, 0) + COALESCE(w.esttoolcost, 0)))
                                                  AS variance,
    CASE
        WHEN (COALESCE(w.estlabcost, 0) + COALESCE(w.estmatcost, 0)
              + COALESCE(w.estservcost, 0) + COALESCE(w.esttoolcost, 0)) > 0
        THEN 100.0 *
            ((COALESCE(w.actlabcost, 0) + COALESCE(w.actmatcost, 0)
              + COALESCE(w.actservcost, 0) + COALESCE(w.acttoolcost, 0))
             - (COALESCE(w.estlabcost, 0) + COALESCE(w.estmatcost, 0)
                + COALESCE(w.estservcost, 0) + COALESCE(w.esttoolcost, 0)))
            / (COALESCE(w.estlabcost, 0) + COALESCE(w.estmatcost, 0)
               + COALESCE(w.estservcost, 0) + COALESCE(w.esttoolcost, 0))
        ELSE NULL
    END                                           AS variance_pct
FROM {{catalog}}.{{silver_schema}}.workorder w
LEFT JOIN {{catalog}}.{{silver_schema}}.asset a
    ON a.assetnum = w.assetnum AND a.siteid = w.siteid AND a.__END_AT IS NULL
LEFT JOIN {{catalog}}.{{silver_schema}}.locations l
    ON l.location = w.location AND l.siteid = w.siteid AND l.__END_AT IS NULL;


-- -----------------------------------------------------------------------------
-- v_asset_cost_summary
-- Per-(asset, period) cost rollup. Aggregates LABTRANS + MATUSETRANS to the
-- asset grain. Period = month.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_asset_cost_summary
COMMENT 'Per-(asset, month) cost rollup. One row per (asset, period_start). Aggregates labor + material from LABTRANS/MATUSETRANS via WO join.'
AS
WITH labor_costs AS (
    SELECT
        w.assetnum,
        w.siteid,
        date_trunc('MONTH', lt.startdate)        AS period_start,
        SUM(lt.linecost)                          AS labor_cost,
        COUNT(DISTINCT lt.wonum)                  AS labor_wo_count
    FROM {{catalog}}.{{silver_schema}}.labtrans lt
    JOIN {{catalog}}.{{silver_schema}}.workorder w
        ON w.wonum = lt.wonum AND w.siteid = lt.siteid
    WHERE lt.transtype = 'WORK'
      AND w.assetnum IS NOT NULL
    GROUP BY w.assetnum, w.siteid, date_trunc('MONTH', lt.startdate)
),
material_costs AS (
    SELECT
        w.assetnum,
        w.siteid,
        date_trunc('MONTH', mt.transdate)        AS period_start,
        SUM(CASE WHEN mt.issuetype = 'ISSUE'  THEN mt.linecost ELSE 0 END)
          - SUM(CASE WHEN mt.issuetype = 'RETURN' THEN mt.linecost ELSE 0 END)
                                                  AS material_cost,
        COUNT(DISTINCT mt.wonum)                  AS material_wo_count
    FROM {{catalog}}.{{silver_schema}}.matusetrans mt
    JOIN {{catalog}}.{{silver_schema}}.workorder w
        ON w.wonum = mt.wonum AND w.siteid = mt.siteid
    WHERE mt.issuetype IN ('ISSUE', 'RETURN')
      AND w.assetnum IS NOT NULL
    GROUP BY w.assetnum, w.siteid, date_trunc('MONTH', mt.transdate)
)
SELECT
    COALESCE(lc.assetnum, mc.assetnum)            AS assetnum,
    COALESCE(lc.siteid, mc.siteid)                AS siteid,
    COALESCE(lc.period_start, mc.period_start)    AS period_start,
    a.description                                 AS asset_description,
    a.classstructureid                            AS asset_class_id,
    a.criticality                                 AS asset_criticality,
    COALESCE(lc.labor_cost, 0)                    AS total_labor_cost,
    COALESCE(mc.material_cost, 0)                 AS total_material_cost,
    COALESCE(lc.labor_cost, 0) + COALESCE(mc.material_cost, 0) AS total_cost,
    GREATEST(COALESCE(lc.labor_wo_count, 0), COALESCE(mc.material_wo_count, 0)) AS wo_count
FROM labor_costs lc
FULL OUTER JOIN material_costs mc
    ON lc.assetnum = mc.assetnum
   AND lc.siteid = mc.siteid
   AND lc.period_start = mc.period_start
LEFT JOIN {{catalog}}.{{silver_schema}}.asset a
    ON a.assetnum = COALESCE(lc.assetnum, mc.assetnum)
   AND a.siteid   = COALESCE(lc.siteid, mc.siteid)
   AND a.__END_AT IS NULL;


-- -----------------------------------------------------------------------------
-- v_cost_by_worktype
-- Per-(site, worktype, month) cost rollup. Use for PM-vs-CM cost analysis.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_cost_by_worktype
COMMENT 'Per-(site, worktype, month) cost rollup. Combines labor + material from transaction tables.'
AS
WITH labor_by_wt AS (
    SELECT
        w.siteid,
        w.worktype,
        CASE WHEN w.pmnum IS NOT NULL THEN 'PM' ELSE 'NON_PM' END AS pm_source,
        date_trunc('MONTH', lt.startdate)        AS period_start,
        SUM(lt.linecost)                          AS labor_cost
    FROM {{catalog}}.{{silver_schema}}.labtrans lt
    JOIN {{catalog}}.{{silver_schema}}.workorder w
        ON w.wonum = lt.wonum AND w.siteid = lt.siteid
    WHERE lt.transtype = 'WORK'
    GROUP BY w.siteid, w.worktype,
             CASE WHEN w.pmnum IS NOT NULL THEN 'PM' ELSE 'NON_PM' END,
             date_trunc('MONTH', lt.startdate)
),
mat_by_wt AS (
    SELECT
        w.siteid,
        w.worktype,
        CASE WHEN w.pmnum IS NOT NULL THEN 'PM' ELSE 'NON_PM' END AS pm_source,
        date_trunc('MONTH', mt.transdate)        AS period_start,
        SUM(CASE WHEN mt.issuetype = 'ISSUE'  THEN mt.linecost ELSE 0 END)
          - SUM(CASE WHEN mt.issuetype = 'RETURN' THEN mt.linecost ELSE 0 END) AS material_cost
    FROM {{catalog}}.{{silver_schema}}.matusetrans mt
    JOIN {{catalog}}.{{silver_schema}}.workorder w
        ON w.wonum = mt.wonum AND w.siteid = mt.siteid
    WHERE mt.issuetype IN ('ISSUE', 'RETURN')
    GROUP BY w.siteid, w.worktype,
             CASE WHEN w.pmnum IS NOT NULL THEN 'PM' ELSE 'NON_PM' END,
             date_trunc('MONTH', mt.transdate)
)
SELECT
    COALESCE(l.siteid, m.siteid)                  AS siteid,
    COALESCE(l.worktype, m.worktype)              AS worktype,
    COALESCE(l.pm_source, m.pm_source)            AS pm_source,
    COALESCE(l.period_start, m.period_start)      AS period_start,
    COALESCE(l.labor_cost, 0)                     AS labor_cost,
    COALESCE(m.material_cost, 0)                  AS material_cost,
    COALESCE(l.labor_cost, 0) + COALESCE(m.material_cost, 0) AS total_cost
FROM labor_by_wt l
FULL OUTER JOIN mat_by_wt m
    ON l.siteid = m.siteid
   AND l.worktype = m.worktype
   AND l.pm_source = m.pm_source
   AND l.period_start = m.period_start;


-- -----------------------------------------------------------------------------
-- v_location_cost_summary
-- Maintenance cost rolled up to ANY location parent (uses LOCANCESTOR from
-- maximo-asset-hierarchy). One row per (rollup_location, period_start).
--
-- Composes with maximo-asset-hierarchy. Requires LOCANCESTOR Silver table.
-- If LOCANCESTOR is missing in the customer's environment, fall back to the
-- v_asset_cost_summary (one level — asset only) and document the limitation.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_location_cost_summary
COMMENT 'Per-(rollup_location, month) maintenance cost rollup using LOCANCESTOR. Each asset cost row appears under every ancestor location in its physical hierarchy. Composes with maximo-asset-hierarchy. SYSTEMID = PRIMARY.'
AS
WITH asset_costs AS (
    SELECT
        s.assetnum, s.siteid, s.period_start,
        s.total_labor_cost, s.total_material_cost, s.total_cost
    FROM {{catalog}}.{{gold_schema}}.v_asset_cost_summary s
),
asset_locations AS (
    SELECT a.assetnum, a.siteid, a.location, a.classstructureid
    FROM {{catalog}}.{{silver_schema}}.asset a
    WHERE a.__END_AT IS NULL
)
SELECT
    la.ancestor                                            AS rollup_location,
    ac.siteid,
    ac.period_start,
    a_loc.description                                       AS rollup_location_description,
    a_loc.type                                              AS rollup_location_type,
    SUM(ac.total_labor_cost)                                AS total_labor_cost,
    SUM(ac.total_material_cost)                             AS total_material_cost,
    SUM(ac.total_cost)                                      AS total_cost,
    COUNT(DISTINCT ac.assetnum)                             AS distinct_assets
FROM asset_costs ac
JOIN asset_locations al
    ON al.assetnum = ac.assetnum AND al.siteid = ac.siteid
JOIN {{catalog}}.{{silver_schema}}.locancestor la
    ON la.location = al.location AND la.siteid = al.siteid AND la.systemid = 'PRIMARY'
LEFT JOIN {{catalog}}.{{silver_schema}}.locations a_loc
    ON a_loc.location = la.ancestor AND a_loc.siteid = la.siteid AND a_loc.__END_AT IS NULL
GROUP BY la.ancestor, ac.siteid, ac.period_start, a_loc.description, a_loc.type;
