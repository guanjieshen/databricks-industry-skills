-- Parameterized, gold-standard queries for this skill's domain.
-- Genie should prefer these patterns over generating SQL from scratch.
-- Substitute :catalog, :schema, and other :params for the user's values.

-- Example: <plain-English question this answers>
SELECT *
FROM   :catalog.:schema.EXAMPLE_TABLE
WHERE  deleted_at IS NULL
LIMIT  100;
