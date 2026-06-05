# <Source> Genie Agent — Sample Questions

Canonical questions the Agent should answer well after curation. Use as the validation set when standing up a new Agent.

## Operational

- "What's our open work-order backlog by site?"
- "Show me WOs aging over 90 days."
- "Labor hours by craft last month."
- "Top 10 assets by WO volume this quarter."

## Reliability

- "MTBF for centrifugal pumps over the last year."
- "PM compliance by site for the current quarter."
- "Which assets are our bad actors?"

## Status / history

- "Status history for WO `<WONUM>`."
- "Average time in INPRG for corrective WOs."

## Cross-domain

- "Workload vs capacity by craft next month."
- "Maintenance cost rolled up to region X."

## Validation expectations

For each question, confirm:
- The Agent calls the right Trusted UDF (not regenerated SQL) when one exists
- Filters reflect the customer's open-status set / WORKTYPE conventions
- Site/composite-key joins are intact
- Pre-joined Gold view is used over raw tables when applicable
