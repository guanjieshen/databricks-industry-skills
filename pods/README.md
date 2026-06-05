# PODS (Pipeline Open Data Standard) — Skill Family

A library of Genie Code skills for working with **PODS-modeled pipeline data** in Databricks. Once installed, **Genie Code behaves as though the customer has a PODS data-model specialist and an integrity engineer on call** — it knows the linear-referencing model, the route/measure math that Genie gets wrong unaided, the canonical integrity formulas (ERF, B31G/RSTRENG, %SMYS), and the standard patterns for taking PODS data through pipelines, Genie Spaces, dashboards, and ML.

Primary industry served: **midstream oil & gas** (gas transmission, hazardous-liquid pipelines, gathering). PODS is the vendor-neutral pipeline data model maintained by the [PODS Association](https://pods.org/) since 1998; PODS 7 is the current generation, built on an M-aware centerline / linear-referencing model with six optional modules.

The skill format follows the [Agent Skills](https://agentskills.io/) standard.

## Why this family exists (and why linear referencing is the crux)

Out of the box, Genie Code guesses at PODS tables — and the scariest failures are **invisible** to the end user. A pipeline integrity engineer has deep ILI/NDE/integrity expertise but is usually **not** a PODS-data-model expert and **not** fluent in prompting. They ask terse, jargon-heavy questions ("show me the worst anomalies on line 4", "interacting threats near the river crossing") and trust the table that comes back.

Unaided, Genie typically:
- Ranks "worst" anomalies by **raw depth** instead of **ERF** (failure-pressure risk) — backwards for integrity.
- Joins ILI stationing (often **feet**) directly to centerline/HCA measures (often **meters**) — a silent ~3.28× unit error the engineer can't see.
- Mixes anomalies across **ILI run vintages** and **tool vendors** whose depth sizing isn't comparable.
- Does naive distance filtering instead of **route+measure dynamic segmentation** for "what's near station X / between stations".

These skills fix exactly those failure modes. The single highest-value piece is **`pods-linear-referencing`** — the M-aware centerline and dynamic-segmentation model is the universal substrate every other skill depends on, and it's where unaided Genie fails hardest.

## Personas served

The integrity engineer is the primary persona. None of these personas are PODS-data-model specialists.

| Persona | What they do | Skills they use most |
|---|---|---|
| **Pipeline integrity engineer** | ILI anomaly analysis, dig programs, %SMYS / B31G, reassessment | `overview`, `setup`, `linear-referencing`, `ili-integrity` |
| **Integrity / GIS analyst** | HCA overlap, "what's between stations", consequence | `overview`, `setup`, `linear-referencing`, `consequence-hca` |
| **Compliance / regulatory** | PHMSA reporting, assessment intervals, records | `overview`, `setup`, `phmsa-reporting`, `tvc-records` |
| **Corrosion / CP technician** | Cathodic protection surveys, coverage gaps | `overview`, `setup`, `cathodic-protection` |
| **D&A / platform engineer** | Building pipelines, Genie Spaces, dashboards on PODS | `overview`, `setup`, `data-engineering`, plus a module |

## Architecture: foundation + module

### Foundation tier (always-loaded for PODS questions)

| Skill | Single focused task |
|---|---|
| [`pods-overview`](./pods-overview/) | Orient Genie on the PODS 7 model — pipeline hierarchy, the LRS networks (`CONTINUOUS_MEAS_NETWORK`, `ENGINEERING_STATION_NETWORK`), the six modules, and the universal gotchas (units, run vintage, route vs measure) |
| [`pods-setup`](./pods-setup/) | Bootstrap a customer's workspace — introspect their PODS-ish schema, generate a glossary skill mapping their physical columns to canonical PODS concepts, register UC comments |
| [`pods-linear-referencing`](./pods-linear-referencing/) | **The keystone.** Dynamic segmentation / route-measure overlay, station↔measure conversion, "assets between stations", locate-along-route — the LRS math Genie cannot do correctly unaided |
| [`pods-data-engineering`](./pods-data-engineering/) | Model raw pipeline feeds → conformed PODS centerline / event tables (Bronze→Silver→Gold, Lakeflow SDP) |
| [`pods-data-quality`](./pods-data-quality/) | Diagnose LRS data-quality issues — non-monotonic measures, route gaps/overlaps, orphan events, unit inconsistency |

> **Why 5 foundation skills, not 4.** The family template ships 4 (overview/setup/data-engineering/data-quality). PODS adds `pods-linear-referencing` as a 5th foundation skill because the M-aware centerline + dynamic segmentation is the *universal substrate every module depends on* — it is too load-bearing to bury in `overview`'s gotchas, and it carries real executable content (conversion + overlay UDFs).

### Module tier (loaded based on the domain in the question)

| Skill | Domain | Status |
|---|---|---|
| [`pods-ili-integrity`](./pods-ili-integrity/) | Inline-inspection anomaly analysis — ERF ranking, B31G/RSTRENG remaining strength, run comparison + vendor-comparability, dig candidates | **shipped (flagship)** |
| `pods-consequence-hca` | High-Consequence-Area overlap, interacting threats, consequence-of-failure | fast-follow |
| `pods-cathodic-protection` | CP survey readings, coverage gaps, −850 mV criteria along route | fast-follow |
| `pods-phmsa-reporting` | Assessment intervals, repair criteria, reassessment scheduling (49 CFR 192/195) — high value, high liability | fast-follow |
| `pods-tvc-records` | Traceable / Verifiable / Complete material-records completeness | fast-follow |
| [`pods-genie-space`](./pods-genie-space/) | Scaffold/curate a Genie Space over PODS data — assembles instructions, units, certified example SQL, synonyms, and Trusted Asset functions (ERF, remaining strength, overlap), then benchmarks accuracy | **shipped** |

Discovery + quality test cases live in [`evals/`](./evals/) (`query → expected_behavior`).

## Composes with the Maximo family

PODS and [Maximo](../maximo/) are two complementary lenses on the same integrity engineer:

- **`maximo-integrity`** = the **EAM / work-order** lens — inspections as work orders, corrosion from `METERREADING` thickness gauging, regulatory PM compliance.
- **`pods-*`** = the **spatial / GIS / route** lens — ILI runs along an M-aware centerline, anomalies by station, HCA overlap, dynamic segmentation.

An operator running both can ask Genie *"corrosion rate on vessel X"* (Maximo) **and** *"interacting threats near MP 42 on the latest ILI run"* (PODS).

## Install order (recommended)

1. Install `pods-overview` first — it orients Genie for everything else.
2. Run `pods-setup` once per customer — it introspects the operator's PODS-ish schema and generates the workspace glossary skill the other skills reference. **This is the load-bearing precondition** — without an accurate mapping, the analytical skills produce confident, invisible errors.
3. Install `pods-linear-referencing` — every analytical question depends on it.
4. Install whichever module skills match the customer's primary use cases (`pods-ili-integrity` first for most midstream operators).

## Install

**Recommended:** run the repo's [`install_industry_skills.py`](../install_industry_skills.py)
notebook and pick `FAMILY = pods` — it installs all PODS skills straight from GitHub, no clone needed.

**Or install via CLI:**

```bash
# Workspace-scoped (admin, visible to all users)
databricks workspace import-dir \
  pods/ \
  /Workspace/.assistant/skills/ \
  --overwrite

# Or user-scoped (just for you)
databricks workspace import-dir \
  pods/ \
  /Workspace/Users/<your-email>/.assistant/skills/ \
  --overwrite
```

After installing, open a **new** Genie Code chat — skills load when their description matches your prompt.

## What's intentionally out of scope

- **Ingestion from Esri / GIS** (ArcGIS Pipeline Referencing exports, GeoDatabase replication, vendor ILI file formats). Assumes pipeline data is already landed in Databricks. `pods-data-engineering` covers modeling, not connectors.
- **Fitness-for-service / pressure-derate determinations.** The skills screen and rank (ERF, predicted failure pressure) but never declare a segment "safe" — that needs current operating pressure, engineering judgment, and a qualified engineer.
- **Re-implementing an operator's certified integrity methodology.** Shipped formulas (B31G/RSTRENG/ERF) are the standard published formulations as defensible defaults; operators with a certified in-house variant should register it as a separate UDF.
- **Live Esri / GIS MCP server.** Static skill content only.

## References

- [PODS Association](https://pods.org/) · [PODS data models](https://pods.org/data-models/pods-data-models/) · [PODS 7 conceptual poster (PDF)](https://pods.org/wp-content/uploads/2024/11/PODS7-Poster.pdf)
- [Esri ArcGIS Pipeline Referencing — LRS data model](https://pro.arcgis.com/en/pro-app/latest/help/production/location-referencing-pipelines/alrs-data-model.htm)
- [PHMSA hazardous-liquid integrity management](https://www.phmsa.dot.gov/pipeline/hazardous-liquid-integrity-management/hl-im-fact-sheet) · [49 CFR 195.452](https://www.law.cornell.edu/cfr/text/49/195.452)
- [Databricks Genie Code skills](https://docs.databricks.com/aws/en/genie-code/skills) · [Genie best practices](https://docs.databricks.com/aws/en/genie/best-practices)
- [Databricks Spatial SQL (ST_ functions)](https://docs.databricks.com/aws/en/sql/language-manual/sql-ref-st-geospatial-functions) · [H3 functions](https://docs.databricks.com/aws/en/sql/language-manual/sql-ref-h3-geospatial-functions)
- [Agent Skills standard](https://agentskills.io/)
