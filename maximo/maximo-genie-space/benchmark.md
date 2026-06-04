# Maximo Genie Space benchmark

A starter set to measure whether a Maximo Genie Space answers correctly. Ask each
question in the Space, then score against the expected behavior. Add the
customer's own real questions (especially ones from the Monitoring tab) over time.

## Contents
- How to score
- Work management
- Reliability
- Integrity
- HSE
- Cross-cutting / traps

## How to score

For each question, the answer **passes** only if it: uses the right table(s),
applies the universal gotchas (WOCLASS, ISTASK, SITEID, WOSTATUS-vs-WORKORDER),
resolves the customer's business terms via the glossary, and returns the number a
Maximo SME would accept. A confident wrong answer is the worst outcome — log it.

| Score | Meaning |
|---|---|
| Pass | Correct table, joins, filters, and result |
| Partial | Right approach, wrong filter/term (fix glossary or instruction) |
| Fail | Wrong table/metric, or fabricated columns (fix UC comment / example) |

## Work management
- "What's our open work-order backlog by site?" → uses WORKORDER, `WOCLASS='WORKORDER'`, `ISTASK=0`, customer open-status set, grouped by SITEID.
- "Show work orders aging over 90 days." → backlog filter + age from report/created date.
- "Labor hours by craft last month." → LABTRANS/WPLABOR, not planned hours.
- "Corrective vs preventive completed last quarter." → worktype split from glossary.

## Reliability
- "MTBF for centrifugal pumps this year." → calls the Trusted Asset MTBF function; resolves "centrifugal pump" via glossary CLASSSTRUCTUREID.
- "PM compliance by site." → certified PM-compliance function, not ad-hoc SQL.
- "Top 10 bad-actor assets." → failure counts via the reliability functions.

## Integrity
- "Which inspections are overdue?" → regulatory PM/inspection logic, correct due-date basis.
- "Corrosion rate trend for line X." → ASSETMETER/METERREADING thickness, unit-aware.

## HSE
- "TRIR for the last 12 months." → INCIDENT + recordable classification, correct exposure-hours basis.
- "Open permits to work right now." → plusgpermitwork active status.

## Cross-cutting / traps (these catch the common failures)
- "How many work orders do we have?" → must scope to `WOCLASS='WORKORDER'`, `ISTASK=0` (not tasks/PMs).
- "Total labor on WO 12345." → actuals (LABTRANS), not planned (WPLABOR).
- "Status of WO 12345 over time." → WOSTATUS history, not WORKORDER.STATUS.
- A question using a customer term not in the glossary → Genie should ask, not guess.
