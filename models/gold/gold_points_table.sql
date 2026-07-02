{{config(
    materialized='table',
    tags=['gold', 'dashboard', 'standings']
)}}

-- gold_points_table: Group Standings (Requirement #5)

WITH current_stage AS (
    SELECT
        team_id,
        CASE
            WHEN COUNT(*) >= 7 THEN 'Final'
            WHEN COUNT(*) >= 6 THEN 'Semi Final'
            WHEN COUNT(*) >= 5 THEN 'Quarter Final'
            WHEN COUNT(*) >= 4 THEN 'Round of 16'
            WHEN COUNT(*) > 3 THEN 'Round of 32'
            ELSE 'Group Stage'
        END AS stage
    FROM (
        SELECT home_team_id AS team_id FROM {{ ref('silver_matches') }}
        UNION ALL
        SELECT away_team_id AS team_id FROM {{ ref('silver_matches') }}
    )
    GROUP BY team_id
)

SELECT
    ROW_NUMBER() OVER (ORDER BY gs.points DESC, gs.goal_difference DESC, gs.goals_for DESC) AS rank_overall,
    gs.rank AS rank_in_group,
    gs.team_id,
    t.team_name,
    t.team_logo,
    gs.group_name,
    gs.matches_played,
    gs.wins,
    gs.draws,
    gs.losses,
    gs.goals_for,
    gs.goals_against,
    gs.goal_difference,
    gs.points,
    CASE
        WHEN gs.rank <= 2 THEN 'Qualified'
        WHEN gs.rank > 2 AND gs.matches_played = 3 THEN 'Disqualified'
        ELSE 'In Progress'
    END AS qualification_status,
    COALESCE(cs.stage, 'Group Stage') AS stage
FROM {{ ref('silver_group_standings') }} gs
JOIN {{ ref('silver_teams') }} t ON gs.team_id = t.team_id
LEFT JOIN current_stage cs ON gs.team_id = cs.team_id
ORDER BY rank_overall