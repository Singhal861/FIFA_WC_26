{{config(
    materialized='table',
    tags=['silver','fact', 'events', 'goals']
)}}

-- Parse goal events from scorer strings into normalized event records

WITH home_goals AS (
    SELECT
        match_id,
        home_team_id AS team_id,
        home_team_name AS team_name,
        TRUE AS is_home_goal,  -- ← Directly set to TRUE for home goals
        EXPLODE(
            FROM_JSON(
                REGEXP_REPLACE(REGEXP_REPLACE(home_scorers, '\\{', '['), '\\}', ']'),
                'ARRAY<STRING>'
            )
        ) AS goal_string
    FROM {{ source('bronze', 'matches') }}
    WHERE home_scorers IS NOT NULL 
      AND home_scorers != 'null'
      AND LENGTH(home_scorers) > 5
),

away_goals AS (
    SELECT
        match_id,
        away_team_id AS team_id,
        away_team_name AS team_name,
        FALSE AS is_home_goal,  -- ← Directly set to FALSE for away goals
        EXPLODE(
            FROM_JSON(
                REGEXP_REPLACE(REGEXP_REPLACE(away_scorers, '\\{', '['), '\\}', ']'),
                'ARRAY<STRING>'
            )
        ) AS goal_string
    FROM {{ source('bronze', 'matches') }}
    WHERE away_scorers IS NOT NULL 
      AND away_scorers != 'null'
      AND LENGTH(away_scorers) > 5
),

all_goals AS (
    SELECT * FROM home_goals
    UNION ALL
    SELECT * FROM away_goals
)

SELECT
    MD5(CONCAT(match_id, team_id, goal_string)) AS goal_event_id,
    match_id,
    team_id,
    team_name,
    
    -- Parse player name (everything before the minute)
    TRIM(REGEXP_EXTRACT(goal_string, '^([^0-9]+)', 1)) AS scorer_name,
    
    -- Parse full minute string (preserves injury time: "90+3'", "45+1'", "67'")
    REGEXP_EXTRACT(goal_string, '([0-9]+(?:\\+[0-9]+)?\\')', 1) AS minute,
    
    -- Parse base minute as integer (for sorting/filtering)
    CAST(REGEXP_EXTRACT(goal_string, '([0-9]+)', 1) AS INT) AS minute_base,
    
    -- Parse injury time minutes (NULL if no injury time)
    CAST(REGEXP_EXTRACT(goal_string, '\\+([0-9]+)', 1) AS INT) AS injury_time_minutes,
    
    -- Detect penalty
    CASE WHEN goal_string LIKE '%(p)%' THEN TRUE ELSE FALSE END AS is_penalty,
    
    -- Home/Away flag (already set in CTEs above)
    is_home_goal,
    
    goal_string AS goal_string_raw,
    CURRENT_TIMESTAMP() AS ingested_at
    
FROM all_goals
WHERE goal_string IS NOT NULL
  AND TRIM(goal_string) != ''
ORDER BY match_id, minute_base, injury_time_minutes