# WellView — Genie Agent Curation

The WellView-specific include-list for a curated Genie Agent on daily-ops/cost data. Used by
the platform-layer `databricks-genie` skill to populate the Agent's scope.

## Include — Gold views / fact

Pre-joined, unit-normalized, `LV`-decoded. Include these over raw `WV` tables.

- `v_daily_report_enriched` — daily report + job/well context, depth in metres
- `v_time_log_enriched` — time-log activities, NPT-classified, footage in metres
- `v_job_cost_rollup` — cost rolled to the job grain, cost-code decoded
- `v_daily_ops_cost_fact` — the report-grained metric-view source

## Include — Trusted UDFs (governed metrics)

Register so the Agent calls them instead of regenerating SQL:

- `wellview_cost_per_foot(well_id)` — cost per metre per job
- `wellview_npt_pct(well_id)` — NPT % per job
- `wellview_afe_variance_pct(well_id)` — AFE variance % per job
- `wellview_rop(footage, hours)` — rate of penetration
- `wellview_ft_to_m(ft)` — unit normalizer

## Include — metric view

- `wellview_daily_ops_metrics` — the sliceable semantic layer (cost/ft, NPT %, ROP, days-on-well).

## Include — raw tables (only when needed)

Expose only when a question shape isn't covered by the Gold layer: `WVWELLHEADER`, `WVJOB`,
`WVJOBREPORT`. Keep `LV*`/`SYS*` out of the Agent surface.

## Required Agent instructions (the two non-negotiables)

Bake these into the Agent's general instructions — they're the top silent-error sources:

1. **Master units.** "All depth/footage in the Gold layer is in metres; cost is in
   `<currency>`. Never compare raw `WV` columns without normalizing."
2. **NPT definition.** "Non-productive time is defined as `<customer rule>` (e.g. activities
   flagged non-productive or carrying an `LVWVCODENPT` reason). Use this for NPT %."
3. **Grain.** "Roll cost/footage/days up by job (`WVJOB.IDREC`) before the well — a well has
   many jobs."

## Semantic synonyms to attach

Source from the `<customer>-wellview-glossary` skill. Examples:

| Business term | Physical mapping |
|---|---|
| "the last well" | latest **drilling** job on the well (`JOBTYPE` via `LVWVTYPEJOB`) |
| "cost per foot" | `wellview_cost_per_foot` (confirm cost-code scope) |
| "NPT" | per customer's NPT rule (see glossary) |
| "the Permian wells" | (per customer's field/lease mapping) |
