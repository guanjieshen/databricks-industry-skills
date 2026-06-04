"""Apply standardized Unity Catalog table and column comments to Maximo Silver tables.

Reads a JSON file describing the canonical Maximo MBO descriptions and runs
`ALTER TABLE ... ALTER COLUMN ... COMMENT '...'` against the customer's UC.

SAFETY: this is a PREVIEW (dry run) by default — it prints the COMMENT/ALTER
statements and writes NOTHING. It modifies Unity Catalog ONLY when you pass
--apply, which must never be used without the user's explicit approval of the
previewed statements.

Usage:
    # 1) preview (default — safe, no writes). Show this to the user:
    python apply_uc_comments.py --catalog eam --schema maximo_silver \
        --comments-file maximo_comments.json
    # 2) ONLY after the user explicitly approves, apply for real:
    python apply_uc_comments.py --catalog eam --schema maximo_silver \
        --comments-file maximo_comments.json --apply --warehouse-id <id>

The comments file shape (see maximo_comments.json):

    {
      "WORKORDER": {
        "table_comment": "...",
        "columns": {
          "WONUM": "...",
          "WOCLASS": "...",
          ...
        }
      },
      ...
    }
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from databricks.sdk import WorkspaceClient


def build_statements(catalog: str, schema: str, comments: dict) -> list[str]:
    """Build the COMMENT/ALTER statements (no execution)."""
    statements: list[str] = []
    for table_name, spec in comments.items():
        fq = f"`{catalog}`.`{schema}`.`{table_name}`"
        if "table_comment" in spec:
            statements.append(f"COMMENT ON TABLE {fq} IS {sql_literal(spec['table_comment'])}")
        for col, col_comment in spec.get("columns", {}).items():
            statements.append(
                f"ALTER TABLE {fq} ALTER COLUMN `{col}` COMMENT {sql_literal(col_comment)}"
            )
    return statements


def sql_literal(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def main():
    parser = argparse.ArgumentParser(
        description="Preview (default) or apply UC comments on Maximo Silver tables. PREVIEW writes nothing.")
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--schema", required=True)
    parser.add_argument("--comments-file", required=True, type=Path)
    parser.add_argument("--apply", action="store_true",
                        help="Write the comments to Unity Catalog. Use ONLY after the user explicitly approves the preview. Omit to preview.")
    parser.add_argument("--warehouse-id", help="SQL warehouse ID. Required with --apply.")
    args = parser.parse_args()

    comments = json.loads(args.comments_file.read_text())
    statements = build_statements(args.catalog, args.schema, comments)
    print(f"loaded {len(comments)} tables from {args.comments_file}; {len(statements)} comment statements\n")

    if not args.apply:
        print("PREVIEW ONLY — no changes written. Review these with the user, then re-run with "
              "--apply --warehouse-id <id> ONLY after they approve:\n")
        for s in statements:
            print(f"{s};\n")
        return 0

    if not args.warehouse_id:
        print("--warehouse-id is required with --apply", file=sys.stderr)
        return 2

    client = WorkspaceClient()
    for s in statements:
        client.statement_execution.execute_statement(
            warehouse_id=args.warehouse_id, statement=s, wait_timeout="30s",
        )
    print(f"applied {len(statements)} comment statements to {args.catalog}.{args.schema}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
