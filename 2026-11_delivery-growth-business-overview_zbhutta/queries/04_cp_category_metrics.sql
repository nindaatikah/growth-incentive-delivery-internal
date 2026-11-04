-- =============================================================================
-- QUERY: GMV, Orders, Spend & Contribution Profit by CP Category
-- =============================================================================
-- Joins dim_order_delivery with provider targeting features to get
-- contribution_profit_pct_category per provider per day.
--
-- Grain: one row per date × country × city × cp_category
-- =============================================================================

SELECT
    o.order_created_date                                        AS order_date,
    LOWER(o.country_code)                                       AS country,
    o.country_name,
    COALESCE(o.city_name, 'Unknown')                            AS city_name,
    COALESCE(f.contribution_profit_pct_category, 'unknown')     AS cp_category,
    ROUND(SUM(o.order_gmv_eur), 2)                              AS gmv_eur,
    COUNT(DISTINCT o.order_id)                                  AS total_orders,
    ROUND(SUM(o.campaign_spend_bolt_eur), 2)                    AS bolt_spend_eur,
    ROUND(SUM(o.campaign_spend_provider_eur), 2)                AS provider_spend_eur,
    ROUND(SUM(o.contribution_profit_eur), 2)                    AS contribution_profit_eur
FROM main.ng_delivery.dim_order_delivery o
LEFT JOIN main.ng_public.etl_incentives_provider_targeting_features f
    ON o.provider_id = f.provider_id
    AND o.order_created_date = f.date
WHERE o.order_created_date >= DATE '2024-04-01'
  AND o.order_created_date <  CURRENT_DATE
  AND o.is_failed_order = false
GROUP BY 1, 2, 3, 4, 5
ORDER BY order_date, country, city_name, cp_category
