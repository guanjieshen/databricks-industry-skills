# <Source> — Genie Agent Curation

The source-specific include-list for a curated Genie Agent on `<source>` data. Used by the platform-layer `databricks-genie` skill to populate the Agent's data scope.

## Include — Gold views

These pre-joined views give the Agent better answers than raw tables. Include them all in the Agent's table set.

- `v_workorder_enriched` — work-order header joined with asset + location + jobplan
- `v_workorder_status_history` — `WOSTATUS` joined with `WORKORDER` for time-in-state queries
- `v_labor_actuals` — `LABTRANS` aggregated per WO
- (add per module)

## Include — Trusted UDFs (governed metrics)

Register these so the Agent calls them as governed metrics instead of regenerating SQL:

- `open_wo_count(site, as_of)` — `<source>-work-orders`
- `wo_aging_bucket(reportdate)` — `<source>-work-orders`
- `mean_time_to_complete(worktype, window_days)` — `<source>-work-orders`
- `mtbf(asset_class, window_days)` — `<source>-reliability`
- (add per module)

## Include — Raw tables (only when needed)

Expose raw tables only when the question shape isn't covered by the Gold views:

- `WORKORDER`, `WOSTATUS`, `ASSET`, `LOCATIONS`
- (add per scope)

## Semantic synonyms to attach

These map customer-business jargon to physical schema. Source them from the workspace `<customer>-<source>-glossary` skill produced by `-setup`:

| Business term | Physical mapping |
|---|---|
| "open work orders" | `STATUS IN (customer's open set)` AND `WOCLASS = 'WORKORDER'` AND `ISTASK = 0` |
| "bad actor" | (per customer's chosen definition — see glossary) |
| "region" | (per customer's hierarchy level — e.g. `LOCANCESTOR` depth) |

## Sample-question seed

See [sample-questions.md](sample-questions.md) — load these as the validation set when the Agent is first stood up.
