-- ─────────────────────────────────────────────────────────────────────────────
-- Trusted Asset functions for Genie.
-- These are UC SQL functions: register them once (CREATE FUNCTION) so Genie
-- Spaces can call them as certified, governed metrics rather than regenerating
-- ad-hoc SQL. Substitute your catalog.schema before running.
-- See: https://docs.databricks.com/aws/en/genie/trusted-assets
-- ─────────────────────────────────────────────────────────────────────────────

-- =============================================================================
-- PODS ILI Integrity — UC SQL Functions (certified integrity math)
-- =============================================================================
-- Substitute {{catalog}}.{{metrics_schema}}.
--
-- These are the STANDARD published formulations (Modified B31G, Barlow) used as
-- defensible defaults. They are SCREENING estimates, NOT fitness-for-service
-- determinations. Operators with a certified in-house method (RSTRENG effective
-- area, vendor-specific) should register that as a separate UDF and document the
-- difference. ALWAYS surface which method produced a number.
--
-- UNITS (be strict — mixing units silently is the core integrity error):
--   od_in, wt_in, depth_in, length_in : INCHES
--   smys_psi, pressure_psig            : PSI / PSIG
-- =============================================================================


-- -----------------------------------------------------------------------------
-- pods_depth_in — convert depth % wall loss to inches
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.pods_depth_in(
    depth_pct DOUBLE COMMENT 'Metal loss as percent of wall thickness (0-100).',
    wt_in DOUBLE     COMMENT 'Nominal wall thickness (inches).'
)
RETURNS DOUBLE
COMMENT 'Defect depth in inches from percent-of-wall metal loss. NULL if inputs invalid.'
RETURN CASE WHEN depth_pct IS NULL OR wt_in IS NULL OR wt_in <= 0 THEN NULL
            ELSE (depth_pct / 100.0) * wt_in END;


-- -----------------------------------------------------------------------------
-- pods_pct_smys — operating stress as % of SMYS (Barlow hoop stress)
-- -----------------------------------------------------------------------------
-- %SMYS = (P * D / (2 * t)) / SMYS * 100
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.pods_pct_smys(
    pressure_psig DOUBLE, od_in DOUBLE, wt_in DOUBLE, smys_psi DOUBLE
)
RETURNS DOUBLE
COMMENT 'Barlow hoop stress as percent of SMYS. NULL if inputs invalid.'
RETURN CASE
    WHEN pressure_psig IS NULL OR od_in IS NULL OR wt_in IS NULL OR smys_psi IS NULL
         OR wt_in <= 0 OR smys_psi <= 0 THEN NULL
    ELSE (pressure_psig * od_in / (2.0 * wt_in)) / smys_psi * 100.0
END;


-- -----------------------------------------------------------------------------
-- pods_failure_pressure_b31g_mod — Modified B31G (0.85dL) failure pressure
-- -----------------------------------------------------------------------------
-- Predicted failure pressure (psig) of a blunt metal-loss defect.
--   S_flow = SMYS + 10000 psi
--   z = L^2 / (D * t)
--   M = sqrt(1 + 0.6275*z - 0.003375*z^2)         for z <= 50
--   M = 0.032*z + 3.3                              for z > 50
--   Pf = (2 * S_flow * t / D) * (1 - 0.85*(d/t)) / (1 - 0.85*(d/t)/M)
-- Assumptions: blunt corrosion metal loss only (NOT cracks, dents, gouges,
-- or dents-with-metal-loss). Screening estimate. Validate before action.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.pods_failure_pressure_b31g_mod(
    od_in DOUBLE, wt_in DOUBLE, depth_in DOUBLE, length_in DOUBLE, smys_psi DOUBLE
)
RETURNS DOUBLE
COMMENT 'Modified B31G (0.85dL) predicted failure pressure (psig) for blunt metal loss. Screening estimate only; NULL if invalid or d/t>=0.8.'
RETURN (
    WITH p AS (
        SELECT
            od_in AS d, wt_in AS t, depth_in AS dep, length_in AS len,
            (smys_psi + 10000.0) AS s_flow,
            CASE WHEN od_in > 0 AND wt_in > 0 THEN (length_in * length_in) / (od_in * wt_in) END AS z
        )
    SELECT CASE
        WHEN d IS NULL OR t IS NULL OR dep IS NULL OR len IS NULL OR s_flow IS NULL
             OR t <= 0 OR d <= 0 OR dep < 0 THEN NULL
        -- B31G is not valid for very deep defects; return NULL to force engineer review.
        WHEN (dep / t) >= 0.80 THEN NULL
        ELSE (
            2.0 * s_flow * t / d
            * (1.0 - 0.85 * (dep / t))
            / (1.0 - 0.85 * (dep / t) / (CASE WHEN z <= 50.0
                                              THEN sqrt(1.0 + 0.6275 * z - 0.003375 * z * z)
                                              ELSE 0.032 * z + 3.3 END))
        )
    END
    FROM p
);


-- -----------------------------------------------------------------------------
-- pods_erf — Estimated Repair Factor
-- -----------------------------------------------------------------------------
-- ERF = MAOP / P_safe,  where  P_safe = P_failure / safety_factor
--     => ERF = MAOP * safety_factor / P_failure
-- ERF >= 1.0 conventionally indicates an immediate condition (predicted safe
-- pressure at/below MAOP). Safety factor varies by code/class — pass it
-- explicitly (e.g. ~1.39 commonly for hazardous liquid; gas varies by class).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.{{metrics_schema}}.pods_erf(
    maop_psig DOUBLE,
    failure_pressure_psig DOUBLE,
    safety_factor DOUBLE COMMENT 'Code/class safety factor. Pass explicitly; do not default silently.'
)
RETURNS DOUBLE
COMMENT 'Estimated Repair Factor = MAOP * safety_factor / predicted_failure_pressure. ERF>=1 => immediate condition. NULL if invalid.'
RETURN CASE
    WHEN maop_psig IS NULL OR failure_pressure_psig IS NULL OR safety_factor IS NULL
         OR failure_pressure_psig <= 0 THEN NULL
    ELSE maop_psig * safety_factor / failure_pressure_psig
END;


-- =============================================================================
-- Grants (uncomment + substitute principal)
-- =============================================================================
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.pods_depth_in                  TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.pods_pct_smys                  TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.pods_failure_pressure_b31g_mod TO `{{principal}}`;
-- GRANT EXECUTE ON FUNCTION {{catalog}}.{{metrics_schema}}.pods_erf                       TO `{{principal}}`;
