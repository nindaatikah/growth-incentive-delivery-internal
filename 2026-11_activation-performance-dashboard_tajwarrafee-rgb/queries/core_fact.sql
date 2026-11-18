WITH tourist_info AS (
    SELECT
        uu.id AS user_id,
        MAX(CASE WHEN phone_anonymized = REPLACE(phone_prefix, '+', '') THEN 1 ELSE 0 END) AS is_local
    FROM main.ng_public.user_user uu
    LEFT JOIN main.ng_delivery.dim_delivery_city dc
        ON uu.home_city_id = dc.city_id
    LEFT JOIN main.ng_public.admin_system_country c
        ON dc.country_code = c.code
    GROUP BY 1
),

base AS (
    SELECT
        dud.user_id,
        COALESCE(dc.country_name, 'Unknown') AS country,
        COALESCE(dc.city_name, 'Unknown') AS city,
        CASE 
            WHEN dud.created_ts >= dc.food_delivery_launch_date
                AND DATEDIFF(DATE_TRUNC('WEEK', dud.created_ts),DATE_TRUNC('WEEK', dc.food_delivery_launch_date)) < 16
            THEN 1
            ELSE 0
        END AS is_new_city,


        CASE
            WHEN dud.app_install_channel_name IN ('organic', 'RiderApp') THEN dud.app_install_channel_name
            WHEN dud.app_install_channel_name IN ('Google Ads','Tiktok Ads','Facebook Ads') THEN 'social_Ads'
            --WHEN dud.app_install_channel_name IS NULL THEN 'Unknown'
            ELSE 'rest'
        END AS media_group,

        COALESCE(t.is_local, 0) AS is_local,

        dud.created_ts AS signup_ts,
        dud.delivery_activation_ts AS activation_ts,

        DATE_TRUNC('DAY', dud.created_ts) AS signup_date,
        DATE_TRUNC('DAY', dud.delivery_activation_ts) AS activation_date,

        DATEDIFF(DATE_TRUNC('DAY', dud.delivery_activation_ts), DATE_TRUNC('DAY', dud.created_ts)) AS activation_lag_days
    FROM main.ng_delivery.dim_user_delivery dud
    LEFT JOIN tourist_info t
        ON dud.user_id = t.user_id
    LEFT JOIN main.ng_delivery.dim_delivery_city dc
        ON dud.city_id = dc.city_id
),

orders_ranked AS (
    SELECT
        user_id,
        order_id,
        order_created,
        CAST(order_created AS DATE) AS order_date,
        gmv_eur,
        (bolt_delivery_campaign_cost_eur + bolt_menu_campaign_cost_eur) AS bolt_spend,
        (provider_delivery_campaign_cost_eur + provider_menu_campaign_cost_eur) AS provider_spend,
        (bolt_delivery_campaign_cost_eur + bolt_menu_campaign_cost_eur
         + provider_delivery_campaign_cost_eur + provider_menu_campaign_cost_eur) AS total_spend,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY order_created) AS order_rank
    FROM main.ng_public.etl_delivery_order_monetary_metrics
),

user_order_metrics AS (
    SELECT
        b.user_id,
        b.signup_ts,
        b.activation_ts,

        MIN(CASE WHEN o.order_rank = 1 THEN o.order_created END) AS first_order_ts,
        MAX(CASE WHEN o.order_rank = 1 THEN o.gmv_eur END) AS first_order_gmv,
        MAX(CASE WHEN o.order_rank = 1 THEN o.total_spend END) AS first_order_discount,
        MAX(CASE WHEN o.order_rank = 1 THEN o.bolt_spend END) AS first_order_discount_bolt,

        COUNT(CASE WHEN o.order_created <= DATEADD(DAY, 7, b.activation_ts) THEN o.order_id END) AS orders_7d,
        COUNT(CASE WHEN o.order_created <= DATEADD(DAY, 30, b.activation_ts) THEN o.order_id END) AS orders_30d,

        SUM(CASE WHEN o.order_created <= DATEADD(DAY, 30, b.activation_ts) THEN o.gmv_eur END) AS gmv_30d,
        SUM(CASE WHEN o.order_created <= DATEADD(DAY, 30, b.activation_ts) THEN o.total_spend END) AS discount_30d,
        SUM(CASE WHEN o.order_created <= DATEADD(DAY, 30, b.activation_ts) THEN o.bolt_spend END) AS discount_30d_bolt,

        MIN(CASE WHEN o.order_rank = 2 THEN o.order_created END) AS second_order_ts
    FROM base b
    LEFT JOIN orders_ranked o
        ON b.user_id = o.user_id
    WHERE b.activation_ts IS NOT NULL
    GROUP BY 1,2,3
),

user_metrics AS (
    SELECT
        user_id,
        CAST(TIMESTAMPDIFF(SECOND, signup_ts, first_order_ts) / 60.0 AS DOUBLE) AS time_to_first_order_minutes,
        orders_30d,
        orders_7d,
        DATEDIFF(second_order_ts, first_order_ts) AS days_to_second_order,
        CASE WHEN orders_7d >= 2 THEN 1 ELSE 0 END AS is_power_user_7d,
        CASE WHEN orders_30d >= 2 THEN 1 ELSE 0 END AS is_power_user_30d
    FROM user_order_metrics
),

signup_data AS (
    SELECT
        signup_date AS event_date,
        country, city, is_new_city, media_group, is_local,
        COUNT(DISTINCT user_id) AS signup_users
    FROM base
    GROUP BY 1,2,3,4,5,6
),

activation_data AS (
    SELECT
        b.activation_date AS event_date,
        b.country, b.city, b.is_new_city, b.media_group, b.is_local,

        COUNT(DISTINCT b.user_id) AS activated_users,
        COUNT(DISTINCT CASE WHEN b.activation_lag_days = 0 THEN b.user_id END) AS activated_users_d0,
        COUNT(DISTINCT CASE WHEN b.activation_lag_days between 1 and 14 THEN b.user_id END) AS activated_users_d14,
        COUNT(DISTINCT CASE WHEN b.activation_lag_days > 14 THEN b.user_id END) AS activated_users_d14_plus,

        SUM(uom.first_order_gmv) AS first_order_gmv,
        SUM(uom.first_order_discount) AS first_order_discount,
        SUM(uom.first_order_discount_bolt) AS first_order_discount_bolt,

        SUM(uom.gmv_30d) AS gmv_30d,
        SUM(uom.discount_30d) AS discount_30d,
        SUM(uom.discount_30d_bolt) AS discount_30d_bolt,

        SUM(um.orders_30d) AS orders_30d,
        SUM(um.days_to_second_order) AS days_to_second_order,
        SUM(um.time_to_first_order_minutes) AS time_to_first_order_minutes,
        SUM(um.time_to_first_order_minutes) FILTER (WHERE b.activation_lag_days = 0) AS time_to_first_order_minutes_d0,
        SUM(um.is_power_user_7d) AS power_users_7d,
        SUM(um.is_power_user_30d) AS power_users_30d

    FROM base b
    LEFT JOIN user_order_metrics uom
        ON b.user_id = uom.user_id
    LEFT JOIN user_metrics um
        ON b.user_id = um.user_id
    WHERE b.activation_date IS NOT NULL
    GROUP BY 1,2,3,4,5,6
)

SELECT
    COALESCE(s.event_date, a.event_date) AS event_date,
    COALESCE(s.country, a.country) AS country,
    COALESCE(s.city, a.city) AS city,
    COALESCE(s.is_new_city, a.is_new_city) AS is_new_city,
    COALESCE(s.media_group, a.media_group) AS media_group,
    COALESCE(s.is_local, a.is_local) AS is_local,

    COALESCE(s.signup_users, 0) AS signup_users,

    COALESCE(a.activated_users, 0) AS activated_users,
    COALESCE(a.activated_users_d0, 0) AS activated_users_d0,
    COALESCE(a.activated_users_d14, 0) AS activated_users_d14,
    COALESCE(a.activated_users_d14_plus, 0) AS activated_users_d14_plus,

    a.first_order_gmv,
    a.first_order_discount,
    a.first_order_discount_bolt,
    a.gmv_30d,
    a.discount_30d,
    a.discount_30d_bolt,
    a.orders_30d,
    a.days_to_second_order,
    a.time_to_first_order_minutes,
    a.time_to_first_order_minutes_d0,
    a.power_users_7d,
    a.power_users_30d
FROM signup_data s
FULL OUTER JOIN activation_data a
    ON s.event_date = a.event_date
   AND s.country = a.country
   AND s.city = a.city
   AND s.is_new_city = a.is_new_city
   AND s.media_group = a.media_group
   AND s.is_local = a.is_local
