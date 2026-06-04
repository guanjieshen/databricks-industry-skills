-- =============================================================================
-- Maximo Workflow & Approvals — Gold-Standard Query Examples
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} (e.g. eam.maximo_silver) before running.
-- These queries are written against Silver tables directly so they work even
-- if v_open_approvals / v_workflow_history aren't registered yet.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. My current approval inbox
-- -----------------------------------------------------------------------------
-- Trigger: "what's in my inbox", "what do I need to approve"
SELECT
    wi.processname,
    wi.ownertable, wi.ownerid,
    n.nodename, n.title          AS node_title,
    wa.assigndate,
    datediff(HOUR, wa.assigndate, current_timestamp()) AS hours_waiting
FROM {{catalog}}.{{silver_schema}}.wfassignment wa
JOIN {{catalog}}.{{silver_schema}}.wfinstance wi   ON wi.wfid = wa.wfid
JOIN {{catalog}}.{{silver_schema}}.wfnode n        ON n.nodeid = wa.nodeid
WHERE wa.assignstatus = 'ACTIVE'
  AND (wa.personid = '{{user_personid}}'
       OR wa.persongroup IN (
           SELECT persongroup
           FROM {{catalog}}.{{silver_schema}}.persongroupteam
           WHERE personid = '{{user_personid}}'
       ))
ORDER BY wa.assigndate;


-- -----------------------------------------------------------------------------
-- 2. Records stuck in approval > N days
-- -----------------------------------------------------------------------------
-- Trigger: "stuck in approval", "POs older than 7 days in approval"
SELECT
    wi.processname,
    wi.ownertable,
    wi.ownerid,
    wi.startdate                                    AS workflow_started,
    datediff(DAY, wi.startdate, current_timestamp()) AS days_in_workflow,
    -- The current active assignment(s)
    array_agg(DISTINCT wa.personid)                 AS waiting_on_users,
    array_agg(DISTINCT wa.persongroup)              AS waiting_on_groups,
    array_agg(DISTINCT n.nodename)                  AS current_nodes
FROM {{catalog}}.{{silver_schema}}.wfinstance wi
LEFT JOIN {{catalog}}.{{silver_schema}}.wfassignment wa
       ON wa.wfid = wi.wfid
      AND wa.assignstatus = 'ACTIVE'
LEFT JOIN {{catalog}}.{{silver_schema}}.wfnode n
       ON n.nodeid = wa.nodeid
WHERE wi.active = 1
  AND datediff(DAY, wi.startdate, current_timestamp()) >= {{stuck_threshold_days}}
GROUP BY wi.processname, wi.ownertable, wi.ownerid, wi.startdate
ORDER BY days_in_workflow DESC;


-- -----------------------------------------------------------------------------
-- 3. Approval cycle time by node, last quarter
-- -----------------------------------------------------------------------------
-- Trigger: "approval bottlenecks", "which node is slowest"
SELECT
    wi.processname,
    n.nodename, n.title,
    COUNT(*)                                                       AS assignment_count,
    ROUND(AVG(datediff(HOUR, wa.assigndate, wa.completedate)), 1)  AS avg_hours,
    ROUND(PERCENTILE(datediff(HOUR, wa.assigndate, wa.completedate), 0.5), 1) AS p50_hours,
    ROUND(PERCENTILE(datediff(HOUR, wa.assigndate, wa.completedate), 0.9), 1) AS p90_hours
FROM {{catalog}}.{{silver_schema}}.wfassignment wa
JOIN {{catalog}}.{{silver_schema}}.wfinstance wi ON wi.wfid = wa.wfid
JOIN {{catalog}}.{{silver_schema}}.wfnode n      ON n.nodeid = wa.nodeid
WHERE wa.assignstatus IN ('COMPLETE', 'FORWARDED')
  AND wa.completedate IS NOT NULL
  AND wa.assigndate >= add_months(current_date(), -3)
GROUP BY wi.processname, n.nodename, n.title
ORDER BY avg_hours DESC;


-- -----------------------------------------------------------------------------
-- 4. End-to-end workflow cycle time
-- -----------------------------------------------------------------------------
-- Trigger: "how long does PO approval take end to end", "workflow cycle time"
WITH wf_end AS (
    SELECT
        wi.wfid,
        wi.processname,
        wi.startdate,
        MAX(wt.transdate)                            AS endtime
    FROM {{catalog}}.{{silver_schema}}.wfinstance wi
    JOIN {{catalog}}.{{silver_schema}}.wftransaction wt ON wt.wfid = wi.wfid
    WHERE wi.active = 0
      AND wi.startdate >= add_months(current_date(), -6)
    GROUP BY wi.wfid, wi.processname, wi.startdate
)
SELECT
    processname,
    COUNT(*)                                              AS workflow_count,
    ROUND(AVG(datediff(HOUR, startdate, endtime)), 1)     AS avg_hours,
    ROUND(PERCENTILE(datediff(HOUR, startdate, endtime), 0.5), 1) AS p50_hours,
    ROUND(PERCENTILE(datediff(HOUR, startdate, endtime), 0.9), 1) AS p90_hours
FROM wf_end
GROUP BY processname
ORDER BY avg_hours DESC;


-- -----------------------------------------------------------------------------
-- 5. Who currently owns this specific business record's workflow?
-- -----------------------------------------------------------------------------
-- Trigger: "who needs to approve WO-12345", "where is PO-9876"
SELECT
    wi.processname,
    n.nodename, n.title              AS current_node,
    wa.personid, wa.persongroup,
    wa.assigndate,
    datediff(HOUR, wa.assigndate, current_timestamp()) AS hours_waiting
FROM {{catalog}}.{{silver_schema}}.wfinstance wi
JOIN {{catalog}}.{{silver_schema}}.wfassignment wa ON wa.wfid = wi.wfid AND wa.assignstatus = 'ACTIVE'
JOIN {{catalog}}.{{silver_schema}}.wfnode n        ON n.nodeid = wa.nodeid
WHERE wi.active = 1
  AND wi.ownertable = '{{owner_table}}'
  AND wi.ownerid    = {{owner_id}};


-- -----------------------------------------------------------------------------
-- 6. Full workflow history for a closed workflow (audit trail)
-- -----------------------------------------------------------------------------
-- Trigger: "show me the approval history for this PO"
SELECT
    wt.transdate,
    wt.transaction,
    n.nodename,
    wt.personid,
    wt.memo
FROM {{catalog}}.{{silver_schema}}.wftransaction wt
LEFT JOIN {{catalog}}.{{silver_schema}}.wfnode n ON n.nodeid = wt.nodeid
WHERE wt.wfid = {{wfid}}
ORDER BY wt.transdate;


-- -----------------------------------------------------------------------------
-- 7. Top approvers by volume (last quarter)
-- -----------------------------------------------------------------------------
-- Trigger: "who approves the most POs", "approver workload"
SELECT
    wa.personid,
    wi.processname,
    COUNT(*)                                                  AS approval_count,
    ROUND(AVG(datediff(HOUR, wa.assigndate, wa.completedate)), 1) AS avg_response_hours
FROM {{catalog}}.{{silver_schema}}.wfassignment wa
JOIN {{catalog}}.{{silver_schema}}.wfinstance wi ON wi.wfid = wa.wfid
WHERE wa.assignstatus = 'COMPLETE'
  AND wa.completedate >= add_months(current_date(), -3)
  AND wa.personid IS NOT NULL
GROUP BY wa.personid, wi.processname
ORDER BY approval_count DESC
LIMIT 50;


-- -----------------------------------------------------------------------------
-- 8. Workflow termination outcomes (completed vs cancelled vs rejected)
-- -----------------------------------------------------------------------------
-- Trigger: "what % of POs get approved", "rejection rate"
WITH last_transaction AS (
    SELECT
        wi.wfid,
        wi.processname,
        wi.ownertable,
        wt.transaction,
        wt.memo,
        ROW_NUMBER() OVER (PARTITION BY wi.wfid ORDER BY wt.transdate DESC) AS rn
    FROM {{catalog}}.{{silver_schema}}.wfinstance wi
    JOIN {{catalog}}.{{silver_schema}}.wftransaction wt ON wt.wfid = wi.wfid
    WHERE wi.active = 0
      AND wi.startdate >= add_months(current_date(), -6)
)
SELECT
    processname,
    transaction,
    COUNT(*)                                          AS count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY processname), 2) AS pct_of_process
FROM last_transaction
WHERE rn = 1
GROUP BY processname, transaction
ORDER BY processname, count DESC;
