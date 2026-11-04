-- =============================================================================
-- QUERY: City-level Daily Trend Metrics
-- =============================================================================
-- All key metrics at date × country × city for the trend summary table.
-- Sessions from Mixpanel joined separately.
-- =============================================================================

WITH order_metrics AS (
    SELECT
        o.order_created_date                                    AS order_date,
        LOWER(o.country_code)                                   AS country,
        o.country_name,
        COALESCE(o.city_name, 'Unknown')                        AS city_name,
        COUNT(DISTINCT o.order_id)                              AS total_orders,
        COUNT(DISTINCT o.user_id)                               AS active_users,
        COUNT(DISTINCT CASE WHEN o.is_first_delivery_order THEN o.user_id END) AS new_users,
        ROUND(SUM(o.order_gmv_eur), 2)                         AS gmv_eur,
        ROUND(SUM(o.order_provider_commission_eur), 2)          AS commission_eur,
        ROUND(SUM(CASE WHEN o.campaign_spend_provider_eur = 0 OR o.campaign_spend_provider_eur IS NULL
                       THEN o.campaign_spend_bolt_eur ELSE 0 END), 2)   AS bolt_spend_fully_funded_eur,
        ROUND(SUM(CASE WHEN o.campaign_spend_provider_eur > 0
                       THEN o.campaign_spend_bolt_eur ELSE 0 END), 2)   AS bolt_spend_cost_shared_eur,
        ROUND(SUM(CASE WHEN o.campaign_spend_bolt_eur = 0 OR o.campaign_spend_bolt_eur IS NULL
                       THEN o.campaign_spend_provider_eur ELSE 0 END), 2) AS provider_spend_fully_funded_eur,
        ROUND(SUM(CASE WHEN o.campaign_spend_bolt_eur > 0
                       THEN o.campaign_spend_provider_eur ELSE 0 END), 2) AS provider_spend_cost_shared_eur,
        ROUND(SUM(o.contribution_profit_eur), 2)                AS contribution_profit_eur,
        ROUND(SUM(o.delivery_price_after_discount_eur), 2)      AS total_delivery_fee_eur,
        ROUND(SUM(o.provider_price_after_discount_eur), 2)      AS total_provider_price_eur
    FROM main.ng_delivery.dim_order_delivery o
    WHERE o.order_created_date >= DATE '2025-01-01'
      AND o.order_created_date <  CURRENT_DATE
      AND o.is_failed_order = false
    GROUP BY 1, 2, 3, 4
),
session_metrics AS (
    SELECT
        s.session_created_date                                  AS order_date,
        LOWER(s.country_code)                                   AS country,
        COALESCE(s.city_name, 'Unknown')                        AS city_name,
        COUNT(DISTINCT s.session_id)                            AS total_sessions
    FROM main.ng_delivery.dim_session_user_delivery_mixpanel s
    WHERE s.session_created_date >= DATE '2025-01-01'
      AND s.session_created_date <  CURRENT_DATE
    GROUP BY 1, 2, 3
),
courier_metrics AS (
    SELECT
        f.metric_timestamp_partition                              AS order_date,
        f.city_id,
        SUM(f.courier_total_utilised_hours)                       AS courier_busy_hours,
        SUM(f.courier_total_online_hours)                         AS courier_online_hours
    FROM main.ng_delivery.fact_courier_daily_v2 f
    WHERE f.metric_timestamp_partition >= DATE '2025-01-01'
      AND f.metric_timestamp_partition <  CURRENT_DATE
    GROUP BY 1, 2
),
courier_by_city AS (
    SELECT
        cm.order_date,
        LOWER(dc.country_code)                                    AS country,
        COALESCE(dc.city_name, 'Unknown')                         AS city_name,
        ROUND(SUM(cm.courier_busy_hours), 4)                      AS courier_busy_hours,
        ROUND(SUM(cm.courier_online_hours), 4)                    AS courier_online_hours
    FROM courier_metrics cm
    INNER JOIN main.ng_delivery.dim_delivery_city dc
        ON cm.city_id = dc.city_id
    GROUP BY 1, 2, 3
)
SELECT
    om.*,
    COALESCE(sm.total_sessions, 0) AS total_sessions,
    COALESCE(cb.courier_busy_hours, 0) AS courier_busy_hours,
    COALESCE(cb.courier_online_hours, 0) AS courier_online_hours
FROM order_metrics om
LEFT JOIN session_metrics sm
    ON om.order_date = sm.order_date
    AND om.country = sm.country
    AND om.city_name = sm.city_name
LEFT JOIN courier_by_city cb
    ON om.order_date = cb.order_date
    AND om.country = cb.country
    AND om.city_name = cb.city_name
ORDER BY om.order_date, om.country, om.city_name
