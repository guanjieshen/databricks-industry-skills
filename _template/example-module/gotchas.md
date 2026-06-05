# <Skill> gotchas

Environment-specific facts that defy reasonable assumptions — concrete
corrections to mistakes Genie will make without being told. The 3–5 highest-value
ones also live inline in SKILL.md (Genie may not load this file in time).

> Add a `## Contents` ToC once this file exceeds ~100 lines.

- **Soft deletes** — example: `WHERE deleted_at IS NULL` or results include deactivated rows.
- **Composite keys** — example: always join on `ID` *and* `SITEID`.
- **History vs current** — which table is append-only history vs current-state.
