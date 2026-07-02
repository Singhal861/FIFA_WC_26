-- Test: All match_date_local must be parseable for UTC conversion
-- Fails if: Any match has invalid datetime format

SELECT 
    match_id,
    match_date_local,
    'Invalid datetime format for UTC conversion' AS error_reason
FROM {{ ref('silver_matches') }}
WHERE 
    -- Check if REGEXP_REPLACE fails (datetime has unexpected format)
    REGEXP_REPLACE(match_date_local, ' [A-Z]{3,4}$', '') IS NULL
    OR LENGTH(REGEXP_REPLACE(match_date_local, ' [A-Z]{3,4}$', '')) < 10