# PODS Setup — Interview Questions

Use these to confirm the introspection draft and fill gaps. Ask in **batches of 2–3**, never all at once. Lead with what `introspect_schema.py` already proposed.

For each answer capture: (a) the customer's physical table/column, (b) the canonical PODS concept it maps to, (c) for measure columns, the **unit**, (d) any caveats.

---

## Batch 1 — Route key and units (the critical batch)

1. **"What column identifies the line / route, and is it the same name across your anomaly, centerline, and HCA tables?"**
   - Map to: canonical `route_id`
   - Flag if the key differs across tables (common; record each)

2. **"For each measure/stationing column — is it in FEET or METERS?"** Go column by column: ILI stationing, centerline measure, HCA begin/end.
   - This is the single most important answer in the whole setup. Do not let it slide to "not sure" — if unsure, propose checking a known physical point.

## Batch 2 — ILI anomalies and runs

3. **"Which table holds ILI anomalies / features, and which columns are: feature id, run id, measure/station, depth, length, width, feature type?"**
   - Map to canonical anomaly columns

4. **"Is ERF (or predicted failure pressure / %SMYS) stored on the anomaly, or does it need to be computed? Which column if stored?"**
   - Determines whether `pods-ili-integrity` uses a stored field or the B31G/RSTRENG UDFs

5. **"Which table holds the ILI runs, with run date, vendor, and tool type (MFL/UT/EMAT)?"**
   - Needed for latest-run selection and cross-run comparability warnings

## Batch 3 — Pipe attributes for integrity math

6. **"Where are pipe physical attributes — outer diameter (OD), wall thickness, SMYS / grade, MAOP? Per segment or per route?"**
   - Needed for B31G / ERF. Record table + columns + units (inches? psi?)

7. **"Is MAOP a single value per line or does it vary by segment / class location?"**
   - ERF needs the MAOP applicable at the anomaly's location

## Batch 4 — Modules and hierarchy

8. **"Which PODS modules have you adopted — IR, TVC, ILI, CP, SL, OFF?"** (Check `MODULE_METADATA` if present.)
   - Module skills degrade gracefully when a module is absent

9. **"What do you call your lines / segments in business terms, and how do they map to route_id? (e.g. 'Line 4', 'the 30-inch', 'the river crossing')"**
   - Business jargon → route_id list

## Batch 5 — Direction and quality caveats

10. **"Does measure increase in the direction of flow on your routes, or is it digitization-dependent?"**
    - Needed for upstream/downstream queries

11. **"Any known data-quality issues — station equations/restarts, recalibrations between runs, segments with reversed measures?"**
    - Feeds `pods-data-quality` and tolerance choices

## Closing

12. **"Any pipeline term you use daily that wouldn't make sense reading PODS docs cold? Anything that's tripped up past data work?"**
    - Tribal knowledge catch-all

---

## How to record answers

Save as `answers.json` (consumed by `generate_glossary.py`):

```json
{
  "customer": "acme-midstream",
  "route_key": {"canonical": "route_id", "physical": "line_id", "consistent_across_tables": false,
                "per_table": {"ili_features": "line_ref", "hca_segments": "line_id"}},
  "measure_units": {
    "ili_features.begin_stn": "ft",
    "centerline.measure": "m",
    "hca_segments.begin_measure": "m"
  },
  "ili": {
    "anomaly_table": "integrity.smartpig_features",
    "columns": {"feature_id": "feature_id", "run_id": "insp_id", "measure": "feature_md",
                "depth_pct": "depth_pct", "length_in": "length_in", "feature_type": "feat_type"},
    "erf_stored": false,
    "runs_table": "integrity.ili_runs",
    "run_columns": {"run_id": "insp_id", "run_date": "run_date", "vendor": "vendor", "tool_type": "tool"}
  },
  "pipe_attributes": {"table": "engineering.pipe_segments",
                      "od_in": "od_inches", "wt_in": "wall_thk_in", "smys_psi": "smys", "maop_psig": "maop"},
  "modules_adopted": ["ILI", "IR", "CP"],
  "lines": {"Line 4": ["L04"], "the 30-inch": ["L04"], "river crossing": ["L04-RC"]},
  "flow_direction": "increasing_measure_is_downstream",
  "tribal_knowledge": [
    "2019 run was Baker UT; 2024 run was Rosen MFL — depth sizing not directly comparable",
    "Station equation at 1500+00 on L07 after the 2021 reroute"
  ]
}
```
