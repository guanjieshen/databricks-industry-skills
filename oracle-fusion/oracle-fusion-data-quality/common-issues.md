# Common Oracle Fusion Data Quality Issues — Symptom → Cause → Fix

## Contents

- Issue 1 — Unbalanced journals (trial balance doesn't tie)
- Issue 2 — Posted vs unposted leakage (actuals too high)
- Issue 3 — Multi-currency summing without conversion
- Issue 4 — `_ALL` multi-org duplicate / double-counting
- Issue 5 — Period status mismatch (open periods not final)
- Issue 6 — BICC extract gaps (deletes not captured / late-arriving)
- Issue 7 — GL-to-subledger (XLA) reconciliation drift
- Issue 8 — Orphan code combinations (CCID not in GL_CODE_COMBINATIONS)
- Quick triage tree

Each entry maps to a `diagnostics.sql` probe. After running the probe, use this guide to
interpret findings and recommend remediation.

> Universal mechanics (`_ALL` scoping, CCID segments, posted-vs-unposted, entered-vs-accounted
> currency, period open/close, the GL↔XLA bridge, BICC deletes-not-captured) are owned by
> `oracle-fusion-overview`; the accounting depth (segment/currency/period/XLA) by the keystone
> `oracle-fusion-ledger-coa`. This file applies them; it does not re-teach them.

---

## Issue 1 — Unbalanced journals (trial balance doesn't tie)

**Probe**: `Probe 1 — Unbalanced journals`

**Symptom**: a journal header's `ACCOUNTED_DR` ≠ `ACCOUNTED_CR`; the trial balance doesn't tie.

**Rule out first (not defects)**:
- Comparing on `ENTERED` instead of `ACCOUNTED` — a multi-currency journal balances in ledger currency, not document currency. Re-check on `ACCOUNTED`.

**Causes**:
1. **Lines dropped / late in the extract** — the most common ingestion cause; some lines of a header didn't land (see Issue 6). A **posted** header that doesn't balance is almost always this, because Fusion will not post an unbalanced journal at source.
2. **Join fan-out** — joining headers to lines and another child without care duplicates lines.
3. **Genuine source corruption** — rare.

**Fix**: confirm completeness against a full snapshot; fix the extract to land all lines (data-engineering). For analytics, exclude or flag headers with a nonzero imbalance and surface the count.

---

## Issue 2 — Posted vs unposted leakage (actuals too high)

**Probe**: `Probe 2 — Posted vs unposted leakage`

**Symptom**: actuals are higher than expected.

**Cause**: the query included unposted journals (`STATUS='U'`) or budget/encumbrance rows (`ACTUAL_FLAG IN ('B','E')`). Correct actuals = `STATUS='P' AND ACTUAL_FLAG='A'`.

**Fix**: add the filters. Universal for any "actuals" question. This is a **definition mismatch**, not a data defect — keep unposted/budget rows in Silver; filter at consumption.

---

## Issue 3 — Multi-currency summing without conversion

**Probe**: `Probe 3 — Multi-currency summing without conversion`

**Symptom**: cross-entity / multi-currency totals look wrong.

**Cause**: `ENTERED_DR/CR` were summed across rows with different `CURRENCY_CODE` — summing document-currency amounts of different currencies is meaningless.

**Fix**: use `ACCOUNTED` (ledger) amounts for cross-currency totals, or convert `ENTERED` via `GL_DAILY_RATES` (rate type + conversion date), owned by `oracle-fusion-ledger-coa`. Definition mismatch, not a defect.

---

## Issue 4 — `_ALL` multi-org duplicate / double-counting

**Probe**: `Probe 4 — _ALL multi-org duplicate counting`

**Symptom**: spend / PO totals inflated; the same PO appears more than once.

**Causes**:
1. **Missing `PRC_BU_ID` scope** — `_ALL` tables hold every business unit; an unscoped query mixes orgs. Definition mismatch.
2. **Join fan-out** — header amount summed at line/distribution grain double-counts the header. Aggregate at the right grain.
3. **Duplicate `PO_HEADER_ID`** — a genuine ingestion idempotency bug (missing dedup on the PVO key).

**Fix**: scope by `PRC_BU_ID`; aggregate at header grain for header amounts; fix the Silver dedup (data-engineering) if `PO_HEADER_ID` is duplicated.

---

## Issue 5 — Period status mismatch (open periods not final)

**Probe**: `Probe 5 — Period status mismatch`

**Symptom**: a period's numbers keep changing or don't match a closed report.

**Cause**: the period's `closing_status` is `O` (Open) or `F` (Future) — open periods legitimately change as journals post. Only `C`/`P` (closed / permanently closed) periods are final.

**Fix**: this is **expected behavior, not corruption** — confirm the period status before flagging. Sort periods by effective period number (`PERIOD_YEAR*10000 + PERIOD_NUM`), never alphabetically by `PERIOD_NAME`. For point-in-time comparisons, scope to closed periods.

---

## Issue 6 — BICC extract gaps (deletes not captured / late-arriving)

**Probe**: `Probe 6 — BICC extract gaps`

**Symptom**: lakehouse numbers drifted upward vs Fusion; rows deleted in Fusion still appear; a feed looks stale.

**Causes**:
1. **Deletes not captured** — BICC incremental extracts (last-update-date) catch INSERT/UPDATE only. A row hard-deleted in Fusion stops appearing in the extract but **stays in Bronze/Silver**, so totals drift upward. The single most common Fusion-in-lakehouse drift cause.
2. **Late-arriving / paused feed** — a large `days_since_last_update` means the extract stalled.

**Fix**:
- Deletes: add a BICC **Deleted-Record extract** (applied as tombstones) or a **periodic full-reload reconcile** (anti-join the latest full snapshot vs Silver, tombstone missing keys). Owned by `oracle-fusion-data-engineering`.
- Stalled feed: a pipeline/scheduling issue, not bad data — escalate to whoever owns the extract job.
- Record the customer's extract fidelity in the `oracle-fusion-setup` glossary so this is expected, not re-discovered.

---

## Issue 7 — GL-to-subledger (XLA) reconciliation drift

**Probe**: `Probe 7 — GL-to-subledger (XLA) reconciliation drift`

**Symptom**: a GL account total doesn't match the subledger (AP/AR/PO) detail.

**Rule out first (not defects)**:
- **Untransferred XLA** (`GL_TRANSFER_STATUS_CODE='N'`) is simply not in GL yet — expected, not a gap.
- **Adding levels** — XLA detail rolls *up into* GL. Adding GL journal amounts to XLA detail double-counts. Reconciliation **compares** the two levels via `GL_SL_LINK_ID`; it never sums them.

**Cause (genuine)**: XLA lines marked transferred (`'Y'`) with no matching `GL_JE_LINES` row — the GL side didn't land or was deleted (see Issue 6).

**Fix**: confirm the GL feed landed all transferred lines; fix the extract. For analytics, reconcile at one level (GL for posted summaries, XLA for transaction-level detail) and surface the gap count.

---

## Issue 8 — Orphan code combinations (CCID not in GL_CODE_COMBINATIONS)

**Probe**: `Probe 8 — Orphan code combinations`

**Symptom**: account decode returns NULL; segment resolution errors; an account "has no name".

**Causes**:
1. **COA dimension lags the transaction feeds** — `GL_CODE_COMBINATIONS` didn't fully land, or loaded after the journal/PO feeds. Load the COA dimension first.
2. **CCID purged at source** — a combination was removed (rare; relates to Issue 6 deletes).

**Fix**: ensure `GL_CODE_COMBINATIONS` ingests completely and ahead of the transaction tables (data-engineering). Until fixed, segment decode (owned by `oracle-fusion-ledger-coa`) returns NULL for orphan CCIDs — surface them rather than dropping silently.

---

## Quick triage tree

```
Wrong financial number observed
│
├─ Trial balance won't tie → Probe 1 (unbalanced) → then Probe 6 (dropped lines)
├─ Actuals too high → Probe 2 (posted/unposted, actual_flag)
├─ Multi-currency total off → Probe 3 (ENTERED vs ACCOUNTED)
├─ Spend / PO inflated or duplicated → Probe 4 (_ALL scope, fan-out, dup PO_HEADER_ID)
├─ Period keeps changing → Probe 5 (period open/close status)
├─ Drifted from Fusion / deletes persist → Probe 6 (BICC extract gaps)
├─ GL ≠ subledger → Probe 7 (XLA reconciliation via GL_SL_LINK_ID)
└─ Account decode NULL → Probe 8 (orphan CCID)
```

Before any of the above: rule out a **user-side definition mismatch** (currency basis,
posted-only, ledger/BU scope) — the most common "wrong number" is a differing definition,
not bad data.
