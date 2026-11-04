-- Parameterized liquidity zone map + zone detail metrics (YoY windows set in Python).
-- Placeholders: __ZONE_COL__, __CURR_START__, __CURR_END__, __BASE_START__, __BASE_END__
-- __INCLUDE_SESSIONS__ = 1 adds session CTE; 0 omits (provider zone mode).

WITH target_cities AS (
    SELECT DISTINCT city_name
    FROM main.ng_delivery.dim_delivery_city
    WHERE is_primary_city = true
      AND COALESCE(is_city_active, true) = true
),

zone_orders AS (
    SELECT
        LOWER(o.country_code) AS country,
        o.city_name,
        o.__ZONE_COL__ AS zone_name,
        CASE
            WHEN o.order_created_date >= DATE '__BASE_START__'
             AND o.order_created_date <  DATE '__BASE_END__' THEN 'base'
            WHEN o.order_created_date >= DATE '__CURR_START__'
             AND o.order_created_date <  DATE '__CURR_END__' THEN 'curr'
        END AS period,
        o.order_id,
        o.user_id,
        o.provider_id,
        o.total_price_before_discount_eur AS gmv_eur
    FROM main.ng_delivery.dim_order_delivery o
    WHERE o.is_failed_order = false
      AND o.city_name IN (SELECT city_name FROM target_cities)
      AND o.__ZONE_COL__ IS NOT NULL
      AND TRIM(o.__ZONE_COL__) <> ''
      AND LOWER(o.__ZONE_COL__) <> 'undefined'
      AND (
          (o.order_created_date >= DATE '__BASE_START__' AND o.order_created_date < DATE '__BASE_END__')
       OR (o.order_created_date >= DATE '__CURR_START__' AND o.order_created_date < DATE '__CURR_END__')
      )
),

zone_gmv AS (
    SELECT
        country,
        city_name,
        zone_name,
        ROUND(SUM(CASE WHEN period = 'base' THEN gmv_eur ELSE 0 END), 2) AS gmv_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN gmv_eur ELSE 0 END), 2) AS gmv_curr,
        COUNT(DISTINCT CASE WHEN period = 'base' THEN order_id END) AS orders_base,
        COUNT(DISTINCT CASE WHEN period = 'curr' THEN order_id END) AS orders_curr,
        COUNT(DISTINCT CASE WHEN period = 'base' THEN user_id END) AS users_base,
        COUNT(DISTINCT CASE WHEN period = 'curr' THEN user_id END) AS users_curr,
        COUNT(DISTINCT CASE WHEN period = 'base' THEN provider_id END) AS merchants_base,
        COUNT(DISTINCT CASE WHEN period = 'curr' THEN provider_id END) AS merchants_curr,
        ROUND((SUM(CASE WHEN period = 'curr' THEN gmv_eur ELSE 0 END)
             - SUM(CASE WHEN period = 'base' THEN gmv_eur ELSE 0 END))
            * 100.0 / NULLIF(SUM(CASE WHEN period = 'base' THEN gmv_eur ELSE 0 END), 0), 1) AS gmv_yoy_pct
    FROM zone_orders
    WHERE period IS NOT NULL
    GROUP BY 1, 2, 3
),

zone_sessions AS (
    SELECT
        LOWER(s.country_code) AS country,
        s.city_name,
        s.zone_name AS zone_name,
        CASE
            WHEN s.session_created_date >= DATE '__BASE_START__'
             AND s.session_created_date <  DATE '__BASE_END__' THEN 'base'
            WHEN s.session_created_date >= DATE '__CURR_START__'
             AND s.session_created_date <  DATE '__CURR_END__' THEN 'curr'
        END AS period,
        COUNT(DISTINCT s.session_id) AS sessions,
        COUNT(DISTINCT CASE WHEN s.has_order_placed THEN s.session_id END) AS sessions_with_order
    FROM main.ng_delivery.dim_session_user_delivery_mixpanel s
    WHERE __INCLUDE_SESSIONS__ = 1
      AND COALESCE(s.is_dine_in_session, false) = false
      AND s.city_name IN (SELECT city_name FROM target_cities)
      AND s.zone_name IS NOT NULL
      AND TRIM(s.zone_name) <> ''
      AND LOWER(s.zone_name) <> 'undefined'
      AND (
          (s.session_created_date >= DATE '__BASE_START__' AND s.session_created_date < DATE '__BASE_END__')
       OR (s.session_created_date >= DATE '__CURR_START__' AND s.session_created_date < DATE '__CURR_END__')
      )
    GROUP BY 1, 2, 3, 4
),

zone_sessions_pivot AS (
    SELECT
        country,
        city_name,
        zone_name,
        SUM(CASE WHEN period = 'base' THEN sessions ELSE 0 END) AS sessions_base,
        SUM(CASE WHEN period = 'curr' THEN sessions ELSE 0 END) AS sessions_curr,
        SUM(CASE WHEN period = 'base' THEN sessions_with_order ELSE 0 END) AS swo_base,
        SUM(CASE WHEN period = 'curr' THEN sessions_with_order ELSE 0 END) AS swo_curr
    FROM zone_sessions
    WHERE period IS NOT NULL
    GROUP BY 1, 2, 3
),

zone_spend AS (
    SELECT
        LOWER(c.country) AS country,
        d.city_name,
        d.__ZONE_COL__ AS zone_name,
        CASE
            WHEN c.order_created_date >= DATE '__BASE_START__'
             AND c.order_created_date <  DATE '__BASE_END__' THEN 'base'
            WHEN c.order_created_date >= DATE '__CURR_START__'
             AND c.order_created_date <  DATE '__CURR_END__' THEN 'curr'
        END AS period,
        ROUND(SUM(c.bolt_spend), 2) AS bolt_spend_eur,
        ROUND(SUM(c.provider_spend), 2) AS provider_spend_eur,
        ROUND(SUM(c.bolt_spend) + SUM(c.provider_spend), 2) AS total_spend_eur
    FROM main.ng_public.etl_delivery_campaign_order_metrics c
    INNER JOIN main.ng_delivery.dim_order_delivery d
        ON c.order_id = d.order_id
        AND c.order_created_date = d.order_created_date
    WHERE d.is_failed_order = false
      AND d.city_name IN (SELECT city_name FROM target_cities)
      AND d.__ZONE_COL__ IS NOT NULL
      AND TRIM(d.__ZONE_COL__) <> ''
      AND LOWER(d.__ZONE_COL__) <> 'undefined'
      AND (
          (c.order_created_date >= DATE '__BASE_START__' AND c.order_created_date < DATE '__BASE_END__')
       OR (c.order_created_date >= DATE '__CURR_START__' AND c.order_created_date < DATE '__CURR_END__')
      )
    GROUP BY 1, 2, 3, 4
),

zone_spend_pivot AS (
    SELECT
        country,
        city_name,
        zone_name,
        ROUND(SUM(CASE WHEN period = 'base' THEN bolt_spend_eur ELSE 0 END), 2) AS bolt_spend_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN bolt_spend_eur ELSE 0 END), 2) AS bolt_spend_curr,
        ROUND(SUM(CASE WHEN period = 'base' THEN provider_spend_eur ELSE 0 END), 2) AS provider_spend_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN provider_spend_eur ELSE 0 END), 2) AS provider_spend_curr,
        ROUND(SUM(CASE WHEN period = 'base' THEN total_spend_eur ELSE 0 END), 2) AS total_spend_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN total_spend_eur ELSE 0 END), 2) AS total_spend_curr
    FROM zone_spend
    WHERE period IS NOT NULL
    GROUP BY 1, 2, 3
),

zone_segment_orders AS (
    SELECT
        LOWER(o.country_code) AS country,
        o.city_name,
        o.__ZONE_COL__ AS zone_name,
        COALESCE(p.business_segment_v2, 'Unknown') AS merchant_segment,
        CASE
            WHEN o.order_created_date >= DATE '__BASE_START__'
             AND o.order_created_date <  DATE '__BASE_END__' THEN 'base'
            WHEN o.order_created_date >= DATE '__CURR_START__'
             AND o.order_created_date <  DATE '__CURR_END__' THEN 'curr'
        END AS period,
        COUNT(DISTINCT o.order_id) AS orders,
        COUNT(DISTINCT o.provider_id) AS merchants,
        ROUND(SUM(o.total_price_before_discount_eur), 2) AS gmv_eur
    FROM main.ng_delivery.dim_order_delivery o
    LEFT JOIN main.ng_delivery.dim_provider_v2 p
        ON o.provider_id = p.provider_id
    WHERE o.is_failed_order = false
      AND o.city_name IN (SELECT city_name FROM target_cities)
      AND o.__ZONE_COL__ IS NOT NULL
      AND TRIM(o.__ZONE_COL__) <> ''
      AND LOWER(o.__ZONE_COL__) <> 'undefined'
      AND (
          (o.order_created_date >= DATE '__BASE_START__' AND o.order_created_date < DATE '__BASE_END__')
       OR (o.order_created_date >= DATE '__CURR_START__' AND o.order_created_date < DATE '__CURR_END__')
      )
    GROUP BY 1, 2, 3, 4, 5
),

zone_segment_spend AS (
    SELECT
        LOWER(c.country) AS country,
        d.city_name,
        d.__ZONE_COL__ AS zone_name,
        COALESCE(p.business_segment_v2, 'Unknown') AS merchant_segment,
        CASE
            WHEN c.order_created_date >= DATE '__BASE_START__'
             AND c.order_created_date <  DATE '__BASE_END__' THEN 'base'
            WHEN c.order_created_date >= DATE '__CURR_START__'
             AND c.order_created_date <  DATE '__CURR_END__' THEN 'curr'
        END AS period,
        ROUND(SUM(c.bolt_spend), 2) AS bolt_spend_eur,
        ROUND(SUM(c.provider_spend), 2) AS provider_spend_eur,
        ROUND(SUM(c.bolt_spend) + SUM(c.provider_spend), 2) AS total_spend_eur
    FROM main.ng_public.etl_delivery_campaign_order_metrics c
    INNER JOIN main.ng_delivery.dim_order_delivery d
        ON c.order_id = d.order_id
        AND c.order_created_date = d.order_created_date
    LEFT JOIN main.ng_delivery.dim_provider_v2 p
        ON d.provider_id = p.provider_id
    WHERE d.is_failed_order = false
      AND d.city_name IN (SELECT city_name FROM target_cities)
      AND d.__ZONE_COL__ IS NOT NULL
      AND TRIM(d.__ZONE_COL__) <> ''
      AND LOWER(d.__ZONE_COL__) <> 'undefined'
      AND (
          (c.order_created_date >= DATE '__BASE_START__' AND c.order_created_date < DATE '__BASE_END__')
       OR (c.order_created_date >= DATE '__CURR_START__' AND c.order_created_date < DATE '__CURR_END__')
      )
    GROUP BY 1, 2, 3, 4, 5
),

zone_segment_orders_pivot AS (
    SELECT
        country,
        city_name,
        zone_name,
        merchant_segment,
        ROUND(SUM(CASE WHEN period = 'base' THEN gmv_eur ELSE 0 END), 2) AS gmv_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN gmv_eur ELSE 0 END), 2) AS gmv_curr,
        SUM(CASE WHEN period = 'base' THEN orders ELSE 0 END) AS orders_base,
        SUM(CASE WHEN period = 'curr' THEN orders ELSE 0 END) AS orders_curr,
        SUM(CASE WHEN period = 'base' THEN merchants ELSE 0 END) AS merchants_base,
        SUM(CASE WHEN period = 'curr' THEN merchants ELSE 0 END) AS merchants_curr
    FROM zone_segment_orders
    WHERE period IS NOT NULL
    GROUP BY 1, 2, 3, 4
),

zone_segment_spend_pivot AS (
    SELECT
        country,
        city_name,
        zone_name,
        merchant_segment,
        ROUND(SUM(CASE WHEN period = 'base' THEN bolt_spend_eur ELSE 0 END), 2) AS bolt_spend_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN bolt_spend_eur ELSE 0 END), 2) AS bolt_spend_curr,
        ROUND(SUM(CASE WHEN period = 'base' THEN provider_spend_eur ELSE 0 END), 2) AS provider_spend_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN provider_spend_eur ELSE 0 END), 2) AS provider_spend_curr,
        ROUND(SUM(CASE WHEN period = 'base' THEN total_spend_eur ELSE 0 END), 2) AS total_spend_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN total_spend_eur ELSE 0 END), 2) AS total_spend_curr
    FROM zone_segment_spend
    WHERE period IS NOT NULL
    GROUP BY 1, 2, 3, 4
),

zone_segment_pivot AS (
    SELECT
        COALESCE(o.country, s.country) AS country,
        COALESCE(o.city_name, s.city_name) AS city_name,
        COALESCE(o.zone_name, s.zone_name) AS zone_name,
        COALESCE(o.merchant_segment, s.merchant_segment) AS merchant_segment,
        COALESCE(o.gmv_base, 0) AS gmv_base,
        COALESCE(o.gmv_curr, 0) AS gmv_curr,
        COALESCE(o.orders_base, 0) AS orders_base,
        COALESCE(o.orders_curr, 0) AS orders_curr,
        COALESCE(o.merchants_base, 0) AS merchants_base,
        COALESCE(o.merchants_curr, 0) AS merchants_curr,
        COALESCE(s.bolt_spend_base, 0) AS bolt_spend_base,
        COALESCE(s.bolt_spend_curr, 0) AS bolt_spend_curr,
        COALESCE(s.provider_spend_base, 0) AS provider_spend_base,
        COALESCE(s.provider_spend_curr, 0) AS provider_spend_curr,
        COALESCE(s.total_spend_base, 0) AS total_spend_base,
        COALESCE(s.total_spend_curr, 0) AS total_spend_curr
    FROM zone_segment_orders_pivot o
    FULL OUTER JOIN zone_segment_spend_pivot s
        ON o.country = s.country
        AND o.city_name = s.city_name
        AND o.zone_name = s.zone_name
        AND o.merchant_segment = s.merchant_segment
),

zone_objective_spend AS (
    SELECT
        LOWER(c.country) AS country,
        d.city_name,
        d.__ZONE_COL__ AS zone_name,
        COALESCE(c.spend_objective, 'Unknown') AS spend_objective,
        CASE
            WHEN c.order_created_date >= DATE '__BASE_START__'
             AND c.order_created_date <  DATE '__BASE_END__' THEN 'base'
            WHEN c.order_created_date >= DATE '__CURR_START__'
             AND c.order_created_date <  DATE '__CURR_END__' THEN 'curr'
        END AS period,
        ROUND(SUM(c.bolt_spend), 2) AS bolt_spend_eur,
        ROUND(SUM(c.provider_spend), 2) AS provider_spend_eur,
        ROUND(SUM(c.bolt_spend) + SUM(c.provider_spend), 2) AS total_spend_eur
    FROM main.ng_public.etl_delivery_campaign_order_metrics c
    INNER JOIN main.ng_delivery.dim_order_delivery d
        ON c.order_id = d.order_id
        AND c.order_created_date = d.order_created_date
    WHERE d.is_failed_order = false
      AND d.city_name IN (SELECT city_name FROM target_cities)
      AND d.__ZONE_COL__ IS NOT NULL
      AND TRIM(d.__ZONE_COL__) <> ''
      AND LOWER(d.__ZONE_COL__) <> 'undefined'
      AND (
          (c.order_created_date >= DATE '__BASE_START__' AND c.order_created_date < DATE '__BASE_END__')
       OR (c.order_created_date >= DATE '__CURR_START__' AND c.order_created_date < DATE '__CURR_END__')
      )
    GROUP BY 1, 2, 3, 4, 5
),

zone_objective_pivot AS (
    SELECT
        country,
        city_name,
        zone_name,
        spend_objective,
        ROUND(SUM(CASE WHEN period = 'base' THEN bolt_spend_eur ELSE 0 END), 2) AS bolt_spend_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN bolt_spend_eur ELSE 0 END), 2) AS bolt_spend_curr,
        ROUND(SUM(CASE WHEN period = 'base' THEN provider_spend_eur ELSE 0 END), 2) AS provider_spend_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN provider_spend_eur ELSE 0 END), 2) AS provider_spend_curr,
        ROUND(SUM(CASE WHEN period = 'base' THEN total_spend_eur ELSE 0 END), 2) AS total_spend_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN total_spend_eur ELSE 0 END), 2) AS total_spend_curr
    FROM zone_objective_spend
    WHERE period IS NOT NULL
    GROUP BY 1, 2, 3, 4
),

zone_objective_json AS (
    SELECT
        country,
        city_name,
        zone_name,
        TO_JSON(
            SORT_ARRAY(
                COLLECT_LIST(
                    NAMED_STRUCT(
                        'objective', spend_objective,
                        'boltBase', bolt_spend_base,
                        'boltCurr', bolt_spend_curr,
                        'boltYoy', ROUND((bolt_spend_curr - bolt_spend_base) * 100.0 / NULLIF(bolt_spend_base, 0), 1),
                        'provBase', provider_spend_base,
                        'provCurr', provider_spend_curr,
                        'provYoy', ROUND((provider_spend_curr - provider_spend_base) * 100.0 / NULLIF(provider_spend_base, 0), 1),
                        'totalBase', total_spend_base,
                        'totalCurr', total_spend_curr,
                        'totalYoy', ROUND((total_spend_curr - total_spend_base) * 100.0 / NULLIF(total_spend_base, 0), 1)
                    )
                ),
                true
            )
        ) AS objective_spend_json
    FROM zone_objective_pivot
    WHERE bolt_spend_base > 0 OR bolt_spend_curr > 0
       OR provider_spend_base > 0 OR provider_spend_curr > 0
    GROUP BY 1, 2, 3
),

zone_segment_json AS (
    SELECT
        country,
        city_name,
        zone_name,
        TO_JSON(
            SORT_ARRAY(
                COLLECT_LIST(
                    NAMED_STRUCT(
                        'segment', merchant_segment,
                        'gmvBase', gmv_base,
                        'gmvCurr', gmv_curr,
                        'gmvYoy', ROUND((gmv_curr - gmv_base) * 100.0 / NULLIF(gmv_base, 0), 1),
                        'ordersBase', orders_base,
                        'ordersCurr', orders_curr,
                        'ordersYoy', ROUND((orders_curr - orders_base) * 100.0 / NULLIF(orders_base, 0), 1),
                        'merchantsBase', merchants_base,
                        'merchantsCurr', merchants_curr,
                        'merchantsYoy', ROUND((merchants_curr - merchants_base) * 100.0 / NULLIF(merchants_base, 0), 1),
                        'boltBase', bolt_spend_base,
                        'boltCurr', bolt_spend_curr,
                        'boltYoy', ROUND((bolt_spend_curr - bolt_spend_base) * 100.0 / NULLIF(bolt_spend_base, 0), 1),
                        'provBase', provider_spend_base,
                        'provCurr', provider_spend_curr,
                        'provYoy', ROUND((provider_spend_curr - provider_spend_base) * 100.0 / NULLIF(provider_spend_base, 0), 1),
                        'totalBase', total_spend_base,
                        'totalCurr', total_spend_curr,
                        'totalYoy', ROUND((total_spend_curr - total_spend_base) * 100.0 / NULLIF(total_spend_base, 0), 1),
                        'spendPctGmvBase', ROUND(total_spend_base * 100.0 / NULLIF(gmv_base, 0), 1),
                        'spendPctGmvCurr', ROUND(total_spend_curr * 100.0 / NULLIF(gmv_curr, 0), 1),
                        'spendPctGmvPp', ROUND(
                            (total_spend_curr * 100.0 / NULLIF(gmv_curr, 0))
                          - (total_spend_base * 100.0 / NULLIF(gmv_base, 0))
                        , 1)
                    )
                ),
                true
            )
        ) AS segment_spend_json
    FROM zone_segment_pivot
    WHERE merchant_segment <> 'Missing Segment'
      AND (gmv_base > 0 OR gmv_curr > 0 OR bolt_spend_base > 0 OR bolt_spend_curr > 0
           OR provider_spend_base > 0 OR provider_spend_curr > 0)
    GROUP BY 1, 2, 3
),

liquidity_spend_base AS (
    SELECT
        LOWER(c.country) AS country,
        d.city_name,
        d.__ZONE_COL__ AS zone_name,
        ROUND(SUM(c.bolt_spend) + SUM(c.provider_spend), 2) AS liquidity_spend_eur
    FROM main.ng_public.etl_delivery_campaign_order_metrics c
    INNER JOIN main.ng_delivery.dim_order_delivery d
        ON c.order_id = d.order_id
        AND c.order_created_date = d.order_created_date
    WHERE c.order_created_date >= DATE '__BASE_START__'
      AND c.order_created_date <  DATE '__BASE_END__'
      AND LOWER(c.spend_objective) LIKE '%liquidity%'
      AND LOWER(c.spend_objective) NOT LIKE 'bolt_market%'
      AND d.city_name IN (SELECT city_name FROM target_cities)
      AND d.__ZONE_COL__ IS NOT NULL
      AND TRIM(d.__ZONE_COL__) <> ''
      AND LOWER(d.__ZONE_COL__) <> 'undefined'
      AND d.is_failed_order = false
    GROUP BY 1, 2, 3
),

city_bounds AS (
    SELECT
        city_name,
        MAX(city_polygon) AS city_polygon
    FROM main.ng_delivery.dim_delivery_city
    WHERE city_name IN (SELECT city_name FROM target_cities)
    GROUP BY 1
)

SELECT
    zg.country,
    zg.city_name,
    zg.zone_name,
    zg.gmv_base,
    zg.gmv_curr,
    zg.gmv_yoy_pct,
    zg.orders_base,
    zg.orders_curr,
    zg.users_base,
    zg.users_curr,
    zg.merchants_base,
    zg.merchants_curr,
    COALESCE(zss.sessions_base, 0) AS sessions_base,
    COALESCE(zss.sessions_curr, 0) AS sessions_curr,
    COALESCE(zss.swo_base, 0) AS sessions_with_order_base,
    COALESCE(zss.swo_curr, 0) AS sessions_with_order_curr,
    COALESCE(ls.liquidity_spend_eur, 0) AS liquidity_spend_base_period,
    CASE WHEN COALESCE(ls.liquidity_spend_eur, 0) > 0 THEN true ELSE false END AS had_liquidity_investment,
    ROUND(100.0 * COALESCE(zsp.bolt_spend_base, 0) / NULLIF(zg.gmv_base, 0), 2) AS bolt_di_pct_base,
    ROUND(100.0 * COALESCE(zsp.bolt_spend_curr, 0) / NULLIF(zg.gmv_curr, 0), 2) AS bolt_di_pct_curr,
    ROUND(100.0 * COALESCE(zsp.provider_spend_base, 0) / NULLIF(zg.gmv_base, 0), 2) AS provider_di_pct_base,
    ROUND(100.0 * COALESCE(zsp.provider_spend_curr, 0) / NULLIF(zg.gmv_curr, 0), 2) AS provider_di_pct_curr,
    ROUND(100.0 * COALESCE(zsp.total_spend_base, 0) / NULLIF(zg.gmv_base, 0), 2) AS total_di_pct_base,
    ROUND(100.0 * COALESCE(zsp.total_spend_curr, 0) / NULLIF(zg.gmv_curr, 0), 2) AS total_di_pct_curr,
    ROUND(
        100.0 * COALESCE(zsp.bolt_spend_curr, 0) / NULLIF(zg.gmv_curr, 0)
      - 100.0 * COALESCE(zsp.bolt_spend_base, 0) / NULLIF(zg.gmv_base, 0), 2
    ) AS bolt_di_yoy_pp,
    ROUND(
        100.0 * COALESCE(zsp.provider_spend_curr, 0) / NULLIF(zg.gmv_curr, 0)
      - 100.0 * COALESCE(zsp.provider_spend_base, 0) / NULLIF(zg.gmv_base, 0), 2
    ) AS provider_di_yoy_pp,
    ROUND(
        100.0 * COALESCE(zsp.total_spend_curr, 0) / NULLIF(zg.gmv_curr, 0)
      - 100.0 * COALESCE(zsp.total_spend_base, 0) / NULLIF(zg.gmv_base, 0), 2
    ) AS total_di_yoy_pp,
    COALESCE(zsp.bolt_spend_base, 0) AS bolt_spend_base,
    COALESCE(zsp.bolt_spend_curr, 0) AS bolt_spend_curr,
    COALESCE(zsp.provider_spend_base, 0) AS provider_spend_base,
    COALESCE(zsp.provider_spend_curr, 0) AS provider_spend_curr,
    COALESCE(zsp.total_spend_base, 0) AS total_spend_base,
    COALESCE(zsp.total_spend_curr, 0) AS total_spend_curr,
    zsj.segment_spend_json,
    zoj.objective_spend_json,
    dz.polygon AS zone_polygon,
    cb.city_polygon
FROM zone_gmv zg
LEFT JOIN zone_spend_pivot zsp
    ON zg.country = zsp.country AND zg.city_name = zsp.city_name AND zg.zone_name = zsp.zone_name
LEFT JOIN zone_sessions_pivot zss
    ON zg.country = zss.country AND zg.city_name = zss.city_name AND zg.zone_name = zss.zone_name
LEFT JOIN zone_segment_json zsj
    ON zg.country = zsj.country AND zg.city_name = zsj.city_name AND zg.zone_name = zsj.zone_name
LEFT JOIN zone_objective_json zoj
    ON zg.country = zoj.country AND zg.city_name = zoj.city_name AND zg.zone_name = zoj.zone_name
LEFT JOIN liquidity_spend_base ls
    ON zg.country = ls.country AND zg.city_name = ls.city_name AND zg.zone_name = ls.zone_name
LEFT JOIN main.ng_delivery.dim_delivery_zone_view dz
    ON zg.city_name = dz.city_name AND zg.zone_name = dz.zone_name
LEFT JOIN city_bounds cb
    ON zg.city_name = cb.city_name
WHERE zg.gmv_base > 0 OR zg.gmv_curr > 0
ORDER BY zg.city_name, COALESCE(ls.liquidity_spend_eur, 0) DESC, zg.gmv_base DESC
