# Maximo Setup — Interview (profile-first)

Run **after** `scripts/introspect_schema.py` has produced `draft_profile.json`. Conduct
this like a Maximo implementation consultant **who can already see the data**: the
profile answers "what" (the distinct values, the custom columns, which modules are
populated). Your job is to capture what data **can't** prove — **intent, exceptions,
process reality, and KPI definitions** — and to confirm/correct the profiler's proposals.

**Ground every question in the profile.** Don't ask "what are your statuses?" — say "your
data has these statuses; walk me through what they mean." Ask in **batches of 2–3**, not
all at once. For each answer capture: the business term, the schema mapping
(table.column or value list), and any "approximate / needs validation" flag.

---

## Batch 0 — Industry & how you actually use Maximo

Confirm `draft_profile.json → usage_profile`.

1. **"The profile {found / did not find} `plusg*` tables. Are you on the Maximo Oil & Gas (PLUSG) industry solution? What industry and sub-segment are you?"** Other add-ons to ask about: PLUSC (Calibration), PLUST (Transportation), PLUSU (Utilities), Nuclear, Aviation, Spatial.
2. **"`modules_in_use` shows {WORKORDER, PM populated; INVENTORY empty}. Which modules do you actually run *in Maximo* vs. another system of record (SAP/Oracle/GIS)?"** Empty/sparse indicator tables usually mean the process lives elsewhere.
3. **"What's your maintenance maturity — run-to-failure, time-based PM, condition-based, RCM/PdM? Who uses this data and what decisions do they make from it?"**

→ records to `industry_usage`.

## Batch 1 — Work-order lifecycle & statuses

Ground in `work_order.status_values` + `proposed_open_statuses`.

4. **"Your data has these statuses: {list}. Walk me through the lifecycle — which count as 'open'/backlog? Which is 'work done but not financially closed' (`COMP` vs `CLOSE`)? What are the non-standard ones {e.g. WPCOND, FAPPR} in your shop?"**
   - → confirms `open_statuses`
5. **"How are statuses changed — UI, MIF/integration, or a mobile/REST app?"** On classic 7.6, REST changes can skip `WOSTATUS` history (APAR IJ17261) — flag if so, it breaks time-in-status.
6. **"The profile shows {N%} `CAN` — what drives cancellations? Any 'parking' statuses that inflate backlog age?"**

## Batch 2 — Work types & the PM-vs-CM truth

Ground in `work_order.worktype_values`.

7. **"Your `WORKTYPE` values are {list}. Which are corrective / preventive / emergency / project? Is capital or project work mixed into maintenance WOs?"** (it inflates maintenance cost)
   - → confirms `worktypes`
8. **"Does `WORKTYPE='PM'` actually equal PM-generated (`PMNUM IS NOT NULL`), or do planners set it by hand?"** Affects `maximo-maintenance-cost` and `maximo-pm-planning`.

## Batch 3 — Sites, orgs & hierarchy

Ground in `work_order.siteid_values`.

9. **"Your `SITEID`s are {list} across {N} orgs. How do these roll up to business regions? Any test or decommissioned sites to exclude? Do you compare across orgs (watch for different calendars/currencies)?"**
   - → confirms `sites` + `location_hierarchy`
10. **"Is `LOCATIONS` hierarchy, `ASSET` parent-child, or both authoritative for 'where the work is'?"**

## Batch 4 — Asset classes

Ground in `asset.classstructureid_values`.

11. **"There are {N} `CLASSSTRUCTUREID`s. Which classes matter for reliability/integrity, and what do you call them ('centrifugal pump')? Is the taxonomy maintained, or is most equipment in a few generic classes?"**
    - → confirms `asset_classes`
12. **"How do you flag 'critical' assets — `ASSET.CRITICALITY`, a tag, or a custom field?"** → `criticality`

## Batch 5 — Custom columns & tables

Ground in `custom_columns` (detected) + `stats.high_null_columns`.

13. **"I detected these custom columns: {list}. What does each drive? Which are mandatory in your process? Do any *replace* a standard field (e.g. a custom priority instead of `WOPRIORITY`)?"**
    - → `custom_columns`
14. **"Column {X} is {high_null}% null — deprecated, or only used for a subset of work?"**
15. **"Any custom tables that join to standard Maximo (PCMS, GIS, integrity records)?"** → `custom_tables`

## Batch 6 — Data integrity & process reality

These decide whether analytics are trustworthy at all. Ground in `stats` + null density.

16. **"`FAILUREREPORT` is {N%} populated — if low, MTBF/failure-mode analysis isn't reliable. Do engineers actually code failures?"**
17. **"Are labor hours *booked* (`LABTRANS`) or estimated? Mobile vs back-office entry?"**
18. **"Did you migrate from an older Maximo or another CMMS? Pre-cutover WOs often have null history / placeholder statuses — what's the cutover date?"**
19. **"Are dates UTC or site-local?"** (changes "completed yesterday")

## Batch 7 — KPIs & reconciliation

20. **"How do you define PM compliance (numerator/denominator + tolerance), schedule compliance window, and 'backlog' today?"** → so the certified metrics reconcile to their definitions.
21. **"Show me one number you currently trust — a report you run — so we reconcile our queries to it."** The fastest way to earn trust.

## Batch 8 — Regulatory & HSE (only if PLUSG present / O&G-utilities-mining)

22. **"Which regulatory codes drive inspection PMs (API 510/570, B31.4, CSA Z662, DOT)? How is inspection work isolated — `WORKTYPE`, a custom flag, or a `JPNUM` set?"** → `regulatory_codes`
23. **"Is Permit-to-Work in `plusgpermitwork`, or a custom/other system? What's your TRIR hours-worked source (usually a corporate HR system, not Maximo)?"**

## Closing — tribal knowledge

24. **"Any business term or quirk that's caused confusion in past data work? Anything that's burned you?"** → `tribal_knowledge`

---

## How to record answers

The profiler seeds most of this; you confirm. Save as `answers.json` (consumed by
`generate_glossary.py`). Same shape as before **plus** the new `industry_usage` block:

```json
{
  "customer": "enbridge",
  "industry_usage": {
    "industry": "Midstream oil & gas (liquids + gas transmission)",
    "industry_solutions": ["Oil & Gas (PLUSG)"],
    "modules_in_use": ["work_management", "preventive_maintenance", "asset_integrity", "hse"],
    "modules_elsewhere": {"inventory": "SAP", "procurement": "SAP"},
    "maintenance_maturity": "time-based PM moving to condition-based on rotating equipment",
    "kpis": ["PM compliance (completed within 10% of frequency)", "schedule compliance (weekly)"],
    "notes": ["Capital work is WORKTYPE=CAP — exclude from maintenance cost"]
  },
  "sites": { "Mainline": ["MAIN-E", "MAIN-W", "MAIN-C"], "Field": ["FLD-AB1", "FLD-AB2"] },
  "location_hierarchy": { "Region": "LOCHIERARCHY level 1", "Station": "LOCHIERARCHY level 2" },
  "asset_classes": { "centrifugal pump": [4521, 4522], "pressure vessel": [7100, 7101] },
  "criticality": { "critical": "ASSET.CRITICALITY = 10" },
  "open_statuses": ["WAPPR", "APPR", "INPRG", "WSCH", "WMATL", "WPCOND"],
  "worktypes": { "corrective": ["CM", "EM"], "preventive": ["PM"], "capital": ["CAP"] },
  "custom_columns": {
    "WORKORDER.WO_PIPELINE_KM": "Pipeline kilometer of the work site",
    "WORKORDER.WO_REG_FLAG": "Y/N — does this WO satisfy a regulatory requirement"
  },
  "custom_tables": { "eam.maximo_silver.pcms_thickness_readings": "Joined to ASSET on assetnum; corrosion gauging" },
  "regulatory_codes": ["API 510", "API 570", "CSA Z662"],
  "tribal_knowledge": ["'In service' colloquially means STATUS='INPRG', not the asset status"],
  "followups": [
    {"question": "WPCOND meaning / is it 'open'?", "owner": "Maintenance planners"},
    {"question": "Official CLASSSTRUCTUREID → asset-class names", "owner": "Reliability"}
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
| `usage_profile` (plusg_present, modules_in_use) | Batch 0 → `industry_usage` |
| `work_order.proposed_open_statuses` | Batch 1 → `open_statuses` |
| `work_order.worktype_values` | Batch 2 → `worktypes` |
| `work_order.siteid_values` | Batch 3 → `sites` / `location_hierarchy` |
| `asset.classstructureid_values` | Batch 4 → `asset_classes` |
| `custom_columns` (detected) | Batch 5 → `custom_columns` |
