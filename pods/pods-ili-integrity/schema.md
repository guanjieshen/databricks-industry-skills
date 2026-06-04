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
| `tool_type` | MFL / UT / EMAT / caliper | **Comparability warning**, method validity |

Tool type matters: **MFL** sizes metal loss; **UT** measures wall directly; **EMAT** targets cracks; **caliper/geometry** finds dents. Comparing depth across different tool types is not apples-to-apples.

## Pipe attributes (joined by location)

Needed for B31G/ERF/%SMYS, enriched onto anomalies by range-overlap on measure (see `v_anomalies_enriched`):

| Concept | Unit | Used for |
|---|---|---|
| `od_in` (outer diameter) | inches | Barlow, B31G |
| `wt_in` (wall thickness) | inches | depth%→in, B31G |
| `smys_psi` (SMYS / grade) | psi | flow stress, %SMYS |
| `maop_psig` | psig | ERF, %SMYS at MAOP |

## Cardinality

| Relationship | Cardinality |
|---|---|
| run → anomalies | 1 : N |
| anomaly → pipe-attribute segment | N : 1 (range-overlap) |
| anomaly (latest run) ↔ anomaly (prior run) | 0..1 : 0..1 via tolerance box-match |
