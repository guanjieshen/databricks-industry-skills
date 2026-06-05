-- =============================================================================
-- Maximo Workflow & Approvals — Gold-Standard Query Examples
-- =============================================================================
-- Substitute :catalog.:silver_schema (e.g. eam.maximo_silver) before running.
-- Databricks-native :param placeholders bind at execution time.
--
-- Column notes (see schema.md / gotchas.md):
--  * WFASSIGNMENT timestamps: STARTDATE (inbox entry) + DUEDATE (SLA). The actual
--    completion timestamp and route disposition live in WFTRANSACTION, NOT in
--    WFASSIGNMENT.RESULT/COMPLETED (not documented columns) — verify before use.
--  * WFTRANSACTION.TRANSTYPE is a SYNONYM domain (WFTRANSTYPE) — resolve via
--    SYNONYMDOMAIN; do not hardcode literals. WFUSERSTOPPED is a verified value.
--  * ASSIGNSTATUS persisted states: DEFAULT/ACTIVE/COMPLETE/INACTIVE. No FORWARDED.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. My current approval inbox
-- -----------------------------------------------------------------------------
-- Trigger: "what's in my inbox", "what do I need to approve"
SELECT
    wi.processname,
    wi.ownertable, wi.ownerid,
    n.nodetype, n.title                                  AS node_title,
    wa.startdate                                         AS in_inbox_since,
    wa.duedate                                           AS sla_due,
    datediff(HOUR, wa.startdate, current_timestamp())    AS hours_waiting
FROM :catalog.:silver_schema.wfassignment wa
JOIN :catalog.:silver_schema.wfinstance wi   ON wi.wfid = wa.wfid
JOIN :catalog.:silver_schema.wfnode n        ON n.nodeid = wa.nodeid
WHERE wa.assignstatus = 'ACTIVE'
  AND wi.active = 1
  AND (wa.personid = :user_personid
       OR wa.persongroup IN (
           SELECT persongroup
           FROM :catalog.:silver_schema.persongroupteam
           WHERE personid = :user_personid
       ))
ORDER BY wa.startdate;


-- -----------------------------------------------------------------------------
-- 2. Records stuck in approval > N days
-- -----------------------------------------------------------------------------
-- Trigger: "stuck in approval", "POs older than 7 days in approval"
-- Who-owns-it-now is read from the ACTIVE assignment's ASSIGNCODE/PERSONID
-- (reassignment changes ASSIGNCODE in place, gotcha 6).
SELECT
    wi.processname,
    wi.ownertable,
    wi.ownerid,
    wi.startdate                                          AS workflow_started,
    datediff(DAY, wi.startdate, current_timestamp())      AS days_in_workflow,
    array_agg(DISTINCT wa.assigncode)                     AS current_assignees,
    array_agg(DISTINCT wa.personid)                       AS waiting_on_users,
    array_agg(DISTINCT wa.persongroup)                    AS waiting_on_groups,
    array_agg(DISTINCT n.title)                           AS current_nodes
FROM :catalog.:silver_schema.wfinstance wi
LEFT JOIN :catalog.:silver_schema.wfassignment wa
       ON wa.wfid = wi.wfid
      AND wa.assignstatus = 'ACTIVE'
LEFT JOIN :catalog.:silver_schema.wfnode n
       ON n.nodeid = wa.nodeid
WHERE wi.active = 1
  AND datediff(DAY, wi.startdate, current_timestamp()) >= :stuck_threshold_days
GROUP BY wi.processname, wi.ownertable, wi.ownerid, wi.startdate
ORDER BY days_in_workflow DESC;


-- -----------------------------------------------------------------------------
-- 3. Time-in-approval (per-assignment) by node, last quarter
-- -----------------------------------------------------------------------------
-- Trigger: "approval bottlenecks", "which node is slowest"
-- Per-assignment time = STARTDATE (inbox entry) -> the COMPLETE-ing route
-- transaction in WFTRANSACTION (there is no COMPLETEDATE on WFASSIGNMENT).
-- Match the completing transaction by (wfid, nodeid) at-or-after the assignment.
WITH completed_assignments AS (
    SELECT
        wa.wfid, wa.nodeid, wa.startdate,
        MIN(wt.transdate) AS completed_at
    FROM :catalog.:silver_schema.wfassignment wa
    JOIN :catalog.:silver_schema.wftransaction wt
           ON wt.wfid = wa.wfid
          AND wt.nodeid = wa.nodeid
          AND wt.transdate >= wa.startdate
    WHERE wa.assignstatus = 'COMPLETE'
      AND wa.startdate >= add_months(current_date(), -3)
    GROUP BY wa.wfid, wa.nodeid, wa.startdate
)
SELECT
    wi.processname,
    n.nodetype, n.title,
    COUNT(*)                                                       AS assignment_count,
    ROUND(AVG(datediff(HOUR, ca.startdate, ca.completed_at)), 1)   AS avg_hours,
    ROUND(PERCENTILE(datediff(HOUR, ca.startdate, ca.completed_at), 0.5), 1) AS p50_hours,
    ROUND(PERCENTILE(datediff(HOUR, ca.startdate, ca.completed_at), 0.9), 1) AS p90_hours
FROM completed_assignments ca
JOIN :catalog.:silver_schema.wfinstance wi ON wi.wfid = ca.wfid
JOIN :catalog.:silver_schema.wfnode n      ON n.nodeid = ca.nodeid
GROUP BY wi.processname, n.nodetype, n.title
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
    FROM :catalog.:silver_schema.wfinstance wi
    JOIN :catalog.:silver_schema.wftransaction wt ON wt.wfid = wi.wfid
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
-- Current owner = ASSIGNCODE/PERSONID on the ACTIVE assignment (gotcha 6).
SELECT
    wi.processname,
    n.nodetype, n.title              AS current_node,
    wa.assigncode, wa.personid, wa.persongroup,
    wa.startdate                     AS in_inbox_since,
    wa.duedate                       AS sla_due,
    datediff(HOUR, wa.startdate, current_timestamp()) AS hours_waiting
FROM :catalog.:silver_schema.wfinstance wi
JOIN :catalog.:silver_schema.wfassignment wa ON wa.wfid = wi.wfid AND wa.assignstatus = 'ACTIVE'
JOIN :catalog.:silver_schema.wfnode n        ON n.nodeid = wa.nodeid
WHERE wi.active = 1
  AND wi.ownertable = :owner_table
  AND wi.ownerid    = :owner_id;


-- -----------------------------------------------------------------------------
-- 6. Full workflow history for a workflow (audit trail)
-- -----------------------------------------------------------------------------
-- Trigger: "show me the approval history for this PO"
-- View Workflow History excludes CONDITION nodes; TRANSTYPE is a synonym value.
SELECT
    wt.transdate,
    wt.transtype,
    n.nodetype,
    n.title,
    wt.personid,
    wt.memo
FROM :catalog.:silver_schema.wftransaction wt
LEFT JOIN :catalog.:silver_schema.wfnode n ON n.nodeid = wt.nodeid
WHERE wt.wfid = :wfid
  AND coalesce(n.nodetype, '') <> 'CONDITION'
ORDER BY wt.transdate;


-- -----------------------------------------------------------------------------
-- 7. Top approvers by volume (last quarter)
-- -----------------------------------------------------------------------------
-- Trigger: "who approves the most POs", "approver workload"
-- COMPLETE assignments = the person acted. Response time = STARTDATE -> the
-- completing transaction (no COMPLETEDATE column on WFASSIGNMENT).
WITH acted AS (
    SELECT
        wa.wfid, wa.nodeid, wa.personid, wa.startdate,
        MIN(wt.transdate) AS completed_at
    FROM :catalog.:silver_schema.wfassignment wa
    JOIN :catalog.:silver_schema.wftransaction wt
           ON wt.wfid = wa.wfid AND wt.nodeid = wa.nodeid AND wt.transdate >= wa.startdate
    WHERE wa.assignstatus = 'COMPLETE'
      AND wa.personid IS NOT NULL
      AND wa.startdate >= add_months(current_date(), -3)
    GROUP BY wa.wfid, wa.nodeid, wa.personid, wa.startdate
)
SELECT
    a.personid,
    wi.processname,
    COUNT(*)                                                  AS approval_count,
    ROUND(AVG(datediff(HOUR, a.startdate, a.completed_at)), 1) AS avg_response_hours
FROM acted a
JOIN :catalog.:silver_schema.wfinstance wi ON wi.wfid = a.wfid
GROUP BY a.personid, wi.processname
ORDER BY approval_count DESC
LIMIT 50;


-- -----------------------------------------------------------------------------
-- 8. Workflow termination outcomes (completed vs user-stopped vs rejected)
-- -----------------------------------------------------------------------------
-- Trigger: "what % of POs get approved", "rejection rate"
-- Resolve outcome from the terminating WFTRANSACTION.TRANSTYPE. TRANSTYPE is a
-- synonym domain — map your deployment's positive/negative/stop synonyms first
-- (see Questions to surface first). WFUSERSTOPPED is a verified stop value.
WITH last_transaction AS (
    SELECT
        wi.wfid,
        wi.processname,
        wi.ownertable,
        wt.transtype,
        wt.memo,
        ROW_NUMBER() OVER (PARTITION BY wi.wfid ORDER BY wt.transdate DESC) AS rn
    FROM :catalog.:silver_schema.wfinstance wi
    JOIN :catalog.:silver_schema.wftransaction wt ON wt.wfid = wi.wfid
    WHERE wi.active = 0
      AND wi.startdate >= add_months(current_date(), -6)
)
SELECT
    processname,
    transtype,
    COUNT(*)                                          AS count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY processname), 2) AS pct_of_process
FROM last_transaction
WHERE rn = 1
GROUP BY processname, transtype
ORDER BY processname, count DESC;
