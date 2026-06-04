# PODS Genie Space benchmark

A starter set to measure whether a PODS Genie Space answers correctly. Ask each
question in the Space, then score against the expected behavior. Add the
customer's own real questions (especially Monitoring-tab misses) over time. PODS
errors are usually *silent* — a confident wrong number is the failure mode to hunt.

## Contents
- How to score
- Linear referencing
- ILI / integrity
- Units & data quality
- Traps

## How to score

An answer **passes** only if it: uses route + measure correctly (never measure
alone), respects the canonical unit, ranks anomalies by ERF/remaining strength
(not raw depth), honors ILI run vintage, and resolves the customer's terms via
the glossary.

| Score | Meaning |
|---|---|
| Pass | Correct LRS logic, units, severity basis, and result |
| Partial | Right approach, wrong unit/term/filter (fix glossary or instruction) |
| Fail | Measure-only join, depth-ranked severity, or unit confusion (fix UC comment / example / Trusted Asset) |

## Linear referencing
- "What assets are between station 1240+00 and 1310+00?" → station→measure conversion, route + measure range-overlap.
- "What's near milepost 42?" → milepost→measure, correct route.
- "Which anomalies fall inside an HCA?" → range-overlap join on the same route, not measure-only.
- "What valve is immediately upstream of this anomaly?" → ordered-by-measure on the route.

## ILI / integrity
- "What are the worst anomalies on line X?" → ranked by **ERF / predicted failure pressure**, not raw depth (Trusted Asset).
- "Give me a dig list." → severity-screened candidates via remaining-strength functions.
- "Corrosion growth between the last two runs." → matches features across runs with tool/vendor comparability and run vintage.
- "%SMYS for these features." → certified function, correct pipe attributes.

## Units & data quality
- "How long is route 12?" → answer in the canonical unit recorded by pods-setup; not a feet/meter mix.
- "Why did my overlap return nothing?" → diagnoses non-monotonic measures / unit mismatch / route gap.

## Traps (these catch the common silent failures)
- A question that joins features by measure alone → must also constrain by route.
- "Deepest anomalies" used as a proxy for "most dangerous" → Genie should rank by ERF/remaining strength and say why.
- A measure given without a unit, where the glossary unit differs → Genie should apply the recorded unit, not assume.
- A customer term not in the glossary → Genie should ask, not guess.
