# Recommended Data Quality Expectations

Lakeflow SDP expectations to attach to each Silver table. Use `@dlt.expect` for advisory rules (logs violations), `@dlt.expect_or_drop` to drop violating rows, `@dlt.expect_or_fail` to halt the pipeline on violation.

Recommended severity per check is in the **Severity** column. Customers should adjust for their specific tolerance.

## `workorder` (Silver)

| Expectation | Rule | Severity |
|---|---|---|
| `wonum_not_null` | `WONUM IS NOT NULL` | `expect_or_fail` |
| `siteid_not_null` | `SITEID IS NOT NULL` | `expect_or_fail` |
| `woclass_is_workorder` | `WOCLASS = 'WORKORDER'` | `expect_or_fail` (since this table is pre-filtered) |
| `status_set_valid` | `STATUS IS NOT NULL` | `expect` |
| `dates_plausible` | `reportdate IS NOT NULL AND reportdate <= current_timestamp()` | `expect` |
| `actfinish_after_reportdate` | `actfinish IS NULL OR actfinish >= reportdate` | `expect` |
| `child_has_parent` | `istask = 0 OR parent IS NOT NULL` | `expect` |

## `wostatus` (Silver)

| Expectation | Rule | Severity |
|---|---|---|
| `wonum_not_null` | `WONUM IS NOT NULL` | `expect_or_fail` |
| `changedate_not_null` | `CHANGEDATE IS NOT NULL` | `expect_or_fail` |
| `status_not_null` | `STATUS IS NOT NULL` | `expect_or_fail` |

## `labtrans` (Silver)

| Expectation | Rule | Severity |
|---|---|---|
| `wonum_not_null` | `WONUM IS NOT NULL` | `expect_or_fail` |
| `hours_non_negative` | `regularhrs >= 0 AND COALESCE(premiumpayhours, 0) >= 0` | `expect` |
| `transtype_known` | `transtype IN ('WORK', 'TRAVEL')` | `expect` |

## `asset` (Silver SCD2)

| Expectation | Rule | Severity |
|---|---|---|
| `assetnum_not_null` | `ASSETNUM IS NOT NULL` | `expect_or_fail` |
| `siteid_not_null` | `SITEID IS NOT NULL` | `expect_or_fail` |
| `criticality_range` | `criticality IS NULL OR (criticality >= 0 AND criticality <= 100)` | `expect` |

## `locations` (Silver SCD2)

| Expectation | Rule | Severity |
|---|---|---|
| `location_not_null` | `LOCATION IS NOT NULL` | `expect_or_fail` |
| `siteid_not_null` | `SITEID IS NOT NULL` | `expect_or_fail` |

## `meterreading` (Silver)

| Expectation | Rule | Severity |
|---|---|---|
| `assetnum_not_null` | `ASSETNUM IS NOT NULL` | `expect_or_fail` |
| `readingdate_not_null` | `READINGDATE IS NOT NULL` | `expect_or_fail` |
| `reading_not_null` | `READING IS NOT NULL` | `expect_or_drop` |
| `readingdate_not_future` | `READINGDATE <= current_timestamp()` | `expect` |

## `pm` (Silver SCD2)

| Expectation | Rule | Severity |
|---|---|---|
| `pmnum_not_null` | `PMNUM IS NOT NULL` | `expect_or_fail` |
| `frequency_positive` | `frequency > 0` | `expect` |

## `failurereport` (Silver)

| Expectation | Rule | Severity |
|---|---|---|
| `wonum_not_null` | `WONUM IS NOT NULL` | `expect_or_fail` |
| `failurecode_not_null` | `FAILURECODE IS NOT NULL` | `expect_or_drop` |

---

## Example Python expectation usage

```python
@dlt.table(name="workorder")
@dlt.expect_or_fail("wonum_not_null", "WONUM IS NOT NULL")
@dlt.expect_or_fail("siteid_not_null", "SITEID IS NOT NULL")
@dlt.expect("dates_plausible", "reportdate <= current_timestamp()")
def workorder():
    return ...
```

## A note on customer-specific expectations

The expectations above are universal. Customers will want to add their own:
- "WORKORDER.WO_BU IN ('Liquids', 'Gas', 'Renewables')" if they have a business-unit column
- "ASSET.CRITICALITY <= 10" if they use a 1-10 scale
- Site-specific status sets

These belong in a workspace-level extension to the pipeline, not the canonical template.
