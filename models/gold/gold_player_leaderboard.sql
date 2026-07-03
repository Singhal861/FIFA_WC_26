{{config(
    materialized='table',
    tags=['gold', 'dashboard', 'player']
)}}

-- gold_player_leaderboard: Top Scorers with Spider Chart Data (Requirement #2)

WITH current_stats AS (
    SELECT
        ps.player_id,
        p.player_name,
        p.team_id,
        p.team_name,
        ps.goals_scored,
        ps.assists,
        ps.matches_played,
        ps.minutes_played,
        ps.rating_0_to_10
    FROM {{ ref('silver_player_stats_history') }} ps
    JOIN {{ ref('silver_players') }} p ON ps.player_id = p.player_id
    WHERE ps.is_current = TRUE
),

penalty_goals AS (
    SELECT
        npm.player_id,
        COUNT(*) AS penalty_goals
    FROM {{ ref('silver_goal_events') }} ge
    JOIN {{ source('fifa_worldcup_silver', 'silver_player_name_mapping') }} npm 
        ON ge.scorer_name = npm.scorer_name
        AND npm.status = 'RESOLVED'  -- ✅ Only RESOLVED
    WHERE ge.is_penalty = TRUE
    GROUP BY npm.player_id
),

goals_by_opponent AS (
    SELECT
        p.player_id,
        CASE 
            WHEN ge.is_home_goal THEN m.away_team_name
            ELSE m.home_team_name
        END AS opponent_team_name,
        COUNT(*) AS goals_against_team
    FROM {{ ref('silver_goal_events') }} ge
    JOIN {{ ref('silver_players') }} p ON ge.scorer_name = p.player_name
    JOIN {{ ref('silver_matches') }} m ON ge.match_id = m.match_id
    GROUP BY p.player_id, opponent_team_name
),

most_goals_against AS (
    SELECT
        player_id,
        opponent_team_name AS most_goals_against_team_name,
        goals_against_team AS most_goals_against_team_count,
        ROW_NUMBER() OVER (PARTITION BY player_id ORDER BY goals_against_team DESC) AS rn
    FROM goals_by_opponent
),

percentiles AS (
    SELECT
        player_id,
        goals_scored,
        assists,
        minutes_played,
        matches_played,
        PERCENT_RANK() OVER (ORDER BY goals_scored) * 100 AS goals_percentile,
        PERCENT_RANK() OVER (ORDER BY assists) * 100 AS assists_percentile,
        PERCENT_RANK() OVER (ORDER BY minutes_played) * 100 AS minutes_percentile,
        PERCENT_RANK() OVER (ORDER BY matches_played) * 100 AS matches_percentile
    FROM current_stats
),

base_leaderboard AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY cs.goals_scored DESC, cs.assists DESC, cs.minutes_played ASC) AS rank,
        cs.player_id,
        cs.player_name,
        cs.team_id,
        cs.team_name,
        t.team_logo,
        cs.goals_scored,
        cs.assists,
        cs.matches_played,
        cs.minutes_played,
        cs.rating_0_to_10,
        COALESCE(pg.penalty_goals, 0) AS penalty_goals,
        cs.goals_scored - COALESCE(pg.penalty_goals, 0) AS non_penalty_goals,
        ROUND(p.goals_percentile, 0) AS goals_percentile,
        ROUND(p.assists_percentile, 0) AS assists_percentile,
        ROUND(p.minutes_percentile, 0) AS minutes_percentile,
        ROUND(p.matches_percentile, 0) AS matches_percentile,
        mga.most_goals_against_team_name,
        mga.most_goals_against_team_count,
        -- FIFA Golden Boot ranking with tiebreakers
        DENSE_RANK() OVER (
            ORDER BY 
                cs.goals_scored DESC,      -- Primary: Most goals
                cs.assists DESC,           -- Tiebreaker 1: Most assists
                cs.minutes_played ASC      -- Tiebreaker 2: Fewer minutes
        ) AS golden_boot_rank
    FROM current_stats cs
    LEFT JOIN {{ ref('silver_teams') }} t ON cs.team_id = t.team_id
    LEFT JOIN penalty_goals pg ON cs.player_id = pg.player_id
    LEFT JOIN percentiles p ON cs.player_id = p.player_id
    LEFT JOIN most_goals_against mga ON cs.player_id = mga.player_id AND mga.rn = 1
    WHERE cs.goals_scored > 0
),

leader_goals AS (
    SELECT MAX(goals_scored) AS max_goals
    FROM base_leaderboard
)

SELECT
    bl.*,
    -- Golden Boot specific columns
    CASE WHEN bl.golden_boot_rank <= 3 THEN TRUE ELSE FALSE END AS is_top_3,
    lg.max_goals - bl.goals_scored AS goals_behind_leader,
    CURRENT_TIMESTAMP() AS last_updated
FROM base_leaderboard bl
CROSS JOIN leader_goals lg
ORDER BY golden_boot_rank, assists DESC, minutes_played ASC