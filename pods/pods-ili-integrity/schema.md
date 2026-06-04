# PODS ILI Integrity — Schema Reference

For the universal PODS model, see `pods-overview/SKILL.md`; for route-measure mechanics, `pods-linear-referencing/schema.md`. This file focuses on the ILI module.

> All names are canonical PODS concepts. Resolve to physical columns via the `<customer>-pods-glossary` (from `pods-setup`). The integrity math needs OD/wall/SMYS/MAOP — confirm those exist before promising ERF/B31G.

## ILI anomaly / feature table

One row per detected feature per run. Key columns (canonical):

| Concept | Meaning | Used for |
|---|---|---|
| `feature_id` | Unique feature identifier | Identity, box-matching across runs |
| `run_id` | The ILI run that detected it | Vintage selection, comparison |
| `route_id` | Line/route key | Locating, joins |
| measure / station | Position along route (CONFIRM UNIT — often feet) | Locating, HCA overlap |
| `depth_pct` | Metal loss as % of wall | Depth → inches for B31G |
| `length_in` | Axial length of the defect | B31G Folias factor |
| `width_in` | Circumferential width | Some methods / interaction |
| `feature_type` | Metal loss / dent / crack / mfg | Method selection (B31G = metal loss only) |
| ERF / pred failure pressure | If the vendor/operator stored it | Use instead of computing, if present |

## ILI run dimension

| Concept | Meaning | Used for |
|---|---|---|
| `run_id` | Run identifier | Join key |
| `route_id` | Line inspected | Per-line latest selection |
| `run_date` | Date of the run | Latest-run selection, growth interval |
| `vendor` | ILI vendor (Rosen, Baker, PII, …) | **Comparability warning** |
| `tool_type` | MFL / UT / EMAT / caliper | **Comparability warning**, method validity, tool-aware run selection |
| `tool_tolerance_pct_wall` | ± %wall tool accuracy (e.g. 10); nullable | Conservative (POE) depth via `pods_depth_in_tol`; sourced in `pods-setup` |

Tool type matters: **MFL** sizes metal loss; **UT** measures wall directly; **EMAT** targets cracks; **caliper/geometry** finds dents. Comparing depth across different tool types is not apples-to-apples — and a metal-loss question must select the latest **MFL/UT** run (`v_latest_metal_loss_run`), not the latest run overall.

## Pipe attributes (joined by location)

Needed for B31G/ERF/%SMYS, enriched onto anomalies by range-overlap on measure (see `v_anomalies_enriched`):

| Concept | Unit | Used for |
|---|---|---|
| `od_in` (outer diameter) | inches | Barlow, B31G |
| `wt_in` (wall thickness) | inches | depth%→in, B31G |
| `smys_psi` (SMYS / grade) | psi | flow stress, %SMYS |
| `maop_psig` | psig | ERF, %SMYS at MAOP |

Two attributes worth capturing if available (improve assessment quality):
- **`tool_tolerance_pct_wall`** on the run/tool (above) — enables tolerance-adjusted depth.
- **ID/OD flag** on the anomaly (internal vs external metal loss) — different growth mechanisms, locations (e.g. 6-o'clock internal), and remediation. Integrity engineers nearly always want this split; map it via the glossary if the operator records it.

## Cluster fields (derived — `v_anomaly_clusters` / `v_cluster_severity`)

| Field | Meaning |
|---|---|
| `cluster_id` | Stable id for an axially-interacting group (route+run+sequence) |
| `cluster_member_count` | Features in the cluster; 1 = single feature |
| `cluster_begin_m` / `cluster_end_m` | Cluster envelope along measure (meters) |
| `effective_length_in` | Envelope length used for B31G (inches) |
| `governing_depth_pct` | Deepest member's depth (screening governing depth) |
| `assessment_basis` | `'clustered'` vs `'single'` |

## Cardinality

| Relationship | Cardinality |
|---|---|
| run → anomalies | 1 : N |
| anomaly → pipe-attribute segment | N : 1 (range-overlap) |
| anomaly → cluster | N : 1 (per route + run) |
| anomaly (latest run) ↔ anomaly (prior run) | 0..1 : 0..1 via tolerance box-match |
