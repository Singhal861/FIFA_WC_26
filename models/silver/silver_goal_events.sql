{{config(
    materialized='table',
    tags=['fact', 'events', 'goals', 'silver']
)}}

-- ✅ UPDATED: Read directly from bronze.goal_events table
-- This preserves full goal timestamps (90+3', 45+1', etc.) that were lost in old parsing

WITH goal_events_enriched AS (
    SELECT
        ge.match_id,
        ge.player_name AS scorer_name,
        ge.goal_time,  -- ✅ Full timestamp preserved: "90+3'", "45+1'", "67'"
        ge.team_id,
        ge.team_name,
        
        -- Extract base minute for sorting/analytics
        CAST(REGEXP_EXTRACT(ge.goal_time, '([0-9]+)', 1) AS INT) AS minute_base,
        
        -- Extract injury time (if any)
        CASE 
            WHEN ge.goal_time LIKE '%+%' 
            THEN CAST(REGEXP_EXTRACT(ge.goal_time, '\\+([0-9]+)', 1) AS INT)
            ELSE 0
        END AS injury_time_minutes,
        
        -- Enrich with match context
        m.home_team_id,
        m.away_team_id,
        m.home_team_name,
        m.away_team_name,
        m.home_score,
        m.away_score,
        m.match_type,
        m.group,
        m.matchday,
        m.local_date AS match_date,
        
        -- Determine if home/away goal
        CASE 
            WHEN ge.team_id = m.home_team_id THEN TRUE 
            ELSE FALSE 
        END AS is_home_goal,
        
        ge.ingested_at
        
    FROM {{ source('bronze', 'goal_events') }} ge
    INNER JOIN {{ source('bronze', 'matches') }} m
        ON ge.match_id = m.match_id
)

SELECT
    MD5(CONCAT(match_id, team_id, scorer_name, goal_time)) AS goal_event_id,
    match_id,
    scorer_name,
    goal_time,  -- ✅ PRESERVED: "90+3'", "45+1'", "67'"
    minute_base,  -- For analytics: 90, 45, 67
    injury_time_minutes,  -- For analytics: 3, 1, 0
    team_id,
    team_name,
    is_home_goal,
    
    -- Match context
    home_team_id,
    away_team_id,
    home_team_name,
    away_team_name,
    home_score,
    away_score,
    match_type,
    group,
    matchday,
    match_date,
    
    ingested_at
    
FROM goal_events_enriched
ORDER BY match_id, minute_base, injury_time_minutes