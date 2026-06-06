# WellView Data Model

Broader entity catalogue and cross-module concepts. Load when a question spans modules or needs
the entity map beyond the daily-ops/cost spine. Names are canonical — resolve physical names via
the `<customer>-wellview-glossary`.

## Contents
- The universal column contract
- The prefix grammar (WV / LV / SYS)
- Core entities by domain
- Cross-module conventions

## The universal column contract

Nearly every `WV*` table carries the same keys + audit columns:

| Column | Role |
|---|---|
| `IDREC` | Primary key (GUID), globally unique |
| `IDRECPARENT` | FK to the parent row's `IDREC` — **the hierarchy edge** |
| `IDWELL` | Denormalized well GUID (filter, not relate); = `WVWELLHEADER.IDREC` |
| `SYSCREATEDATE` / `SYSMODDATE` | Audit; `SYSMODDATE` is the CDC watermark |

**Relate rows with `IDRECPARENT → IDREC`; filter to a well with `IDWELL`.**

## The prefix grammar (WV / LV / SYS)

| Prefix | Meaning | Use |
|---|---|---|
| `WV…` | Data tables (the record tree) | The analytical surface |
| `LV…` | List-of-values lookups (code → label) | Decode coded columns; customer-configurable |
| `SYS…` | System/config (units, calc defs, security) | Interpretation + ETL, not analytics |

`WV<entity>` is the spine row; `WV<entity><subpart>` are its children, so names are predictable
(`WVCASING` ⇒ `WVCASINGTUBULAR` / `…CEMENT`). A full DB has 200–300 tables; learn the grammar,
introspect the rest.

## Core entities by domain

| Domain | Tables (canonical) | Owned by |
|---|---|---|
| Well / structure | `WVWELLHEADER`, `WVWELLBORE` | `wellview-overview` |
| Job / planning | `WVJOB`, `WVJOBRIG` | `wellview-daily-ops-cost` |
| Daily ops / time log | `WVJOBREPORT`, `WVJOBREPORTOP` | `wellview-daily-ops-cost` |
| Cost / AFE | `WVCOST`, `WVAFE`, `WVAFEDETAIL` | `wellview-daily-ops-cost` |
| Drilling detail | `WVBITRUN`, `WVSURVEY`, `WVCASING` | `wellview-drilling-npt` *(fast-follow)* |
| Completion | `WVPERFORATION`, `WVSTIM` | `wellview-completions-workovers` *(fast-follow)* |
| Integrity | `WVPRESSURETEST`, `WVCOMPONENT`, `WVANNULUS` | `wellview-well-integrity` *(fast-follow)* |
| Lookups / config | `LV*`, `SYSUNIT`, `SYSCALC` | `wellview-setup` |

## Cross-module conventions

- **One well → many jobs.** Roll up by `WVJOB.IDREC` before the well.
- **Master units.** Numbers are stored in a configurable master unit (`SYSUNIT`); the Gold layer
  normalizes to metres / a base currency. Never compare raw `WV` numerics across columns.
- **Calc-vs-stored.** UI metrics (`CostCum`, `DaysFromSpud`, `ROP`) may be calc-engine outputs,
  absent from a raw extract; recompute in Gold.
- **Codes via `LV`.** Every coded column resolves through its `LV` table; codes are per-install.
