# WellView Daily Ops & Cost — Schema Reference

For the universal record tree and `WV`/`LV`/`SYS` grammar, see `wellview-overview/SKILL.md`.
This file focuses on the daily-report / time-log / cost / AFE spine.

> **All names are canonical WellView concepts.** Resolve to physical tables/columns via the
> `<customer>-wellview-glossary` (from `wellview-setup`). Physical spellings vary per install
> (e.g. the time log may be `WVJOBREPORTOP`, `WVOPERATION`, or `WVTIME`; cost may be `WVCOST`,
> `WVJOBREPORTCOST`, or `WVDAILYCOST`). **Confirm before querying.** Every numeric column has a
> **master unit** recorded in the glossary — never compute without it.

## Contents
- The spine & how it joins
- WVWELLHEADER / WVJOB (context)
- WVJOBREPORT (daily report)
- Time log (WVJOBREPORTOP / operations)
- WVCOST (cost)
- WVAFE / WVAFEDETAIL (AFE)
- Cardinality

## The spine & how it joins

```
WVWELLHEADER (well, IDREC = IDWELL)
└── WVJOB (1 / job)                         job.IDWELL = well.IDWELL
    ├── WVJOBREPORT (1 / day / job)         report.IDRECPARENT = job.IDREC
    │   ├── time log (1 / activity)         op.IDRECPARENT = report.IDREC
    │   └── WVCOST (cost lines)             cost.IDRECPARENT = report.IDREC OR job.IDREC  ← CONFIRM
    └── WVAFE → WVAFEDETAIL                  afe.IDRECPARENT = job.IDREC
```
Every row also carries `IDWELL` (well bucket) and audit columns (`SYSCREATEDATE`, `SYSMODDATE`).
**Join the tree on `IDRECPARENT → IDREC`; use `IDWELL` only to filter to a well.**

## WVWELLHEADER / WVJOB (context)

| Concept | Meaning | Used for |
|---|---|---|
| `WVWELLHEADER.IDREC` (= `IDWELL`) | Well identity | Top-level filter, well name/API |
| `WVJOB.IDREC` | Job identity (drill / completion / workover / P&A) | **The grain for cost/footage/days roll-ups** |
| `WVJOB.JOBTYPE` | Job type code (decode via `LVWVTYPEJOB`) | Pick drilling jobs for days-vs-depth |
| `WVJOB.DTTMSTART` / spud | Job/well start | Days-from anchor (confirm spud vs job-start) |

## WVJOBREPORT (daily report) — grain: one row per day per job

| Concept | Meaning | Used for |
|---|---|---|
| `IDREC` | Report identity | Parent of time-log + (maybe) cost rows |
| `IDRECPARENT` | → `WVJOB.IDREC` | Join to job |
| report date (`DTTMSTART`) | The operational day | Daily readout, days elapsed |
| `DEPTHMD` / `DEPTHTVD` | Depth at 24:00 (**master unit!**) | Days-vs-depth, daily footage |
| `DAYSFROMSPUD` | Days since spud (**may be calc, not stored**) | Days-vs-depth x-axis |
| 24-hr summary | Free-text day summary | Report readout |
| `COSTDAY` / `COSTCUM` | Daily / cumulative cost (**may be calc, not stored**) | Cost trend (else recompute) |

## Time log (WVJOBREPORTOP / operations) — grain: one row per activity

| Concept | Meaning | Used for |
|---|---|---|
| `IDREC` | Activity identity | — |
| `IDRECPARENT` | → `WVJOBREPORT.IDREC` | Join to report-day |
| time-on / time-off (`DTTMSTART`/`DTTMEND`) | Activity start/end | Duration; reconcile to ~24h/day |
| `HRS` | Stored duration (hours) | NPT %, activity time |
| `PHASE` | Hole section / phase code (decode via `LVWVPHASE`) | Section ROP, phase NPT |
| `CODEOP` | Operation code (decode via `LVWVCODEOP`) | Activity classification |
| productive flag / `CODENPT` | NPT marker (decode via `LVWVCODENPT`) | **NPT classification** |
| `DEPTHSTART` / `DEPTHEND` | Footage drilled in the activity (**master unit!**) | ROP, daily footage |

## WVCOST (cost) — grain: one row per cost line

| Concept | Meaning | Used for |
|---|---|---|
| `IDREC` | Cost-line identity | — |
| `IDRECPARENT` | → report **or** job `IDREC` (**CONFIRM per install**) | Join; drives roll-up grain |
| `CODECOST` | Cost code (decode + rollup via `LVWVCODECOST`) | Tangible/intangible, category filters |
| `AMOUNT` | Cost amount (**currency = master unit!**) | Cost/ft, daily/cum cost |
| currency | Cost currency | Multi-currency normalization |
| `AFENUM` | AFE reference | AFE vs actual |

## WVAFE / WVAFEDETAIL (AFE)

| Concept | Meaning | Used for |
|---|---|---|
| `WVAFE.IDREC` | AFE identity | — |
| `WVAFE.IDRECPARENT` | → `WVJOB.IDREC` | Join to job |
| `AFENUM` | AFE number | Match to cost `AFENUM` |
| `AFEAMOUNT` | Authorized amount (original vs supplement — confirm) | Variance baseline |
| `AFESTATUS`, `DTTMAFE` | AFE status / date | Lifecycle |
| `WVAFEDETAIL` | AFE cost-code lines + **% allocation across jobs/wells** | De-dup shared AFE before variance |

## Cardinality

| Relationship | Cardinality |
|---|---|
| well → job | 1 : N (the double-count risk) |
| job → daily report | 1 : N (one per day) |
| daily report → time-log activity | 1 : N |
| job (or report) → cost line | 1 : N |
| AFE ↔ job/well | N : N (percentage allocation) |
