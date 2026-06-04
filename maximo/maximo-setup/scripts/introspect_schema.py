"""Profile a customer's Maximo Silver schema and produce a DRAFT for the
maximo-setup interview to confirm.

Built on the repo's cross-cutting `data-exploration` skill: it shells out to
`databricks experimental aitools tools` to find tables via information_schema and
discover each table's schema + null counts + row counts, then extracts the
data-PROVABLE facts:
  - distinct WOCLASS / STATUS / WORKTYPE values on WORKORDER
  - the SITEID list, the ASSET.CLASSSTRUCTUREID list
  - custom/extension columns (columns present in the data but NOT in the
    documented base MBO columns in maximo_comments.json)
  - which modules are populated (work mgmt, inventory, procurement, service
    desk, PM, HSE, integrity) and whether the Oil & Gas PLUSG solution is present
  - row counts + high-null columns

Everything is a DRAFT. The *meaning* of each value — which statuses are "open",
the PM-vs-CM worktype mapping, business jargon, what a custom column stores, and
the industry / how-they-use-Maximo context — is confirmed by a human in the
interview (see interview.md, Batch 0 + Batches 1-5).

In-workspace Genie Code is already authenticated to the current workspace, so
--profile is OPTIONAL (omit in-workspace; pass it only for local runs against a
~/.databrickscfg profile).

Usage (in-workspace):
    python introspect_schema.py --catalog eam --schema maximo_silver --output draft_profile.json
Usage (local):
    python introspect_schema.py --catalog eam --schema maximo_silver --profile my-workspace --output draft_profile.json

Requires Databricks CLI >= v0.294.0 (experimental aitools).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

# Statuses that are NOT "open" in stock Maximo. Used only to PROPOSE an
# open-status set (distinct STATUS minus these) — the customer confirms it,
# because "open" is org-configurable.
NON_OPEN_STATUSES = {"COMP", "CLOSE", "CAN"}

# A column is flagged "custom" when its null fraction is below this — i.e. it
# actually carries data — purely to order the custom-column list by usefulness.
HIGH_NULL_FRACTION = 0.5

# Which populated MBO tables indicate a module is in use. Presence + rows = "in use".
MODULE_INDICATORS = {
    "work_management": ["WORKORDER"],
    "preventive_maintenance": ["PM"],
    "inventory_storeroom": ["INVENTORY", "INVBALANCES"],
    "procurement": ["PO", "PR", "INVOICE", "POLINE"],
    "service_desk": ["SR", "TICKET"],
    "asset_integrity": ["ASSETMETER", "METERREADING"],
    "hse": ["INCIDENT", "PLUSGPERMITWORK"],
}


def _run(cmd: list[str]) -> str:
    """Run a CLI command, returning stdout. Raises RuntimeError on failure."""
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"command failed: {' '.join(cmd)}\n{proc.stderr.strip()}")
    return proc.stdout


def _aitools(sub: list[str], profile: str | None) -> object:
    """Invoke `databricks experimental aitools tools <sub...>` with JSON output.

    --profile is appended only when provided; omitted for in-workspace ambient auth.
    """
    cmd = ["databricks", "experimental", "aitools", "tools", *sub, "--output", "json"]
    if profile:
        cmd += ["--profile", profile]
    return json.loads(_run(cmd))


def _query(sql: str, profile: str | None) -> list[dict]:
    out = _aitools(["query", sql], profile)
    # data-exploration query returns a list of row dicts (or {"rows": [...]}).
    if isinstance(out, dict):
        return out.get("rows", out.get("result", []))
    return out


def load_base_columns() -> dict[str, set[str]]:
    """Documented base MBO columns, keyed by UPPER table name, from maximo_comments.json."""
    path = Path(__file__).parent / "maximo_comments.json"
    data = json.loads(path.read_text())
    return {t.upper(): {c.upper() for c in spec.get("columns", {})} for t, spec in data.items()}


def find_tables(catalog: str, schema: str, profile: str | None) -> list[str]:
    sql = (
        "SELECT table_name FROM system.information_schema.tables "
        f"WHERE table_catalog = '{catalog}' AND table_schema = '{schema}'"
    )
    rows = _query(sql, profile)
    return [r["table_name"] for r in rows if r.get("table_name")]


def discover(fqtn: str, profile: str | None) -> dict:
    out = _aitools(["discover-schema", fqtn], profile)
    # discover-schema returns one table's info; normalize to a dict.
    if isinstance(out, list):
        return out[0] if out else {}
    return out


def _distinct(fqtn: str, column: str, profile: str | None, limit: int = 200) -> list:
    sql = f"SELECT DISTINCT {column} AS v FROM {fqtn} WHERE {column} IS NOT NULL LIMIT {limit}"
    return [r["v"] for r in _query(sql, profile) if r.get("v") is not None]


def _has_rows(fqtn: str, profile: str | None) -> bool:
    return bool(_query(f"SELECT 1 AS v FROM {fqtn} LIMIT 1", profile))


def build_draft(catalog: str, schema: str, profile: str | None) -> dict:
    base_cols = load_base_columns()
    present = find_tables(catalog, schema, profile)
    present_upper = {t.upper(): t for t in present}  # UPPER -> actual-cased name

    draft: dict = {
        "catalog": catalog,
        "schema": schema,
        "tables_present": sorted(present),
        "usage_profile": {"_confirm": "Confirm industry + module usage in interview Batch 0"},
        "work_order": {},
        "asset": {},
        "custom_columns": {},
        "stats": {},
        "gaps_for_interview": [],
        "errors": [],
    }

    def fq(table_upper: str) -> str | None:
        actual = present_upper.get(table_upper)
        return f"{catalog}.{schema}.{actual}" if actual else None

    # --- usage profile: which modules are populated, PLUSG presence -----------
    modules: dict = {}
    for module, indicators in MODULE_INDICATORS.items():
        found = [t for t in indicators if t in present_upper]
        populated = False
        for t in found:
            try:
                populated = populated or _has_rows(fq(t), profile)
            except RuntimeError as e:
                draft["errors"].append(f"{t} row-check: {e}")
        modules[module] = {"indicator_tables_present": found, "populated": populated}
    draft["usage_profile"]["modules_in_use"] = modules
    draft["usage_profile"]["plusg_present"] = any(t.startswith("PLUSG") for t in present_upper)

    # --- WORKORDER distinct values + custom columns + stats -------------------
    wo = fq("WORKORDER")
    if wo:
        try:
            draft["work_order"]["woclass_values"] = _distinct(wo, "WOCLASS", profile)
            statuses = _distinct(wo, "STATUS", profile)
            draft["work_order"]["status_values"] = statuses
            draft["work_order"]["proposed_open_statuses"] = sorted(
                s for s in statuses if str(s).upper() not in NON_OPEN_STATUSES
            )
            draft["work_order"]["_open_status_note"] = (
                "PROPOSAL = all STATUS minus COMP/CLOSE/CAN. Confirm with the customer."
            )
            draft["work_order"]["worktype_values"] = _distinct(wo, "WORKTYPE", profile)
            draft["work_order"]["siteid_values"] = _distinct(wo, "SITEID", profile)
        except RuntimeError as e:
            draft["errors"].append(f"WORKORDER distinct values: {e}")
    else:
        draft["gaps_for_interview"].append("WORKORDER table not found — confirm catalog/schema.")

    # --- ASSET class list -----------------------------------------------------
    asset = fq("ASSET")
    if asset:
        try:
            draft["asset"]["classstructureid_values"] = _distinct(asset, "CLASSSTRUCTUREID", profile)
        except RuntimeError as e:
            draft["errors"].append(f"ASSET.CLASSSTRUCTUREID: {e}")

    # --- custom-column detection + null stats on the core MBOs ----------------
    for table_upper in ("WORKORDER", "ASSET", "LOCATIONS"):
        fqtn = fq(table_upper)
        if not fqtn or table_upper not in base_cols:
            continue
        try:
            info = discover(fqtn, profile)
        except RuntimeError as e:
            draft["errors"].append(f"discover {table_upper}: {e}")
            continue
        cols = info.get("columns", [])
        row_count = info.get("row_count")
        custom, high_null = [], []
        for c in cols:
            name = c.get("name", "")
            if name.upper() not in base_cols[table_upper]:
                custom.append(name)
            null_frac = c.get("null_fraction")
            if null_frac is None and row_count and c.get("null_count") is not None:
                null_frac = c["null_count"] / row_count if row_count else None
            if null_frac is not None and null_frac > HIGH_NULL_FRACTION:
                high_null.append(name)
        if custom:
            draft["custom_columns"][table_upper] = custom
        draft["stats"][table_upper] = {"row_count": row_count, "high_null_columns": high_null}

    # --- interview gap list (the un-inferable semantics) ----------------------
    draft["gaps_for_interview"] += [
        "Batch 0: confirm industry, industry-solution add-ons (PLUSG?), and which modules above are actually used + for what.",
        "Confirm which STATUS values count as 'open' (see work_order.proposed_open_statuses).",
        "Map WORKTYPE values to corrective / preventive / emergency / regulatory.",
        "Label SITEID values with business site names (e.g. 'Mainline').",
        "Label CLASSSTRUCTUREID values with business asset-class names (e.g. 'centrifugal pump').",
        "Describe each detected custom column (what it stores, who uses it).",
    ]
    return draft


def main() -> int:
    ap = argparse.ArgumentParser(description="Profile a Maximo Silver schema into a draft for the maximo-setup interview.")
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--schema", required=True)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--profile", default=None,
                    help="Databricks CLI profile. OMIT in-workspace (ambient auth); set only for local runs.")
    args = ap.parse_args()

    try:
        draft = build_draft(args.catalog, args.schema, args.profile)
    except RuntimeError as e:
        print(f"profiling failed: {e}", file=sys.stderr)
        return 1

    args.output.write_text(json.dumps(draft, indent=2))
    n_tables = len(draft["tables_present"])
    n_custom = sum(len(v) for v in draft["custom_columns"].values())
    print(f"wrote {args.output}: {n_tables} tables, {n_custom} custom columns detected, "
          f"PLUSG={draft['usage_profile']['plusg_present']}")
    if draft["errors"]:
        print(f"{len(draft['errors'])} non-fatal errors recorded in the draft.", file=sys.stderr)
    print("NEXT: confirm the gaps in draft_profile.json during the maximo-setup interview "
          "(Batch 0 first), then feed the confirmed answers.json to generate_glossary.py.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
