"""Introspect a customer's PODS-ish schema and propose a draft mapping to
canonical PODS concepts.

Built on the repo's cross-cutting `data-exploration` skill (../../_common/data-exploration/):
it shells out to `databricks experimental aitools tools` to find tables via
information_schema and discover each table's schema + samples, then applies
heuristics to guess which canonical PODS feature class each table maps to.

The output is a DRAFT for the pods-setup interview to confirm — especially the
UNIT of each measure column, which cannot be inferred reliably and is flagged
for human decision.

Usage:
    python introspect_schema.py --catalog pipeline --schema pods_silver \
        --profile my-workspace --output draft_mapping.json
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


# --- canonical-concept heuristics ------------------------------------------
# Column-name patterns that hint at a canonical PODS concept. Intentionally
# permissive — this is a draft for human confirmation, not the final mapping.
ROUTE_KEY_PATTERNS = [r"route.?id", r"line.?id", r"line.?no", r"line.?ref", r"pipe.?id"]
MEASURE_PATTERNS = [r"measure", r"\bmd\b", r"station", r"stn", r"begin.?m\b", r"end.?m\b", r"milepost", r"\bmp\b"]
ANOMALY_HINTS = [r"anomal", r"ili", r"feature", r"pig", r"metal.?loss", r"dent", r"crack"]
RUN_HINTS = [r"run", r"inspection", r"insp", r"survey"]
HCA_HINTS = [r"hca", r"high.?consequence", r"consequence"]
CP_HINTS = [r"\bcp\b", r"cathodic", r"rectifier", r"test.?station"]
PIPE_ATTR_HINTS = [r"segment", r"pipe", r"\bod\b", r"diameter", r"wall", r"smys", r"maop", r"grade"]


def _matches(name: str, patterns: list[str]) -> bool:
    return any(re.search(p, name, re.IGNORECASE) for p in patterns)


def _run(cmd: list[str]) -> str:
    """Run a CLI command, returning stdout. Raises on failure."""
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"command failed: {' '.join(cmd)}\n{proc.stderr}")
    return proc.stdout


def find_tables(catalog: str, schema: str, profile: str) -> list[dict]:
    """Find all tables in the schema via information_schema (data-exploration pattern)."""
    sql = (
        "SELECT table_catalog, table_schema, table_name "
        "FROM system.information_schema.tables "
        f"WHERE table_catalog = '{catalog}' AND table_schema = '{schema}'"
    )
    out = _run([
        "databricks", "experimental", "aitools", "tools", "query", sql,
        "--profile", profile, "--output", "json",
    ])
    return json.loads(out)


def discover_schema(fqtn: str, profile: str) -> dict:
    """Discover a table's columns/types/samples/null-counts via discover-schema."""
    out = _run([
        "databricks", "experimental", "aitools", "tools", "discover-schema", fqtn,
        "--profile", profile, "--output", "json",
    ])
    return json.loads(out)


def classify_table(table_name: str, columns: list[str]) -> str:
    """Guess the canonical PODS concept for a table from its name + columns."""
    name = table_name.lower()
    has_route = any(_matches(c, ROUTE_KEY_PATTERNS) for c in columns)
    has_measure = any(_matches(c, MEASURE_PATTERNS) for c in columns)
    if _matches(name, ANOMALY_HINTS) and has_measure:
        return "ILI_ANOMALY"
    if _matches(name, RUN_HINTS):
        return "ILI_RUN"
    if _matches(name, HCA_HINTS):
        return "HCA_SEGMENT"
    if _matches(name, CP_HINTS):
        return "CP"
    if _matches(name, PIPE_ATTR_HINTS):
        return "PIPE_ATTRIBUTES"
    if "centerline" in name or ("continuous_meas" in name):
        return "CENTERLINE / CONTINUOUS_MEAS_NETWORK"
    if "station" in name and has_route:
        return "ENGINEERING_STATION_NETWORK"
    if has_route and has_measure:
        return "ROUTE_EVENT (unclassified)"
    return "UNKNOWN"


def build_draft(catalog: str, schema: str, profile: str) -> dict:
    tables = find_tables(catalog, schema, profile)
    draft = {"catalog": catalog, "schema": schema, "tables": [], "unit_decisions_needed": []}
    for t in tables:
        fqtn = f"{t['table_catalog']}.{t['table_schema']}.{t['table_name']}"
        try:
            info = discover_schema(fqtn, profile)
        except RuntimeError as e:
            draft["tables"].append({"table": fqtn, "error": str(e)})
            continue
        columns = [c["name"] for c in info.get("columns", [])]
        concept = classify_table(t["table_name"], columns)
        route_keys = [c for c in columns if _matches(c, ROUTE_KEY_PATTERNS)]
        measure_cols = [c for c in columns if _matches(c, MEASURE_PATTERNS)]
        draft["tables"].append({
            "table": fqtn,
            "guessed_concept": concept,
            "route_key_candidates": route_keys,
            "measure_columns": measure_cols,
            "columns": columns,
        })
        # Every measure column needs an explicit unit decision (ft vs m) — flag it.
        for mc in measure_cols:
            draft["unit_decisions_needed"].append({
                "column": f"{fqtn}.{mc}",
                "unit": "UNKNOWN — confirm ft or m in the interview",
            })
    return draft


def main() -> int:
    ap = argparse.ArgumentParser(description="Draft PODS schema mapping via Databricks data-exploration tools.")
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--schema", required=True)
    ap.add_argument("--profile", required=True, help="Databricks CLI profile (workspace).")
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()

    try:
        draft = build_draft(args.catalog, args.schema, args.profile)
    except RuntimeError as e:
        print(f"introspection failed: {e}", file=sys.stderr)
        return 1

    args.output.write_text(json.dumps(draft, indent=2))
    n_tables = len(draft["tables"])
    n_units = len(draft["unit_decisions_needed"])
    print(f"wrote {args.output}: {n_tables} tables, {n_units} measure columns needing a UNIT decision")
    print("NEXT: confirm guessed_concept and EVERY unit in the pods-setup interview before generating the glossary.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
