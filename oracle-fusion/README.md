# Oracle Fusion Cloud ERP — Skill Family

A library of [Genie Code skills](https://docs.databricks.com/aws/en/genie-code/skills) for working with **Oracle Fusion Cloud ERP** data (Financials + Supply Chain) in Databricks. Once installed, **Genie Code behaves as though the customer has an Oracle Fusion ERP implementation specialist on call** — it knows the ledger / legal-entity / business-unit org model, the chart-of-accounts and subledger-to-GL mechanics, the joins and currency/period traps that silently produce wrong financials, the canonical metric definitions (trial balance, net activity, spend), and the standard patterns for taking Fusion data through pipelines, Genie Agents, dashboards, and ML.

v1 covers **Finance + SCM**: general ledger and procurement, on the shared accounting foundation. The format follows the [Agent Skills](https://agentskills.io/) standard.

## How Fusion data lands (SaaS / BICC / FDI — landing-agnostic)

Fusion Cloud is **SaaS — there is no direct JDBC/ODBC to the transaction tables.** Analytics data leaves Fusion Cloud one of a few ways, and **which one the customer uses changes the physical table/column names, not the meaning:**

| Path | What lands | Naming |
|---|---|---|
| **BICC** (BI Cloud Connector) — most common Databricks source | Bulk extracts of **Public View Objects (PVOs)** to object storage → Delta | PVO names like `JournalSourceExtractPVO`, `RequisitionHeaderExtractPVO` |
| **Fusion Data Intelligence (FDI/FAW)** | A prebuilt **star schema** (facts/dims, prebuilt metrics) | Subject areas like `Financials - GL Balance Sheet` |
| **BI Publisher / OTBI** | Templated/real-time reporting extracts | Reporting subject-area PVOs |

**The landing-agnostic rule (central to this family):** Fusion's underlying physical tables keep the E-Business Suite names almost verbatim (`GL_JE_HEADERS`, `GL_BALANCES`, `GL_CODE_COMBINATIONS`, `PO_HEADERS_ALL`, `XLA_AE_LINES`). The family's `schema.md` files describe that **canonical model**; what the customer actually receives is PVOs or FDI artifacts with different names. So **module skills reference canonical entities/columns; the physical→canonical mapping for THIS customer lives in the `<customer>-oracle-fusion-glossary` produced by `oracle-fusion-setup`.** Never hard-code a physical table name without checking the glossary — and never promise raw-table access (it's SaaS). The family is **ingestion-agnostic**: it assumes the extracts are already landing and describes the canonical model on top.

## Personas served

None of these personas is a Fusion data-model specialist; the skills close that gap.

| Persona | What they do | Skills they use most |
|---|---|---|
| **Controller / GL accountant** | Trial balance, account analysis, journal review, period close, posted actuals | `overview`, `setup`, `ledger-coa`, `general-ledger`, `data-quality` |
| **FP&A analyst** | Actual-vs-budget variance, net activity by cost center, financial trending | `overview`, `setup`, `ledger-coa`, `general-ledger` |
| **Procurement / sourcing analyst** | Supplier spend, open-PO backlog, PO cycle time, blanket-agreement usage, 3-way-match exceptions | `overview`, `setup`, `ledger-coa`, `procurement` |
| **Supply chain analyst** | Receipts, requisition-to-PO flow, spend by category / BU | `overview`, `setup`, `procurement` |
| **AP / AR analyst** *(future)* | Invoice aging, payment runs, receivables, DSO | `overview`, `setup`, `ledger-coa` + `payables` / `receivables` (planned) |
| **D&A / platform engineer** | Building pipelines, Genie Agents, dashboards, ML on Fusion | `overview`, `setup`, `data-engineering`, `genie-agent`, plus a module |

## Architecture: foundation + module

### Foundation tier (always-loaded for Fusion questions)

| Skill | Single focused task |
|---|---|
| [`oracle-fusion-overview`](./oracle-fusion-overview/) | Orient Genie on the Fusion data model — the Ledger / Legal-Entity / Business-Unit org model, the subledger→GL bridge, the module map, the landing-agnostic rule, and the universal gotchas (multi-org `_ALL` scoping, CCID segments, accounting vs transaction date, period open/close, entered vs accounted currency, GL↔XLA double-count, posted-vs-unposted, BICC deletes-not-captured) |
| [`oracle-fusion-setup`](./oracle-fusion-setup/) | One-time bootstrap — profile the customer's Fusion data, interview on COA segment meaning / ledgers / BUs / landing pattern, generate the `<customer>-oracle-fusion-glossary` (incl. physical→canonical mapping + segment→meaning map), register UC comments (preview-then-apply) |
| [`oracle-fusion-data-engineering`](./oracle-fusion-data-engineering/) | Model BICC/FDI extracts → Silver/Gold (incremental, `_ALL`/org handling, deletes-not-captured); defers SDP mechanics to `databricks-spark-declarative-pipelines` |
| [`oracle-fusion-data-quality`](./oracle-fusion-data-quality/) | "This number looks wrong" diagnostics — GL↔subledger drift, unbalanced journals, currency gaps, extract gaps |
| [`oracle-fusion-ledger-coa`](./oracle-fusion-ledger-coa/) | **KEYSTONE.** The chart-of-accounts / ledger / LE / BU / period / currency / XLA model every financial question joins to. Ships Trusted UDFs for segment resolution, currency conversion, and period mapping, plus the `v_code_combination` / `v_gl_period` / `v_ledger_org` views |

> **Why a 5th foundation skill (the keystone).** The family template ships 4 foundation skills (overview/setup/data-engineering/data-quality). Oracle Fusion adds `oracle-fusion-ledger-coa` as a 5th — exactly like PODS adds `pods-linear-referencing`. The chart-of-accounts / ledger / period / currency / subledger-bridge model is the **universal substrate every financial module depends on**: GL, procurement spend-by-account, and the accounting side of every SCM and future AP/AR flow all join to a CCID, a ledger, a period, and a currency. It is too load-bearing to bury in `overview`'s gotchas, and it carries real executable content (segment-decode, currency-conversion, and period-mapping UDFs + pre-joined views). Module skills *compose* it rather than restating accounting mechanics.

### Module tier (loaded based on the domain in the question)

| Skill | Domain | Status |
|---|---|---|
| [`oracle-fusion-general-ledger`](./oracle-fusion-general-ledger/) | Journals, balances, trial balance, account analysis, actual-vs-budget. Ships the `gl_metrics` metric view + `trial_balance`/`account_balance`/`journal_count` Trusted UDFs. Hard-depends on the keystone | **shipped** |
| [`oracle-fusion-procurement`](./oracle-fusion-procurement/) | Requisitions, POs, agreements, receipts, supplier spend, PO cycle time, 3-way-match exceptions. Hands invoice/payment to a future `oracle-fusion-payables` (P2P boundary). Composes the keystone for spend-by-account | **shipped** |
| [`oracle-fusion-genie-agent`](./oracle-fusion-genie-agent/) | Scaffold/curate a **Genie Agent** (curated text-to-SQL data product, formerly "Genie Space") over Fusion data — curates UC objects, metric views, Trusted UDFs, semantic descriptions, synonyms, and certified example questions; then benchmarks accuracy. Defers Agent create/export mechanics to `databricks-genie` | **shipped** |

Discovery + quality test cases live in [`evals/`](./evals/) (`query → expected_behavior`).

### Fast-follow modules (planned, not yet built)

Gated on customer scope; each composes the keystone:

- `oracle-fusion-payables` — `AP_INVOICES_ALL`, invoice aging, payment runs, P2P close-out
- `oracle-fusion-receivables` — `RA_CUSTOMER_TRX_ALL`, DSO, collections
- `oracle-fusion-inventory` — on-hand, transactions, valuation
- `oracle-fusion-order-management` — sales orders, fulfillment
- `oracle-fusion-cost-management` — inventory/COGS costing
- `oracle-fusion-fixed-assets` — asset register, depreciation
- `oracle-fusion-subledger-recon` — XLA↔GL reconciliation across subledgers
- `oracle-fusion-expenses` — expense reports, T&E spend

## Install order (recommended)

1. Install the platform skill prerequisites (see below).
2. Install `oracle-fusion-overview` first — it orients Genie for everything else in the family.
3. Run `oracle-fusion-setup` once per customer — it profiles the data, interviews on COA/ledger/BU/landing pattern, generates the `<customer>-oracle-fusion-glossary` (the load-bearing physical→canonical + segment→meaning mapping), and registers UC comments. **Without an accurate segment map, the analytical skills produce confident, invisible errors.**
4. Install `oracle-fusion-ledger-coa` (the keystone) — every financial question depends on it.
5. Install whichever module skills match the customer's scope (`oracle-fusion-general-ledger`, `oracle-fusion-procurement`), and `oracle-fusion-genie-agent` to curate a data product.

## Install

**Recommended:** run the repo's [`install_industry_skills.py`](../install_industry_skills.py) notebook and pick `FAMILY = oracle-fusion` — it installs all Oracle Fusion skills straight from GitHub, no clone needed.

**Or install via CLI:**

```bash
# Workspace-scoped (admin, visible to all users)
databricks workspace import-dir \
  oracle-fusion/ \
  /Workspace/.assistant/skills/ \
  --overwrite

# Or user-scoped (just for you)
databricks workspace import-dir \
  oracle-fusion/ \
  /Workspace/Users/<your-email>/.assistant/skills/ \
  --overwrite
```

After installing, open a **new** Genie Code chat in Agent mode — skills load when their description matches your prompt.

## Required platform skills

This family references the following platform skills at [`databricks-solutions/ai-dev-kit/databricks-skills/`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills). Install them alongside:

- [`databricks-genie`](https://github.com/databricks-solutions/ai-dev-kit/blob/main/databricks-skills/databricks-genie/SKILL.md) — Genie Agent create / export / import / API mechanics (for `-genie-agent`)
- [`databricks-spark-declarative-pipelines`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-spark-declarative-pipelines) — Lakeflow pipelines (for `-data-engineering`)
- [`databricks-unity-catalog`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-unity-catalog) — UC mechanics: comments, grants, lineage (for `-setup`)
- [`databricks-metric-views`](https://github.com/databricks-solutions/ai-dev-kit/tree/main/databricks-skills/databricks-metric-views) — semantic metric layers (for the GL / procurement metric views and `-genie-agent`)

## Composes with other families

The Fusion family is one lens on an enterprise's data estate; it composes with other source families through Unity Catalog. An organization running Fusion ERP for finance/procurement and a separate EAM for operations can ask Genie about both — e.g. **maintenance spend** in [Maximo](../maximo/) (`maximo-maintenance-cost`) reconciled against **GL actuals** in Fusion (`oracle-fusion-general-ledger`), or Fusion **procurement spend** against Maximo **PO receipts**. Each family owns its own canonical model, gotchas, and glossary; UC is the shared catalog layer.

## What's intentionally out of scope

- **Ingestion connectors** (BICC extract scheduling, FDI/FAW provisioning, OTBI/BI Publisher setup). Assumes Fusion extracts are already landing in Databricks; `-data-engineering` covers modeling, not connectors.
- **Direct transaction-table access.** Fusion Cloud is SaaS — there is no JDBC/ODBC to the live tables; only BICC/FDI extracts.
- **Other ERPs** (SAP, NetSuite, Oracle EBS on-prem). Separate families — see `_template/`.
- **Live MCP server for Fusion.** Static skill content only.

## Contributing

See [`_authoring/authoring-industry-skills/`](../_authoring/authoring-industry-skills/SKILL.md) for the contributor standard before adding new skills (e.g. the fast-follow modules).

## References

- [Oracle Fusion Financials data model (OEDMF)](https://docs.oracle.com/en/cloud/saas/financials/25c/oedmf/)
- [Oracle Fusion Procurement data model (OEDMP)](https://docs.oracle.com/en/cloud/saas/procurement/25c/oedmp/)
- [BICC (BI Cloud Connector)](https://docs.oracle.com/en/cloud/saas/applications-common/bicc/) · [Fusion Data Intelligence](https://docs.oracle.com/en/cloud/saas/analytics/)
- [Databricks Genie Code skills](https://docs.databricks.com/aws/en/genie-code/skills) · [Genie best practices](https://docs.databricks.com/aws/en/genie/best-practices)
- [Agent Skills standard](https://agentskills.io/)
