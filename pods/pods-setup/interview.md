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

5b. **"What is each ILI tool's depth tolerance (± %wall, at what confidence), and is it recorded per run/vendor/tool or a known spec? Which tools count as metal-loss tools (MFL, UT, …)?"**
   - Map tolerance to canonical `tool_tolerance_pct_wall`; capture the metal-loss tool-type set
   - Tolerance enables conservative (POE) depth; the tool set drives `v_latest_metal_loss_run`. If tolerance unknown, assessments fall back to call depth and say so

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

## Batch 6 — Integrity assessment configuration

12. **"For interacting/clustered corrosion, what spacing rule do you use to decide features interact (e.g. 3× wall, 6× wall, a fixed distance)?"**
    - Drives the `v_anomaly_clusters` interaction window (default 3× wall if unknown)

13. **"What ERF / predicted-failure-pressure thresholds and safety factor define your immediate / scheduled / monitor response classes, per your IM program and 49 CFR (195.452(h) liquid / 192.933 + B31.8S gas)?"**
    - Parameterizes the dig examples; never default the safety factor or thresholds silently — these are operator + regulatory criteria

## Closing

14. **"Any pipeline term you use daily that wouldn't make sense reading PODS docs cold? Anything that's tripped up past data work?"**
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
    "run_columns": {"run_id": "insp_id", "run_date": "run_date", "vendor": "vendor", "tool_type": "tool",
                    "tool_tolerance_pct_wall": "depth_tol_pct"},
    "metal_loss_tool_types": ["MFL", "UT"],
    "tool_tolerance_pct_wall": {"MFL": 10.0, "UT": 5.0}
  },
  "pipe_attributes": {"table": "engineering.pipe_segments",
                      "od_in": "od_inches", "wt_in": "wall_thk_in", "smys_psi": "smys", "maop_psig": "maop"},
  "integrity_assessment": {
    "interaction_window_rule": "3x_wall",
    "safety_factor": 1.39,
    "response_thresholds": {"immediate_erf": 1.0, "scheduled_erf": 0.8}
  },
  "modules_adopted": ["ILI", "IR", "CP"],
  "lines": {"Line 4": ["L04"], "the 30-inch": ["L04"], "river crossing": ["L04-RC"]},
  "flow_direction": "increasing_measure_is_downstream",
  "tribal_knowledge": [
    "2019 run was Baker UT; 2024 run was Rosen MFL — depth sizing not directly comparable",
    "Station equation at 1500+00 on L07 after the 2021 reroute"
  ]
}
```
