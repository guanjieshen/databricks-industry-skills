# =============================================================================
# PODS Data Engineering — Lakeflow Declarative Pipeline (SDP) skeleton
# =============================================================================
# Bronze -> Silver -> Gold for PODS pipeline data. The critical step is
# measure-unit normalization at the Silver->Gold boundary so every downstream
# PODS skill works against ONE route key and ONE unit (meters).
#
# Substitute physical table/column names from the <customer>-pods-glossary
# produced by pods-setup. The feet/meter conversions below assume ILI stationing
# in FEET and centerline/HCA measures in METERS — adjust to the operator's
# actual units (recorded in the glossary).
# =============================================================================
import dlt
from pyspark.sql import functions as F

FT_TO_M = 0.3048


# ---- Bronze: land raw feeds as-is ------------------------------------------
@dlt.table(comment="Raw ILI anomaly/feature feed, landed as-is.")
def bronze_ili_features():
    return spark.readStream.format("cloudFiles") \
        .option("cloudFiles.format", "parquet") \
        .load("/Volumes/pipeline/landing/ili_features/")


@dlt.table(comment="Raw ILI run metadata feed.")
def bronze_ili_runs():
    return spark.readStream.format("cloudFiles") \
        .option("cloudFiles.format", "parquet") \
        .load("/Volumes/pipeline/landing/ili_runs/")


# ---- Silver: typed, deduped; PODS structure preserved; units documented ----
@dlt.table(comment="Typed ILI anomalies. begin_stn is in FEET (see glossary).")
@dlt.expect_or_drop("has_route", "route_id IS NOT NULL")
@dlt.expect_or_drop("has_measure", "begin_stn IS NOT NULL")
def silver_ili_features():
    return (
        dlt.read("bronze_ili_features")
        .select(
            F.col("feature_id").cast("string").alias("feature_id"),
            F.col("insp_id").cast("string").alias("run_id"),
            F.col("line_ref").alias("route_id"),          # glossary: physical route key
            F.col("feature_md").cast("double").alias("begin_stn"),  # FEET per glossary
            F.col("depth_pct").cast("double").alias("depth_pct"),
            F.col("length_in").cast("double").alias("length_in"),
            F.col("width_in").cast("double").alias("width_in"),
            F.col("feat_type").alias("feature_type"),
        )
        .dropDuplicates(["feature_id", "run_id"])
    )


@dlt.table(comment="ILI run dimension — vendor/tool/date drive comparability warnings.")
def silver_ili_runs():
    return (
        dlt.read("bronze_ili_runs")
        .select(
            F.col("insp_id").cast("string").alias("run_id"),
            F.col("line_ref").alias("route_id"),
            F.to_date("run_date").alias("run_date"),
            F.col("vendor").alias("vendor"),
            F.col("tool").alias("tool_type"),
        )
        .dropDuplicates(["run_id"])
    )


# ---- Gold: normalized route-measure spine (ONE unit = meters) ---------------
@dlt.table(comment="Gold anomalies with normalized measure_m (meters). The analytical contract.")
def gold_ili_features_m():
    f = dlt.read("silver_ili_features")
    return f.withColumn("measure_m", F.col("begin_stn") * F.lit(FT_TO_M))  # FEET -> METERS, once


# The unified v_route_events_m spine (anomalies + assets + HCA) is created as a
# SQL view in gold_views.sql, layering on these Gold tables. Keeping it as a
# view avoids materialization drift; materialize only if latency requires it.
