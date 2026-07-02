-- Test: All scorers must be RESOLVED in mapping table
WITH distinct_scorers AS (
    SELECT DISTINCT scorer_name, team_name
    FROM {{ ref('silver_goal_events') }}
),

unmapped_scorers AS (
    SELECT 
        ds.scorer_name,
        ds.team_name
    FROM distinct_scorers ds
    LEFT JOIN {{ ref('silver_player_name_mapping') }} m 
        ON ds.scorer_name = m.scorer_name
    WHERE m.scorer_name IS NULL 
       OR m.status != 'RESOLVED'
)

SELECT * FROM unmapped_scorers