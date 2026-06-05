# <Source> Setup — Interview Playbook

The script for the customer-conventions interview (step 2 of the setup workflow). Walk through these questions with the business contact; record their answers; encode them into the workspace glossary skill + apply to UC comments where they fit.

## 1. UC catalog and schema

- "Where is your `<source>` Silver data?" → `<catalog>.<schema>` (e.g. `eam.maximo_silver`).

## 2. Open-status set

- "Which `STATUS` values count as 'open' work orders in your operation?" Defaults: `(WAPPR, APPR, INPRG, WSCH, WMATL)` — confirm or override.

## 3. Canonical metric definitions

- **MTBF / MTTR formula** — IBM O&G default, SMRP, or customer-specific?
- **PM compliance** — SMRP 10% tolerance, strict on-time, or customer-specific?
- **Bad-actor criterion** — count, downtime, cost, criticality-weighted?

## 4. Custom worktype codes

- Defaults are `CM` / `PM` / `EM` / `PROJ`. Does your deployment use additional or different codes?

## 5. Business jargon

- What business terms do you use that don't appear in `<source>`'s schema? (These become the workspace glossary entries.)
- "Region" / "area" / "unit" → which physical column or hierarchy level?

## 6. Approvals

- Who reviews the UC-comments preview before `--apply` runs?

Record answers in the workspace glossary skill (`<customer>-<source>-glossary`) and in this skill's `<source>_comments.json` where they fit per-column.
