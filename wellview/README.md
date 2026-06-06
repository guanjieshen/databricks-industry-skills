# Peloton WellView — Skill Family

A library of Genie Code skills for working with **Peloton WellView** well-lifecycle
data in Databricks. Once installed, **Genie Code behaves as though the customer has a
WellView data-model specialist and a drilling/cost engineer on call** — it knows the
GUID record tree (`IDREC` / `IDRECPARENT` / `IDWELL`), the `WV` / `LV` / `SYS` table
grammar that lets it navigate a 200–300-table schema, the daily-operations and cost
model, the canonical drilling metrics (cost/ft, days-vs-depth, NPT %, ROP, AFE
variance), and the unit/calc-engine traps that make WellView answers *confidently and
invisibly* wrong without help.

Primary industry served: **upstream oil & gas** (drilling, completions, workovers,
well operations). The flagship lens is **daily operations & cost** — the drilling/
workover supervisor and cost/AFE engineer.

The skill format follows the [Agent Skills](https://agentskills.io/) standard.

> **⚠️ Schema-confidence note (read before trusting any SQL).** Peloton does **not**
> publish the WellView data dictionary. This family is authored against **canonical
> WellView concepts** (the GUID contract, the well→job tree, the daily-report/cost
> grain) that are high-confidence from the data model — but **specific physical table
> and column names** (e.g. `WVJOBREPORTOP`, `WVCOST` vs `WVJOBREPORTCOST`, the `LV*`
> code tables) and **the master unit of every numeric column** must be confirmed on
> the customer's instance. That confirmation is exactly what **`wellview-setup`** does.
> Treat un-validated table/column names as hypotheses until the glossary exists.

## Why this family exists (and why units + the record tree are the crux)

Out of the box, Genie guesses at WellView tables — and the scariest failures are
**invisible** to the user. A drilling supervisor or cost engineer knows operations
cold but is usually **not** a WellView-schema expert and prompts tersely ("cost per
foot on the last well", "how much NPT last month", "are we ahead of the AFE"). They
trust the number that comes back.

Unaided, Genie typically:
- **Joins everything on `IDWELL`** instead of walking the record tree
  (`child.IDRECPARENT = parent.IDREC`) — fanning out and **double-counting**.
- **Sums daily cost/footage across a well** without grouping by **job**, so multiple
  jobs on one well (drill + workover + re-entry) **double-count**.
- **Reads raw numeric columns as if they were display units** — but WellView stores in
  **master/storage units** (§ unit subsystem). A depth shown as 10,000 ft may be
  stored in metres. A silent error the engineer cannot see.
- **Assumes UI metrics are stored columns** (`DaysFromSpud`, `CostCum`, `ROP`) when
  many are **calc-engine outputs** absent from a raw extract.
- **Hard-codes operation / NPT / cost codes** instead of decoding them through the
  customer's configurable **`LV` lookup tables**.

These skills fix exactly those failure modes. The single highest-value piece is
**`wellview-setup`** — without an accurate physical→canonical mapping *and the master
unit of every measure column*, every analytical skill produces confident, invisible
errors.

## How WellView data reaches Databricks

WellView is a SQL Server application. Peloton exposes data through **(1) the Peloton
Platform API** and **(2) "Peloton ETL powered by Snowflake" (read-only)** — the latter
is the realistic path to land WellView into a lakehouse. Assume the data is **already
replicated into Databricks**; this family models and queries it, it does not build the
Peloton→lakehouse connector.

## Personas served

None of these personas is a WellView-schema specialist.

| Persona | What they do | Skills they use most |
|---|---|---|
| **Drilling / workover supervisor** | Daily ops report, time log, depth & NPT, days-vs-depth | `overview`, `setup`, `daily-ops-cost` |
| **Cost / AFE engineer** | Daily cost, cost/ft, AFE vs actual, overrun % | `overview`, `setup`, `daily-ops-cost` |
| **Drilling engineer** | ROP, NPT root-cause by phase/op code, bit performance | `overview`, `setup`, `drilling-npt` *(fast-follow)* |
| **Completions engineer** | Completion design, perforations, stimulation, workovers | `overview`, `setup`, `completions-workovers` *(fast-follow)* |
| **Well integrity engineer / compliance** | Barriers, pressure tests, annulus, well status | `overview`, `setup`, `well-integrity` *(fast-follow)* |
| **D&A / platform engineer** | Land + model WellView; build Genie Spaces / dashboards | `overview`, `setup`, `data-engineering`, plus a module |

## Required platform skills

This family references the following platform skills at
[`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills).
Install them alongside (the WellView skills supply the source-specific content; these supply the mechanics):

- [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md) — Genie Agent creation (for `wellview-genie-agent`)
- [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines) — Lakeflow pipelines (for `wellview-data-engineering`)
- [`databricks-unity-catalog`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-unity-catalog) — UC comment mechanics (for `wellview-setup`)
- [`databricks-metric-views`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-metric-views) — metric-view registration (for `wellview-daily-ops-cost`)

## Architecture: foundation + module

### Foundation tier (always-loaded for WellView questions)

| Skill | Single focused task |
|---|---|
| [`wellview-overview`](./wellview-overview/) | Orient Genie on the WellView model — the **`IDREC`/`IDRECPARENT`/`IDWELL` record tree**, the **`WV`/`LV`/`SYS` table grammar** (so it navigates 200–300 tables), the ~17-table daily-ops/cost spine, and the **universal gotchas** (master units, calc-vs-stored, one-well-many-jobs, AFE allocation) |
| [`wellview-setup`](./wellview-setup/) | Bootstrap a customer's workspace — introspect their WellView/Snowflake schema, generate a glossary skill mapping physical tables/columns to canonical concepts **and the master unit of every numeric column**, decode the `LV` code tables, register UC comments. **The load-bearing precondition.** |
| [`wellview-data-engineering`](./wellview-data-engineering/) | Model raw WellView feeds → conformed Silver/Gold — the **per-job spine**, master-unit normalization, `LV` decode, AFE de-duplication |
| [`wellview-data-quality`](./wellview-data-quality/) | Diagnose WellView data issues — orphan `IDRECPARENT`, well/job double-counting, unit inconsistency, AFE over-allocation, calc-vs-stored mismatches |

### Module tier (loaded based on the domain in the question)

| Skill | Domain | Status |
|---|---|---|
| [`wellview-daily-ops-cost`](./wellview-daily-ops-cost/) | **Flagship.** Daily operations report + time log + cost: NPT %, days-vs-depth, cost per foot, AFE vs actual, daily cost roll-up | **shipped (flagship)** |
| `wellview-drilling-npt` | ROP / FPD / MSE, NPT root-cause by phase & operation code, bit-run performance | fast-follow |
| `wellview-completions-workovers` | Completion design, perforations, stimulation/frac stages, workover jobs | fast-follow |
| `wellview-well-integrity` | Barriers, pressure/annulus tests, well status, integrity anomalies | fast-follow |
| [`wellview-genie-agent`](./wellview-genie-agent/) | Scaffold/curate a Genie Agent (formerly Genie Space) over WellView — curation list, Trusted Asset functions (cost/ft, NPT %, AFE variance, ROP), synonyms, and the master-unit + NPT-definition instructions; defers creation mechanics to `databricks-genie` | **shipped** |

Discovery + quality test cases live in [`evals/`](./evals/) (`query → expected_behavior`).

## Composes with the Maximo family

WellView and [Maximo](../maximo/) are complementary lenses on an upstream operator:

- **`wellview-*`** = the **well-construction / well-lifecycle** lens — jobs, daily
  drilling/workover reports, AFE/cost, integrity by wellbore.
- **`maximo-*`** = the **EAM / facility-maintenance** lens — surface equipment work
  orders, reliability, inventory.

An operator running both can ask Genie *"cost per foot on our last 5 wells"* (WellView)
**and** *"open work-order backlog at the compressor station"* (Maximo).

## Install order (recommended)

0. Install [`_common/data-exploration`](../_common/data-exploration/) — the universal
   discovery skill (`databricks experimental aitools tools query` / `discover-schema`).
   It provides the *mechanics* of exploring tables; the WellView skills provide the
   *domain knowledge* of which `WV*` table is which.
1. Install `wellview-overview` next — it orients Genie for everything else.
2. **Run `wellview-setup` once per customer** — it introspects the 200–300-table schema
   and generates the workspace glossary the other skills reference. **This is the
   load-bearing precondition** — without an accurate mapping *and units*, the analytical
   skills produce confident, invisible errors.
3. Install whichever module skills match the customer's use cases
   (`wellview-daily-ops-cost` first for most drilling/cost teams).

## Install command

```bash
# Workspace-scoped (admin, visible to all users)
databricks workspace import-dir \
  wellview/ \
  /Workspace/.assistant/skills/ \
  --overwrite

# Or user-scoped (just for you)
databricks workspace import-dir \
  wellview/ \
  /Workspace/Users/<your-email>/.assistant/skills/ \
  --overwrite
```

After installing, open a **new** Genie Code chat — skills load when their description
matches your prompt.

## What's intentionally out of scope

- **The Peloton→Databricks connector.** Assumes WellView data is already landed (via
  Peloton ETL on Snowflake or the Platform API). `wellview-data-engineering` covers
  *modeling* the landed data, not replication.
- **ProdView / production-volume analytics.** WellView's sibling product; a separate
  family if needed.
- **Re-deriving an operator's certified cost or engineering methodology.** Shipped
  formulas (cost/ft, NPT %, ROP) are standard published defaults; operators with a
  certified in-house variant register it as a separate UDF.
- **Live Peloton MCP server.** Static skill content only.

## References

- Peloton WellView: [product](https://www.peloton.com/products/well-data-lifecycle/wellview/data-analysis/) · [integration](https://www.peloton.com/products/well-data-lifecycle/wellview/integration) · [Peloton platform](https://www.peloton.com/products)
- Drilling metrics: SPE/IADC 128288-MS (CPF/FPD/MSE) · Bourgoyne et al., *Applied Drilling Engineering* (cost per foot) · [AAPG wiki — ROP](https://wiki.aapg.org/Rate_of_penetration)
- [Databricks Genie Code skills](https://docs.databricks.com/aws/en/genie-code/skills) · [Genie best practices](https://docs.databricks.com/aws/en/genie/best-practices) · [Trusted Assets](https://docs.databricks.com/aws/en/genie/trusted-assets)
- [Agent Skills standard](https://agentskills.io/)
- **Schema reconstruction & confidence notes:** see the family's research dossier
  (`wellview-data-model-research.md`) — the source for the canonical model, the blind
  review, and the validation punch-list `wellview-setup` closes.
