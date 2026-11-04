-- Lean zone × merchant_segment active merchant counts (for map segment table).
-- Placeholders: __ZONE_COL__, __CURR_START__, __CURR_END__, __BASE_START__, __BASE_END__

WITH target_cities AS (
    SELECT DISTINCT city_name
    FROM main.ng_delivery.dim_delivery_city
    WHERE is_primary_city = true
      AND COALESCE(is_city_active, true) = true
),

orders AS (
    SELECT
        o.city_name,
        o.__ZONE_COL__ AS zone_name,
        COALESCE(p.business_segment_v2, 'Unknown') AS merchant_segment,
        CASE
            WHEN o.order_created_date >= DATE '__BASE_START__'
             AND o.order_created_date <  DATE '__BASE_END__' THEN 'base'
            WHEN o.order_created_date >= DATE '__CURR_START__'
             AND o.order_created_date <  DATE '__CURR_END__' THEN 'curr'
        END AS period,
        o.provider_id
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
)

SELECT
    city_name,
    zone_name,
    merchant_segment,
    COUNT(DISTINCT CASE WHEN period = 'base' THEN provider_id END) AS merchants_base,
    COUNT(DISTINCT CASE WHEN period = 'curr' THEN provider_id END) AS merchants_curr
FROM orders
WHERE period IS NOT NULL
  AND COALESCE(merchant_segment, 'Unknown') <> 'Missing Segment'
GROUP BY 1, 2, 3
HAVING COUNT(DISTINCT CASE WHEN period = 'base' THEN provider_id END) > 0
    OR COUNT(DISTINCT CASE WHEN period = 'curr' THEN provider_id END) > 0
ORDER BY city_name, zone_name, merchant_segment
