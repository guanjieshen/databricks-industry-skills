"""Apply standardized Unity Catalog table and column comments to Maximo Silver tables.

Reads a JSON file describing the canonical Maximo MBO descriptions and runs
`ALTER TABLE ... ALTER COLUMN ... COMMENT '...'` against the customer's UC.

Usage:
    python apply_uc_comments.py \
        --catalog eam \
        --schema maximo_silver \
        --comments-file maximo_comments.json \
        [--dry-run]

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


def apply_comments(
    client: WorkspaceClient,
    warehouse_id: str,
    catalog: str,
    schema: str,
    comments: dict,
    dry_run: bool,
) -> int:
    """Returns the number of statements executed (or that would have been)."""
    statements: list[str] = []

    for table_name, spec in comments.items():
        fq = f"`{catalog}`.`{schema}`.`{table_name}`"

        if "table_comment" in spec:
            statements.append(
                f"COMMENT ON TABLE {fq} IS {sql_literal(spec['table_comment'])}"
            )

        for col, col_comment in spec.get("columns", {}).items():
            statements.append(
                f"ALTER TABLE {fq} ALTER COLUMN `{col}` COMMENT {sql_literal(col_comment)}"
            )

    if dry_run:
        for s in statements:
            print(f"-- [dry-run]\n{s};\n")
        return len(statements)

    for s in statements:
        client.statement_execution.execute_statement(
            warehouse_id=warehouse_id,
            statement=s,
            wait_timeout="30s",
        )
    print(f"applied {len(statements)} comment statements to {catalog}.{schema}")
    return len(statements)


def sql_literal(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def main():
    parser = argparse.ArgumentParser(description="Apply UC comments to Maximo Silver tables.")
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--schema", required=True)
    parser.add_argument("--comments-file", required=True, type=Path)
    parser.add_argument("--warehouse-id", help="SQL warehouse ID for executing comment DDL. Required unless --dry-run.")
    parser.add_argument("--dry-run", action="store_true", help="Print statements instead of executing.")
    args = parser.parse_args()

    comments = json.loads(args.comments_file.read_text())
    print(f"loaded {len(comments)} tables from {args.comments_file}")

    if args.dry_run:
        apply_comments(None, "", args.catalog, args.schema, comments, dry_run=True)
        return 0

    if not args.warehouse_id:
        print("--warehouse-id required for non-dry-run execution", file=sys.stderr)
        return 2

    client = WorkspaceClient()
    apply_comments(client, args.warehouse_id, args.catalog, args.schema, comments, dry_run=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
