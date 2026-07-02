-- Test: All goal events must reference valid matches
-- Fails if: Any goal event has match_id that doesn't exist in silver_matches

SELECT 
    ge.match_id,
    ge.scorer_name,
    COUNT(*) AS orphaned_goals,
    'Goal event references non-existent match' AS error_reason
FROM {{ ref('silver_goal_events') }} ge
LEFT JOIN {{ ref('silver_matches') }} m ON ge.match_id = m.match_id
WHERE m.match_id IS NULL
GROUP BY ge.match_id, ge.scorer_name