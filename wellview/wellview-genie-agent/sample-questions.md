# WellView Genie Agent — Sample Questions

Canonical daily-ops/cost questions the Agent should answer well after curation. Use as the
validation set when standing up a new Agent.

## Daily operations

- "Pull the daily drilling report for well X on 2026-05-10."
- "How many hours of NPT did we have on the last well, and what caused it?"
- "Show the time log for that report-day."
- "Average ROP by hole section on job Y."

## Cost & AFE

- "Cost per foot on our last 5 drilling wells."
- "Are we over AFE on job Y? By how much?"
- "Cumulative cost to date on the current job."
- "Total intangible cost on well X."

## Benchmarking

- "Days-vs-depth curve for the Permian drilling wells."
- "Which well had the highest NPT % last quarter?"

## Validation expectations

For each question, confirm the Agent:
- **Surfaces the NPT definition** before reporting NPT % (no silent default).
- **Reports in the documented master unit** (metres / the cost currency) and doesn't compare raw `WV` columns.
- **Rolls up by job** (`WVJOB.IDREC`) before the well — no multi-job double-count.
- **Calls the Trusted UDF** (cost_per_foot, npt_pct, afe_variance_pct) when one exists, not regenerated SQL.
- **Walks the record tree** on `IDRECPARENT → IDREC`, not `IDWELL`.
