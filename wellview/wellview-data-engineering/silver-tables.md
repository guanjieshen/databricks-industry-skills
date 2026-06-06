# WellView — Silver table list

The curated subset to materialize for the daily-ops/cost family. A full WellView DB has
**200–300 tables**; only the spine + decode + unit config below are needed here. Resolve
physical names via the `<customer>-wellview-glossary` (spellings vary per install).

> CDC: merge on **`IDREC`** (GUID PK), watermark on **`SYSMODDATE`**. No composite key.

## Contents
- WV spine (data)
- LV (decode)
- SYS (config)

## WV spine (data tables)

| Canonical | Grain | Parent edge | Why materialize |
|---|---|---|---|
| `WVWELLHEADER` | 1 / well | root (`IDREC=IDWELL`) | Well identity, name, API/UWI |
| `WVJOB` | 1 / job | `IDWELL` → well | The roll-up grain; job type, spud, AFE ref |
| `WVJOBREPORT` | 1 / day / job | `IDRECPARENT` → job | Daily report: date, depth, days |
| `WVJOBREPORTOP` (time log) | 1 / activity | `IDRECPARENT` → report | Hours, phase, op/NPT code, footage |
| `WVCOST` | 1 / cost line | `IDRECPARENT` → report or job | Daily cost, code, currency, AFE# |
| `WVAFE` | 1 / AFE | `IDRECPARENT` → job | AFE baseline for variance |
| `WVAFEDETAIL` | AFE line | `IDRECPARENT` → AFE | % allocation across jobs/wells |
| `WVJOBRIG` | rig assignment | `IDRECPARENT` → job | Rig dimension |

*(Drilling/completion/integrity modules add `WVBITRUN`, `WVSURVEY`, `WVCASING`, `WVPERFORATION`,
`WVPRESSURETEST`, etc. — materialize per active module.)*

## LV (decode) tables

Small lookups; materialize all that decode columns the family uses. Code→label is typically
`CODE` → `DESCRIPTION` (confirm).

| Table | Decodes |
|---|---|
| `LVWVTYPEJOB` | `WVJOB.JOBTYPE` (Drilling / Completion / Workover / P&A) |
| `LVWVPHASE` | `WVJOBREPORTOP.PHASE` (hole section) |
| `LVWVCODEOP` | `WVJOBREPORTOP.CODEOP` (operation) |
| `LVWVCODENPT` | `WVJOBREPORTOP.CODENPT` (NPT reason) |
| `LVWVCODECOST` | `WVCOST.CODECOST` (cost code + `CATEGORY` rollup) |

## SYS (config) tables

Not analytical, but required to interpret values correctly.

| Table | Why |
|---|---|
| `SYSUNIT` (unit defs) | **The master unit of each numeric column.** Source the depth/footage unit + cost currency for Silver→Gold normalization. |
| `SYSCALC` (calc defs) | Tells you which UI fields are calc-engine outputs (not stored) so you recompute them in Gold. |
