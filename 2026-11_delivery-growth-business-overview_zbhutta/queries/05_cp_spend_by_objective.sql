-- =============================================================================
-- QUERY: Spend by CP Category × Spend Objective (weekly)
-- =============================================================================
-- Joins campaign_order_metrics with dim_order_delivery (for provider_id) and
-- provider targeting features (for cp_category).
-- Pre-aggregated to weekly to keep size manageable.
-- =============================================================================

SELECT
    DATE_TRUNC('week', c.order_created_date)                    AS week_start,
    c.country,
    dc.country_name,
    COALESCE(f.contribution_profit_pct_category, 'unknown')     AS cp_category,
    COALESCE(c.spend_objective, 'Unknown')                      AS spend_objective,
    ROUND(SUM(c.bolt_spend), 2)                                 AS bolt_spend_eur,
    ROUND(SUM(c.provider_spend), 2)                             AS provider_spend_eur,
    COUNT(DISTINCT c.order_id)                                  AS discount_orders
FROM main.ng_public.etl_delivery_campaign_order_metrics c
INNER JOIN main.ng_delivery.dim_order_delivery d
    ON c.order_id = d.order_id
    AND c.order_created_date = d.order_created_date
LEFT JOIN main.ng_public.etl_incentives_provider_targeting_features f
    ON d.provider_id = f.provider_id
    AND c.order_created_date = f.date
LEFT JOIN (
    SELECT DISTINCT LOWER(country_code) AS country_code, country_name
    FROM main.ng_delivery.dim_delivery_city
) dc ON LOWER(c.country) = dc.country_code
WHERE c.order_created_date >= DATE '2024-04-01'
  AND c.order_created_date <  CURRENT_DATE
GROUP BY 1, 2, 3, 4, 5
ORDER BY week_start, country, cp_category, spend_objective
