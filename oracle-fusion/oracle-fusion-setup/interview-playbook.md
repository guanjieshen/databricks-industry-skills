# Oracle Fusion Setup — Interview (profile-first)

Run **after** `scripts/introspect_schema.py` (or the Path B SQL profiler) has produced
`draft_profile.json`. Conduct this like a Fusion implementation consultant **who can
already see the data**: the profile answers "what" (which tables are populated, which
`SEGMENT1..30` carry distinct values, the ledger/currency/BU/BSV lists, candidate custom
columns). Your job is to capture what data **can't** prove — **segment MEANING, the
landing-pattern physical→canonical mapping, intent, scope, and KPI definitions** — and to
confirm/correct the profiler's proposals.

**Ground every question in the profile.** Don't ask "what are your segments?" — say "your
data uses SEGMENT1, SEGMENT3, SEGMENT5; walk me through what each means." Ask in **batches
of 2–3**, not all at once. For each answer capture: the business term, the schema mapping
(table.column / value list / canonical entity), and any "approximate / needs validation" flag.

## Contents
- Batch 0 — Modules in use, landing pattern & industry (scopes everything)
- Batch 1 — Ledgers & currencies
- Batch 2 — COA structure: which SEGMENT means what + value-set meanings
- Batch 3 — Legal entities & balancing segment values
- Batch 4 — Business units
- Batch 5 — Period calendar
- Batch 6 — Landing-pattern physical names per canonical entity (the mapping)
- Batch 7 — Custom / DFF columns
- Closing — tribal knowledge & KPIs
- How to record answers (`answers.json` shape + profiler mapping)

---

## Batch 0 — Modules in use, landing pattern & industry

Confirm `draft_profile.json → usage_profile` and `landing_pattern`. **This batch scopes the rest.**

1. **"Which Fusion modules do you actually run *in Fusion* vs. another system of record?"** The profile shows `{GL + procurement tables populated; AP/AR empty}`. Empty/sparse canonical tables usually mean the process lives elsewhere (legacy ERP, another cloud).
2. **"How does your Fusion data land in the lakehouse — BICC PVO extracts, Fusion Data Intelligence (FDI/FAW), BI Publisher/OTBI, or base-table mirrors?"** The object naming in the profile hints at this; confirm it. **This decides the physical→canonical mapping (Batch 6) and the currency-basis columns.** If BICC: which extraction schedule, and do you run a Deleted-Record extract (or periodic full reload), or incremental-only?
3. **"What industry / sub-segment are you, and who consumes this data?"** Scopes which value-set meanings and KPIs matter.

→ records to `usage_profile` + `landing_pattern`.

## Batch 1 — Ledgers & currencies

Ground in `ledgers` (distinct `LEDGER_ID` / names) and `currencies`.

4. **"Your data has these ledgers: {list}. Which are in scope? Is this a single primary ledger or a consolidated ledger set? Any secondary/reporting ledgers?"** → `ledgers`
5. **"What's the ledger (functional) currency per ledger, and do you report in entered (document), accounted (ledger), or — under FDI — analytics currency? Are there translated balances?"** Totals differ by basis; capture the default basis. → `currency_basis`

## Batch 2 — COA structure: which SEGMENT means what

Ground in `coa.segments_with_values` (which `SEGMENT1..30` carry distinct values + cardinality). **This is the single most-reused fact in the whole family.**

6. **"Your COA uses these segments: {SEGMENT1, SEGMENT3, SEGMENT5, …}. Walk me through what each means — which is company, cost center, natural account, intercompany, product, future-use?"** Never assume positions. → `segment_meaning`
7. **"Decode the value sets: for the natural-account segment, which value ranges mean revenue / COGS / opex / asset / liability? For cost center, what do the values group to?"** Fusion decodes segment values to names via `FND_FLEX_VALUES_VL`; capture the meaningful ranges/groupings the customer reports on. → `value_sets`
8. **"Which segment is the *balancing segment*?"** Its values map to legal entities (Batch 3). → `balancing_segment`

## Batch 3 — Legal entities & balancing segment values

Ground in `coa.balancing_segment_values` (distinct BSVs).

9. **"Your balancing-segment values are {list}. How do these map to legal entities? Any that are eliminations, intercompany, or inactive?"** Consolidation and "by legal entity" reporting key off the BSV→LE assignment, not a raw LE column. → `legal_entities`

## Batch 4 — Business units

Ground in `org.business_units` (distinct BU IDs on `_ALL` tables, e.g. `PRC_BU_ID`).

10. **"Your `_ALL` tables span these business units: {list}. Which are real vs test/decommissioned? How do they roll up to regions/divisions? (Fusion BU ≈ EBS Operating Unit.)"** Summing `_ALL` without a BU scope mixes orgs. → `business_units`

## Batch 5 — Period calendar

Ground in `periods` (`GL_PERIODS` rows + period statuses).

11. **"What's your accounting calendar — monthly, 4-4-5, 13-period? Any adjustment periods (period 13)? What's the earliest period with trustworthy data (post-cutover)?"** → `period_calendar`
12. **"How do you typically scope 'as-of' — by `PERIOD_NAME`, or open/closed status? Which periods are currently open?"** Periods sort by effective period number, never alphabetically. → `period_calendar.notes`

## Batch 6 — Landing-pattern physical names per canonical entity (THE MAPPING)

Ground in `landing_pattern` (Batch 0) + the profiled object list. **This produces the physical→canonical mapping — the central deliverable.**

13. **"For each canonical Fusion entity we'll query, what's your actual object name and the key column renames?"** Walk the entities in scope. For BICC: PVO names (e.g. `JournalSourceExtractPVO` → `GL_JE_HEADERS`). For FDI: subject-area fact/dim names. For base mirrors: usually verbatim EBS names. → `physical_canonical_map`

| Canonical entity | Ask for the customer's physical object + key column renames |
|---|---|
| `GL_JE_HEADERS` / `GL_JE_LINES` | journal header/line PVO or fact |
| `GL_BALANCES` | balances PVO or FDI balance fact |
| `GL_CODE_COMBINATIONS` | code-combination PVO or COA dim |
| `GL_PERIODS` / `GL_PERIOD_STATUSES` | period + status objects |
| `GL_DAILY_RATES` | daily-rates object |
| `XLA_AE_HEADERS` / `XLA_AE_LINES` | subledger-accounting objects (if in scope) |
| `PO_HEADERS_ALL` → `PO_LINES_ALL` → `PO_DISTRIBUTIONS_ALL` | PO header/line/distribution PVOs |
| `POZ_SUPPLIERS` + supplier sites | supplier-master objects |

14. **"Does the extract capture hard deletes?"** BICC incremental (last-update-date) extracts catch INSERT/UPDATE only — deletes need a separate Deleted-Record extract or periodic full reload. Record it; it's a `oracle-fusion-data-quality` concern (Bronze drift). → `physical_canonical_map.deletes_captured`

## Batch 7 — Custom / DFF columns

Ground in `custom_columns` (detected `ATTRIBUTE1..n`, `*_DFF`, non-base columns) + `high_null_columns`.

15. **"I detected these candidate custom/DFF columns: {list}. What does each store (a descriptive flexfield segment, a customer extension)? Which are mandatory in your process?"** → `custom_columns`
16. **"Column {X} is {high_null}% null — deprecated, or only used for a subset?"**

## Closing — tribal knowledge & KPIs

17. **"How do you define your headline financial metrics today (e.g. revenue, spend, gross margin) — which segment-value ranges, which currency basis, posted-only?"** Record the stated definition in `kpis`; certified formulas live with `oracle-fusion-general-ledger` / `oracle-fusion-procurement`.
18. **"Any business term or quirk that's caused confusion in past Fusion data work? Anything that's burned you?"** → `tribal_knowledge`
19. **"Show me one number you currently trust — a report you run — so we reconcile our queries to it."** The fastest way to earn trust.

---

## How to record answers

The profiler seeds most of this; you confirm. Save as `answers.json` (consumed by the
glossary generation step). Shape:

```json
{
  "customer": "acme",
  "usage_profile": {
    "modules_in_use": ["general_ledger", "procurement"],
    "modules_elsewhere": {"payables": "legacy ERP until 2025", "receivables": "Salesforce billing"},
    "industry": "Discrete manufacturing"
  },
  "landing_pattern": {
    "type": "BICC PVO",
    "schedule": "nightly incremental + monthly full reload",
    "deletes_captured": "no Deleted-Record extract; monthly full reload only"
  },
  "ledgers": { "US Primary (USD)": 1, "EU Primary (EUR)": 2 },
  "currency_basis": "accounted (ledger) currency default; entered retained per document",
  "segment_meaning": {
    "SEGMENT1": "company / balancing segment",
    "SEGMENT3": "cost center",
    "SEGMENT5": "natural account",
    "SEGMENT7": "product",
    "SEGMENT9": "future use (always 00000)"
  },
  "balancing_segment": "SEGMENT1",
  "value_sets": {
    "natural_account": {"revenue": "40000-49999", "COGS": "50000-59999", "opex": "60000-69999"},
    "cost_center": "values 1000-1999 = manufacturing, 2000-2999 = SG&A"
  },
  "legal_entities": { "Acme US Inc (BSV 01)": "01", "Acme GmbH (BSV 20)": "20", "Eliminations": "99" },
  "business_units": { "US Procurement BU": 101, "EU Procurement BU": 201, "TEST (exclude)": 999 },
  "period_calendar": {
    "type": "monthly + adjustment period 13",
    "earliest_trustworthy": "JAN-2023 (cutover)",
    "notes": ["Sort by PERIOD_YEAR*10000 + PERIOD_NUM, never PERIOD_NAME"]
  },
  "physical_canonical_map": {
    "GL_JE_HEADERS": {"physical": "bicc.JournalSourceExtractPVO_hdr", "renames": {"JeHeaderId": "JE_HEADER_ID"}},
    "GL_CODE_COMBINATIONS": {"physical": "bicc.GlCodeCombinationExtractPVO", "renames": {}},
    "PO_HEADERS_ALL": {"physical": "bicc.PurchaseOrderHeaderExtractPVO", "renames": {"PoHeaderId": "PO_HEADER_ID"}}
  },
  "custom_columns": {
    "GL_JE_HEADERS.ATTRIBUTE1": "Source feeder-system batch id",
    "PO_HEADERS_ALL.ATTRIBUTE5": "Internal project code (DFF)"
  },
  "kpis": ["Net revenue = posted accounted CR-DR on natural-account 40000-49999, ledger currency"],
  "tribal_knowledge": ["'Company 01' colloquially means BSV 01 = Acme US Inc, not LEDGER_ID 1"],
  "followups": [
    {"question": "Meaning of SEGMENT7 values 9xxx", "owner": "GL accounting lead"},
    {"question": "Is BU 999 truly test or a live BU?", "owner": "Procurement systems"}
  ]
}
```

> Build `followups` from every item flagged `_unknown_ — confirm with <role>`: each becomes a
> `{question, owner}` row. It renders as the glossary's follow-up-contacts table and is the
> worklist a **re-run** walks through. Use the **physical column casing** from the data in all
> mappings so generated SQL matches.

### `draft_profile.json` → `answers.json` mapping (what the profiler pre-fills)
| Profiler field | Interview confirms → answers.json key |
|---|---|
| `usage_profile` (populated modules) | Batch 0 → `usage_profile` |
| object naming (PVO/FDI/base) | Batch 0 → `landing_pattern` (confirm) |
| `ledgers`, `currencies` | Batch 1 → `ledgers` / `currency_basis` |
| `coa.segments_with_values` | Batch 2 → `segment_meaning` / `value_sets` (MEANING not data-provable) |
| `coa.balancing_segment_values` | Batch 3 → `legal_entities` |
| `org.business_units` | Batch 4 → `business_units` |
| `periods` | Batch 5 → `period_calendar` |
| profiled object list | Batch 6 → `physical_canonical_map` |
| `custom_columns` (detected) | Batch 7 → `custom_columns` |
