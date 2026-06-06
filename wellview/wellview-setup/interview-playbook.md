# WellView Setup — Interview

Ask in **batches of 2–3**, never the whole list. Lead each batch with what the
introspection draft already guessed ("I think `wvjobreport` is your daily report keyed by
`idrecparent → wvjob.idrec`, and `depthmd` is in **feet** — right?"). Record answers in
`answers.json` for `generate_glossary.py`.

## Batch 1 — Identity & the well→job spine (always first)
1. Which catalog/schema holds WellView? (e.g. `wellview.silver`)
2. Confirm the **well** table (`WVWELLHEADER`?) and that `IDREC = IDWELL` at the well level.
3. Confirm the **job** table (`WVJOB`?). How do business well/job names map to records
   (well name, API/UWI, job number)?
4. Do wells routinely have **multiple jobs** (drill + workover + re-entry)? (Confirms the
   double-counting risk.)

## Batch 2 — Master units (the critical batch)
5. What is the **master/storage unit** for **depth & footage** — feet or metres? (Per the
   draft's flagged numeric columns.)
6. What is the **cost currency**, and is it stored per-row? Any multi-currency wells?
7. For every other numeric column used in metrics (mud weight, pressure, diameter),
   what's the master unit?
8. Are values stored in master units and converted only in the UI? (Confirms raw extracts
   are master-unit.)

## Batch 3 — Daily report & time log
9. Confirm the **daily operations report** table (`WVJOBREPORT`?) and that its grain is
   **one row per day per job** (parented `idrecparent → wvjob.idrec`).
10. Confirm the **time-log / operations** table (one row per activity within a day). Which
    columns are time-on / time-off / duration, **phase**, **operation code**, depth
    start/end?
11. Which column / value marks an activity as **NPT (non-productive)** vs productive?

## Batch 4 — Cost & AFE
12. Confirm the **cost** table and **its parentage** — does daily cost hang off the
    **job** or the **daily report**? (Changes every roll-up.)
13. Cost columns: cost code, amount, currency, AFE reference, daily-vs-cumulative.
14. Confirm the **AFE** table and how AFE amounts allocate across jobs/wells
    (percentage allocation?). Are there shared AFEs across multiple jobs?

## Batch 5 — Codes (LV) & calc-vs-stored
15. Which `LV*` tables decode **operation**, **phase**, **NPT**, **cost**, and
    **job-type** codes? What is the code→label column pair?
16. Which metrics are **stored columns** vs **calc-engine outputs** that won't appear in a
    raw extract? (Check `DaysFromSpud`, `CostCum`, `ROP`, cumulative footage.)

## Batch 6 — Domains present & jargon
17. Which domains/detail trees exist in this install — drilling, completion, workover,
    integrity? (Drives which module skills are useful.)
18. Business jargon: rig names, field/lease groupings, cost-code rollup categories,
    well-status conventions.

> For anything the customer can't confirm, write `_unknown_ — needs validation from
> <role>` in the glossary rather than guessing.
