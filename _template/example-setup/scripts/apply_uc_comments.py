"""Apply standardized UC table and column comments for the <source> family.

SAFETY: PREVIEW (no writes) by default. Modifies Unity Catalog ONLY when
--apply is passed, which must never be used without the user's explicit
approval of the previewed statements.

Usage:
    # 1) preview (default — safe, no writes). Show this output to the user:
    python apply_uc_comments.py --catalog <cat> --schema <schema> \
        --comments-file example_comments.json

    # 2) ONLY after explicit approval, apply for real:
    python apply_uc_comments.py --catalog <cat> --schema <schema> \
        --comments-file example_comments.json --apply --warehouse-id <id>

Reference implementation: ../../maximo/maximo-setup/scripts/apply_uc_comments.py
(replace this skeleton with that pattern, parameterized for your source).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def build_statements(catalog: str, schema: str, comments: dict) -> list[str]:
    statements: list[str] = []
    for table, spec in comments.items():
        fq = f"`{catalog}`.`{schema}`.`{table}`"
        if "table_comment" in spec:
            statements.append(
                f"COMMENT ON TABLE {fq} IS {sql_literal(spec['table_comment'])}"
            )
        for col, col_comment in spec.get("columns", {}).items():
            statements.append(
                f"ALTER TABLE {fq} ALTER COLUMN `{col}` COMMENT {sql_literal(col_comment)}"
            )
    return statements


def sql_literal(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Preview (default) or apply UC comments. PREVIEW writes nothing."
    )
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--schema", required=True)
    parser.add_argument("--comments-file", required=True, type=Path)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write to Unity Catalog. Use ONLY after explicit user approval.",
    )
    parser.add_argument("--warehouse-id", help="SQL warehouse ID. Required with --apply.")
    args = parser.parse_args()

    comments = json.loads(args.comments_file.read_text())
    statements = build_statements(args.catalog, args.schema, comments)
    print(f"loaded {len(comments)} tables; {len(statements)} statements\n")

    if not args.apply:
        print(
            "PREVIEW ONLY — no changes written. Review with the user, then re-run "
            "with --apply --warehouse-id <id> ONLY after they approve:\n"
        )
        for s in statements:
            print(f"{s};\n")
        return 0

    if not args.warehouse_id:
        print("--warehouse-id is required with --apply", file=sys.stderr)
        return 2

    from databricks.sdk import WorkspaceClient  # type: ignore

    client = WorkspaceClient()
    for s in statements:
        client.statement_execution.execute_statement(
            warehouse_id=args.warehouse_id, statement=s, wait_timeout="30s"
        )
    print(f"applied {len(statements)} statements to {args.catalog}.{args.schema}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
