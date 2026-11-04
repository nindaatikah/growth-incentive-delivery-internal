-- Lean zone × delivery_vertical YoY metrics for the map vertical slicer.
-- Placeholders: __ZONE_COL__, __CURR_START__, __CURR_END__, __BASE_START__, __BASE_END__

WITH target_cities AS (
    SELECT DISTINCT city_name
    FROM main.ng_delivery.dim_delivery_city
    WHERE is_primary_city = true
      AND COALESCE(is_city_active, true) = true
),

orders AS (
    SELECT
        LOWER(o.country_code) AS country,
        o.city_name,
        o.__ZONE_COL__ AS zone_name,
        COALESCE(o.delivery_vertical, 'Unknown') AS delivery_vertical,
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

gmv AS (
    SELECT
        country,
        city_name,
        zone_name,
        delivery_vertical,
        ROUND(SUM(CASE WHEN period = 'base' THEN gmv_eur ELSE 0 END), 2) AS gmv_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN gmv_eur ELSE 0 END), 2) AS gmv_curr,
        COUNT(DISTINCT CASE WHEN period = 'base' THEN order_id END) AS orders_base,
        COUNT(DISTINCT CASE WHEN period = 'curr' THEN order_id END) AS orders_curr,
        COUNT(DISTINCT CASE WHEN period = 'base' THEN user_id END) AS users_base,
        COUNT(DISTINCT CASE WHEN period = 'curr' THEN user_id END) AS users_curr,
        COUNT(DISTINCT CASE WHEN period = 'base' THEN provider_id END) AS merchants_base,
        COUNT(DISTINCT CASE WHEN period = 'curr' THEN provider_id END) AS merchants_curr
    FROM orders
    WHERE period IS NOT NULL
    GROUP BY 1, 2, 3, 4
),

spend AS (
    SELECT
        LOWER(c.country) AS country,
        d.city_name,
        d.__ZONE_COL__ AS zone_name,
        COALESCE(d.delivery_vertical, 'Unknown') AS delivery_vertical,
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

spend_pivot AS (
    SELECT
        country,
        city_name,
        zone_name,
        delivery_vertical,
        ROUND(SUM(CASE WHEN period = 'base' THEN bolt_spend_eur ELSE 0 END), 2) AS bolt_spend_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN bolt_spend_eur ELSE 0 END), 2) AS bolt_spend_curr,
        ROUND(SUM(CASE WHEN period = 'base' THEN provider_spend_eur ELSE 0 END), 2) AS provider_spend_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN provider_spend_eur ELSE 0 END), 2) AS provider_spend_curr,
        ROUND(SUM(CASE WHEN period = 'base' THEN total_spend_eur ELSE 0 END), 2) AS total_spend_base,
        ROUND(SUM(CASE WHEN period = 'curr' THEN total_spend_eur ELSE 0 END), 2) AS total_spend_curr
    FROM spend
    WHERE period IS NOT NULL
    GROUP BY 1, 2, 3, 4
)

SELECT
    g.country,
    g.city_name,
    g.zone_name,
    g.delivery_vertical,
    g.gmv_base,
    g.gmv_curr,
    ROUND((g.gmv_curr - g.gmv_base) * 100.0 / NULLIF(g.gmv_base, 0), 1) AS gmv_yoy_pct,
    g.orders_base,
    g.orders_curr,
    g.users_base,
    g.users_curr,
    g.merchants_base,
    g.merchants_curr,
    COALESCE(s.bolt_spend_base, 0) AS bolt_spend_base,
    COALESCE(s.bolt_spend_curr, 0) AS bolt_spend_curr,
    COALESCE(s.provider_spend_base, 0) AS provider_spend_base,
    COALESCE(s.provider_spend_curr, 0) AS provider_spend_curr,
    COALESCE(s.total_spend_base, 0) AS total_spend_base,
    COALESCE(s.total_spend_curr, 0) AS total_spend_curr,
    ROUND(100.0 * COALESCE(s.bolt_spend_base, 0) / NULLIF(g.gmv_base, 0), 2) AS bolt_di_pct_base,
    ROUND(100.0 * COALESCE(s.bolt_spend_curr, 0) / NULLIF(g.gmv_curr, 0), 2) AS bolt_di_pct_curr,
    ROUND(100.0 * COALESCE(s.provider_spend_base, 0) / NULLIF(g.gmv_base, 0), 2) AS provider_di_pct_base,
    ROUND(100.0 * COALESCE(s.provider_spend_curr, 0) / NULLIF(g.gmv_curr, 0), 2) AS provider_di_pct_curr,
    ROUND(100.0 * COALESCE(s.total_spend_base, 0) / NULLIF(g.gmv_base, 0), 2) AS total_di_pct_base,
    ROUND(100.0 * COALESCE(s.total_spend_curr, 0) / NULLIF(g.gmv_curr, 0), 2) AS total_di_pct_curr
FROM gmv g
LEFT JOIN spend_pivot s
  ON g.country = s.country
 AND g.city_name = s.city_name
 AND g.zone_name = s.zone_name
 AND g.delivery_vertical = s.delivery_vertical
WHERE g.gmv_base > 0 OR g.gmv_curr > 0
ORDER BY g.city_name, g.zone_name, g.delivery_vertical
