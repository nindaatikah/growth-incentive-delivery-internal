-- =============================================================================
-- Cohort trend metrics (light): weekly 24w + monthly 12m, country rollup only
-- =============================================================================
-- Grain: grain × period_start × country × city_name='All' × user_cohort × user_sub_cohort
-- Daily trends use existing cohort_daily_metrics.csv (last 30 days) in the dashboard.
-- Country-only keeps this extract fast enough for Databricks SQL warehouse.
-- =============================================================================

WITH bounds AS (
    SELECT
        DATE_TRUNC('month', CURRENT_DATE) - INTERVAL 11 MONTHS AS start_date,
        CURRENT_DATE AS end_date,
        DATE_TRUNC('week', CURRENT_DATE) - INTERVAL 24 WEEKS AS weekly_start,
        DATE_TRUNC('week', CURRENT_DATE) - INTERVAL 7 DAYS AS last_full_week_start
),
periods AS (
    -- Weekly: last 24 ISO weeks (Mon starts), through last full week
    SELECT
        'weekly' AS grain,
        w AS period_start,
        DATE_ADD(w, 7) AS period_end_exclusive
    FROM (
        SELECT explode(sequence(
            (SELECT weekly_start FROM bounds),
            (SELECT last_full_week_start FROM bounds),
            INTERVAL 7 DAYS
        )) AS w
    )
    UNION ALL
    -- Monthly: last 12 calendar months including current month-to-date
    SELECT
        'monthly' AS grain,
        m AS period_start,
        ADD_MONTHS(m, 1) AS period_end_exclusive
    FROM (
        SELECT explode(sequence(
            (SELECT start_date FROM bounds),
            DATE_TRUNC('month', CURRENT_DATE),
            INTERVAL 1 MONTH
        )) AS m
    )
),
country_filter AS (
    SELECT country FROM VALUES
        ('gh'),('ke'),('lv'),('mt'),('ee'),('lt'),('pl'),('bg'),
        ('sk'),('cy'),('az'),('pt'),('cz'),('ro'),('ua'),('ge')
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
cohort_eop AS (
    SELECT
        p.grain,
        p.period_start,
        LOWER(c.country_code) AS country,
        c.user_id,
        max_by(COALESCE(c.user_cohort, 'Unknown'), c.metric_date) AS user_cohort,
        max_by(COALESCE(c.user_sub_cohort, 'Unknown'), c.metric_date) AS user_sub_cohort
    FROM main.ng_delivery.int_user_metrics_user_cohort c
    INNER JOIN periods p
      ON c.metric_date >= p.period_start
     AND c.metric_date <  LEAST(p.period_end_exclusive, (SELECT end_date FROM bounds))
    WHERE LOWER(c.country_code) IN (SELECT country FROM country_filter)
    GROUP BY p.grain, p.period_start, LOWER(c.country_code), c.user_id
),
orders AS (
    SELECT
        o.order_id,
        o.user_id,
        o.total_price_before_discount_eur AS gmv_eur,
        o.order_created_date,
        LOWER(o.country_code) AS country
    FROM main.ng_delivery.dim_order_delivery o
    WHERE o.is_failed_order = false
      AND LOWER(o.country_code) IN (SELECT country FROM country_filter)
      AND o.order_created_date >= (SELECT start_date FROM bounds)
      AND o.order_created_date <  (SELECT end_date FROM bounds)
),
orders_cohort AS (
    SELECT
        o.country,
        p.grain,
        p.period_start,
        COALESCE(c.user_cohort, 'Unknown') AS user_cohort,
        COALESCE(c.user_sub_cohort, 'Unknown') AS user_sub_cohort,
        o.order_id,
        o.user_id,
        o.gmv_eur
    FROM orders o
    JOIN periods p
      ON o.order_created_date >= p.period_start
     AND o.order_created_date <  LEAST(p.period_end_exclusive, (SELECT end_date FROM bounds))
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
        LOWER(s.country_code) AS country
    FROM main.ng_delivery.dim_session_user_delivery_mixpanel s
    WHERE COALESCE(s.is_dine_in_session, false) = false
      AND LOWER(s.country_code) IN (SELECT country FROM country_filter)
      AND s.session_created_date >= (SELECT start_date FROM bounds)
      AND s.session_created_date <  (SELECT end_date FROM bounds)
),
sessions_cohort AS (
    SELECT
        s.country,
        p.grain,
        p.period_start,
        COALESCE(c.user_cohort, 'Unknown') AS user_cohort,
        COALESCE(c.user_sub_cohort, 'Unknown') AS user_sub_cohort,
        s.session_id,
        try_cast(s.user_id AS bigint) AS user_id,
        s.has_order_placed
    FROM sessions s
    JOIN periods p
      ON s.session_created_date >= p.period_start
     AND s.session_created_date <  LEAST(p.period_end_exclusive, (SELECT end_date FROM bounds))
    LEFT JOIN cohort_daily c
      ON  try_cast(s.user_id AS bigint) = c.user_id
      AND s.country = c.country
      AND s.session_created_date = c.metric_date
),
spend AS (
    SELECT
        c.order_created_date,
        LOWER(c.country) AS country,
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
    GROUP BY 1, 2, 3, 4
),
spend_cohort AS (
    SELECT
        s.country,
        p.grain,
        p.period_start,
        COALESCE(c.user_cohort, 'Unknown') AS user_cohort,
        COALESCE(c.user_sub_cohort, 'Unknown') AS user_sub_cohort,
        s.order_id,
        s.bolt_spend_eur,
        s.provider_spend_eur,
        s.total_spend_eur
    FROM spend s
    JOIN periods p
      ON s.order_created_date >= p.period_start
     AND s.order_created_date <  LEAST(p.period_end_exclusive, (SELECT end_date FROM bounds))
    LEFT JOIN cohort_daily c
      ON  s.user_id = c.user_id
      AND s.country = c.country
      AND s.order_created_date = c.metric_date
),
size_country AS (
    SELECT
        grain, period_start, country,
        user_cohort, user_sub_cohort,
        COUNT(DISTINCT user_id) AS cohort_size
    FROM cohort_eop
    GROUP BY 1, 2, 3, 4, 5
),
order_metrics AS (
    SELECT
        grain, period_start, country,
        user_cohort, user_sub_cohort,
        COUNT(DISTINCT user_id) AS active_users,
        COUNT(DISTINCT order_id) AS orders,
        ROUND(SUM(gmv_eur), 2) AS gmv_eur
    FROM orders_cohort
    GROUP BY 1, 2, 3, 4, 5
),
session_metrics AS (
    SELECT
        grain, period_start, country,
        user_cohort, user_sub_cohort,
        COUNT(DISTINCT session_id) AS sessions,
        COUNT(DISTINCT CASE WHEN has_order_placed THEN session_id END) AS sessions_with_order
    FROM sessions_cohort
    GROUP BY 1, 2, 3, 4, 5
),
spend_metrics AS (
    SELECT
        grain, period_start, country,
        user_cohort, user_sub_cohort,
        ROUND(SUM(bolt_spend_eur), 2) AS bolt_spend_eur,
        ROUND(SUM(provider_spend_eur), 2) AS provider_spend_eur,
        ROUND(SUM(total_spend_eur), 2) AS total_spend_eur
    FROM spend_cohort
    GROUP BY 1, 2, 3, 4, 5
),
country_gmv AS (
    SELECT grain, period_start, country, ROUND(SUM(gmv_eur), 2) AS country_gmv_eur
    FROM orders_cohort
    GROUP BY 1, 2, 3
),
keys AS (
    SELECT grain, period_start, country, user_cohort, user_sub_cohort FROM size_country
    UNION
    SELECT grain, period_start, country, user_cohort, user_sub_cohort FROM order_metrics
    UNION
    SELECT grain, period_start, country, user_cohort, user_sub_cohort FROM session_metrics
    UNION
    SELECT grain, period_start, country, user_cohort, user_sub_cohort FROM spend_metrics
),
combined AS (
    SELECT
        k.grain,
        k.period_start,
        k.country,
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
    LEFT JOIN size_country sz
      ON k.grain = sz.grain AND k.period_start = sz.period_start AND k.country = sz.country
     AND k.user_cohort = sz.user_cohort AND k.user_sub_cohort = sz.user_sub_cohort
    LEFT JOIN order_metrics om
      ON k.grain = om.grain AND k.period_start = om.period_start AND k.country = om.country
     AND k.user_cohort = om.user_cohort AND k.user_sub_cohort = om.user_sub_cohort
    LEFT JOIN session_metrics sm
      ON k.grain = sm.grain AND k.period_start = sm.period_start AND k.country = sm.country
     AND k.user_cohort = sm.user_cohort AND k.user_sub_cohort = sm.user_sub_cohort
    LEFT JOIN spend_metrics sp
      ON k.grain = sp.grain AND k.period_start = sp.period_start AND k.country = sp.country
     AND k.user_cohort = sp.user_cohort AND k.user_sub_cohort = sp.user_sub_cohort
    LEFT JOIN country_gmv cg
      ON k.grain = cg.grain AND k.period_start = cg.period_start AND k.country = cg.country
)
SELECT
    c.grain,
    CAST(c.period_start AS DATE) AS period_start,
    c.country,
    COALESCE(cn.country_name, UPPER(c.country)) AS country_name,
    'All' AS city_name,
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
ORDER BY c.grain, c.period_start, c.country, c.user_cohort, c.user_sub_cohort
