"""Apply standardized Unity Catalog table and column comments to Oracle Fusion Silver tables.

Reads a JSON file describing the canonical Fusion table/column descriptions and
either prints them for review (default PREVIEW) or writes them directly to UC
via the Databricks SDK (--apply).

SAFETY: PREVIEW (no writes) is the DEFAULT. Unity Catalog is modified ONLY when
--apply is passed, which must never be used without the user's explicit approval
of the previewed statements (per the preview-then-apply flow in SKILL.md
§Optional: UC comment registration). This mirrors the repo-wide rule that any
script writing to existing UC objects defaults to a no-op preview.

Usage:
    # 1) PREVIEW (default — safe, no writes). Show this output to the user:
    python apply_uc_comments.py --catalog <cat> --schema <silver-schema> \
        --comments-file example_comments.json

    # 2) ONLY after explicit user approval (Checkpoint 2), apply for real:
    python apply_uc_comments.py --catalog <cat> --schema <silver-schema> \
        --comments-file example_comments.json --apply --warehouse-id <id>

The comments file shape (see example_comments.json):
    { "GL_JE_HEADERS": { "table_comment": "...",
                         "columns": { "JE_HEADER_ID": "...", ... } },
      ... }

NOTE on the landing-agnostic rule: this JSON keys on the CANONICAL EBS-style
table names (GL_JE_HEADERS, PO_HEADERS_ALL). Before applying for a real
customer, remap the keys to the customer's PHYSICAL object names (BICC PVO /
FDI / base mirror) using the <customer>-oracle-fusion-glossary physical->canonical
mapping — comments must land on the objects the customer actually has.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def sql_literal(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def build_statements(catalog: str, schema: str, comments: dict) -> list[str]:
    """Build COMMENT ON / ALTER COLUMN statements for the given namespace."""
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


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Preview (default) or apply UC comments on Oracle Fusion Silver "
            "tables. PREVIEW writes nothing. --apply executes via the Databricks "
            "SDK and must only be used after explicit user approval of the "
            "previewed statements (see SKILL.md §Optional)."
        )
    )
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--schema", required=True, help="Silver schema holding the Fusion tables.")
    parser.add_argument("--comments-file", required=True, type=Path)
    parser.add_argument(
        "--apply",
        action="store_true",
        help=(
            "Write the comments to Unity Catalog via the Databricks SDK. Use "
            "ONLY after explicit user approval of the previewed statements "
            "(Checkpoint 2 in SKILL.md §Optional)."
        ),
    )
    parser.add_argument(
        "--warehouse-id",
        help="SQL warehouse ID. Required with --apply.",
    )
    args = parser.parse_args()

    comments = json.loads(args.comments_file.read_text())
    statements = build_statements(args.catalog, args.schema, comments)
    print(f"loaded {len(comments)} tables; {len(statements)} statements\n")

    if not args.apply:
        print(
            "PREVIEW ONLY — no changes written. Review every statement with the "
            "user, then re-run with --apply --warehouse-id <id> ONLY after they "
            "give explicit, unambiguous approval (not 'looks good' / 'okay'):\n"
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
