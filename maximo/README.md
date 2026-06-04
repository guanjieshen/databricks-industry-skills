# IBM Maximo — Skill Family

A library of Genie Code skills for working with IBM Maximo data in Databricks. Once installed, **Genie Code behaves as though the customer has a Maximo IT implementation specialist on call** — it knows the data model, the error-prone joins, the canonical metric formulas, and the standard patterns for taking Maximo data through pipelines, Genie Spaces, dashboards, and ML features.

Primary industry served: **oil & gas** (PLUSG industry-solution extensions, regulatory inspection workflows, HSE/permit-to-work). The core skills generalize to other Maximo industries (utilities, mining, manufacturing, federal) but the O&G-specific content (`maximo-integrity`, `maximo-hse`) is opt-in.

## Personas served

Neither persona is a Maximo specialist.

| Persona | What they do | Skills they use most |
|---|---|---|
| **Maintenance planner / analyst** | Operational queries — backlog, scheduling, completion, labor hours | `overview`, `setup`, `data-quality`, `work-orders` |
| **Reliability engineer** | Reliability metrics, failure-mode analysis | `overview`, `setup`, `data-quality`, `work-orders`, `reliability` |
| **Integrity engineer** | Pressure-vessel inspections, corrosion trending, RBI, regulatory compliance | `overview`, `setup`, `data-quality`, `integrity`, `reliability` |
| **HSE manager** | Permits, incidents, investigations, regulatory reporting | `overview`, `setup`, `data-quality`, `hse` |
| **D&A / platform engineer** | Building pipelines, Genie Spaces, dashboards, ML on Maximo | `overview`, `setup`, `data-engineering`, plus whichever module |
| **Data scientist** | PdM models on Maximo + sensor data | `overview`, `setup`, `reliability`, plus `maximo-pdm` (v3) |

## Architecture: foundation + module

### Foundation tier (always-loaded for Maximo questions)

| Skill | Single focused task |
|---|---|
| [`maximo-overview`](./maximo-overview/) | Orient Genie on Maximo's data model + universal gotchas (SITEID composite keys, WOCLASS filter, WOSTATUS history split, ISTASK dedup) |
| [`maximo-setup`](./maximo-setup/) | Bootstrap a customer's workspace glossary + register UC table/column comments |
| [`maximo-data-quality`](./maximo-data-quality/) | Diagnose Maximo data quality issues |
| [`maximo-data-engineering`](./maximo-data-engineering/) | Model Maximo Bronze → Silver/Gold (Lakeflow SDP) |

### Module tier (loaded based on the domain in the question)

| Skill | Domain |
|---|---|
| [`maximo-work-orders`](./maximo-work-orders/) | Work-order operations — backlog, status history, labor analytics, completion |
| [`maximo-reliability`](./maximo-reliability/) | MTBF / MTTR / PM compliance / failure-mode analysis |
| [`maximo-integrity`](./maximo-integrity/) | Corrosion trending, regulatory inspections, RBI, inspection-tied incidents (O&G-heavy) |
| [`maximo-hse`](./maximo-hse/) | Permits, incidents, investigations, MOC (O&G-heavy) |

### v3 candidates (after v2 proves out)

- `maximo-inventory` — INVENTORY / PO / INVOICE / COMPANIES analytics
- `maximo-pdm` — PdM ML patterns joining Maximo asset hierarchy + WO history with sensor / historian data
- `maximo-work-orders-genie-space` — focused workflow for setting up a Genie Space over WO data
- `maximo-work-orders-dashboard` — focused workflow for building an AI/BI dashboard over WO data

## Install order (recommended)

0. Install [`_common/data-exploration`](../_common/data-exploration/) — universal data-discovery patterns (`databricks experimental aitools tools query` / `discover-schema`). Pairs naturally with Maximo skills: `_common/data-exploration` provides the *mechanics* of exploring tables; the Maximo skills provide the *domain knowledge* about which tables are which MBOs.
1. Install `maximo-overview` next — it orients Genie for everything else in the Maximo family.
2. Run `maximo-setup` once per customer — it creates the workspace-tier glossary skill that the other skills reference.
3. Install whichever module skills match the customer's primary use cases.

## Install command

```bash
# Workspace-scoped (admin, visible to all users)
databricks workspace import-dir \
  maximo/ \
  /Workspace/.assistant/skills/ \
  --overwrite

# Or user-scoped (just for you)
databricks workspace import-dir \
  maximo/ \
  /Workspace/Users/<your-email>/.assistant/skills/ \
  --overwrite
```

After installing, open a **new** Genie Code chat — skills load when their description matches your prompt.

## What's intentionally out of scope

- **Ingestion** (MAS Kafka, OSLC, JDBC/CDC, partner connectors). Assumes Maximo data is already landed in Databricks.
- **Other CMMS / EAM systems** (SAP PM, Oracle EAM, Avantis). Separate families — see `_template/`.
- **Live MCP server for Maximo.** Static skill content only.
- **Custom MBO extensions** beyond what the workspace glossary captures.

## References

- [IBM Maximo Manage docs](https://www.ibm.com/docs/en/masv-and-l/maximo-manage/)
- [IBM Maximo Oil & Gas docs](https://www.ibm.com/docs/en/mfo-and-g/)
- [Databricks Genie best practices](https://docs.databricks.com/aws/en/genie/best-practices)
- [Agent Skills standard](https://agentskills.io/)
