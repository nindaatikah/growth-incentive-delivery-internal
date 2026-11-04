-- =============================================================================
-- QUERY: Daily Sessions by Country × City (from Mixpanel)
-- =============================================================================
-- Source: dim_session_user_delivery_mixpanel
-- Captures ALL sessions (including those without orders) for true conversion %.
-- =============================================================================

SELECT
    s.session_created_date                          AS order_date,
    LOWER(s.country_code)                           AS country,
    s.country_name,
    COALESCE(s.city_name, 'Unknown')                AS city_name,
    COUNT(DISTINCT s.session_id)                    AS total_sessions,
    COUNT(DISTINCT CASE WHEN s.has_order_placed THEN s.session_id END) AS sessions_with_order
FROM main.ng_delivery.dim_session_user_delivery_mixpanel s
WHERE s.session_created_date >= DATE '2024-04-01'
  AND s.session_created_date <  CURRENT_DATE
GROUP BY 1, 2, 3, 4
ORDER BY order_date, country, city_name
