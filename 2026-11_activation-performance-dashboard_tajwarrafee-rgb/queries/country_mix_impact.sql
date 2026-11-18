WITH base AS (
    SELECT
        dud.user_id,
        dc.country_name AS country,
        DATE_TRUNC('WEEK', dud.created_ts) AS week,
        CASE
            WHEN DATE_TRUNC('DAY', dud.delivery_activation_ts)
               = DATE_TRUNC('DAY', dud.created_ts)
            THEN 1 ELSE 0
        END AS is_same_day_activated
    FROM main.ng_delivery.dim_user_delivery dud
    JOIN main.ng_delivery.dim_delivery_city dc
        ON dud.city_id = dc.city_id
    WHERE dud.created_ts IS NOT NULL
        AND dc.country_name IN (
       'Estonia', 'Latvia', 'Lithuania', 'Slovakia', 'Czech Republic', 'Malta',
        'Romania', 'Poland', 'Portugal', 'Ukraine', 'Cyprus',
        'Bulgaria', 'Azerbaijan', 'Ghana', 'Kenya')
),

weekly_country AS (
    SELECT
        week,
        country,
        COUNT(DISTINCT user_id) AS signup_users,
        SUM(is_same_day_activated) AS same_day_activations,
        SUM(is_same_day_activated) * 1.0 / NULLIF(signup_users, 0) AS same_day_activation_rate
    FROM base
    GROUP BY 1,2
),

weekly_with_shares AS (
    SELECT
        *,
        signup_users * 1.0
            / SUM(signup_users) OVER (PARTITION BY week)
            AS signup_share
    FROM weekly_country
),

weekly_yoy AS (
    SELECT
        cur.week,
        cur.country,

        cur.signup_users,
        cur.signup_share,
        cur.same_day_activation_rate,

        prev.signup_users AS signup_users_yoy,
        prev.signup_share AS signup_share_yoy,
        prev.same_day_activation_rate AS same_day_activation_rate_yoy

    FROM weekly_with_shares cur
    LEFT JOIN weekly_with_shares prev
        ON cur.country = prev.country
       AND cur.week = DATEADD(WEEK, 52, prev.week)
)

SELECT *
FROM weekly_yoy
WHERE week >= DATE '2024-01-01'
ORDER BY week, country
