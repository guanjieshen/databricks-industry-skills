-- ─────────────────────────────────────────────────────────────────────────────
-- Trusted Asset functions for Genie.
-- These are UC SQL functions: register them once (CREATE FUNCTION) so Genie
-- Spaces can call them as certified, governed metrics rather than regenerating
-- ad-hoc SQL. Substitute your catalog.schema before running.
-- See: https://docs.databricks.com/aws/en/genie/trusted-assets
-- ─────────────────────────────────────────────────────────────────────────────

-- =============================================================================
-- PODS Linear Referencing — UC SQL Functions (conversion + overlap)
-- =============================================================================
-- Substitute {{catalog}}.{{metrics_schema}}. These centralize the unit and
-- station math so every PODS skill converts consistently and auditably.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- pods_ft_to_m — feet to meters
-- -----------------------------------------------------------------------------
-- The single most important conversion in the family. ILI stationing is
-- frequently in feet; centerline / HCA measures frequently in meters. Mixing
-- them silently is the #1 invisible error.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.pods_ft_to_m(
    feet DOUBLE
)
RETURNS DOUBLE
COMMENT 'Convert feet to meters (x 0.3048). Use before comparing a feet-based measure to a meters-based measure.'
RETURN feet * 0.3048;


-- -----------------------------------------------------------------------------
-- pods_station_to_measure — engineering station string -> numeric measure (ft)
-- -----------------------------------------------------------------------------
-- Parses "1240+00" -> 124000.0 (feet). Handles the standard "SSS+FF" notation
-- where the part after '+' is feet within the 100-ft station. Returns NULL on
-- unparseable input rather than guessing.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.pods_station_to_measure(
    station STRING COMMENT 'Engineering station like "1240+00" (station+offset, feet).'
)
RETURNS DOUBLE
COMMENT 'Parse engineering stationing "SSS+FF" to a numeric measure in FEET. NULL if not parseable.'
RETURN (
    CASE
        WHEN station IS NULL OR station NOT RLIKE '^[0-9]+\\+[0-9]+(\\.[0-9]+)?$'
            THEN NULL
        ELSE CAST(split(station, '\\+')[0] AS DOUBLE) * 100.0
           + CAST(split(station, '\\+')[1] AS DOUBLE)
    END
);


-- -----------------------------------------------------------------------------
-- pods_measure_to_milepost — measure -> milepost
-- -----------------------------------------------------------------------------
-- Converts a numeric measure to mileposts. Pass the measure's unit so the math
-- is explicit ('ft' or 'm'). Mileposts are how engineers talk ("near MP 42").
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.pods_measure_to_milepost(
    measure DOUBLE,
    unit STRING COMMENT "Unit of `measure`: 'ft' or 'm'."
)
RETURNS DOUBLE
COMMENT 'Convert a numeric measure to mileposts. unit must be ft or m. NULL for unknown unit.'
RETURN (
    CASE lower(unit)
        WHEN 'ft' THEN measure / 5280.0
        WHEN 'm'  THEN measure / 1609.344
        ELSE NULL
    END
);


-- -----------------------------------------------------------------------------
-- pods_events_overlap — do two linear ranges on the SAME route overlap?
-- -----------------------------------------------------------------------------
-- Half-open interval overlap test [begin, end). Caller must ensure both ranges
-- are in the SAME unit and the route_id match is enforced in the join — this
-- function only tests the measures.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.pods_events_overlap(
    a_begin DOUBLE, a_end DOUBLE,
    b_begin DOUBLE, b_end DOUBLE
)
RETURNS BOOLEAN
COMMENT 'TRUE if linear ranges [a_begin,a_end) and [b_begin,b_end) overlap. Same unit + same route assumed.'
RETURN a_begin < b_end AND a_end > b_begin;


-- =============================================================================
-- Grants (uncomment + substitute principal)
-- =============================================================================
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.pods_ft_to_m            TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.pods_station_to_measure TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.pods_measure_to_milepost TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.pods_events_overlap      TO `{{principal}}`;
