# Reliability — Gotchas

These are the definitional traps that cause reliability metrics to be wrong or to drift from what Maximo's own UI shows.

## 1. MTBF and MTTR have specific Maximo O&G definitions

There are multiple valid definitions of MTBF in industry:
- **Operational MTBF**: (total operating time) / (number of failures)
- **Inherent MTBF**: design value from manufacturer
- **SMRP MTBF**: number of operating hours divided by number of failures

IBM's Maximo O&G application has its own specific formula displayed in the UI, documented at:
`https://www.ibm.com/support/pages/mttr-and-mtbf-fields-explained-maximo-oil-gas-asset-oil-application`

**The UDFs in `metric_udfs.sql` match the IBM formula.** If you compute MTBF a different way in SQL, the number won't reconcile to Maximo screens, and the reliability engineer will reject the result. Use the UDFs.

## 2. PM compliance has at least three valid definitions

| Definition | Numerator | Denominator |
|---|---|---|
| **SMRP** | PMs completed within 10% tolerance window | PMs scheduled |
| **Strict on-time** | PMs completed by `NEXTDATE` | PMs with `NEXTDATE` in period |
| **Customer-specific** | (varies) | (varies) |

The default in `metric_udfs.sql` is SMRP. If the customer uses a different definition, register a customer-specific UDF alongside (with a customer-prefixed name).

## 3. FAILURECODE hierarchy must be flattened before aggregation

`FAILURECODE` is a tree:
```
PROBLEM: "Bearing failure"
  └─ CAUSE: "Lubrication failure"
       └─ REMEDY: "Replace bearing, audit oil change frequency"
  └─ CAUSE: "Misalignment"
       └─ REMEDY: "Realign, recheck after 30 days"
```

If you `GROUP BY FAILURECODE`, you aggregate at the leaf level — usually too granular. To aggregate by problem category, flatten the tree to the `TYPE = 'PROBLEM'` level first:

```sql
WITH problems AS (
    SELECT failurecode, description AS problem_desc
    FROM failurecode WHERE type = 'PROBLEM'
)
SELECT p.problem_desc, COUNT(*)
FROM failurereport fr
JOIN failurecode fc ON fc.failurecode = fr.failurecode
JOIN problems p ON (
    fc.failurecode = p.failurecode
    OR fc.parent = p.failurecode
    OR fc.parent IN (SELECT failurecode FROM failurecode WHERE parent = p.failurecode)
)
GROUP BY p.problem_desc;
```

For deeper hierarchies, use a recursive CTE.

## 4. Failure event timestamp ≠ WO close timestamp

Reliability metrics anchor on **when the failure occurred**, not when the WO was closed. These differ by hours-to-days. Use the best-available approximation in order of preference:
1. `WORKORDER.ACTSTART` (if recorded) — closest to failure
2. `WORKORDER.REPORTDATE` — when reported (often within minutes of failure)
3. `WORKORDER.ACTFINISH` — last resort; significantly biased toward repair completion

The shipped UDFs use a defensible default (`ACTSTART` if non-null, else `REPORTDATE`).

## 5. PM Compliance and "skipped" PMs

When a PM is skipped (manually disabled, deferred, retired, decommissioned), should it count against compliance? Different organizations answer differently. The shipped UDF includes a `PM.STATUS = 'ACTIVE'` filter to exclude obviously-disabled PMs but does NOT exclude deferrals (`PM.DEFERREDDATE IS NOT NULL`) since deferrals are often legitimate exceptions.

If the customer wants stricter accounting, register a custom variant.

## 6. Meter-reading-driven analytics

`METERREADING` is high-volume — joining it to `WORKORDER` without windowing produces millions of rows. Common pattern: aggregate readings first (daily / weekly), then join to events.

Threshold-exceedance is also customer-specific — `WARNLIMITHI` / `ACTIONLIMITHI` are configurable per meter and may be unset.

## 7. "Bad actor" definitions

Bad-actor analysis has multiple valid definitions:
- Top N by failure count in period
- Top N by total downtime
- Top N by repair cost
- Top N by criticality-weighted failure count

Confirm with the user which they mean. The shipped `bad_actor_assets` example uses failure count, with criticality-weighted variant available.

## 8. Asset class hierarchy uses CLASSSTRUCTUREID, not strings

When the user says "centrifugal pumps", they're using a business-friendly name. The actual filter is `ASSET.CLASSSTRUCTUREID IN (4521, 4522, ...)` — IDs from `CLASSSTRUCTURE`.

Resolve via the workspace glossary skill (`<customer>-maximo-glossary`) if available. Otherwise ASK — don't `WHERE DESCRIPTION LIKE '%pump%'` (catches non-pumps and misses pumps with different naming conventions).
