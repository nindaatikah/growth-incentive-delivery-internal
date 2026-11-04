-- =============================================================================
-- QUERY: Supply Health metrics (Looker dashboard 29667 family)
-- =============================================================================
-- Session metrics: session_created_date (session time basis), dine-in excluded.
-- Courier / order metrics: order_created_date (aligned to calendar day).
-- Grain: metric_date × country × city
-- =============================================================================

WITH session_base AS (
    SELECT
        s.session_created_date AS metric_date,
        LOWER(s.country_code) AS country,
        s.country_name,
        COALESCE(s.city_name, 'Unknown') AS city_name,
        s.session_id,
        s.active_orders_at_session_created,
        s.online_couriers_at_session_created,
        s.radius_shrinking_provider_count,
        s.total_provider_count_session,
        s.surge_pricing_multiplier,
        s.demand_campaigns_paused_minutes_during_hour,
        s.pressure_pause_demand_incentive_provider_count
    FROM main.ng_delivery.dim_session_user_delivery_mixpanel s
    WHERE s.session_created_date >= DATE '2024-04-01'
      AND s.session_created_date < CURRENT_DATE
      AND COALESCE(s.is_dine_in_session, false) = false
),
session_agg AS (
    SELECT
        metric_date,
        country,
        country_name,
        city_name,
        COUNT(DISTINCT session_id) AS session_count,
        SUM(
            s.active_orders_at_session_created
            / NULLIF(s.online_couriers_at_session_created, 0)
        ) AS session_busy_ratio_sum,
        SUM(
            s.radius_shrinking_provider_count
            / NULLIF(s.total_provider_count_session, 0)
        ) AS session_radius_shrink_pct_sum,
        SUM(COALESCE(s.surge_pricing_multiplier, 1)) AS session_delivery_fee_mult_sum,
        COUNT(DISTINCT CASE
            WHEN COALESCE(s.demand_campaigns_paused_minutes_during_hour, 0) > 0
              OR COALESCE(s.pressure_pause_demand_incentive_provider_count, 0) > 0
            THEN session_id END) AS sessions_pause_incentive,
        COUNT(DISTINCT CASE
            WHEN COALESCE(s.surge_pricing_multiplier, 1) > 1.0001
            THEN session_id END) AS sessions_eater_surge,
        COUNT(DISTINCT CASE
            WHEN COALESCE(s.radius_shrinking_provider_count, 0) > 0
            THEN session_id END) AS sessions_radius_shrinkage,
        ROUND(SUM(
            0.177 * s.radius_shrinking_provider_count
            / NULLIF(s.total_provider_count_session, 0)
        ), 4) AS est_orders_lost_radius_shrinkage,
        ROUND(SUM(
            0.107 * (COALESCE(s.surge_pricing_multiplier, 1) - 1)
        ), 4) AS est_orders_lost_eater_surge,
        ROUND(SUM(
            0.035 * COALESCE(s.demand_campaigns_paused_minutes_during_hour, 0) / 60.0
        ), 4) AS est_orders_lost_pause_incentive
    FROM session_base s
    GROUP BY 1, 2, 3, 4
),
order_agg AS (
    SELECT
        o.order_created_date AS metric_date,
        LOWER(o.country_code) AS country,
        o.country_name,
        COALESCE(o.city_name, 'Unknown') AS city_name,
        COUNT(DISTINCT o.order_id) AS courier_delivered_orders,
        COUNT(DISTINCT CASE WHEN COALESCE(o.is_bad_order, false) THEN o.order_id END) AS bad_orders,
        COUNT(DISTINCT CASE WHEN COALESCE(o.is_batched_order, false) THEN o.order_id END) AS batched_orders,
        ROUND(SUM(o.total_price_before_discount_eur), 2) AS total_gmv_before_discounts_eur,
        ROUND(SUM(COALESCE(o.courier_earnings_paid_eur, o.courier_earning_eur, 0)), 2) AS courier_total_earnings_eur,
        ROUND(SUM(
            COALESCE(o.actual_courier_seconds_per_order_delivery_courier, 0)
            + COALESCE(o.actual_courier_seconds_per_order_non_delivery_courier, 0)
        ) / 60.0, 4) AS courier_minutes_per_order_sum,
        SUM(COALESCE(o.order_courier_acceptance_count, 0)) AS courier_acceptance_count,
        SUM(COALESCE(o.order_courier_proposal_count, 0)) AS courier_proposal_count,
        ROUND(SUM(COALESCE(o.courier_to_provider_route_distance_meters, 0)) / 1000.0, 4) AS courier_pickup_distance_km,
        ROUND(SUM(COALESCE(o.courier_log_distance_meters_to_dropoff, 0)) / 1000.0, 4) AS courier_dropoff_distance_km
    FROM main.ng_delivery.dim_order_delivery o
    WHERE o.order_created_date >= DATE '2024-04-01'
      AND o.order_created_date < CURRENT_DATE
      AND o.is_failed_order = false
    GROUP BY 1, 2, 3, 4
),
courier_agg AS (
    SELECT
        f.metric_timestamp_partition AS metric_date,
        LOWER(dc.country_code) AS country,
        dc.country_name,
        COALESCE(dc.city_name, 'Unknown') AS city_name,
        ROUND(SUM(f.courier_total_online_hours), 4) AS courier_total_online_hours,
        ROUND(SUM(f.courier_total_utilised_hours), 4) AS courier_total_busy_hours,
        COUNT(DISTINCT CASE
            WHEN COALESCE(f.courier_total_online_hours, 0) > 0 THEN f.courier_id
        END) AS active_couriers
    FROM main.ng_delivery.fact_courier_daily_v2 f
    INNER JOIN main.ng_delivery.dim_delivery_city dc
        ON f.city_id = dc.city_id
    WHERE f.metric_timestamp_partition >= DATE '2024-04-01'
      AND f.metric_timestamp_partition < CURRENT_DATE
    GROUP BY 1, 2, 3, 4
),
keys AS (
    SELECT metric_date, country, country_name, city_name FROM session_agg
    UNION
    SELECT metric_date, country, country_name, city_name FROM order_agg
    UNION
    SELECT metric_date, country, country_name, city_name FROM courier_agg
)
SELECT
    k.metric_date AS order_date,
    k.country,
    k.country_name,
    k.city_name,
    COALESCE(sa.session_count, 0) AS session_count,
    COALESCE(sa.session_busy_ratio_sum, 0) AS session_busy_ratio_sum,
    COALESCE(sa.session_radius_shrink_pct_sum, 0) AS session_radius_shrink_pct_sum,
    COALESCE(sa.session_delivery_fee_mult_sum, 0) AS session_delivery_fee_mult_sum,
    COALESCE(sa.sessions_pause_incentive, 0) AS sessions_pause_incentive,
    COALESCE(sa.sessions_eater_surge, 0) AS sessions_eater_surge,
    COALESCE(sa.sessions_radius_shrinkage, 0) AS sessions_radius_shrinkage,
    COALESCE(sa.est_orders_lost_radius_shrinkage, 0) AS est_orders_lost_radius_shrinkage,
    COALESCE(sa.est_orders_lost_eater_surge, 0) AS est_orders_lost_eater_surge,
    COALESCE(sa.est_orders_lost_pause_incentive, 0) AS est_orders_lost_pause_incentive,
    COALESCE(oa.courier_delivered_orders, 0) AS courier_delivered_orders,
    COALESCE(oa.bad_orders, 0) AS bad_orders,
    COALESCE(oa.batched_orders, 0) AS batched_orders,
    COALESCE(oa.total_gmv_before_discounts_eur, 0) AS total_gmv_before_discounts_eur,
    COALESCE(oa.courier_total_earnings_eur, 0) AS courier_total_earnings_eur,
    COALESCE(oa.courier_minutes_per_order_sum, 0) AS courier_minutes_per_order_sum,
    COALESCE(oa.courier_acceptance_count, 0) AS courier_acceptance_count,
    COALESCE(oa.courier_proposal_count, 0) AS courier_proposal_count,
    COALESCE(oa.courier_pickup_distance_km, 0) AS courier_pickup_distance_km,
    COALESCE(oa.courier_dropoff_distance_km, 0) AS courier_dropoff_distance_km,
    COALESCE(ca.courier_total_online_hours, 0) AS courier_total_online_hours,
    COALESCE(ca.courier_total_busy_hours, 0) AS courier_total_busy_hours,
    COALESCE(ca.active_couriers, 0) AS active_couriers
FROM keys k
LEFT JOIN session_agg sa
    ON k.metric_date = sa.metric_date
   AND k.country = sa.country
   AND k.city_name = sa.city_name
LEFT JOIN order_agg oa
    ON k.metric_date = oa.metric_date
   AND k.country = oa.country
   AND k.city_name = oa.city_name
LEFT JOIN courier_agg ca
    ON k.metric_date = ca.metric_date
   AND k.country = ca.country
   AND k.city_name = ca.city_name
ORDER BY order_date, country, city_name
