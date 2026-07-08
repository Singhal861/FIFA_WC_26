-- Requirement 5: Group Stage Points Table
-- Validates: gold_fact_team_performance (unified table)

-- Test that points table has:
-- 1. All teams with group assignments
-- 2. Correct points calculation (win=3, draw=1, loss=0)
-- 3. Team logos
-- 4. Proper group rankings

WITH validation_failures AS (
    -- Check 1: All teams have group assignments
    SELECT
        'Missing group assignment' AS failure_type,
        team_name,
        CONCAT('Team ', team_name, ' has NULL group_name') AS failure_detail
    FROM {{ ref('gold_fact_team_performance') }}
    WHERE group_name IS NULL
    
    UNION ALL
    
    -- Check 2: All teams have logos
    SELECT
        'Missing team logo' AS failure_type,
        team_name,
        CONCAT('Team ', team_name, ' missing team_logo') AS failure_detail
    FROM {{ ref('gold_fact_team_performance') }}
    WHERE team_logo IS NULL
    
    UNION ALL
    
    -- Check 3: Points calculation is valid (points = group_wins*3 + group_draws*1)
    SELECT
        'Invalid points calculation' AS failure_type,
        team_name,
        CONCAT('Team ', team_name, ' points mismatch - expected: ',
               CAST((group_wins * 3 + group_draws) AS STRING),
                ', actual: ', CAST(total_points AS STRING)) AS failure_detail
    FROM {{ ref('gold_fact_team_performance') }}
    WHERE total_points != (group_wins * 3 + group_draws)
    
    UNION ALL
    
    -- Check 4: Goal difference is valid (group_goals_for - group_goals_against)
    SELECT
        'Invalid goal difference' AS failure_type,
        team_name,
        CONCAT('Team ', team_name, ' goal_diff mismatch - expected: ',
               CAST((group_goals_for - group_goals_against) AS STRING),
               ', actual: ', CAST(group_goal_difference AS STRING)) AS failure_detail
    FROM {{ ref('gold_fact_team_performance') }}
    WHERE group_goal_difference != (group_goals_for - group_goals_against)
    
    UNION ALL
    
    -- Check 5: Group rankings should be sequential per group
    SELECT
        'Invalid group ranking' AS failure_type,
        team_name,
        CONCAT('Group ', group_name, ' has gap in rankings at position ', 
               rank_in_group) AS failure_detail
    FROM (
        SELECT
            team_name,
            group_name,
            rank_in_group,
            ROW_NUMBER() OVER (PARTITION BY group_name ORDER BY rank_in_group) AS expected_position
        FROM {{ ref('gold_fact_team_performance') }}
    )
    WHERE rank_in_group != expected_position
    
    UNION ALL
    
    -- Check 6: Group matches should equal group_wins + group_draws + group_losses
    SELECT
        'Invalid matches count' AS failure_type,
        team_name,
        CONCAT('Team ', team_name, ' matches mismatch - W+D+L: ',
               CAST((group_wins + group_draws + group_losses) AS STRING),
               ', group_matches_played: ', CAST(group_matches_played AS STRING)) AS failure_detail
    FROM {{ ref('gold_fact_team_performance') }}
    WHERE group_matches_played != (group_wins + group_draws + group_losses)
)

SELECT
    failure_type,
    failure_detail,
    COUNT(*) AS failure_count
FROM validation_failures
GROUP BY failure_type, failure_detail
