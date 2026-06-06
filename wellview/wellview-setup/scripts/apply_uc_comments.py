#!/usr/bin/env python3
"""
apply_uc_comments.py — preview/apply Unity Catalog comments for WellView Silver tables.

REPO CENTRAL SAFETY RULE: this modifies customer-owned objects, so it defaults to PREVIEW
(--apply=false). It NEVER applies without an explicit --apply flag, and the skill must show
the previewed diff and get explicit user approval before that flag is used.

Reads comment content from wellview_comments.json. The MASTER UNIT of each numeric column
belongs in its column comment so Genie sees it on DESCRIBE.

Usage:
  # preview only (default) — prints every statement, writes nothing
  python apply_uc_comments.py --catalog wellview --silver-schema silver

  # emit a hand-runnable SQL file for warehouse-only customers
  python apply_uc_comments.py --catalog wellview --silver-schema silver --emit-sql comments.sql

  # apply (gated) — only after the user approves the preview
  python apply_uc_comments.py --catalog wellview --silver-schema silver --apply --warehouse-id <id>

Defers UC ALTER mechanics knowledge to the platform skill databricks-unity-catalog.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
COMMENTS = os.path.join(HERE, "..", "wellview_comments.json")


def _esc(s: str) -> str:
    return s.replace("'", "''")


def build_statements(spec: dict, catalog: str, schema: str) -> list[str]:
    stmts = []
    for table, body in spec.get("tables", {}).items():
        fqn = f"{catalog}.{schema}.{table}"
        if body.get("comment"):
            stmts.append(f"COMMENT ON TABLE {fqn} IS '{_esc(body['comment'])}';")
        for col, comment in body.get("columns", {}).items():
            stmts.append(
                f"ALTER TABLE {fqn} ALTER COLUMN {col} COMMENT '{_esc(comment)}';"
            )
    return stmts


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--silver-schema", required=True)
    ap.add_argument("--apply", action="store_true",
                    help="GATED. Only after the user approves the preview. Requires --warehouse-id.")
    ap.add_argument("--warehouse-id", default=None)
    ap.add_argument("--emit-sql", default=None, help="write statements to a .sql file instead of applying")
    args = ap.parse_args()

    with open(COMMENTS) as f:
        spec = json.load(f)
    stmts = build_statements(spec, args.catalog, args.silver_schema)

    if args.emit_sql:
        with open(args.emit_sql, "w") as f:
            f.write("-- WellView UC comments. Review before running in SQL Editor.\n")
            f.write("\n".join(stmts) + "\n")
        print(f"Wrote {len(stmts)} statements to {args.emit_sql} (nothing applied).")
        return

    if not args.apply:
        print(f"-- PREVIEW ONLY ({len(stmts)} statements). Nothing applied.")
        print("-- Review with the user and get explicit approval before re-running with --apply.\n")
        print("\n".join(stmts))
        return

    if not args.warehouse_id:
        sys.exit("ERROR: --apply requires --warehouse-id.")

    # Apply only reaches here after explicit approval + --apply.
    try:
        from databricks.sdk import WorkspaceClient
    except ImportError:
        sys.exit("ERROR: databricks-sdk not installed. `pip install databricks-sdk`.")

    w = WorkspaceClient()
    print(f"Applying {len(stmts)} statements via warehouse {args.warehouse_id} ...")
    for s in stmts:
        w.statement_execution.execute_statement(warehouse_id=args.warehouse_id, statement=s)
    print("Done. Verify with: DESCRIBE TABLE EXTENDED <table>; or system.information_schema.columns.")


if __name__ == "__main__":
    main()
