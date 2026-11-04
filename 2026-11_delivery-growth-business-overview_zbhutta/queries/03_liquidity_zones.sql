-- =============================================================================
-- QUERY: Liquidity Spend by Country × City/Zone × Date
-- =============================================================================
-- Spend data comes from campaign_order_metrics (the authoritative source).
-- dim_order_delivery is joined only to get city_id and city_name for zone
-- identification.
--
-- Grain: one row per date × country × city
--
-- Only orders with liquidity spend objectives are included.
--
-- Used for the weekly summary to count how many zones had liquidity
-- investment and show zone-level detail.
--
-- Duration: Apr 2024 → latest available
-- =============================================================================

SELECT
    c.order_created_date                                   AS order_date,
    c.country,
    dc.country_name,
    d.city_id,
    d.city_name,
    ROUND(SUM(c.bolt_spend), 2)                            AS liquidity_bolt_spend_eur,
    ROUND(SUM(c.provider_spend), 2)                        AS liquidity_provider_spend_eur,
    ROUND(SUM(c.bolt_spend) + SUM(c.provider_spend), 2)   AS liquidity_total_spend_eur,
    COUNT(DISTINCT c.order_id)                             AS liquidity_orders
FROM main.ng_public.etl_delivery_campaign_order_metrics c
INNER JOIN main.ng_delivery.dim_order_delivery d
    ON c.order_id = d.order_id
    AND c.order_created_date = d.order_created_date
LEFT JOIN (
    SELECT DISTINCT LOWER(country_code) AS country_code, country_name
    FROM main.ng_delivery.dim_delivery_city
) dc
    ON LOWER(c.country) = dc.country_code
WHERE c.order_created_date >= DATE '2024-04-01'
  AND c.order_created_date <  CURRENT_DATE
  AND LOWER(c.spend_objective) LIKE '%liquidity%'
  AND LOWER(c.spend_objective) NOT LIKE 'bolt_market%'
GROUP BY 1, 2, 3, 4, 5
ORDER BY order_date, country, city_name
