{{config(
    materialized='table',
    tags=['gold', 'dashboard', 'bracket']
)}}

-- gold_tournament_bracket: Knockout Bracket Visualization (Requirement #1)

WITH timezone_ref AS (
    SELECT * FROM {{ source('fifa_worldcup_gold', 'ref_stadium_enriched') }}
),

knockout_matches AS (
    SELECT
        m.match_id,
        m.home_team_id,
        m.away_team_id,
        m.home_team_name,
        m.away_team_name,
        m.home_score,
        m.away_score,
        m.stage,
        m.is_finished,
        m.match_date_local,
        m.stadium_id,
        kb.bracket_position,
        kb.feeds_into_position,
        s.name AS stadium_name,
        tz.city AS stadium_city,
        tz.actual_country,
        tz.utc_offset_hours,
        TO_TIMESTAMP(
            REGEXP_REPLACE(m.match_date_local, ' [A-Z]{3,4}$', ''),
            'MM/dd/yyyy HH:mm'
        ) + MAKE_DT_INTERVAL(0, tz.utc_offset_hours, 0, 0) AS match_datetime_utc,
        CASE
            WHEN m.is_finished = TRUE AND m.home_score > m.away_score THEN m.home_team_id
            WHEN m.is_finished = TRUE AND m.away_score > m.home_score THEN m.away_team_id
            ELSE NULL
        END AS winner_team_id,
        CASE
            WHEN m.is_finished = TRUE AND m.home_score > m.away_score THEN m.home_team_name
            WHEN m.is_finished = TRUE AND m.away_score > m.home_score THEN m.away_team_name
            ELSE NULL
        END AS winner_team_name
    FROM {{ ref('silver_matches') }} m
    JOIN {{ ref('silver_knockout_bracket') }} kb ON m.match_id = kb.match_id
    JOIN {{ ref('silver_stadiums') }} s ON m.stadium_id = s.stadium_id
    JOIN timezone_ref tz ON m.stadium_id = tz.stadium_id
    WHERE m.stage != 'Group Stage'
),

with_team_logos AS (
    SELECT
        km.*,
        ht.team_logo AS home_team_logo,
        at.team_logo AS away_team_logo,
        wt.team_logo AS winner_team_logo
    FROM knockout_matches km
    LEFT JOIN {{ ref('silver_teams') }} ht ON km.home_team_id = ht.team_id
    LEFT JOIN {{ ref('silver_teams') }} at ON km.away_team_id = at.team_id
    LEFT JOIN {{ ref('silver_teams') }} wt ON km.winner_team_id = wt.team_id
)

SELECT
    match_id,
    stage AS round,
    bracket_position,
    feeds_into_position,
    CASE 
        WHEN bracket_position LIKE '%1' OR bracket_position LIKE '%3' THEN 'Top'
        ELSE 'Bottom'
    END AS bracket_side,
    home_team_id,
    home_team_name,
    home_team_logo,
    home_score,
    away_team_id,
    away_team_name,
    away_team_logo,
    away_score,
    winner_team_id,
    winner_team_name,
    winner_team_logo,
    match_datetime_utc,
    match_date_local,
    stadium_name,
    stadium_city,
    actual_country,
    is_finished,
    ROW_NUMBER() OVER (ORDER BY 
        CASE stage
            WHEN 'Round of 32' THEN 1
            WHEN 'Round of 16' THEN 2
            WHEN 'Quarter Final' THEN 3
            WHEN 'Semi Final' THEN 4
            WHEN 'Third Place' THEN 5
            WHEN 'Final' THEN 6
        END,
        match_datetime_utc
    ) AS match_order
FROM with_team_logos
ORDER BY match_order