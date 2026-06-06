# =============================================================================
# WellView — Lakeflow SDP skeleton (Bronze -> Silver -> Gold)
# =============================================================================
# SDP / Auto Loader / AutoCDC MECHANICS are owned by the platform skill
# `databricks-spark-declarative-pipelines`. This skeleton adds only the
# WellView-specific shape: IDREC GUID CDC keys, master-unit normalization at
# Silver->Gold, LV decode, and the report-grained daily-ops/cost gold fact the
# metric view consumes. Resolve physical names + master units via the glossary.
# =============================================================================
import dlt
from pyspark.sql import functions as F

CATALOG = spark.conf.get("catalog")
BRONZE  = spark.conf.get("bronze_schema")
SILVER  = spark.conf.get("silver_schema")
GOLD    = spark.conf.get("gold_schema")

# Master unit pinned by wellview-setup / SYSUNIT. Set FT_TO_M = 1.0 if depth is
# already stored in metres for this customer.
FT_TO_M = float(spark.conf.get("depth_ft_to_m", "0.3048"))

# Spine tables to land + their (single, GUID) CDC key. No composite keys.
SPINE = ["WVWELLHEADER", "WVJOB", "WVJOBREPORT", "WVJOBREPORTOP",
         "WVCOST", "WVAFE", "WVAFEDETAIL", "WVJOBRIG"]
LV    = ["LVWVTYPEJOB", "LVWVPHASE", "LVWVCODEOP", "LVWVCODENPT", "LVWVCODECOST"]


# --- BRONZE: raw passthrough of the replicated WellView tables -----------------
def _bronze(tbl):
    @dlt.table(name=f"bz_{tbl.lower()}")
    def _t():
        return spark.readStream.table(f"{CATALOG}.{BRONZE}.{tbl.lower()}")
    return _t

for t in SPINE + LV:
    _bronze(t)


# --- SILVER: type + dedup by IDREC (GUID), keep latest by SYSMODDATE -----------
# Prefer AutoCDC / apply_changes from the platform skill; shown here as the shape.
def _silver(tbl):
    @dlt.table(name=f"{tbl.lower()}")
    @dlt.expect_or_drop("idrec_not_null", "IDREC IS NOT NULL")
    def _t():
        return (
            dlt.read(f"bz_{tbl.lower()}")
               .withWatermark("SYSMODDATE", "2 days")
               .dropDuplicates(["IDREC"])
        )
    return _t

for t in SPINE + LV:
    _silver(t)


# --- GOLD: the report-grained daily-ops/cost fact for the metric view ---------
# One row per report-day per job. Footage/depth normalized to metres; cost rolled
# from children; NPT/total hours aggregated; calc fields recomputed.
@dlt.table(name="v_daily_ops_cost_fact", comment="Report-grained daily-ops/cost fact (metres; per-job).")
def daily_ops_cost_fact():
    report = dlt.read("wvjobreport")
    job    = dlt.read("wvjob").select("IDREC", "JOBTYPE", "IDWELL")
    well   = dlt.read("wvwellheader").select("IDWELL", "WELLNAME")
    rig    = dlt.read("wvjobrig").select(F.col("IDRECPARENT").alias("JOB_IDREC"),
                                         F.col("RIGNAME").alias("rig_name"))
    lvjob  = dlt.read("lvwvtypejob").select(F.col("CODE").alias("JOBTYPE"),
                                            F.col("DESCRIPTION").alias("job_type"))

    # time-log aggregates per report (footage in metres; NPT rule per glossary)
    ops = (dlt.read("wvjobreportop")
             .withColumn("is_npt", (F.coalesce("PRODUCTIVE", F.lit(True)) == F.lit(False)) |
                                    F.col("CODENPT").isNotNull())
             .withColumn("footage_m", (F.col("DEPTHEND") - F.col("DEPTHSTART")) * F.lit(FT_TO_M))
             .groupBy("IDRECPARENT")
             .agg(F.sum("footage_m").alias("footage_m"),
                  F.sum("HRS").alias("total_hours"),
                  F.sum(F.when(F.col("is_npt"), F.col("HRS")).otherwise(0)).alias("npt_hours"),
                  F.sum(F.when(~F.col("is_npt"), F.col("HRS")).otherwise(0)).alias("on_bottom_hours")))

    # daily cost per report (resolve report-vs-job parentage per glossary)
    cost = (dlt.read("wvcost")
              .groupBy("IDRECPARENT")
              .agg(F.sum("AMOUNT").alias("daily_cost")))

    return (report.alias("r")
            .join(job.alias("j"), F.col("r.IDRECPARENT") == F.col("j.IDREC"))
            .join(well, "IDWELL", "left")
            .join(lvjob, "JOBTYPE", "left")
            .join(rig, F.col("j.IDREC") == F.col("JOB_IDREC"), "left")
            .join(ops, F.col("r.IDREC") == ops.IDRECPARENT, "left")
            .join(cost, F.col("r.IDREC") == cost.IDRECPARENT, "left")
            .select(
                F.col("r.IDREC").alias("report_id"),
                F.col("j.IDREC").alias("job_id"),
                F.col("r.IDWELL").alias("well_id"),
                F.col("WELLNAME").alias("well_name"),
                F.col("job_type"),
                F.col("rig_name"),
                F.col("r.DTTMSTART").cast("date").alias("report_date"),
                F.col("r.DAYSFROMSPUD").alias("days_from_spud"),
                (F.col("r.DEPTHMD") * F.lit(FT_TO_M)).alias("depth_md_m"),
                F.coalesce("footage_m", F.lit(0.0)).alias("footage_m"),
                F.coalesce("daily_cost", F.lit(0.0)).alias("daily_cost"),
                F.coalesce("npt_hours", F.lit(0.0)).alias("npt_hours"),
                F.coalesce("total_hours", F.lit(0.0)).alias("total_hours"),
                F.coalesce("on_bottom_hours", F.lit(0.0)).alias("on_bottom_hours"),
            ))
