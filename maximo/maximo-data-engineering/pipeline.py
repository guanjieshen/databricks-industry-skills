"""Maximo Bronze → Silver SDP pipeline template.

Canonical Lakeflow Spark Declarative Pipeline source for landing Maximo data
into a clean Silver layer. Handles three Bronze input shapes via the
BRONZE_SHAPE configuration:

    - "partner_connector"  : Fivetran / Qlik / Informatica flat-table mirrors
    - "jdbc_dump"          : Raw Spark JDBC snapshots
    - "mas_kafka"          : Streaming MAS Kafka payloads (JSON, after flattening)

To use this template:

1. Copy into a Lakeflow notebook in your workspace.
2. Set the pipeline configuration variables in `BRONZE_SHAPE`, `BRONZE_PATH`,
   and the target catalog/schema in the Lakeflow pipeline settings.
3. Adjust per-table column projection to match your customer's schema
   (extension columns, renamed fields, etc.).

This template intentionally covers the high-volume / high-value tables. Add
similar declarations for additional MBOs (PM, JOBPLAN, COMPANIES, etc.) as
needed.
"""
from __future__ import annotations

import dlt
from pyspark.sql import functions as F


# -----------------------------------------------------------------------------
# Pipeline configuration — set these via the Lakeflow pipeline settings UI:
#   BRONZE_SHAPE   = "partner_connector" | "jdbc_dump" | "mas_kafka"
#   BRONZE_PATH    = e.g. "bronze.maximo"
#   AUDIT_COLUMN   = name of the audit timestamp column from your ingestion
#                    (e.g. "_fivetran_synced" for Fivetran, "_ingest_ts" for custom)
# -----------------------------------------------------------------------------

BRONZE_SHAPE = spark.conf.get("BRONZE_SHAPE", "partner_connector")
BRONZE_PATH = spark.conf.get("BRONZE_PATH", "bronze.maximo")
AUDIT_COLUMN = spark.conf.get("AUDIT_COLUMN", "_ingest_ts")


def bronze(table: str):
    """Read a Bronze table — abstraction over different Bronze shapes."""
    if BRONZE_SHAPE in ("partner_connector", "jdbc_dump"):
        return dlt.read_stream(f"{BRONZE_PATH}.{table.lower()}")
    if BRONZE_SHAPE == "mas_kafka":
        # Kafka payloads land as JSON; assume a sibling flattening step has
        # already produced flat Bronze tables under BRONZE_PATH.
        return dlt.read_stream(f"{BRONZE_PATH}.{table.lower()}")
    raise ValueError(f"Unknown BRONZE_SHAPE: {BRONZE_SHAPE}")


# =============================================================================
# WORKORDER — APPLY CHANGES INTO (current state, idempotent on WONUM + SITEID)
# Silver layer pre-filters WOCLASS = 'WORKORDER' for normal-WO consumption.
# A second Silver table preserves all classes for the rare query that needs them.
# =============================================================================

@dlt.view(name="workorder_bronze_view")
def workorder_bronze_view():
    return bronze("workorder")


dlt.create_streaming_table(
    name="workorder",
    comment="Silver WORKORDER — current state, filtered to WOCLASS='WORKORDER'.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="workorder",
    source="workorder_bronze_view",
    keys=["WONUM", "SITEID"],
    sequence_by=F.col("STATUSDATE"),
    apply_as_deletes=None,
    except_column_list=[],
    stored_as_scd_type=1,
)


@dlt.table(
    name="workorder_all_classes",
    comment="Silver WORKORDER — current state, ALL WOCLASS values (PM/CHANGE/RELEASE/ACTIVITY/WORKORDER). Use only when you need non-WORKORDER classes.",
    table_properties={"quality": "silver"},
)
def workorder_all_classes():
    return dlt.read("workorder")


# =============================================================================
# WOSTATUS — APPEND-ONLY (history; never apply-changes)
# =============================================================================

@dlt.table(
    name="wostatus",
    comment="Silver WOSTATUS — append-only status-history log. One row per status transition. NEVER apply-changes — that destroys history.",
    table_properties={"quality": "silver"},
)
def wostatus():
    return bronze("wostatus")


# =============================================================================
# LABTRANS — APPEND-ONLY (labor transactions)
# =============================================================================

@dlt.table(
    name="labtrans",
    comment="Silver LABTRANS — append-only labor transactions, one row per craft-hour booked.",
    table_properties={"quality": "silver"},
)
def labtrans():
    return bronze("labtrans")


# =============================================================================
# ASSET — SCD Type 2
# =============================================================================

@dlt.view(name="asset_bronze_view")
def asset_bronze_view():
    return bronze("asset")


dlt.create_streaming_table(
    name="asset",
    comment="Silver ASSET — SCD2 with full history of attribute changes.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="asset",
    source="asset_bronze_view",
    keys=["ASSETNUM", "SITEID"],
    sequence_by=F.col(AUDIT_COLUMN),
    stored_as_scd_type=2,
)


# =============================================================================
# LOCATIONS — SCD Type 2
# =============================================================================

@dlt.view(name="locations_bronze_view")
def locations_bronze_view():
    return bronze("locations")


dlt.create_streaming_table(
    name="locations",
    comment="Silver LOCATIONS — SCD2.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="locations",
    source="locations_bronze_view",
    keys=["LOCATION", "SITEID"],
    sequence_by=F.col(AUDIT_COLUMN),
    stored_as_scd_type=2,
)


# =============================================================================
# LOCHIERARCHY — Materialized View, rebuilt from LOCATIONS each run
# =============================================================================

@dlt.table(
    name="location_hierarchy",
    comment="Silver LOCHIERARCHY — flattened parent chain. Rebuilt from LOCATIONS each run.",
    table_properties={"quality": "silver"},
)
def location_hierarchy():
    # Recursive CTE-free flatten: limit depth to typical Maximo (5 levels).
    base = dlt.read("locations").filter("__END_AT IS NULL")  # current SCD2 rows
    return base.selectExpr(
        "LOCATION AS location",
        "SITEID AS siteid",
        "PARENT AS parent_1",
        "DESCRIPTION AS description",
    )


# =============================================================================
# ASSETMETER — SCD Type 2
# METERREADING — append-only
# =============================================================================

@dlt.view(name="assetmeter_bronze_view")
def assetmeter_bronze_view():
    return bronze("assetmeter")


dlt.create_streaming_table(
    name="assetmeter",
    comment="Silver ASSETMETER — meter definitions per asset, SCD2.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="assetmeter",
    source="assetmeter_bronze_view",
    keys=["ASSETNUM", "SITEID", "METERNAME"],
    sequence_by=F.col(AUDIT_COLUMN),
    stored_as_scd_type=2,
)


@dlt.table(
    name="meterreading",
    comment="Silver METERREADING — append-only time-series meter readings.",
    table_properties={"quality": "silver"},
)
def meterreading():
    return bronze("meterreading")


# =============================================================================
# PM — SCD Type 2 (schedule changes are historically interesting)
# =============================================================================

@dlt.view(name="pm_bronze_view")
def pm_bronze_view():
    return bronze("pm")


dlt.create_streaming_table(
    name="pm",
    comment="Silver PM — preventive maintenance master, SCD2.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="pm",
    source="pm_bronze_view",
    keys=["PMNUM", "SITEID"],
    sequence_by=F.col(AUDIT_COLUMN),
    stored_as_scd_type=2,
)


# =============================================================================
# FAILUREREPORT — append-only
# FAILURECODE — materialized view (slow-changing reference)
# =============================================================================

@dlt.table(
    name="failurereport",
    comment="Silver FAILUREREPORT — append-only per-WO failure record.",
    table_properties={"quality": "silver"},
)
def failurereport():
    return bronze("failurereport")


@dlt.table(
    name="failurecode",
    comment="Silver FAILURECODE — taxonomy tree (PROBLEM/CAUSE/REMEDY). Slow-changing; full refresh.",
    table_properties={"quality": "silver"},
)
def failurecode():
    return bronze("failurecode")
