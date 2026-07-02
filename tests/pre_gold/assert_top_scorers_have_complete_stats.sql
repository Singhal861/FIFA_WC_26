-- Test: Top scorers (>0 goals) must have complete player stats
-- Fails if: Any scorer has NULL in critical fields

SELECT 
    player_id,
    goals_scored,
    CASE 
        WHEN assists IS NULL THEN 'Missing assists'
        WHEN minutes_played IS NULL THEN 'Missing minutes_played'
        WHEN matches_played IS NULL THEN 'Missing matches_played'
    END AS error_reason
FROM {{ ref('silver_player_stats_history') }}
WHERE is_current = TRUE
  AND goals_scored > 0
  AND (
      assists IS NULL 
      OR minutes_played IS NULL 
      OR matches_played IS NULL
  )