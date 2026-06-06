#!/usr/bin/env python3
"""
introspect_schema.py — WellView schema introspection / draft-mapping helper.

Wraps `databricks experimental aitools tools` (query + discover-schema) to inventory a
customer's WellView schema (200-300 WV/LV/SYS tables), classify tables by prefix +
column heuristics, and emit a DRAFT mapping for the wellview-setup interview.

It DOES NOT finalize anything. Every numeric column is flagged as needing a UNIT
decision, and every coded column as needing an LV decode — those are human confirmations
in the interview (master units are configurable; codes are per-install).

Auth note: in-workspace Genie Code is already authenticated — do NOT pass --profile.
Use --profile only for local runs against ~/.databrickscfg.

Usage:
  python introspect_schema.py --catalog wellview --schema silver --output draft_mapping.json
"""
import argparse
import json
import subprocess
from typing import Any

# Canonical spine concepts and the table-name hints that suggest them.
SPINE_HINTS = {
    "well":         ["wvwellheader", "wvwell"],
    "wellbore":     ["wvwellbore"],
    "job":          ["wvjob"],
    "job_rig":      ["wvjobrig"],
    "daily_report": ["wvjobreport", "wvreport", "wvdaysummary", "wvdays"],
    "time_log":     ["wvjobreportop", "wvoperation", "wvtime", "wvjobreportact"],
    "cost":         ["wvcost", "wvjobreportcost", "wvdailycost"],
    "afe":          ["wvafe"],
    "bit_run":      ["wvbitrun"],
    "mud":          ["wvmud", "wvdailymud"],
    "survey":       ["wvsurvey"],
}

# Column-name fragments that almost certainly carry a UNIT and must be confirmed.
NUMERIC_UNIT_HINTS = ["depth", "md", "tvd", "length", "diam", "od", "id_", "weight",
                      "press", "rate", "rop", "footage", "amount", "cost", "vol", "hrs", "hours"]


def _run_query(sql: str, catalog: str, profile: str | None) -> list[dict[str, Any]]:
    cmd = ["databricks", "experimental", "aitools", "tools", "query", sql, "--output", "json"]
    if profile:
        cmd += ["--profile", profile]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True)
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError:
        return []


def _discover(table_fqn: str, profile: str | None) -> dict[str, Any]:
    cmd = ["databricks", "experimental", "aitools", "tools", "discover-schema", table_fqn]
    if profile:
        cmd += ["--profile", profile]
    out = subprocess.run(cmd, capture_output=True, text=True)
    try:
        return json.loads(out.stdout) if out.returncode == 0 else {}
    except json.JSONDecodeError:
        return {}


def classify_table(name: str) -> dict[str, str]:
    n = name.lower()
    if n.startswith("lv"):
        family = "LV-lookup"
    elif n.startswith("sys"):
        family = "SYS-config"
    elif n.startswith("wv"):
        family = "WV-data"
    else:
        family = "other"
    concept = next((c for c, hints in SPINE_HINTS.items()
                    if any(h in n for h in hints)), None)
    return {"family": family, "concept": concept or ""}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--schema", required=True)
    ap.add_argument("--output", default="draft_mapping.json")
    ap.add_argument("--profile", default=None, help="local only; omit in-workspace")
    args = ap.parse_args()

    # 1) Inventory all tables, bucketed by prefix family.
    tables = _run_query(
        f"SELECT table_name FROM system.information_schema.tables "
        f"WHERE table_schema = '{args.schema}' ORDER BY table_name",
        args.catalog, args.profile,
    )
    inventory = []
    for row in tables:
        name = row.get("table_name") or row.get("TABLE_NAME") or ""
        if not name:
            continue
        inventory.append({"table": name, **classify_table(name)})

    # 2) For the identified spine tables, discover columns + flag unit/code decisions.
    spine = {}
    for item in inventory:
        if not item["concept"]:
            continue
        fqn = f"{args.catalog}.{args.schema}.{item['table']}"
        info = _discover(fqn, args.profile)
        cols = [c.get("name", c) if isinstance(c, dict) else c
                for c in info.get("columns", [])]
        unit_decisions = [c for c in cols
                          if isinstance(c, str) and any(h in c.lower() for h in NUMERIC_UNIT_HINTS)]
        code_decisions = [c for c in cols
                          if isinstance(c, str) and c.lower().startswith("code")]
        spine[item["concept"]] = {
            "table": item["table"],
            "columns": cols,
            "UNIT_DECISIONS_NEEDED": unit_decisions,   # confirm master unit in interview
            "LV_DECODE_NEEDED": code_decisions,         # map to LV table in interview
            "parent_edge": "IDRECPARENT -> parent.IDREC (confirm parent table)",
        }

    draft = {
        "catalog": args.catalog,
        "schema": args.schema,
        "counts": {
            "total": len(inventory),
            "WV-data": sum(1 for i in inventory if i["family"] == "WV-data"),
            "LV-lookup": sum(1 for i in inventory if i["family"] == "LV-lookup"),
            "SYS-config": sum(1 for i in inventory if i["family"] == "SYS-config"),
        },
        "spine_draft": spine,
        "all_lv_tables": [i["table"] for i in inventory if i["family"] == "LV-lookup"],
        "NOTES": [
            "Every UNIT_DECISIONS_NEEDED column needs a master-unit confirmation (feet/metres, currency).",
            "Every LV_DECODE_NEEDED column needs an LV table mapped to it.",
            "Confirm the COST table parentage (job vs report) — it changes every roll-up.",
            "Confirm which metrics are stored vs calc-engine outputs.",
        ],
    }
    with open(args.output, "w") as f:
        json.dump(draft, f, indent=2)
    print(f"Wrote draft mapping for {draft['counts']['total']} tables to {args.output}")
    print(f"  WV-data={draft['counts']['WV-data']}  "
          f"LV-lookup={draft['counts']['LV-lookup']}  SYS-config={draft['counts']['SYS-config']}")
    print("Next: run the interview (interview.md), then generate_glossary.py")


if __name__ == "__main__":
    main()
