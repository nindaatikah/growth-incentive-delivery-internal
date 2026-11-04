-- =============================================================================
-- QUERY: Total GMV, Orders & Active Users by Country × Date
-- =============================================================================
-- Source: dim_order_delivery (replaces etl_delivery_order_monetary_metrics)
-- Grain: one row per date × country
--
-- Includes all non-failed orders (is_failed_order = false) so that "bad"
-- orders (late, CS tickets) are still counted — only cancelled/failed ones
-- are excluded.
--
-- This is the fixed denominator for "spend as % of GMV" — it does not change
-- when filtering by merchant segment or spend objective.
--
-- Extracted at daily level so the dashboard can aggregate to weekly / monthly.
--
-- Duration: Apr 2024 → latest available
-- =============================================================================

SELECT
    o.order_created_date                                   AS order_date,
    LOWER(o.country_code)                                  AS country,
    o.country_name,
    COALESCE(o.city_name, 'Unknown')                       AS city_name,
    COALESCE(o.delivery_vertical, 'Unknown')               AS delivery_vertical,
    ROUND(SUM(o.order_gmv_eur), 2)                        AS gmv_eur,
    COUNT(DISTINCT o.order_id)                             AS total_orders,
    COUNT(DISTINCT o.user_id)                              AS active_users,
    COUNT(DISTINCT CASE WHEN o.is_first_delivery_order THEN o.user_id END) AS new_users,
    ROUND(SUM(o.order_provider_commission_eur), 2)         AS commission_eur,
    COUNT(DISTINCT o.session_id)                           AS total_sessions,
    ROUND(SUM(o.contribution_profit_eur), 2)              AS contribution_profit_eur
FROM main.ng_delivery.dim_order_delivery o
WHERE o.order_created_date >= DATE '2024-04-01'
  AND o.order_created_date <  CURRENT_DATE
  AND o.is_failed_order = false
GROUP BY 1, 2, 3, 4, 5
ORDER BY order_date, country, city_name, delivery_vertical
