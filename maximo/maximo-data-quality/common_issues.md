# Common Maximo Data Quality Issues — Root Cause Reference

## Contents

- Issue 1 — WOSTATUS sparse or out of sync with WORKORDER
- Issue 2 — Duplicate (WONUM, SITEID)
- Issue 3 — Task / parent hierarchy broken
- Issue 4 — Inflated counts (WOCLASS not filtered)
- Issue 5 — Orphaned LABTRANS / WPLABOR / WPMATERIAL
- Issue 6 — Hierarchy orphans (ASSET / LOCATIONS pointing at missing parents)
- Issue 7 — Cross-site duplicates (master-data drift)
- Issue 8 — Date inconsistencies
- Issue 9 — PM generation health (compliance dropped suddenly)
- Issue 10 — Custom column unexpectedly NULL
- Quick triage tree
- Issue 11 — LABTRANS orphans against LABOR (composes with maximo-labor-resources)
- Issue 12 — LOCANCESTOR staleness (composes with maximo-asset-hierarchy)
- Issue 13 — Qualifications still ACTIVE past EXPIRYDATE (composes with maximo-labor-resources)

Each entry maps to a `diagnostics.sql` probe. After running the probe, use this guide to interpret findings and recommend remediation.

> Universal mechanics (SITEID, WOCLASS, ISTASK, SYNONYMDOMAIN status resolution, HISTORYFLAG, app-server-timezone) are owned by `maximo-overview`. This file applies them; it does not re-teach them.

---

## Issue 1 — WOSTATUS sparse or out of sync with WORKORDER

**Probe**: `Probe 1 — WOSTATUS coverage`

**Symptoms**:
- Many `WORKORDER` rows have zero corresponding `WOSTATUS` rows
- Latest `WOSTATUS.STATUS` doesn't match `WORKORDER.STATUS`
- Status-transition queries return suspiciously few rows

**Rule out first (not data defects)**:
- **Synonym mismatch**: `WORKORDER.STATUS` and `WOSTATUS.STATUS` store the customer-renamable synonym (`SYNONYMDOMAIN.VALUE`), not the internal `MAXVALUE`. A "mismatch" can be two synonyms of the same internal value — resolve both via `SYNONYMDOMAIN` (`DOMAINID='WOSTATUS'`) before calling it a defect. (Owned by `maximo-overview`.)
- **HISTORYFLAG**: closed WOs (`HISTORYFLAG=1`) drop out of standard List views, so a WO that "lost" its history in a List-derived feed may simply be in history. Count with and without `HISTORYFLAG=0`. (Owned by `maximo-overview`.)

**Root causes**:
1. **REST-API ingestion bug**: Maximo's REST PATCH endpoints can update `WORKORDER.STATUS` directly without writing to `WOSTATUS`. Confirmed by [IBM APAR IJ17261](https://www.ibm.com/support/pages/apar/IJ17261). Most common cause.
2. **Mobile workflow gap**: Some Maximo mobile clients write status changes via a path that bypasses `WOSTATUS`.
3. **Ingestion-side filtering**: A Bronze→Silver pipeline that dedups WOSTATUS too aggressively.

**Remediation**:
- Confirm ingestion path with the platform team.
- If REST/mobile: the only fully correct fix is on the source side (use the OS API for status updates).
- Short-term: document the limitation. Any "status history" or "time in status" report has a known gap.

---

## Issue 2 — Duplicate (WONUM, SITEID)

**Probe**: `Probe 2 — WONUM uniqueness within SITEID`

**Root causes**:
- Ingestion idempotency bug — usually a missing primary key on the Bronze table.
- Bronze→Silver merge that didn't dedup correctly.

**Remediation**:
- Add `dropDuplicates(['WONUM', 'SITEID'])` keeping the latest by `STATUSDATE` or audit timestamp.
- Fix the upstream merge logic.

---

## Issue 3 — Task / parent hierarchy broken

**Probe**: `Probe 3 — ISTASK / PARENT roll-up integrity`

**Root causes**:
- Orphan tasks (`ISTASK=1` but `PARENT IS NULL`): rare; usually corruption or a partial ingestion.
- `PARENT` points to a WONUM that doesn't exist: ingestion dropped the parent header for some reason (delete vs soft-delete mismatch).

**Remediation**:
- For backlog counts, filter to `ISTASK = 0` only.
- For labor / cost totals, roll up by `PARENT` rather than counting all rows.

---

## Issue 4 — Inflated counts (WOCLASS not filtered)

**Probe**: `Probe 4 — WOCLASS filter sanity`

**Root cause**: Query forgot `WHERE WOCLASS = 'WORKORDER'`. The table also holds PM, CHANGE, RELEASE, ACTIVITY records.

**Remediation**: Add the filter. Universal — every WO-analytical query should have it.

---

## Issue 5 — Orphaned LABTRANS / WPLABOR / WPMATERIAL

**Probe**: `Probe 5 — Orphan check`

**Root causes**:
- Parent WO was deleted (soft or hard) but child records remained
- Ingestion order issue (child loaded before parent)
- Cross-environment data leak (DEV WORKORDER ingested as PROD)

**Remediation**:
- Orphans inflate cost/labor totals. Either filter them out at analytics time or fix the ingestion to maintain referential integrity.
- Flag the count in any cost report — orphaned LABTRANS is real cost that won't roll up to its WO.

---

## Issue 6 — Hierarchy orphans (ASSET / LOCATIONS pointing at missing parents)

**Probe**: `Probe 6 — Hierarchy orphans`

**Root causes**:
- Asset was retired but children weren't reassigned
- Hierarchy mid-migration (renames, restructures)
- Cross-site assets whose parent lives at a different SITEID

**Remediation**:
- Pin the parent reassignment to a known good date and accept the gap for analytical purposes
- Flag impacted assets in any hierarchical roll-up

---

## Issue 7 — Cross-site duplicates (master-data drift)

**Probe**: `Probe 7 — Cross-site duplicates`

**Root causes**:
- Intended: large company with shared asset designs (e.g. a pump model deployed at 5 sites, each with its own ASSETNUM at that site — legitimate)
- Unintended: two sites both created their own asset record for the same physical asset

**Remediation**:
- Confirm with the customer which case applies. The workspace glossary skill should record any "same name, multiple SITEIDs is intentional for asset class X" exceptions.

---

## Issue 8 — Date inconsistencies

**Probe**: `Probe 8 — Date sanity`

**Rule out first**: Maximo datetimes are stored in the **app-server timezone** (often UTC, but that is a config choice — not guaranteed) and displayed in the user-profile TZ. A "wrong" date is frequently a TZ-display difference, not corruption. Confirm the deployment's app-server TZ (a `maximo-setup` interview fact) before flagging rows. (Mechanic owned by `maximo-overview`.)

**Root causes** (genuine defects, after ruling out TZ):
- Manual data correction that updated `ACTFINISH` without checking `REPORTDATE`
- Clock drift on the ingestion side — `REPORTDATE` in the future is usually ingestion clock drift
- `LABTRANS` / failure rows appended via Edit History on a closed WO can legitimately postdate `ACTFINISH`/close — that's expected, not a defect

**Remediation**:
- Do NOT blindly rewrite to UTC — first confirm the app-server TZ so conversions are correct (defer the actual TZ to `maximo-setup`).
- Filter out implausible rows or flag them; bucket by day/week/month only after the TZ is known.

---

## Issue 9 — PM generation health (compliance dropped suddenly)

**Probe**: `Probe 9 — PM generation health`

**Root causes**:
- Maximo's PM cron task is paused or failing
- A configuration change disabled generation for a class of assets
- Calendar bug (PMs scheduled past 2025-12-31 fail on a buggy clock setup — has happened)

**Remediation**:
- Coordinate with the Maximo admin team — this is a source-system issue, not an analytics one.
- For reporting, note the drop and exclude from compliance trend analysis until resolved.

---

## Issue 10 — Custom column unexpectedly NULL

**Probe**: `Probe 10 — Custom column population`

**Root causes**:
- Column was added recently — older WOs have no value
- Field-level permission prevents some users from setting it
- Mobile workflow doesn't expose the field
- Ingestion dropped the column at Bronze

**Remediation**:
- Check `Probe 10`'s null %.
- If null % is high for old WOs but low for recent: column is new — limit analytical time range to post-introduction.
- If null % is high across all time: ingestion bug or field-permission issue.

---

## Quick triage tree

```
Wrong number observed
│
├─ Counts inflated → Probe 4 (WOCLASS) → Probe 3 (ISTASK)
├─ History sparse → Probe 1 (WOSTATUS)
├─ Duplicates → Probe 2 (WONUM uniqueness)
├─ Labor/cost off → Probe 3, then Probe 5 (orphans), then Probe 11 (LABTRANS → LABOR orphans)
├─ Site totals weird → Probe 7 (cross-site dupes), Probe 6 (hierarchy orphans)
├─ Trend broken → Probe 8 (dates), Probe 9 (PM gen)
├─ Custom column issue → Probe 10
├─ Hierarchy rollup off → Probe 12 (LOCANCESTOR staleness)
└─ Qualified labor over-counted → Probe 13 (expired QUALPERSON marked ACTIVE)
```

---

## Issue 11 — `LABTRANS` orphans against `LABOR` (composes with `maximo-labor-resources`)

**Probe**: `Probe 11`

**Root cause**: `LABTRANS.LABORCODE` references a labor record that doesn't exist in `LABOR`. Common when:
- Labor records were deleted (hard delete) but transactions retained
- Cross-organization labor (labor borrowed from another org with a different `ORGID`)
- Bronze ingestion of `LABOR` lags `LABTRANS`

**Remediation**: At analytics time, either exclude orphan transactions or surface them as a separate "unattributable labor" bucket. Don't silently include — they inflate craft / contractor totals.

## Issue 12 — `LOCANCESTOR` staleness (composes with `maximo-asset-hierarchy`)

**Probe**: `Probe 12`

**Root cause**: `LOCANCESTOR` is supposed to materialize all ancestor-descendant pairs but isn't in sync with `LOCHIERARCHY` (e.g. ingestion didn't capture a Maximo-side rebuild). The 2-hop probe finds parent-of-parent pairs that should be in `LOCANCESTOR` but aren't.

**Remediation**:
- If many rows missing: fall back to recursive CTE on `LOCHIERARCHY` for hierarchy queries (see `maximo-asset-hierarchy/gotchas.md`).
- If few rows missing: trigger a Maximo-side hierarchy rebuild or fix Bronze ingestion to capture the closure update.

## Issue 13 — Qualifications still ACTIVE past EXPIRYDATE (composes with `maximo-labor-resources`)

**Probe**: `Probe 13`

**Root cause**: `QUALPERSON.STATUS` should transition to `EXPIRED` when `EXPIRYDATE` passes, but the Maximo automatic-transition job is sometimes disabled or fails silently. Rows show `STATUS = 'ACTIVE'` even after expiry.

**Remediation**: Always filter `(EXPIRYDATE IS NULL OR EXPIRYDATE > current_date())` in "qualified labor" queries — don't trust `STATUS` alone. The shipped `qualified_labor_count` UDF in `maximo-labor-resources` already does this.
