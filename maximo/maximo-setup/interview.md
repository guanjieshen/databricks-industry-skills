# Maximo Setup — Interview Questions

Use these questions to collect the mappings needed for the workspace glossary. Ask in **batches of 2–3**, not all at once.

For each question, capture: (a) the business terms the customer uses, (b) how they map to Maximo schema (table.column or value list), (c) any caveats or "this is approximate" flags.

---

## Batch 1 — Sites and locations

1. **"What do you call your sites in business terms? Show me one or two examples of each."**
   - Map to: `SITEID` values
   - Example collection: `"Mainline" → SITEID IN ('MAIN-E', 'MAIN-W', 'MAIN-C')`

2. **"What's your asset/location hierarchy — region → station → equipment, or something different?"**
   - Map to: `LOCATIONS` parent chain (via `LOCHIERARCHY` if needed)
   - Capture the LEVEL at which each business term sits

## Batch 2 — Asset classes

3. **"What asset classes do you reference by name in daily conversation (e.g. 'centrifugal pump', 'compressor', 'pressure vessel')? Do you know the CLASSSTRUCTUREID(s) they map to?"**
   - Map to: `ASSET.CLASSSTRUCTUREID` values
   - If the customer doesn't know: offer to enumerate `CLASSSTRUCTURE` rows and have them pick

4. **"How do you classify 'critical' assets? Is there a number on a scale, a tag, or a custom field?"**
   - Map to: `ASSET.CRITICALITY` value or a custom column

## Batch 3 — Work order semantics

5. **"In your business, what statuses count as 'open' for a work order?"**
   - Map to: `WORKORDER.STATUS` value list
   - Default if unknown: `('WAPPR', 'APPR', 'INPRG', 'WSCH', 'WMATL')`

6. **"What's your set of work types? Especially: how do you distinguish corrective vs preventive vs emergency?"**
   - Map to: `WORKORDER.WORKTYPE` values (customer-configured)

## Batch 4 — Extensions and customizations

7. **"Are there custom columns on `WORKORDER`, `ASSET`, or `LOCATIONS` that you rely on? Pipeline kilometer, regulatory flag, anything like that?"**
   - Capture: column name, what it stores, who uses it

8. **"Any custom tables that join to the standard Maximo tables? (PCMS data, GIS data, custom integrity records, etc.)"**
   - Capture: table name, what it joins on, what it stores

## Batch 5 — Regulatory and HSE (O&G specific)

Only if the customer is in O&G / utilities / mining and runs `maximo-integrity` or `maximo-hse`.

9. **"Which regulatory codes drive your inspection PMs? API 510, 570, B31.4, CSA Z662, DOT, others?"**
   - Capture: regulatory regime → PM filter convention (often a custom column or a `PMTYPE` value)

10. **"How do you track Permit-to-Work — through `plusgpermitwork`, or do you have a custom system?"**
    - Capture: whether `plusgpermitwork` is populated, or another table is the source of truth

## Closing — the "anything else" question

11. **"Is there any business term or concept that you use daily that wouldn't make sense to someone reading Maximo docs cold? Anything that's caused confusion in past data work?"**
    - Catch-all — captures tribal knowledge that isn't in standard categories

---

## How to record answers

Save as `answers.json` in this shape (the `generate_glossary.py` script consumes this):

```json
{
  "customer": "enbridge",
  "sites": {
    "Mainline": ["MAIN-E", "MAIN-W", "MAIN-C"],
    "Field": ["FLD-AB1", "FLD-AB2"]
  },
  "location_hierarchy": {
    "Region": "LOCHIERARCHY level 1",
    "Station": "LOCHIERARCHY level 2",
    "Equipment": "LOCHIERARCHY level 3"
  },
  "asset_classes": {
    "centrifugal pump": [4521, 4522],
    "reciprocating compressor": [5022],
    "pressure vessel": [7100, 7101, 7102]
  },
  "criticality": {
    "high": "ASSET.CRITICALITY >= 8",
    "critical": "ASSET.CRITICALITY = 10"
  },
  "open_statuses": ["WAPPR", "APPR", "INPRG", "WSCH", "WMATL", "WPCOND"],
  "worktypes": {
    "corrective": ["CM", "EM"],
    "preventive": ["PM"],
    "emergency": ["EM"],
    "regulatory": ["REG", "INSP"]
  },
  "custom_columns": {
    "WORKORDER.WO_PIPELINE_KM": "Pipeline kilometer of the work site",
    "WORKORDER.WO_REG_FLAG": "Y/N — does this WO satisfy a regulatory requirement"
  },
  "custom_tables": {
    "eam.maximo_silver.pcms_thickness_readings": "Joined to ASSET on assetnum; corrosion thickness gauging readings"
  },
  "regulatory_codes": ["API 510", "API 570", "CSA Z662"],
  "tribal_knowledge": [
    "'In service' colloquially means STATUS = 'INPRG', not the formal Maximo asset status",
    "Region 5 was renamed to 'North' in 2024 but the LOCATIONS records still say REG5"
  ]
}
```
