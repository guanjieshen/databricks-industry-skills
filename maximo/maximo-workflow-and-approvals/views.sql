-- =============================================================================
-- Maximo Workflow & Approvals — Gold Views
-- =============================================================================
-- Substitute {{catalog}}.{{silver_schema}} and {{catalog}}.{{gold_schema}}.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- v_open_approvals
-- All currently-active workflow assignments, enriched with node and owner context.
-- The workhorse view for "who needs to approve what right now" analytics.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_open_approvals
COMMENT 'All currently-active workflow assignments. One row per (wfid, nodeid, approver). Filter by ownertable to scope to a specific business object (WORKORDER, PO, INVOICE, etc.).'
AS
SELECT
    wi.wfid,
    wi.processname,
    wi.ownertable,
    wi.ownerid,
    wi.startdate                                            AS workflow_started_at,
    datediff(HOUR, wi.startdate, current_timestamp())       AS workflow_hours_open,
    n.nodeid, n.nodename, n.title                           AS node_title,
    n.nodetype,
    wa.assignid,
    wa.personid                                             AS assigned_to_person,
    wa.persongroup                                          AS assigned_to_group,
    wa.assigncode,
    wa.assigndate,
    datediff(HOUR, wa.assigndate, current_timestamp())      AS assignment_hours_open
FROM {{catalog}}.{{silver_schema}}.wfassignment wa
JOIN {{catalog}}.{{silver_schema}}.wfinstance wi
    ON wi.wfid = wa.wfid
JOIN {{catalog}}.{{silver_schema}}.wfnode n
    ON n.nodeid = wa.nodeid
WHERE wa.assignstatus = 'ACTIVE'
  AND wi.active = 1;


-- -----------------------------------------------------------------------------
-- v_workflow_history
-- Workflow event log (WFTRANSACTION) enriched with node + instance context.
-- One row per workflow transition (start, route, stop, etc.). Use for audit
-- trails and end-to-end cycle-time analysis on closed workflows.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_workflow_history
COMMENT 'Workflow event log. One row per workflow transition. Includes both active and closed workflows.'
AS
SELECT
    wi.wfid,
    wi.processname,
    wi.ownertable,
    wi.ownerid,
    wi.active                                               AS workflow_active,
    wi.startdate                                            AS workflow_started_at,
    wt.transactionid,
    wt.transaction                                          AS transaction_type,
    wt.transdate,
    wt.personid                                             AS transaction_user,
    wt.memo,
    n.nodeid, n.nodename, n.title                           AS node_title,
    n.nodetype
FROM {{catalog}}.{{silver_schema}}.wftransaction wt
JOIN {{catalog}}.{{silver_schema}}.wfinstance wi
    ON wi.wfid = wt.wfid
LEFT JOIN {{catalog}}.{{silver_schema}}.wfnode n
    ON n.nodeid = wt.nodeid;


-- -----------------------------------------------------------------------------
-- v_workflow_cycle_times
-- Per-workflow end-to-end cycle times for closed workflows. Use for "PO
-- approval takes X days on average" style analytics.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW {{catalog}}.{{gold_schema}}.v_workflow_cycle_times
COMMENT 'Per-workflow cycle times. One row per closed workflow instance (active=0). Hours from workflow start to last transaction.'
AS
SELECT
    wi.wfid,
    wi.processname,
    wi.ownertable,
    wi.ownerid,
    wi.startdate                                            AS workflow_started_at,
    end_tx.transdate                                        AS workflow_ended_at,
    end_tx.transaction                                      AS ending_transaction,
    datediff(HOUR, wi.startdate, end_tx.transdate)          AS cycle_hours,
    datediff(DAY, wi.startdate, end_tx.transdate)           AS cycle_days
FROM {{catalog}}.{{silver_schema}}.wfinstance wi
JOIN (
    SELECT
        wfid,
        transdate,
        transaction,
        ROW_NUMBER() OVER (PARTITION BY wfid ORDER BY transdate DESC) AS rn
    FROM {{catalog}}.{{silver_schema}}.wftransaction
) end_tx
    ON end_tx.wfid = wi.wfid AND end_tx.rn = 1
WHERE wi.active = 0;
