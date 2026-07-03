{{config(
    materialized='table',
    tags=['gold', 'dashboard', 'player']
)}}

-- Golden Boot Race: Live leaderboard for top scorers

WITH goal_counts AS (
    SELECT
        npm.player_id,
        npm.player_name,
        npm.team_name,
        COUNT(*) AS total_goals,
        SUM(CASE WHEN ge.is_penalty = TRUE THEN 1 ELSE 0 END) AS penalty_goals,
        COUNT(*) - SUM(CASE WHEN ge.is_penalty = TRUE THEN 1 ELSE 0 END) AS open_play_goals
    FROM {{ ref('silver_goal_events') }} ge
    JOIN {{ source('fifa_worldcup_silver', 'silver_player_name_mapping') }} npm 
        ON ge.scorer_name = npm.scorer_name
        AND npm.status = 'RESOLVED'
    GROUP BY npm.player_id, npm.player_name, npm.team_name
),

player_matches AS (
    SELECT
        ps.player_id,
        ps.matches_played,
        ps.minutes_played
    FROM {{ ref('silver_player_stats_history') }} ps
    WHERE ps.is_current = TRUE
)

SELECT
    ROW_NUMBER() OVER (ORDER BY gc.total_goals DESC, gc.open_play_goals DESC, gc.player_name) AS rank,
    gc.player_id,
    gc.player_name,
    gc.team_name,
    gc.total_goals,
    gc.penalty_goals,
    gc.open_play_goals,
    pm.matches_played,
    pm.minutes_played,
    ROUND(gc.total_goals / NULLIF(pm.matches_played, 0), 2) AS goals_per_match,
    ROUND(gc.total_goals / NULLIF(pm.minutes_played, 0) * 90, 2) AS goals_per_90min
FROM goal_counts gc
LEFT JOIN player_matches pm ON gc.player_id = pm.player_id
ORDER BY rank