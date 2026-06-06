# WellView Data Quality — common issues (symptom → cause → fix)

Load when the symptom doesn't match an obvious diagnostics probe. Each fix names the layer
it belongs in — most belong in `wellview-data-engineering` (Silver→Gold), not query patches.

## Contents
- Cost / footage wrong
- Counts / totals wrong
- Metrics blank
- History / reconciliation

## Cost / footage wrong

| Symptom | Likely cause | Fix |
|---|---|---|
| Cost per foot ~3.28× off | Depth/footage in feet compared as metres (or vice-versa) | Normalize master unit at Silver→Gold (`wellview_ft_to_m`); confirm `SYSUNIT`. *(data-engineering)* |
| Well cost looks doubled | Roll-up not grouped by `WVJOB.IDREC`; well has multiple jobs | Group by job first, then roll to well. *(daily-ops-cost)* |
| Cost inflated on shared AFE | AFE allocated to multiple jobs without de-dup | Attribute by `WVAFEDETAIL` % allocation. *(daily-ops-cost)* |
| Totals mix currencies | `WVCOST.CURRENCY` varies; summed raw | Convert to a base currency at Silver→Gold. *(data-engineering)* |

## Counts / totals wrong

| Symptom | Likely cause | Fix |
|---|---|---|
| Activity/cost counts inflated | Tree joined on `IDWELL` not `IDRECPARENT→IDREC` | Fix join to the parent edge. *(any module)* |
| Rows missing from joins | Orphan `IDRECPARENT` (parent row absent) | Report orphan count; fix ingestion/dedup. *(data-engineering)* |
| Footage too high | Footage summed across overlapping/duplicated activities | Dedup time-log by `IDREC`; check 24-h reconciliation. *(data-engineering)* |

## Metrics blank

| Symptom | Likely cause | Fix |
|---|---|---|
| `DaysFromSpud` / `CostCum` / `ROP` NULL | Calc-engine field, not stored in the extract | Recompute in Gold (date diff, window sum, footage/hours). *(data-engineering)* |
| NPT % returns 0 / wrong | NPT rule mis-encoded; codes undecoded | Confirm NPT rule + `LVWVCODENPT` decode. *(setup → daily-ops-cost)* |

## History / reconciliation

| Symptom | Likely cause | Fix |
|---|---|---|
| Doesn't match the WellView daily report | Wrong job selected (well has many), or unit mismatch | Confirm job + master unit; reconcile per-job. *(data-quality → daily-ops-cost)* |
| Day's hours ≠ 24 | Missing/overlapping activities or midnight-crossing math | Inspect time log; prefer stored `HRS`. *(data-quality)* |
