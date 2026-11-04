-- =============================================================================
-- Daily V2 Cohort Performance (42-day window for table; trends use 08_cohort_trend_metrics.sql)
-- =============================================================================
-- Grain: metric_date × country × city_name × user_cohort × user_sub_cohort
--
-- city_name:
--   'All'  = country rollup; cohort_size = labelled users on that date
--   <city> = city attribution (Baltics+ only: ee/lv/lt/mt/ro/sk/cz);
--            cohort_size = distinct labelled users with order or session
--            activity in that city on that date
-- Definitions (aligned with weekly_gmv_cohort_bridge / Looker):
--   cohort_size   = see city_name note above
--   active_users  = distinct orderers with cohort label on order date
--   gmv_eur       = total_price_before_discount_eur
--   sessions      = Mixpanel delivery sessions (dine-in excluded)
--   bolt/provider = etl_delivery_campaign_order_metrics
-- =============================================================================

WITH bounds AS (
    SELECT
        CURRENT_DATE - INTERVAL 42 DAYS AS start_date,
        CURRENT_DATE AS end_date
),
date_spine AS (
    SELECT explode(sequence(
        (SELECT start_date FROM bounds),
        (SELECT end_date FROM bounds) - INTERVAL 1 DAY,
        INTERVAL 1 DAY
    )) AS metric_date
),
country_filter AS (
    SELECT country FROM VALUES
        ('gh'),('ke'),('lv'),('mt'),('ee'),('lt'),('pl'),('bg'),
        ('sk'),('cy'),('az'),('pt'),('cz'),('ro'),('ua'),('ge')
    AS t(country)
),
-- City deep-dive only for Baltics+ (keeps query size manageable)
city_grain_countries AS (
    SELECT country FROM VALUES
        ('ee'),('lv'),('lt'),('mt'),('ro'),('sk'),('cz')
    AS t(country)
),
country_names AS (
    SELECT DISTINCT
        LOWER(country_code) AS country,
        country_name
    FROM main.ng_delivery.dim_delivery_city
    WHERE LOWER(country_code) IN (SELECT country FROM country_filter)
),
cohort_daily AS (
    SELECT
        LOWER(c.country_code) AS country,
        c.user_id,
        c.metric_date,
        COALESCE(c.user_cohort, 'Unknown') AS user_cohort,
        COALESCE(c.user_sub_cohort, 'Unknown') AS user_sub_cohort
    FROM main.ng_delivery.int_user_metrics_user_cohort c
    WHERE LOWER(c.country_code) IN (SELECT country FROM country_filter)
      AND c.metric_date >= (SELECT start_date FROM bounds)
      AND c.metric_date <  (SELECT end_date FROM bounds)
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY LOWER(c.country_code), c.user_id, c.metric_date
        ORDER BY c.metric_date DESC
    ) = 1
),
orders AS (
    SELECT
        o.order_id,
        o.user_id,
        o.total_price_before_discount_eur AS gmv_eur,
        o.order_created_date,
        LOWER(o.country_code) AS country,
        COALESCE(o.city_name, 'Unknown') AS city_name
    FROM main.ng_delivery.dim_order_delivery o
    WHERE o.is_failed_order = false
      AND LOWER(o.country_code) IN (SELECT country FROM country_filter)
      AND o.order_created_date >= (SELECT start_date FROM bounds)
      AND o.order_created_date <  (SELECT end_date FROM bounds)
),
orders_cohort AS (
    SELECT
        o.country,
        o.city_name,
        o.order_created_date AS metric_date,
        COALESCE(c.user_cohort, 'Unknown') AS user_cohort,
        COALESCE(c.user_sub_cohort, 'Unknown') AS user_sub_cohort,
        o.order_id,
        o.user_id,
        o.gmv_eur
    FROM orders o
    LEFT JOIN cohort_daily c
      ON  o.user_id = c.user_id
      AND o.country = c.country
      AND o.order_created_date = c.metric_date
),
sessions AS (
    SELECT
        s.session_id,
        s.user_id,
        s.session_created_date,
        s.has_order_placed,
        LOWER(s.country_code) AS country,
        COALESCE(s.city_name, 'Unknown') AS city_name
    FROM main.ng_delivery.dim_session_user_delivery_mixpanel s
    WHERE COALESCE(s.is_dine_in_session, false) = false
      AND LOWER(s.country_code) IN (SELECT country FROM country_filter)
      AND s.session_created_date >= (SELECT start_date FROM bounds)
      AND s.session_created_date <  (SELECT end_date FROM bounds)
),
sessions_cohort AS (
    SELECT
        s.country,
        s.city_name,
        s.session_created_date AS metric_date,
        COALESCE(c.user_cohort, 'Unknown') AS user_cohort,
        COALESCE(c.user_sub_cohort, 'Unknown') AS user_sub_cohort,
        s.session_id,
        try_cast(s.user_id AS bigint) AS user_id,
        s.has_order_placed
    FROM sessions s
    LEFT JOIN cohort_daily c
      ON  try_cast(s.user_id AS bigint) = c.user_id
      AND s.country = c.country
      AND s.session_created_date = c.metric_date
),
spend AS (
    SELECT
        c.order_created_date,
        LOWER(c.country) AS country,
        COALESCE(d.city_name, 'Unknown') AS city_name,
        d.user_id,
        d.order_id,
        SUM(c.bolt_spend) AS bolt_spend_eur,
        SUM(c.provider_spend) AS provider_spend_eur,
        SUM(c.bolt_spend + c.provider_spend) AS total_spend_eur
    FROM main.ng_public.etl_delivery_campaign_order_metrics c
    INNER JOIN main.ng_delivery.dim_order_delivery d
        ON c.order_id = d.order_id
       AND c.order_created_date = d.order_created_date
    WHERE d.is_failed_order = false
      AND LOWER(c.country) IN (SELECT country FROM country_filter)
      AND c.order_created_date >= (SELECT start_date FROM bounds)
      AND c.order_created_date <  (SELECT end_date FROM bounds)
    GROUP BY 1, 2, 3, 4, 5
),
spend_cohort AS (
    SELECT
        s.country,
        s.city_name,
        s.order_created_date AS metric_date,
        COALESCE(c.user_cohort, 'Unknown') AS user_cohort,
        COALESCE(c.user_sub_cohort, 'Unknown') AS user_sub_cohort,
        s.order_id,
        s.bolt_spend_eur,
        s.provider_spend_eur,
        s.total_spend_eur
    FROM spend s
    LEFT JOIN cohort_daily c
      ON  s.user_id = c.user_id
      AND s.country = c.country
      AND s.order_created_date = c.metric_date
),

-- Country rollup (city = 'All'): labelled users on that date
size_country AS (
    SELECT
        country, metric_date,
        'All' AS city_name,
        user_cohort, user_sub_cohort,
        COUNT(DISTINCT user_id) AS cohort_size
    FROM cohort_daily
    GROUP BY 1, 2, 3, 4, 5
),

-- City grain: labelled users with order or session activity in that city
city_active_users AS (
    SELECT country, city_name, metric_date, user_cohort, user_sub_cohort, user_id
    FROM orders_cohort
    UNION
    SELECT country, city_name, metric_date, user_cohort, user_sub_cohort, user_id
    FROM sessions_cohort
    WHERE user_id IS NOT NULL
),
size_city AS (
    SELECT
        country, metric_date, city_name,
        user_cohort, user_sub_cohort,
        COUNT(DISTINCT user_id) AS cohort_size
    FROM city_active_users
    WHERE country IN (SELECT country FROM city_grain_countries)
    GROUP BY 1, 2, 3, 4, 5
),

order_metrics_country AS (
    SELECT
        country, metric_date,
        'All' AS city_name,
        user_cohort, user_sub_cohort,
        COUNT(DISTINCT user_id) AS active_users,
        COUNT(DISTINCT order_id) AS orders,
        ROUND(SUM(gmv_eur), 2) AS gmv_eur
    FROM orders_cohort
    GROUP BY 1, 2, 3, 4, 5
),
order_metrics_city AS (
    SELECT
        country, metric_date, city_name,
        user_cohort, user_sub_cohort,
        COUNT(DISTINCT user_id) AS active_users,
        COUNT(DISTINCT order_id) AS orders,
        ROUND(SUM(gmv_eur), 2) AS gmv_eur
    FROM orders_cohort
    WHERE country IN (SELECT country FROM city_grain_countries)
    GROUP BY 1, 2, 3, 4, 5
),

session_metrics_country AS (
    SELECT
        country, metric_date,
        'All' AS city_name,
        user_cohort, user_sub_cohort,
        COUNT(DISTINCT session_id) AS sessions,
        COUNT(DISTINCT CASE WHEN has_order_placed THEN session_id END) AS sessions_with_order
    FROM sessions_cohort
    GROUP BY 1, 2, 3, 4, 5
),
session_metrics_city AS (
    SELECT
        country, metric_date, city_name,
        user_cohort, user_sub_cohort,
        COUNT(DISTINCT session_id) AS sessions,
        COUNT(DISTINCT CASE WHEN has_order_placed THEN session_id END) AS sessions_with_order
    FROM sessions_cohort
    WHERE country IN (SELECT country FROM city_grain_countries)
    GROUP BY 1, 2, 3, 4, 5
),

spend_metrics_country AS (
    SELECT
        country, metric_date,
        'All' AS city_name,
        user_cohort, user_sub_cohort,
        ROUND(SUM(bolt_spend_eur), 2) AS bolt_spend_eur,
        ROUND(SUM(provider_spend_eur), 2) AS provider_spend_eur,
        ROUND(SUM(total_spend_eur), 2) AS total_spend_eur
    FROM spend_cohort
    GROUP BY 1, 2, 3, 4, 5
),
spend_metrics_city AS (
    SELECT
        country, metric_date, city_name,
        user_cohort, user_sub_cohort,
        ROUND(SUM(bolt_spend_eur), 2) AS bolt_spend_eur,
        ROUND(SUM(provider_spend_eur), 2) AS provider_spend_eur,
        ROUND(SUM(total_spend_eur), 2) AS total_spend_eur
    FROM spend_cohort
    WHERE country IN (SELECT country FROM city_grain_countries)
    GROUP BY 1, 2, 3, 4, 5
),

-- Country GMV denominator for % of country GMV (same at city rows — country total)
country_gmv AS (
    SELECT country, metric_date, ROUND(SUM(gmv_eur), 2) AS country_gmv_eur
    FROM orders_cohort
    GROUP BY 1, 2
),

size_all AS (
    SELECT * FROM size_country
    UNION ALL
    SELECT * FROM size_city
),
order_metrics AS (
    SELECT * FROM order_metrics_country
    UNION ALL
    SELECT * FROM order_metrics_city
),
session_metrics AS (
    SELECT * FROM session_metrics_country
    UNION ALL
    SELECT * FROM session_metrics_city
),
spend_metrics AS (
    SELECT * FROM spend_metrics_country
    UNION ALL
    SELECT * FROM spend_metrics_city
),

keys AS (
    SELECT country, metric_date, city_name, user_cohort, user_sub_cohort FROM size_all
    UNION
    SELECT country, metric_date, city_name, user_cohort, user_sub_cohort FROM order_metrics
    UNION
    SELECT country, metric_date, city_name, user_cohort, user_sub_cohort FROM session_metrics
    UNION
    SELECT country, metric_date, city_name, user_cohort, user_sub_cohort FROM spend_metrics
),
combined AS (
    SELECT
        k.country,
        k.city_name,
        k.metric_date,
        k.user_cohort,
        k.user_sub_cohort,
        COALESCE(sz.cohort_size, 0) AS cohort_size,
        COALESCE(om.active_users, 0) AS active_users,
        COALESCE(om.orders, 0) AS orders,
        COALESCE(om.gmv_eur, 0) AS gmv_eur,
        COALESCE(sm.sessions, 0) AS sessions,
        COALESCE(sm.sessions_with_order, 0) AS sessions_with_order,
        COALESCE(sp.bolt_spend_eur, 0) AS bolt_spend_eur,
        COALESCE(sp.provider_spend_eur, 0) AS provider_spend_eur,
        COALESCE(sp.total_spend_eur, 0) AS total_spend_eur,
        COALESCE(cg.country_gmv_eur, 0) AS country_gmv_eur
    FROM keys k
    LEFT JOIN size_all sz
      ON k.country = sz.country AND k.metric_date = sz.metric_date
     AND k.city_name = sz.city_name
     AND k.user_cohort = sz.user_cohort AND k.user_sub_cohort = sz.user_sub_cohort
    LEFT JOIN order_metrics om
      ON k.country = om.country AND k.metric_date = om.metric_date
     AND k.city_name = om.city_name
     AND k.user_cohort = om.user_cohort AND k.user_sub_cohort = om.user_sub_cohort
    LEFT JOIN session_metrics sm
      ON k.country = sm.country AND k.metric_date = sm.metric_date
     AND k.city_name = sm.city_name
     AND k.user_cohort = sm.user_cohort AND k.user_sub_cohort = sm.user_sub_cohort
    LEFT JOIN spend_metrics sp
      ON k.country = sp.country AND k.metric_date = sp.metric_date
     AND k.city_name = sp.city_name
     AND k.user_cohort = sp.user_cohort AND k.user_sub_cohort = sp.user_sub_cohort
    LEFT JOIN country_gmv cg
      ON k.country = cg.country AND k.metric_date = cg.metric_date
)
SELECT
    CAST(c.metric_date AS DATE) AS metric_date,
    c.country,
    COALESCE(cn.country_name, UPPER(c.country)) AS country_name,
    c.city_name,
    c.user_cohort,
    c.user_sub_cohort,
    c.cohort_size,
    c.active_users,
    c.orders,
    c.gmv_eur,
    c.sessions,
    c.sessions_with_order,
    ROUND(100.0 * c.sessions_with_order / NULLIF(c.sessions, 0), 2) AS session_to_order_conv_pct,
    c.bolt_spend_eur,
    c.provider_spend_eur,
    c.total_spend_eur,
    ROUND(c.total_spend_eur / NULLIF(c.orders, 0), 2) AS di_per_order,
    ROUND(100.0 * c.bolt_spend_eur / NULLIF(c.country_gmv_eur, 0), 4) AS bolt_pct_country_gmv,
    ROUND(100.0 * c.bolt_spend_eur / NULLIF(c.gmv_eur, 0), 4) AS bolt_pct_cohort_gmv,
    ROUND(100.0 * c.total_spend_eur / NULLIF(c.country_gmv_eur, 0), 4) AS total_pct_country_gmv,
    ROUND(100.0 * c.total_spend_eur / NULLIF(c.gmv_eur, 0), 4) AS total_pct_cohort_gmv,
    c.country_gmv_eur
FROM combined c
LEFT JOIN country_names cn ON c.country = cn.country
ORDER BY c.metric_date, c.country, c.city_name, c.user_cohort, c.user_sub_cohort
