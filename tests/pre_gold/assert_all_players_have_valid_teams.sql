-- Test: All players in goal events must have valid team references
-- Fails if: Any goal event has player without matching team in silver_teams

SELECT 
    ge.scorer_name,
    ge.team_id,
    ge.team_name,
    'Player team not found in silver_teams' AS error_reason
FROM {{ ref('silver_goal_events') }} ge
LEFT JOIN {{ ref('silver_teams') }} t ON ge.team_id = t.team_id
WHERE t.team_id IS NULL