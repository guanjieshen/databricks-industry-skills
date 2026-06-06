-- =============================================================================
-- Oracle Fusion Data Quality — Diagnostic Probes (ordered)
-- =============================================================================
-- Run individually based on the symptom. See common-issues.md for what each
-- finding means and the symptom -> cause -> fix pattern. Probes are ordered so
-- that for a vague "wrong number" you rule out the cheapest/most-common causes
-- first (balance, posting, currency, multi-org) before the harder ones
-- (extract gaps, XLA reconciliation, orphan CCIDs).
--
-- Parameters (Databricks-native :param syntax; bound at execution time):
--   :catalog        Unity Catalog catalog holding the Fusion Silver layer
--   :silver_schema  Silver schema (canonical EBS-style table names assumed; the
--                   <customer>-oracle-fusion-glossary maps these to the
--                   customer's physical PVO/FDI/base objects if they differ)
--   :ledger_id      (most probes) the ledger in scope — never aggregate GL
--                   across ledgers without intent
--   :prc_bu_id      (Probe 4) the procurement business unit in scope
--
-- Universal mechanics applied below (canonical home: oracle-fusion-overview;
-- accounting depth: oracle-fusion-ledger-coa):
--   _ALL multi-org scoping, CCID segments, posted-vs-unposted, entered-vs-
--   accounted currency, period open/close, the GL<->XLA bridge, BICC
--   deletes-not-captured. This file APPLIES them; it does not re-teach them.
-- =============================================================================

-- Contents
--   Probe 1 — Unbalanced journals (debits != credits)
--   Probe 2 — Posted vs unposted leakage
--   Probe 3 — Multi-currency summing without conversion
--   Probe 4 — _ALL multi-org duplicate counting
--   Probe 5 — Period status mismatch (open periods not final)
--   Probe 6 — BICC extract gaps (deletes not captured / late-arriving)
--   Probe 7 — GL-to-subledger (XLA) reconciliation drift
--   Probe 8 — Orphan code combinations (CCID not in GL_CODE_COMBINATIONS)


-- -----------------------------------------------------------------------------
-- Probe 1 — Unbalanced journals (debits != credits)
-- Symptom: trial balance doesn't tie; a journal's debits don't equal credits
-- -----------------------------------------------------------------------------
-- Every journal must balance in ACCOUNTED (ledger) currency per header. Use
-- ACCOUNTED, not ENTERED — ENTERED can legitimately differ across currencies.
SELECT
    h.je_header_id,
    h.period_name,
    h.status,
    SUM(l.accounted_dr)                              AS total_accounted_dr,
    SUM(l.accounted_cr)                              AS total_accounted_cr,
    SUM(l.accounted_dr) - SUM(l.accounted_cr)        AS imbalance
FROM :catalog.:silver_schema.GL_JE_HEADERS h
JOIN :catalog.:silver_schema.GL_JE_LINES l
    ON l.je_header_id = h.je_header_id
WHERE h.ledger_id = :ledger_id
GROUP BY h.je_header_id, h.period_name, h.status
HAVING ABS(SUM(l.accounted_dr) - SUM(l.accounted_cr)) > 0.005
ORDER BY ABS(SUM(l.accounted_dr) - SUM(l.accounted_cr)) DESC
LIMIT 50;
-- Rows here mean a header doesn't balance in ledger currency. Causes: lines
-- dropped/late in the extract (see Probe 6), a multi-currency journal compared
-- on ENTERED instead of ACCOUNTED, or genuine source corruption. Posted ('P')
-- journals that don't balance are the most serious — Fusion won't post an
-- unbalanced journal, so an imbalance on a posted header is an INGESTION defect.


-- -----------------------------------------------------------------------------
-- Probe 2 — Posted vs unposted leakage
-- Symptom: actuals look too high; unposted journals leaking into totals
-- -----------------------------------------------------------------------------
-- Trial balance / actuals use POSTED only (STATUS='P') and ACTUAL_FLAG='A'.
-- This shows how much amount sits in each status/flag bucket so you can see
-- whether unposted or budget/encumbrance rows are inflating a total.
SELECT
    h.status,
    h.actual_flag,
    COUNT(DISTINCT h.je_header_id)                   AS journal_count,
    SUM(l.accounted_dr)                              AS total_accounted_dr,
    SUM(l.accounted_cr)                              AS total_accounted_cr
FROM :catalog.:silver_schema.GL_JE_HEADERS h
JOIN :catalog.:silver_schema.GL_JE_LINES l
    ON l.je_header_id = h.je_header_id
WHERE h.ledger_id = :ledger_id
GROUP BY h.status, h.actual_flag
ORDER BY h.status, h.actual_flag;
-- If the user's "actuals" number matches the row including STATUS='U' or
-- ACTUAL_FLAG IN ('B','E'), they're double-counting non-actuals. Correct
-- actuals = STATUS='P' AND ACTUAL_FLAG='A'.


-- -----------------------------------------------------------------------------
-- Probe 3 — Multi-currency summing without conversion
-- Symptom: cross-entity / multi-currency totals look wrong
-- -----------------------------------------------------------------------------
-- ENTERED amounts are in the DOCUMENT currency and must never be summed across
-- differing CURRENCY_CODE. This probe shows the currency spread; if a single
-- "total" was built on ENTERED across >1 currency, it's meaningless.
SELECT
    l.currency_code,
    COUNT(*)                                         AS line_count,
    SUM(l.entered_dr)                                AS sum_entered_dr,
    SUM(l.entered_cr)                                AS sum_entered_cr,
    SUM(l.accounted_dr)                              AS sum_accounted_dr,
    SUM(l.accounted_cr)                              AS sum_accounted_cr
FROM :catalog.:silver_schema.GL_JE_HEADERS h
JOIN :catalog.:silver_schema.GL_JE_LINES l
    ON l.je_header_id = h.je_header_id
WHERE h.ledger_id = :ledger_id
GROUP BY l.currency_code
ORDER BY line_count DESC;
-- More than one currency_code means any cross-currency total MUST use ACCOUNTED
-- (ledger) amounts, or convert ENTERED via GL_DAILY_RATES (owned by
-- oracle-fusion-ledger-coa). Summing ENTERED across rows here is the bug.


-- -----------------------------------------------------------------------------
-- Probe 4 — _ALL multi-org duplicate counting
-- Symptom: spend / PO totals are inflated; the same PO appears more than once
-- -----------------------------------------------------------------------------
-- _ALL tables hold every business unit. A query that forgets PRC_BU_ID mixes
-- orgs; a join fan-out (header -> lines -> distributions) double-counts headers.
-- First: confirm PO_HEADER_ID is unique (ingestion idempotency).
SELECT po_header_id, COUNT(*) AS dup_count
FROM :catalog.:silver_schema.PO_HEADERS_ALL
GROUP BY po_header_id
HAVING COUNT(*) > 1
ORDER BY dup_count DESC
LIMIT 20;
-- Then: the per-BU header count, so you can see whether an unscoped query is
-- summing across business units.
-- (Run separately; bind :prc_bu_id when scoping to one BU.)
--   SELECT prc_bu_id, COUNT(*) AS header_count
--   FROM :catalog.:silver_schema.PO_HEADERS_ALL
--   GROUP BY prc_bu_id ORDER BY header_count DESC;
-- Duplicate PO_HEADER_ID = ingestion dedup bug (fix in data-engineering).
-- Inflated totals with unique headers = missing PRC_BU_ID scope or a header
-- amount summed at line/distribution grain (join fan-out).


-- -----------------------------------------------------------------------------
-- Probe 5 — Period status mismatch (open periods not final)
-- Symptom: a period's numbers keep changing / don't match a closed report
-- -----------------------------------------------------------------------------
-- A period's status per ledger determines whether numbers are final. Open
-- periods change. Sort by effective period number, never alphabetically.
SELECT
    ps.period_name,
    ps.closing_status,                               -- O / C / F / N / P (open/closed/future/never/permanently)
    p.period_year,
    p.period_num,
    (p.period_year * 10000 + p.period_num)           AS effective_period_sort
FROM :catalog.:silver_schema.GL_PERIOD_STATUSES ps
JOIN :catalog.:silver_schema.GL_PERIODS p
    ON p.period_name = ps.period_name
WHERE ps.ledger_id = :ledger_id
ORDER BY effective_period_sort;
-- If the "wrong" period has closing_status = 'O' (Open), its numbers are not
-- final — expected to change, not a defect. Only 'C'/'P' (closed/permanently
-- closed) periods are final. A user comparing a closed report to a still-open
-- period in the lakehouse will see a difference that is not corruption.


-- -----------------------------------------------------------------------------
-- Probe 6 — BICC extract gaps (deletes not captured / late-arriving)
-- Symptom: lakehouse numbers drifted upward vs Fusion; "deleted" rows persist
-- -----------------------------------------------------------------------------
-- BICC incremental extracts (last-update-date) capture INSERT/UPDATE only —
-- hard deletes are NOT reflected, so deleted rows linger in Silver and inflate
-- totals. Also surfaces stale rows: max audit date per table tells you whether
-- an extract has stopped landing (late-arriving / paused feed).
SELECT
    'GL_JE_HEADERS' AS table_name,
    COUNT(*)                                         AS row_count,
    MAX(last_update_date)                            AS max_last_update,
    datediff(DAY, MAX(last_update_date), current_date()) AS days_since_last_update
FROM :catalog.:silver_schema.GL_JE_HEADERS
UNION ALL
SELECT 'PO_HEADERS_ALL', COUNT(*), MAX(last_update_date),
       datediff(DAY, MAX(last_update_date), current_date())
FROM :catalog.:silver_schema.PO_HEADERS_ALL;
-- A large days_since_last_update means the feed stalled (late-arriving gap).
-- To detect DELETES not captured you need a full snapshot to anti-join against;
-- if none exists, that is itself the finding — recommend a Deleted-Record
-- extract or periodic full-reload reconcile (owned by data-engineering).


-- -----------------------------------------------------------------------------
-- Probe 7 — GL-to-subledger (XLA) reconciliation drift
-- Symptom: GL account total doesn't match the subledger (AP/AR/PO) detail
-- -----------------------------------------------------------------------------
-- XLA subledger lines transfer UP INTO GL via GL_SL_LINK_ID. Reconciliation
-- compares the two levels — it NEVER sums them (that double-counts). This finds
-- XLA lines whose transfer status says transferred but with no matching GL line
-- (transfer/extract gap), and untransferred XLA not yet in GL.
SELECT
    x.gl_transfer_status_code,
    COUNT(*)                                         AS xla_line_count,
    SUM(CASE WHEN gl.gl_sl_link_id IS NULL THEN 1 ELSE 0 END) AS missing_in_gl
FROM :catalog.:silver_schema.XLA_AE_LINES x
LEFT JOIN :catalog.:silver_schema.GL_JE_LINES gl
    ON gl.gl_sl_link_id = x.gl_sl_link_id
GROUP BY x.gl_transfer_status_code
ORDER BY xla_line_count DESC;
-- gl_transfer_status_code 'Y' (transferred) rows with missing_in_gl > 0 are a
-- real reconciliation gap (the GL side didn't land / was deleted — see Probe 6).
-- Untransferred ('N') rows are simply not in GL yet — expected, not a defect.
-- Do NOT add XLA amounts to GL amounts; compare the levels.


-- -----------------------------------------------------------------------------
-- Probe 8 — Orphan code combinations (CCID not in GL_CODE_COMBINATIONS)
-- Symptom: account decode fails; NULL account name; segment resolution errors
-- -----------------------------------------------------------------------------
-- Every CODE_COMBINATION_ID on a journal/PO line should resolve in
-- GL_CODE_COMBINATIONS. Orphans mean the COA dimension didn't fully land or is
-- stale — segment decode (owned by oracle-fusion-ledger-coa) then returns NULL.
SELECT
    'GL_JE_LINES' AS source_table,
    COUNT(DISTINCT l.code_combination_id) AS orphan_ccid_count
FROM :catalog.:silver_schema.GL_JE_LINES l
LEFT JOIN :catalog.:silver_schema.GL_CODE_COMBINATIONS c
    ON c.code_combination_id = l.code_combination_id
WHERE c.code_combination_id IS NULL
UNION ALL
SELECT 'PO_DISTRIBUTIONS_ALL',
       COUNT(DISTINCT d.code_combination_id)
FROM :catalog.:silver_schema.PO_DISTRIBUTIONS_ALL d
LEFT JOIN :catalog.:silver_schema.GL_CODE_COMBINATIONS c
    ON c.code_combination_id = d.code_combination_id
WHERE c.code_combination_id IS NULL;
-- Orphans here mean GL_CODE_COMBINATIONS ingestion lags the transaction feeds
-- (load the COA dimension first), or a CCID was purged at source. Fix at
-- ingestion; until then, account decode returns NULL for these.
