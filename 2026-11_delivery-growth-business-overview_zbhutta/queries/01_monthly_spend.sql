-- =============================================================================
-- QUERY: Daily Bolt & Provider Spend by Country, Merchant Segment, Objective
-- =============================================================================
-- Grain: One row per date × country × merchant_segment × spend_objective × funding_type
--
-- Extracted at daily level so the dashboard can aggregate to weekly / monthly
-- on the fly.  GMV lives in a separate country × date query
-- (02_country_date_gmv.sql) and stays fixed regardless of segment/objective.
--
-- Duration: Apr 2024 → latest available
-- =============================================================================

SELECT
    c.order_created_date                                   AS order_date,
    c.country,
    dc.country_name,
    COALESCE(d.city_name, 'Unknown')                       AS city_name,
    COALESCE(p.business_segment_v2, 'Unknown')             AS merchant_segment,
    COALESCE(c.spend_objective, 'Unknown')                 AS spend_objective,
    COALESCE(d.delivery_vertical, 'Unknown')               AS delivery_vertical,
    CASE WHEN COALESCE(c.provider_spend, 0) = 0
         THEN 'fully_funded' ELSE 'cost_shared' END        AS funding_type,
    ROUND(SUM(c.bolt_spend), 2)                            AS bolt_spend_eur,
    ROUND(SUM(c.provider_spend), 2)                        AS provider_spend_eur,
    ROUND(SUM(c.bolt_spend) + SUM(c.provider_spend), 2)    AS total_spend_eur,
    ROUND(
        SUM(c.provider_spend)
        / NULLIF(SUM(c.bolt_spend) + SUM(c.provider_spend), 0)
        * 100, 2
    )                                                      AS cost_share_pct,
    COUNT(DISTINCT c.order_id)                             AS discount_orders

FROM main.ng_public.etl_delivery_campaign_order_metrics c
LEFT JOIN main.ng_delivery.dim_order_delivery d
    ON c.order_id = d.order_id
    AND c.order_created_date = d.order_created_date
LEFT JOIN main.ng_delivery.dim_provider_v2 p
    ON d.provider_id = p.provider_id
LEFT JOIN (
    SELECT DISTINCT LOWER(country_code) AS country_code, country_name
    FROM main.ng_delivery.dim_delivery_city
) dc
    ON LOWER(c.country) = dc.country_code
WHERE c.order_created_date >= DATE '2024-04-01'
  AND c.order_created_date <  CURRENT_DATE
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
ORDER BY order_date, country, city_name, merchant_segment, spend_objective, delivery_vertical, funding_type
