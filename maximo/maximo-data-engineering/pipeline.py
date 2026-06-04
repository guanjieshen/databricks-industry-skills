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


# =============================================================================
# LABOR & RESOURCES — adds Silver modeling for the labor master + capacity
# tables that maximo-labor-resources composes against.
# =============================================================================

# LABOR — SCD Type 2 (rate / status / craft changes are historically relevant)
@dlt.view(name="labor_bronze_view")
def labor_bronze_view():
    return bronze("labor")


dlt.create_streaming_table(
    name="labor",
    comment="Silver LABOR — labor master, SCD2.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="labor",
    source="labor_bronze_view",
    keys=["LABORCODE", "ORGID"],
    sequence_by=F.col(AUDIT_COLUMN),
    stored_as_scd_type=2,
)


# PERSON — SCD Type 2 (PII updates over time)
@dlt.view(name="person_bronze_view")
def person_bronze_view():
    return bronze("person")


dlt.create_streaming_table(
    name="person",
    comment="Silver PERSON — person master, SCD2. PII-sensitive.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="person",
    source="person_bronze_view",
    keys=["PERSONID"],
    sequence_by=F.col(AUDIT_COLUMN),
    stored_as_scd_type=2,
)


# CRAFT — Materialized View (slow-changing reference)
@dlt.table(
    name="craft",
    comment="Silver CRAFT — craft master, slow-changing reference.",
    table_properties={"quality": "silver"},
)
def craft():
    return bronze("craft")


# LABORCRAFTRATE — SCD Type 2 (rates change over time)
@dlt.view(name="laborcraftrate_bronze_view")
def laborcraftrate_bronze_view():
    return bronze("laborcraftrate")


dlt.create_streaming_table(
    name="laborcraftrate",
    comment="Silver LABORCRAFTRATE — pay rate per (labor, craft, skill level), SCD2.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="laborcraftrate",
    source="laborcraftrate_bronze_view",
    keys=["LABORCODE", "ORGID", "CRAFT", "SKILLLEVEL"],
    sequence_by=F.col(AUDIT_COLUMN),
    stored_as_scd_type=2,
)


# QUALIFICATION — Materialized View
@dlt.table(
    name="qualification",
    comment="Silver QUALIFICATION — qualification catalog.",
    table_properties={"quality": "silver"},
)
def qualification():
    return bronze("qualification")


# CERTIFICATION — Materialized View
@dlt.table(
    name="certification",
    comment="Silver CERTIFICATION — certification catalog.",
    table_properties={"quality": "silver"},
)
def certification():
    return bronze("certification")


# QUALPERSON — SCD Type 2 (expirydate evolves; we need history)
@dlt.view(name="qualperson_bronze_view")
def qualperson_bronze_view():
    return bronze("qualperson")


dlt.create_streaming_table(
    name="qualperson",
    comment="Silver QUALPERSON — person ↔ qualification with expiry, SCD2.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="qualperson",
    source="qualperson_bronze_view",
    keys=["PERSONID", "QUALIFICATIONID"],
    sequence_by=F.col(AUDIT_COLUMN),
    stored_as_scd_type=2,
)


# CREW — SCD Type 2
@dlt.view(name="crew_bronze_view")
def crew_bronze_view():
    return bronze("crew")


dlt.create_streaming_table(
    name="crew",
    comment="Silver CREW — crew master, SCD2.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="crew",
    source="crew_bronze_view",
    keys=["CREWID", "ORGID"],
    sequence_by=F.col(AUDIT_COLUMN),
    stored_as_scd_type=2,
)


# CREWLABOR — SCD2 (membership periods)
@dlt.view(name="crewlabor_bronze_view")
def crewlabor_bronze_view():
    return bronze("crewlabor")


dlt.create_streaming_table(
    name="crewlabor",
    comment="Silver CREWLABOR — crew membership with STARTDATE/ENDDATE, SCD2.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="crewlabor",
    source="crewlabor_bronze_view",
    keys=["CREWID", "ORGID", "LABORCODE"],
    sequence_by=F.col(AUDIT_COLUMN),
    stored_as_scd_type=2,
)


# PERSONGROUP — Materialized View
@dlt.table(
    name="persongroup",
    comment="Silver PERSONGROUP — named person group reference.",
    table_properties={"quality": "silver"},
)
def persongroup():
    return bronze("persongroup")


# CALENDAR — Materialized View
@dlt.table(
    name="calendar",
    comment="Silver CALENDAR — working calendar reference.",
    table_properties={"quality": "silver"},
)
def calendar():
    return bronze("calendar")


# WORKPERIOD — Streaming Table, append-only
@dlt.table(
    name="workperiod",
    comment="Silver WORKPERIOD — append-only shift / holiday periods. Coverage often sparse; downstream skills should probe.",
    table_properties={"quality": "silver"},
)
def workperiod():
    return bronze("workperiod")


# AVAILREFLY — Streaming Table, append-only
@dlt.table(
    name="availrefly",
    comment="Silver AVAILREFLY — planned absences (vacation / leave / training).",
    table_properties={"quality": "silver"},
)
def availrefly():
    return bronze("availrefly")


# ASSIGNMENT — Streaming Table + APPLY CHANGES (status evolves on the row)
@dlt.view(name="assignment_bronze_view")
def assignment_bronze_view():
    return bronze("assignment")


dlt.create_streaming_table(
    name="assignment",
    comment="Silver ASSIGNMENT — labor ↔ WO assignments, current state.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="assignment",
    source="assignment_bronze_view",
    keys=["WONUM", "SITEID", "LABORCODE"],
    sequence_by=F.col("SCHEDDATE"),
    stored_as_scd_type=1,
)


# =============================================================================
# HIERARCHY — adds Silver modeling for the closure tables and classification
# that maximo-asset-hierarchy composes against.
# =============================================================================

# LOCHIERARCHY — Materialized View (small, slow-changing)
@dlt.table(
    name="lochierarchy",
    comment="Silver LOCHIERARCHY — multi-system parent-child for LOCATIONS. Filter SYSTEMID for the hierarchy you want.",
    table_properties={"quality": "silver"},
)
def lochierarchy():
    return bronze("lochierarchy")


# LOCANCESTOR — Materialized View, rebuilt from base.
# This is the closure table; if Bronze captures it natively, mirror it.
# Otherwise compute via recursive CTE on LOCHIERARCHY (commented alternative).
@dlt.table(
    name="locancestor",
    comment="Silver LOCANCESTOR — location closure table. One row per (descendant, ancestor, system) at any depth.",
    table_properties={"quality": "silver"},
)
def locancestor():
    # Default: pass through from Bronze.
    return bronze("locancestor")
    # Alternative for customers without a Bronze LOCANCESTOR: compute via
    # recursive CTE on LOCHIERARCHY (requires SQL, not pure dlt — register
    # via SQL DDL outside the pipeline if needed).


# ASSETANCESTOR — Materialized View, same pattern
@dlt.table(
    name="assetancestor",
    comment="Silver ASSETANCESTOR — asset closure table. One row per (descendant, ancestor) at any depth.",
    table_properties={"quality": "silver"},
)
def assetancestor():
    return bronze("assetancestor")


# SYSTEM — Materialized View
@dlt.table(
    name="system",
    comment="Silver SYSTEM — hierarchy system definitions.",
    table_properties={"quality": "silver"},
)
def system_ref():
    return bronze("system")


# CLASSSTRUCTURE — Materialized View
@dlt.table(
    name="classstructure",
    comment="Silver CLASSSTRUCTURE — asset/location classification tree.",
    table_properties={"quality": "silver"},
)
def classstructure():
    return bronze("classstructure")


# CLASSSPEC — Materialized View
@dlt.table(
    name="classspec",
    comment="Silver CLASSSPEC — specification attributes at class level.",
    table_properties={"quality": "silver"},
)
def classspec():
    return bronze("classspec")


# ASSETSPEC — Streaming Table + APPLY CHANGES (per-asset spec values)
@dlt.view(name="assetspec_bronze_view")
def assetspec_bronze_view():
    return bronze("assetspec")


dlt.create_streaming_table(
    name="assetspec",
    comment="Silver ASSETSPEC — per-asset spec values driven by CLASSSPEC.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="assetspec",
    source="assetspec_bronze_view",
    keys=["ASSETNUM", "SITEID", "ASSETATTRID"],
    sequence_by=F.col(AUDIT_COLUMN),
    stored_as_scd_type=1,
)
