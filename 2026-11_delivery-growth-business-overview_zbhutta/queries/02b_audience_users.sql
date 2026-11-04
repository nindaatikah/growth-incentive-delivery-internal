-- =============================================================================
-- Distinct orderers by the set of verticals they ordered in a period
-- =============================================================================
-- Grain: grain × period × country × city × vertical_mask
--
-- vertical_mask is the bitwise OR of every vertical that user ordered in the
-- period. The dashboard counts a user once for any vertical selection that
-- overlaps that mask (food + 1P in the same week/month = 1 active user).
--
-- Bits (keep in sync with generate_dashboard.py VERTICAL_BITS):
--   food=1  store_1p=2  store_3p_ent=4  store_3p_mm_smb=8
--   dine_in=16  business=32  store_unclassified=64  other=128
--
-- Weekly and monthly rows are true COUNT DISTINCT for that period, not the
-- sum of daily distincts. Not incremental: a late order changes the whole
-- week and month mask.
-- =============================================================================

WITH orders AS (
    SELECT
        o.order_created_date AS order_date,
        CAST(DATE_TRUNC('week', o.order_created_date) AS DATE) AS week_start,
        CAST(DATE_TRUNC('month', o.order_created_date) AS DATE) AS month_start,
        LOWER(o.country_code) AS country,
        o.country_name,
        COALESCE(o.city_name, 'Unknown') AS city_name,
        o.user_id,
        CASE COALESCE(o.delivery_vertical, 'Unknown')
            WHEN 'food' THEN 1
            WHEN 'store_1p' THEN 2
            WHEN 'store_3p_ent' THEN 4
            WHEN 'store_3p_mm_smb' THEN 8
            WHEN 'dine_in' THEN 16
            WHEN 'business' THEN 32
            WHEN 'store_unclassified' THEN 64
            ELSE 128
        END AS vbit,
        CASE WHEN o.is_first_delivery_order THEN 1 ELSE 0 END AS is_new
    FROM main.ng_delivery.dim_order_delivery o
    WHERE o.order_created_date >= DATE '2024-04-01'
      AND o.order_created_date <  CURRENT_DATE
      AND o.is_failed_order = false
      AND o.user_id IS NOT NULL
),
user_period AS (
    SELECT 'daily' AS grain, order_date AS period, country, country_name, city_name, user_id,
           BIT_OR(vbit) AS mask,
           BIT_OR(CASE WHEN is_new = 1 THEN vbit ELSE 0 END) AS new_mask
    FROM orders
    GROUP BY order_date, country, country_name, city_name, user_id
    UNION ALL
    SELECT 'weekly', week_start, country, country_name, city_name, user_id,
           BIT_OR(vbit),
           BIT_OR(CASE WHEN is_new = 1 THEN vbit ELSE 0 END)
    FROM orders
    GROUP BY week_start, country, country_name, city_name, user_id
    UNION ALL
    SELECT 'monthly', month_start, country, country_name, city_name, user_id,
           BIT_OR(vbit),
           BIT_OR(CASE WHEN is_new = 1 THEN vbit ELSE 0 END)
    FROM orders
    GROUP BY month_start, country, country_name, city_name, user_id
)
SELECT
    grain,
    period,
    country,
    country_name,
    city_name,
    mask,
    new_mask,
    COUNT(*) AS active_users
FROM user_period
GROUP BY 1, 2, 3, 4, 5, 6, 7
