"""Skeleton Lakeflow Spark Declarative Pipeline for <source> Silver/Gold.

REPLACE this skeleton with source-specific definitions. The platform-layer
databricks-spark-declarative-pipelines skill carries the SDP mechanics
(decorators, AutoCDC, expectations, streaming-table semantics); THIS file
encodes the source-specific table list, CDC keys, and expectations.
"""
import dlt
from pyspark.sql.functions import col


# ── Bronze ───────────────────────────────────────────────────────────────────
# Define one streaming table per raw <source> table. Real-world Bronze
# definitions typically use Auto Loader against the cloud-files source path.
# Mechanics: see databricks-spark-declarative-pipelines.

# ── Silver ───────────────────────────────────────────────────────────────────
# AutoCDC into Silver using the source's business key + SITEID.

dlt.create_streaming_table("example_table")

dlt.create_auto_cdc_flow(
    target="example_table",
    source="bronze_example_table",
    keys=["example_id", "siteid"],          # composite key — source-specific
    sequence_by=col("changedate"),
    stored_as_scd_type=2,
    apply_as_deletes=col("operation") == "DELETE",
)

# Source-specific data-quality expectations
@dlt.expect_or_drop("siteid_not_null", "siteid IS NOT NULL")
@dlt.expect_or_drop("example_id_not_null", "example_id IS NOT NULL")
@dlt.expect_or_drop("status_known", "status IN ('NEW', 'INPRG', 'DONE')")
def _silver_quality():
    pass


# ── Gold ─────────────────────────────────────────────────────────────────────
# Pre-joined / denormalized views downstream skills compose against.

@dlt.table(comment="Closure table: location → all ancestors at every depth. "
                   "Rebuilt from base; not CDC.")
def v_location_rollup_keys():
    # Recursive CTE pattern — see <source>-asset-hierarchy for the full version.
    return spark.sql("""
        WITH RECURSIVE locs AS (
            SELECT location, parent, 0 AS depth FROM example_locations
            UNION ALL
            SELECT l.location, p.parent, l.depth + 1
            FROM locs l JOIN example_locations p ON p.location = l.parent
            WHERE l.parent IS NOT NULL AND l.depth < 50
        )
        SELECT location, parent AS ancestor, depth FROM locs
    """)
