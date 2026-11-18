WITH base AS (
    SELECT
        dud.user_id,

        CASE
            WHEN dud.app_install_channel_name IN ('organic', 'RiderApp')THEN dud.app_install_channel_name
            WHEN dud.app_install_channel_name IN ('Google Ads','Tiktok Ads','Facebook Ads') THEN 'social_Ads'
            --WHEN dud.app_install_channel_name IS NULL THEN 'Unknown'
            ELSE 'rest'
        END AS media_group,

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
        and dc.country_name IN (
                'Estonia', 'Latvia', 'Lithuania', 'Slovakia', 'Czech Republic', 'Malta',
                'Romania', 'Poland', 'Portugal', 'Ukraine', 'Cyprus',
                'Bulgaria', 'Azerbaijan', 'Ghana', 'Kenya')
),

weekly_media AS (
    SELECT
        week,
        media_group,
        COUNT(DISTINCT user_id) AS signup_users,
        SUM(is_same_day_activated) AS same_day_activations,
        SUM(is_same_day_activated) * 1.0
            / NULLIF(COUNT(DISTINCT user_id), 0) AS same_day_activation_rate
    FROM base
    GROUP BY 1,2
),

weekly_with_shares AS (
    SELECT
        *,
        signup_users * 1.0
            / SUM(signup_users) OVER (PARTITION BY week)
            AS signup_share
    FROM weekly_media
),

weekly_yoy AS (
    SELECT
        cur.week,
        cur.media_group,

        cur.signup_users,
        cur.signup_share,
        cur.same_day_activation_rate,

        prev.signup_users AS signup_users_yoy,
        prev.signup_share AS signup_share_yoy,
        prev.same_day_activation_rate AS same_day_activation_rate_yoy

    FROM weekly_with_shares cur
    LEFT JOIN weekly_with_shares prev
        ON cur.media_group = prev.media_group
       AND cur.week = DATEADD(WEEK, 52, prev.week)
)

SELECT *
FROM weekly_yoy
WHERE week >= DATE '2024-01-01'
ORDER BY week, media_group
