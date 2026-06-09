# Prompting cookbook — Maximo Genie Space

**Audience: end users (planners, analysts, leadership) who query the Space.** Not for the Agent's Instructions field.

Per [Databricks Genie Code best practices](https://docs.databricks.com/aws/en/genie-code/use-genie-code), Genie returns better answers when prompts are specific about scope, table references, output shape, and source-specific conventions. This cookbook teaches that for generic Maximo vocabulary, using standard out-of-the-box Maximo defaults — substitute the customer's actual values from `<customer>-maximo-glossary` before shipping.

## How to read this

Each entry: **Vague** (what users naturally type) → **Specific** (what gets a good answer) → **Why** (which Genie behavior the specificity exploits).

The placeholder examples below use **standard Maximo defaults** (no custom statuses, no custom columns, no customer-specific tribal knowledge). Replace `<customer>` / sites / timezone / status set with values from the customer's glossary skill before shipping.

---

## 1. Lock the table when the question spans modules

**Vague:** *"How many open work orders do we have?"*

**Specific:** *"Using `@workorder`, count open work orders (`status IN (WAPPR, APPR, INPRG, WSCH, WMATL)`) where `istask = 0` and `woclass = 'WORKORDER'` for the last 30 days, grouped by site."*

**Why:** "Open work orders" is ambiguous in Maximo — `WORKORDER` carries WOs, tasks (`ISTASK=1`), changes, releases, and activities (filtered by `WOCLASS`). `@workorder` locks the table; the status list locks the customer's open-status convention; `istask = 0` excludes child tasks from the count; `woclass = 'WORKORDER'` excludes PM/Change/Release rows. Without these, Genie may join in `PM` or `TICKET` and over- or under-count.

---

## 2. Use `/findTables` when you don't know the table name

**Vague:** *"Show me failure data."*

**Specific:** *"/findTables related to equipment failures and root cause analysis"*

Then: *"Using `@failurereport`, list the top 10 failure codes by frequency for assets in `CLASSSTRUCTUREID = <customer's rotating-equipment class>` in the last 12 months."*

**Why:** `/findTables` surfaces `FAILUREREPORT`, `FAILURECODE`, `FAILURELIST` so you can pick the right one. "Failure data" alone could match any of them, and Genie may guess wrong. Run `/findTables` first, then ask the focused question with `@<table>`.

---

## 3. Specify the timezone explicitly

**Vague:** *"How many WOs were completed yesterday?"*

**Specific:** *"Using `@workorder`, count WOs with `status = 'COMP'` and `statusdate` between yesterday 00:00 and 23:59 in `<app_server_tz>` (the Maximo app-server timezone — see customer glossary). Group by site."*

**Why:** Maximo datetimes are stored in the **app-server timezone**, not UTC. If you ask "yesterday" without specifying, Genie may interpret in UTC or your browser TZ — for a planner working across regions this can shift counts by a full day. Naming the customer's TZ explicitly anchors the bucket.

---

## 4. Narrow status / work-type / scope to the customer's convention

**Vague:** *"What's our maintenance backlog?"*

**Specific:** *"Backlog = open work orders (`status IN (<customer's open-status set>)`) where `worktype IN ('PM', 'CM', 'EM')` and excluding capital project work-types. Using `@workorder`, count this set by site, weekly trend over the last 12 weeks. Show as a line chart."*

**Why:** "Maintenance backlog" has 3+ valid framings (which statuses count as backlog? does capital work count? do regulatory inspections count?). The customer's convention is in the glossary; naming it in the prompt removes the guessing. Trends also benefit from explicit output shape ("line chart").

---

## 5. Steer output shape — chart, table, step-by-step

**Vague:** *"PM compliance for last quarter."*

**Specific:** *"PM compliance for Q1 2026 by week and by site. Show as a heatmap (week × site) with the compliance percentage as the cell value. Use `MEASURE(pm_compliance_rate)` from the metric view."*

**Why:** Per Databricks docs, Genie respects explicit structure asks. "By week and by site" tells it the two grouping dimensions; "heatmap" tells it the visualization; `MEASURE()` tells it to call the governed metric instead of reinventing the calculation. Without these, you get a single number (or a chart you didn't want).

---

## 6. Use `@<column>` for ambiguous identifiers

**Vague:** *"Show me work orders for asset 12345."*

**Specific:** *"Using `@workorder`, list open work orders for `@assetnum = '12345'` AND `@siteid = '<site>'` (Maximo asset keys are composite). Include `wonum`, `description`, `status`, `worktype`, and `statusdate`."*

**Why:** Maximo asset keys are **composite** — the same `assetnum` can exist on multiple sites. Asking for "asset 12345" without `siteid` can return WOs from multiple sites, or none (if Genie joins wrong). Naming both columns locks the composite key.

---

## 7. Ask Genie to ask back when the convention is unconfirmed

**Vague:** *"Who are our worst-performing assets?"*

**Specific:** *"I want to identify bad-actor assets. Before answering, ask me which framing to use: (a) most WOs in the last 12 months, (b) highest unplanned downtime, (c) most repeat failures (>3 corrective WOs on the same asset). My choice depends on whether the audience is reliability engineering or operations."*

**Why:** "Bad actor" has 4+ valid framings. Telling Genie to ASK BACK rather than guess is the right pattern when the customer's convention isn't yet in the glossary (one of the `_unknown_` items the glossary surfaces). Trains users to expect dialogue, not just a one-shot answer.

---

## How to customize this cookbook before shipping

When the `-genie-agent` skill is run for a new customer, replace these placeholders before pasting into the customer's Space launchpad. Source values from the customer's `<customer>-maximo-glossary` skill:

| Placeholder | Source |
|---|---|
| `<customer>` | The customer's name |
| Open-status list (`WAPPR, APPR, INPRG, WSCH, WMATL`) | `<customer>-maximo-glossary` → `open_statuses` (may include customer-specific statuses) |
| App-server timezone (`<app_server_tz>`) | `<customer>-maximo-glossary` → `app_server_timezone` |
| Sites (`<site>`) | `<customer>-maximo-glossary` → `sites` |
| Work-type buckets (`PM`, `CM`, `EM`) | `<customer>-maximo-glossary` → `worktypes` (Maximo defaults; customer may extend) |
| Modules in scope | `<customer>-maximo-glossary` → `industry_usage.modules_in_use` |
| Metric view measure names (`pm_compliance_rate`) | The in-scope module's `metric_view.yaml` |
| Asset-class IDs (`<rotating-equipment class>`) | `<customer>-maximo-glossary` → `asset_classes` |

Drop entries that don't apply (e.g. cut #4 if maintenance backlog isn't a customer concern; cut #6 if the customer's data is single-site). Add 1-2 entries for the customer's actual top business questions if benchmark monitoring shows they're under-prompted.

## What NOT to do

- Don't paste this content into the Agent's **Instructions** field. The cookbook is for the human prompting the Agent, not the Agent itself.
- Don't ship it without substituting the customer's actual values for the placeholders. The defaults above are stock Maximo — they will not match any customer's deployment exactly.
- Don't make it long. Aim for 3-7 customer-relevant entries, not a comprehensive guide. The Databricks-general prompting tips live in the [docs](https://docs.databricks.com/aws/en/genie-code/use-genie-code); this file is only for the source-specific patterns.

## References

- [Databricks Genie Code — tips & best practices](https://docs.databricks.com/aws/en/genie-code/use-genie-code)
- [Genie Code skills](https://docs.databricks.com/aws/en/genie-code/skills)
- The customer's `<customer>-maximo-glossary` skill (source of the placeholders above)
