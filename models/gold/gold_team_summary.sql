{{config(
    materialized='table',
    tags=['gold', 'dashboard', 'team']
)}}

-- gold_team_summary: Team Stats for Flag Click Drill-down (Requirements #1, #5)

WITH all_matches AS (
    SELECT
        team_id,
        team_name,
        SUM(matches_played) AS total_matches,
        SUM(wins) AS total_wins,
        SUM(losses) AS total_losses,
        SUM(draws) AS total_draws,
        SUM(goals_for) AS goals_for,
        SUM(goals_against) AS goals_against
    FROM (
        -- Home matches
        SELECT
            home_team_id AS team_id,
            home_team_name AS team_name,
            COUNT(*) AS matches_played,
            SUM(CASE WHEN home_score > away_score THEN 1 ELSE 0 END) AS wins,
            SUM(CASE WHEN home_score < away_score THEN 1 ELSE 0 END) AS losses,
            SUM(CASE WHEN home_score = away_score THEN 1 ELSE 0 END) AS draws,
            SUM(home_score) AS goals_for,
            SUM(away_score) AS goals_against
        FROM {{ ref('silver_matches') }}
        GROUP BY home_team_id, home_team_name
        
        UNION ALL
        
        -- Away matches
        SELECT
            away_team_id AS team_id,
            away_team_name AS team_name,
            COUNT(*) AS matches_played,
            SUM(CASE WHEN away_score > home_score THEN 1 ELSE 0 END) AS wins,
            SUM(CASE WHEN away_score < home_score THEN 1 ELSE 0 END) AS losses,
            SUM(CASE WHEN away_score = home_score THEN 1 ELSE 0 END) AS draws,
            SUM(away_score) AS goals_for,
            SUM(home_score) AS goals_against
        FROM {{ ref('silver_matches') }}
        GROUP BY away_team_id, away_team_name
    )
    GROUP BY team_id, team_name
),

group_stage_points AS (
    SELECT
        team_id,
        points AS total_points
    FROM {{ ref('silver_group_standings') }}
),

top_scorers AS (
    SELECT
        team_id,
        player_name,
        goals_scored,
        ROW_NUMBER() OVER (PARTITION BY team_id ORDER BY goals_scored DESC) AS scorer_rank
    FROM {{ ref('silver_player_stats_history') }}
    WHERE is_current = TRUE
),

top_assisters AS (
    SELECT
        team_id,
        player_name AS assist_provider,
        assists,
        ROW_NUMBER() OVER (PARTITION BY team_id ORDER BY assists DESC) AS assist_rank
    FROM {{ ref('silver_player_stats_history') }}
    WHERE is_current = TRUE
),

clean_sheets_calc AS (
    SELECT
        team_id,
        SUM(CASE WHEN goals_against_in_match = 0 THEN 1 ELSE 0 END) AS clean_sheets
    FROM (
        SELECT home_team_id AS team_id, away_score AS goals_against_in_match
        FROM {{ ref('silver_matches') }}
        UNION ALL
        SELECT away_team_id AS team_id, home_score AS goals_against_in_match
        FROM {{ ref('silver_matches') }}
    )
    GROUP BY team_id
)

SELECT
    t.team_id,
    t.team_name,
    t.team_logo,
    t.group_name,
    am.total_matches,
    am.total_wins,
    am.total_losses,
    am.total_draws,
    am.goals_for,
    am.goals_against,
    am.goals_for - am.goals_against AS goal_difference,
    COALESCE(gsp.total_points, 0) AS total_points,
    
    -- Qualification status
    CASE
        WHEN am.total_matches > 3 THEN 'Qualified'
        WHEN am.total_matches = 3 AND am.total_wins + am.total_draws < 2 THEN 'Disqualified'
        ELSE 'In Progress'
    END AS qualification_status,
    
    -- Current stage
    CASE
        WHEN am.total_matches >= 7 THEN 'Final'
        WHEN am.total_matches >= 6 THEN 'Semi Final'
        WHEN am.total_matches >= 5 THEN 'Quarter Final'
        WHEN am.total_matches >= 4 THEN 'Round of 16'
        WHEN am.total_matches > 3 THEN 'Round of 32'
        ELSE 'Group Stage'
    END AS current_stage,
    
    -- Top scorers
    ts1.player_name AS top_scorer_1_name,
    ts1.goals_scored AS top_scorer_1_goals,
    ts2.player_name AS top_scorer_2_name,
    ts2.goals_scored AS top_scorer_2_goals,
    
    -- Top assist provider
    ta.assist_provider AS top_assist_provider,
    ta.assists AS top_assist_count,
    
    -- Clean sheets
    COALESCE(cs.clean_sheets, 0) AS clean_sheets,
    
    CURRENT_TIMESTAMP() AS last_updated
    
FROM {{ ref('silver_teams') }} t
LEFT JOIN all_matches am ON t.team_id = am.team_id
LEFT JOIN group_stage_points gsp ON t.team_id = gsp.team_id
LEFT JOIN top_scorers ts1 ON t.team_id = ts1.team_id AND ts1.scorer_rank = 1
LEFT JOIN top_scorers ts2 ON t.team_id = ts2.team_id AND ts2.scorer_rank = 2
LEFT JOIN top_assisters ta ON t.team_id = ta.team_id AND ta.assist_rank = 1
LEFT JOIN clean_sheets_calc cs ON t.team_id = cs.team_id