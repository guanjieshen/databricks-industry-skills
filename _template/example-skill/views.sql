-- DDL for reusable, pre-joined Gold views this skill's queries compose from.
-- Built/owned by the family's -data-engineering skill. Substitute catalog.schema.

CREATE OR REPLACE VIEW :catalog.:schema.v_example_enriched AS
SELECT e.*,
       p.name AS parent_name
FROM   :catalog.:schema.EXAMPLE_TABLE e
LEFT   JOIN :catalog.:schema.PARENT p
       ON  e.PARENT_ID = p.ID
       AND e.SITEID    = p.SITEID;
