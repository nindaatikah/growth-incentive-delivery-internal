-- =============================================================================
-- QUERY: Daily User Signups by Country × City
-- =============================================================================
-- Source: dim_user_delivery.created_date (user registration / account creation)
-- Grain: one row per date × country × city
-- =============================================================================

SELECT
    u.created_date                                          AS order_date,
    LOWER(dc.country_code)                                  AS country,
    dc.country_name,
    COALESCE(dc.city_name, 'Unknown')                       AS city_name,
    COUNT(DISTINCT u.user_id)                               AS signups
FROM main.ng_delivery.dim_user_delivery u
LEFT JOIN main.ng_delivery.dim_delivery_city dc
    ON u.city_id = dc.city_id
WHERE u.created_date >= DATE '2024-04-01'
  AND u.created_date <  CURRENT_DATE
  AND COALESCE(u.user_is_bot, false) = false
  AND COALESCE(u.user_is_employee, false) = false
GROUP BY 1, 2, 3, 4
ORDER BY order_date, country, city_name
