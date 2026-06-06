# WellView Daily Ops & Cost — Gotchas

The traps that make daily-ops/cost answers *confidently and invisibly* wrong. The top 5 are
inline in SKILL.md; the full set is here. Load before writing non-trivial joins.

## 1. Walk the tree by `IDRECPARENT = parent.IDREC`, not `IDWELL`

`IDWELL` is the well bucket carried on every row; it is **not** the parent edge. Daily report →
job is `report.IDRECPARENT = job.IDREC`; time-log → report is `op.IDRECPARENT = report.IDREC`.
Joining report-to-job (or op-to-report) on `IDWELL` matches every report/op on the well to every
job, fanning out and inflating counts, hours, and cost. Use `IDWELL` only in a `WHERE` to scope.

## 2. One well has many jobs — group by `WVJOB.IDREC` before rolling to the well

A well accumulates drill + completion + workover + re-entry jobs over its life. Summing footage,
days, or cost across the well without first grouping by job double-counts and mixes unlike work
(a 30-day drill with a 2-day wireline workover). For "the last well," confirm which **job** is
meant (usually the latest **drilling** job, `JOBTYPE` via `LVWVTYPEJOB`), not the whole well.

## 3. Master/storage units, not display units

WellView stores numbers in a configurable **master unit per quantity** and converts only for the
UI. Raw `DEPTHMD` / `DEPTHSTART` / `DEPTHEND` may be **feet or metres**; `AMOUNT` carries a
**currency**. A cost-per-foot that divides USD by metres-read-as-feet is silently ~3.28× off.
**Confirm the master unit of every numeric column via the glossary and normalize first**
(`wellview_ft_to_m` centralizes the depth conversion). Same trap for multi-currency cost.

## 4. `CostCum`, `DaysFromSpud`, `ROP` may be calc-engine outputs, not stored columns

WellView computes many "fields" through its calc engine; they appear in the UI but **may be absent
from a raw / Snowflake-ETL extract**. Don't assume `COSTCUM`, `DAYSFROMSPUD`, or `ROP` exist as
columns. Recompute via the Trusted UDFs / views here (cumulative cost = window sum of cost by job
ordered by date; days = report date − spud; ROP = footage ÷ on-bottom hours).

## 5. Decode NPT / operation / cost codes through `LV` tables — never hard-code

Whether a time-log activity is NPT, which phase a `PHASE` code names, and what a `CODECOST` rolls
up to are all **customer-configurable** in `LVWVCODENPT` / `LVWVPHASE` / `LVWVCODEOP` /
`LVWVCODECOST`. The same code means different things at different operators. Resolve labels and
classifications via the `LV` join (see `views.sql`) or the glossary; never compare to code literals.

## 6. NPT definition is not universal

Operators disagree on whether **planned** downtime (BOP/casing tests, rig moves, waiting on
weather, rig repair vs sub-contractor repair) counts as NPT. Some key NPT off the productive flag,
some off a non-null `CODENPT`, some exclude planned categories. **Surface the rule before computing
NPT %** (see SKILL.md *Questions to surface first*). `NPT% = Σ NPT hrs / Σ all activity hrs`.

## 7. Time-on/time-off must reconcile to ~24 h per report-day

Time-log activity hours for a report-day should sum to ~24. Prefer the stored `HRS`; if computing
from `DTTMSTART`/`DTTMEND`, handle activities that **cross midnight** and any gaps/overlaps. A day
that sums to 26 h or 19 h is a data-quality signal (see `wellview-data-quality`), not a real number.

## 8. AFE allocation is many-to-many — de-dup before variance

An AFE can fund **multiple jobs/wells**, allocated by percentage in `WVAFEDETAIL`. Joining cost or
AFE amounts naively across jobs double-counts. Attribute the AFE by its allocation %, and confirm
**which AFE amount** is the baseline (original vs latest supplement) before reporting overrun %.
`AFE variance % = (actual − AFE) / AFE × 100`.

## 9. Cost parentage: report vs job

Daily cost lines may parent off the **daily report** (`cost.IDRECPARENT = report.IDREC`) or directly
off the **job** in some installs. This changes whether you roll cost up through the report or
straight to the job. **Confirm parentage in `wellview-setup`**; `v_job_cost_rollup` is written to
roll to the job grain either way once the parentage is known.

## 10. Cost-per-foot interval ambiguity

$/ft over a hole section, a job, or the whole well are different numbers, as are all-in vs
intangibles-only vs rig-spread-only. The bit-economics form is `CT = (B + CR·(t + T)) / F`; the
well-level simplification is total cost ÷ total footage. **Confirm interval + cost-code scope +
per-job-or-well** before reporting (see SKILL.md *Questions to surface first*).

## 11. Days-vs-depth must compare like wells

A days-vs-depth (or days-per-1000-ft) curve is only meaningful across wells of the same type /
section / area, anchored consistently (spud vs job-start, MD vs TVD). Mixing a deep horizontal with
a shallow vertical produces a misleading benchmark. Confirm the cohort and the anchor.
