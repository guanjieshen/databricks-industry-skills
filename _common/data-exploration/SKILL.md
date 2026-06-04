---
name: data-exploration
description: |
  Use to discover tables, query data, and explore schemas in any Databricks
  workspace using the `databricks experimental aitools tools` command group.
  Covers discover-schema (table metadata, columns, sample data, null counts)
  and query (SQL execution against Databricks SQL warehouses). Triggers on:
  "what tables are available", "discover schema", "explore", "find tables",
  "run SQL", "query the data", "show me sample data", "find tables containing",
  "table statistics", "data validation". This is a universal data-discovery
  skill that applies to ANY data in Databricks — including but not limited
  to industry-specific sources like Maximo.
tags:
  - tier:common
  - surface:notebook
  - persona:analyst
  - persona:da-platform
owners: [databricks]
---

# Data Exploration

Tools for discovering table schemas and executing SQL queries in Databricks.

> Adapted from [`databricks/databricks-agent-skills/skills/databricks-core/data-exploration.md`](https://github.com/databricks/databricks-agent-skills/blob/main/skills/databricks-core/data-exploration.md). Frontmatter added; tagged for inclusion in this industry skills library.

## Finding Tables by Keyword

**⚠️ START HERE if you don't know which catalog/schema contains your data.**

Use `information_schema` to search for tables by keyword — do NOT manually iterate through `catalogs list` → `schemas list` → `tables list`. Manual enumeration wastes 10+ steps.

```bash
# Find tables matching a keyword
databricks experimental aitools tools query \
  "SELECT table_catalog, table_schema, table_name FROM system.information_schema.tables WHERE table_name LIKE '%keyword%'" \
  --profile <PROFILE>

# Then discover schema for the tables you found
databricks experimental aitools tools discover-schema catalog.schema.table1 catalog.schema.table2 --profile <PROFILE>
```

## Overview

The `databricks experimental aitools tools` command group provides tools for data discovery and exploration:
- **discover-schema**: Batch discover table metadata, columns, types, sample data, and statistics
- **query**: Execute SQL queries against Databricks SQL warehouses

**When to use this**: Use these commands whenever you need to:
- Discover table schemas and metadata
- Execute SQL queries against warehouse data
- Explore data structure and content
- Validate data or check table statistics

## Prerequisites

1. **Authenticated Databricks CLI** — OAuth2 setup and profile configuration
2. **Access to Unity Catalog tables** with appropriate read permissions
3. **SQL Warehouse** (for query command — auto-detected unless `DATABRICKS_WAREHOUSE_ID` is set)

## Discover Schema

Batch discover table metadata including columns, types, sample data, and null counts.

### Command Syntax

```bash
databricks experimental aitools tools discover-schema TABLE... [flags]
```

Tables must be specified in **CATALOG.SCHEMA.TABLE** format.

### What It Returns

For each table, returns:
- Column names and types
- Sample data (5 rows)
- Null counts per column
- Total row count

### Examples

```bash
# Discover schema for a single table
databricks experimental aitools tools discover-schema samples.nyctaxi.trips --profile my-workspace

# Discover schema for multiple tables
databricks experimental aitools tools discover-schema \
  catalog.schema.table1 \
  catalog.schema.table2 \
  --profile my-workspace

# Get JSON output
databricks experimental aitools tools discover-schema \
  samples.nyctaxi.trips \
  --output json \
  --profile my-workspace
```

### Common Use Cases

1. **Understanding table structure before querying**
   ```bash
   databricks experimental aitools tools discover-schema catalog.schema.customer_data --profile my-workspace
   ```

2. **Comparing schemas across multiple tables**
   ```bash
   databricks experimental aitools tools discover-schema \
     catalog.schema.table_v1 \
     catalog.schema.table_v2 \
     --profile my-workspace
   ```

3. **Identifying columns with null values** — the null counts help identify data quality issues.

## Query

Execute SQL statements against a Databricks SQL warehouse and return results.

### Command Syntax

```bash
databricks experimental aitools tools query "SQL" [flags]
```

### Warehouse Selection

The command **auto-detects** an available warehouse unless:
- `DATABRICKS_WAREHOUSE_ID` environment variable is set
- You specify a warehouse using other configuration methods

To check which warehouse will be used:

```bash
databricks experimental aitools tools get-default-warehouse --profile my-workspace
```

### Output

Returns:
- Query results as JSON
- Row count
- Execution metadata

### Examples

```bash
# Simple SELECT
databricks experimental aitools tools query \
  "SELECT * FROM samples.nyctaxi.trips LIMIT 5" \
  --profile my-workspace

# Aggregation
databricks experimental aitools tools query \
  "SELECT vendor_id, COUNT(*) as trip_count FROM samples.nyctaxi.trips GROUP BY vendor_id" \
  --profile my-workspace

# JSON output
databricks experimental aitools tools query \
  "SELECT * FROM catalog.schema.table WHERE date > '2024-01-01'" \
  --output json \
  --profile my-workspace

# Specific warehouse
DATABRICKS_WAREHOUSE_ID=abc123 databricks experimental aitools tools query \
  "SELECT * FROM samples.nyctaxi.trips LIMIT 10" \
  --profile my-workspace
```

### Common Use Cases

- **Exploratory data analysis**: counts, samples, column statistics
- **Data validation**: NULL counts, freshness via `MAX(timestamp_column)`
- **Quick analytics**: `GROUP BY` summaries

## Workflow: Complete Data Exploration

```bash
# 1. Discover the schema first
databricks experimental aitools tools discover-schema \
  samples.nyctaxi.trips \
  --profile my-workspace

# 2. Run targeted queries based on discovered columns
databricks experimental aitools tools query \
  "SELECT vendor_id, payment_type, COUNT(*) as trips, AVG(fare_amount) as avg_fare
   FROM samples.nyctaxi.trips
   GROUP BY vendor_id, payment_type
   ORDER BY trips DESC
   LIMIT 10" \
  --profile my-workspace

# 3. Investigate specific patterns found in the data
databricks experimental aitools tools query \
  "SELECT * FROM samples.nyctaxi.trips
   WHERE fare_amount > 100
   LIMIT 20" \
  --profile my-workspace
```

## Genie Code-specific tips

Each Bash command in Genie Code runs in a separate shell:

```bash
# ✅ RECOMMENDED — use --profile flag
databricks experimental aitools tools discover-schema samples.nyctaxi.trips --profile my-workspace

# ✅ ALTERNATIVE — chain with &&
export DATABRICKS_CONFIG_PROFILE=my-workspace && \
  databricks experimental aitools tools query "SELECT * FROM samples.nyctaxi.trips LIMIT 5"

# ❌ DOES NOT WORK — separate export
export DATABRICKS_CONFIG_PROFILE=my-workspace
databricks experimental aitools tools query "SELECT * FROM samples.nyctaxi.trips LIMIT 5"
```

## Flags

| Flag | Description | Default |
|---|---|---|
| `--profile` | Profile name from ~/.databrickscfg | Default profile |
| `--output` | Output format: `text` or `json` | `text` |
| `--debug` | Enable debug logging | `false` |
| `--target` | Bundle target to use (if applicable) | — |

## Troubleshooting

### Table Not Found
**Symptom**: `Error: TABLE_OR_VIEW_NOT_FOUND`
- Verify table name format: `CATALOG.SCHEMA.TABLE`
- Check read permissions
- List tables: `databricks tables list <catalog> <schema> --profile my-workspace`

### Warehouse Not Available
**Symptom**: `Error: No available SQL warehouse found`
- Check default: `databricks experimental aitools tools get-default-warehouse --profile my-workspace`
- List: `databricks warehouses list --profile my-workspace`
- Set explicit: `DATABRICKS_WAREHOUSE_ID=<id> ...`
- Start stopped: `databricks warehouses start --id <id> --profile my-workspace`

### Permission Denied
**Symptom**: `Error: PERMISSION_DENIED`
- Check grants: `databricks grants get --full-name catalog.schema.table --principal <user-email> --profile my-workspace`
- Request SELECT permission from your workspace admin
- Verify warehouse `USAGE` permission

### SQL Syntax Error
**Symptom**: `Error: PARSE_SYNTAX_ERROR`
- Use standard SQL
- Verify column names with `discover-schema` first
- Quote string literals properly
- Test incrementally

## Best Practices

1. **Always discover schema first** before writing complex queries
2. **Use LIMIT for exploration** on large tables to avoid long-running queries
3. **JSON output for parsing** — `--output json | jq` for programmatic use
4. **Check table existence** before querying: `databricks tables get --full-name catalog.schema.table`
5. **Always specify `--profile`** in Genie Code to avoid authentication issues

## Composes with industry skills

When working with a specific data source from this library (e.g., the `maximo/` family), use the industry-specific skill for schema knowledge AND this skill for the actual exploration mechanics:

- "Find Maximo tables in our catalog" → use this skill's `information_schema` pattern + `maximo-overview` to interpret which tables are which MBOs.
- "Show me sample WORKORDER data" → use this skill's `discover-schema` + `maximo-overview` to know what to expect.
