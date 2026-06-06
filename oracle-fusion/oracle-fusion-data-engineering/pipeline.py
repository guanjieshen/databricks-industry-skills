"""Oracle Fusion Bronze -> Silver SDP pipeline SKETCH.

Illustrative Lakeflow Spark Declarative Pipeline source for landing Oracle
Fusion Cloud ERP extracts into a clean canonical Silver layer. This is a
PATTERN, not a tutorial — it shows the Fusion-specific modeling decisions
(apply-changes vs append, _ALL multi-org handling, PVO dedup keys, currency/
period pass-through) for representative GL + PO tables. It DEFERS all Lakeflow
SDP mechanics (AutoCDC semantics, Auto Loader options, expectations API,
pipeline config/scheduling) to the platform skill:
    databricks-spark-declarative-pipelines
Load that skill for the actual build; load oracle-fusion-overview +
oracle-fusion-data-engineering for the modeling rules applied below.

LANDING-AGNOSTIC RULE: Fusion is SaaS. Bronze is whatever the customer's
landing pattern produced — BICC Public View Object (PVO) extracts, an FDI/FAW
star schema, or base-table mirrors. The canonical EBS-style names below
(GL_JE_HEADERS, PO_HEADERS_ALL) are RESOLVED to the customer's physical objects
via the <customer>-oracle-fusion-glossary physical->canonical mapping. The
bronze() helper centralizes that resolution.

Universal Fusion mechanics applied here (owned by oracle-fusion-overview /
oracle-fusion-ledger-coa, NOT re-taught):
  * _ALL tables keep ALL business units in Silver; BU scope is a consumer concern.
  * Entered vs accounted currency columns pass through unmodified; no conversion here.
  * Posted/unposted (STATUS) and cancel/close flags are kept as columns, not filtered.
  * sequence_by uses LAST_UPDATE_DATE (Fusion audit column) where present.
  * BICC incremental does NOT capture hard deletes — see the reconcile note at the end.
"""
from __future__ import annotations

import dlt
from pyspark.sql import functions as F


# -----------------------------------------------------------------------------
# Pipeline configuration — set via the Lakeflow pipeline settings UI:
#   LANDING_PATTERN = "bicc_pvo" | "fdi" | "base_mirror"
#   BRONZE_PATH     = e.g. "bronze.oracle_fusion"
#   SEQUENCE_COLUMN = audit column for ordering (default Fusion: LAST_UPDATE_DATE)
# The physical->canonical name map comes from the customer glossary; here it is
# represented as PHYSICAL_NAMES (populate from <customer>-oracle-fusion-glossary).
# -----------------------------------------------------------------------------

LANDING_PATTERN = spark.conf.get("LANDING_PATTERN", "bicc_pvo")
BRONZE_PATH = spark.conf.get("BRONZE_PATH", "bronze.oracle_fusion")
SEQUENCE_COLUMN = spark.conf.get("SEQUENCE_COLUMN", "LAST_UPDATE_DATE")

# Canonical entity -> physical Bronze object. POPULATE from the customer glossary
# physical->canonical mapping. Defaults assume base-mirror (verbatim EBS names).
PHYSICAL_NAMES = {
    "GL_JE_HEADERS": "gl_je_headers",
    "GL_JE_LINES": "gl_je_lines",
    "GL_BALANCES": "gl_balances",
    "GL_CODE_COMBINATIONS": "gl_code_combinations",
    "GL_DAILY_RATES": "gl_daily_rates",
    "PO_HEADERS_ALL": "po_headers_all",
    "PO_LINES_ALL": "po_lines_all",
    "PO_DISTRIBUTIONS_ALL": "po_distributions_all",
    "POZ_SUPPLIERS": "poz_suppliers",
}


def bronze(canonical: str):
    """Read a Bronze table by CANONICAL name, resolving the physical object via
    the landing-pattern mapping. Centralizes the landing-agnostic rule so the
    table definitions below speak canonical Fusion."""
    physical = PHYSICAL_NAMES.get(canonical, canonical.lower())
    # All three landing patterns land as Delta in Bronze; FDI rows may need a
    # rename step (handled upstream) so the canonical columns line up.
    return dlt.read_stream(f"{BRONZE_PATH}.{physical}")


# =============================================================================
# GL_JE_HEADERS — APPLY CHANGES (header state evolves: unposted -> posted)
# Keep STATUS (P/U) and ACTUAL_FLAG (A/B/E) as columns; do NOT filter here.
# =============================================================================

@dlt.view(name="gl_je_headers_src")
def gl_je_headers_src():
    return bronze("GL_JE_HEADERS")


dlt.create_streaming_table(
    name="gl_je_headers",
    comment="Silver GL_JE_HEADERS — journal headers, current state. Posted (STATUS='P') and unposted both kept; filter at consumption. Scope by LEDGER_ID.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="gl_je_headers",
    source="gl_je_headers_src",
    keys=["JE_HEADER_ID"],
    sequence_by=F.col(SEQUENCE_COLUMN),
    stored_as_scd_type=1,
)


# =============================================================================
# GL_JE_LINES — APPLY CHANGES on (header, line). Entered + accounted amounts
# pass through unmodified — no currency conversion at Silver.
# =============================================================================

@dlt.view(name="gl_je_lines_src")
def gl_je_lines_src():
    return bronze("GL_JE_LINES")


dlt.create_streaming_table(
    name="gl_je_lines",
    comment="Silver GL_JE_LINES — journal lines. ENTERED_DR/CR (document) and ACCOUNTED_DR/CR (ledger) passed through; never summed across currencies here. CODE_COMBINATION_ID joins to the COA.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="gl_je_lines",
    source="gl_je_lines_src",
    keys=["JE_HEADER_ID", "JE_LINE_NUM"],
    sequence_by=F.col(SEQUENCE_COLUMN),
    stored_as_scd_type=1,
)


# =============================================================================
# GL_BALANCES — APPLY CHANGES on the full balance-slice key. Open-period rows
# are re-extracted as the balance changes; the slice key keeps the latest.
# =============================================================================

@dlt.view(name="gl_balances_src")
def gl_balances_src():
    return bronze("GL_BALANCES")


dlt.create_streaming_table(
    name="gl_balances",
    comment="Silver GL_BALANCES — balances by ledger + CCID + currency + period + actual_flag. One row per slice.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="gl_balances",
    source="gl_balances_src",
    keys=["LEDGER_ID", "CODE_COMBINATION_ID", "CURRENCY_CODE", "PERIOD_NAME", "ACTUAL_FLAG"],
    sequence_by=F.col(SEQUENCE_COLUMN),
    stored_as_scd_type=1,
)


# =============================================================================
# GL_CODE_COMBINATIONS — SCD Type 2 (COA combos are slowly-changing reference;
# SCD2 answers "what was the account's enabled flag on date X"). Segment MEANING
# is customer config — resolved by oracle-fusion-ledger-coa, not here.
# =============================================================================

@dlt.view(name="gl_code_combinations_src")
def gl_code_combinations_src():
    return bronze("GL_CODE_COMBINATIONS")


dlt.create_streaming_table(
    name="gl_code_combinations",
    comment="Silver GL_CODE_COMBINATIONS — SCD2 account combinations (CCID + SEGMENT1..30 + CONCATENATED_SEGMENTS). Segment meaning is customer config (see glossary / ledger-coa).",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="gl_code_combinations",
    source="gl_code_combinations_src",
    keys=["CODE_COMBINATION_ID"],
    sequence_by=F.col(SEQUENCE_COLUMN),
    stored_as_scd_type=2,
)


# =============================================================================
# GL_DAILY_RATES — APPEND-ONLY (one row per from/to/date/type; written once).
# Never apply-changes — rate history is immutable.
# =============================================================================

@dlt.table(
    name="gl_daily_rates",
    comment="Silver GL_DAILY_RATES — append-only currency conversion rates (FROM/TO/CONVERSION_DATE/CONVERSION_TYPE). Used by oracle-fusion-ledger-coa for conversion.",
    table_properties={"quality": "silver"},
)
def gl_daily_rates():
    return bronze("GL_DAILY_RATES")


# =============================================================================
# PO_HEADERS_ALL — APPLY CHANGES. _ALL = MULTI-ORG: keep ALL business units;
# scope by PRC_BU_ID at consumption. Keep CANCEL_FLAG / CLOSED_CODE as columns.
# =============================================================================

@dlt.view(name="po_headers_all_src")
def po_headers_all_src():
    return bronze("PO_HEADERS_ALL")


dlt.create_streaming_table(
    name="po_headers_all",
    comment="Silver PO_HEADERS_ALL — PO headers, current state, ALL business units (scope by PRC_BU_ID). Canceled/closed POs kept; filter at consumption.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="po_headers_all",
    source="po_headers_all_src",
    keys=["PO_HEADER_ID"],
    sequence_by=F.col(SEQUENCE_COLUMN),
    stored_as_scd_type=1,
)


# =============================================================================
# PO_LINES_ALL — APPLY CHANGES on (header, line).
# =============================================================================

@dlt.view(name="po_lines_all_src")
def po_lines_all_src():
    return bronze("PO_LINES_ALL")


dlt.create_streaming_table(
    name="po_lines_all",
    comment="Silver PO_LINES_ALL — PO lines, current state. Multi-org via parent header.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="po_lines_all",
    source="po_lines_all_src",
    keys=["PO_HEADER_ID", "PO_LINE_ID"],
    sequence_by=F.col(SEQUENCE_COLUMN),
    stored_as_scd_type=1,
)


# =============================================================================
# PO_DISTRIBUTIONS_ALL — APPLY CHANGES. Carries the charged CODE_COMBINATION_ID
# (the COA join for spend-by-account / spend-by-cost-center).
# =============================================================================

@dlt.view(name="po_distributions_all_src")
def po_distributions_all_src():
    return bronze("PO_DISTRIBUTIONS_ALL")


dlt.create_streaming_table(
    name="po_distributions_all",
    comment="Silver PO_DISTRIBUTIONS_ALL — distributions with CODE_COMBINATION_ID (charged account). Join to GL_CODE_COMBINATIONS for spend-by-account.",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="po_distributions_all",
    source="po_distributions_all_src",
    keys=["PO_DISTRIBUTION_ID"],
    sequence_by=F.col(SEQUENCE_COLUMN),
    stored_as_scd_type=1,
)


# =============================================================================
# POZ_SUPPLIERS — SCD Type 2 (supplier master; track attribute history).
# =============================================================================

@dlt.view(name="poz_suppliers_src")
def poz_suppliers_src():
    return bronze("POZ_SUPPLIERS")


dlt.create_streaming_table(
    name="poz_suppliers",
    comment="Silver POZ_SUPPLIERS — SCD2 supplier master (VENDOR_ID).",
    table_properties={"quality": "silver"},
)
dlt.apply_changes(
    target="poz_suppliers",
    source="poz_suppliers_src",
    keys=["VENDOR_ID"],
    sequence_by=F.col(SEQUENCE_COLUMN),
    stored_as_scd_type=2,
)


# =============================================================================
# DELETES-NOT-CAPTURED RECONCILE (BICC incremental only) — SKETCH
# -----------------------------------------------------------------------------
# BICC incremental extracts catch INSERT/UPDATE only; a row hard-deleted in
# Fusion simply stops appearing and lingers in Silver. If the customer has NO
# Deleted-Record extract, run a PERIODIC FULL RELOAD reconcile (outside this
# streaming pipeline, e.g. a scheduled job): anti-join the latest full snapshot
# against the Silver table and tombstone keys present in Silver but absent from
# the snapshot. This is intentionally NOT modeled as a streaming table — it is a
# batch reconcile. See oracle-fusion-data-quality for the extract-gap probe and
# silver-tables.md "Deletes-not-captured note" for the options.
# =============================================================================
