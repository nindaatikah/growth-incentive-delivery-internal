-- Daily actuals by city and zone cluster for one date window. The server runs it for two windows:
-- last year from Oct 2025 (for YoY; extended one month at a time) and Sep 2026 -> yesterday.
-- __FROM__ / __TO__ are replaced by the server with SQL date expressions (TO is exclusive).
-- Matches the Delivery Business Review SSOT (the Looker business review dashboard):
--   * dates are local (order_created_date_local);
--   * GMV and spend come from delivered orders only;
--   * CP L1 / CP L2 include every order state, so failed orders' (negative) CP counts too.
-- Spend objectives follow the team's Capital Allocation notebook; see README "Metric definitions".
-- Regular providers, not dine-in. Georgia, Tuvalu and Croatia excluded.
WITH o AS (
  SELECT
    order_id,
    order_created_date_local AS day,
    order_state = 'delivered' AS is_delivered,
    country_name,
    city_name,
    COALESCE(user_delivery_zone_cluster, 'Unclustered') AS zone_cluster,
    -- 1P (Bolt Market) orders: Bolt is the provider, so provider-funded discounts are Bolt spend too.
    delivery_vertical = 'store_1p' AS is_1p,
    -- 3P = store_3p_ent + store_3p_mm_smb (there is no vertical literally called '3p').
    delivery_vertical LIKE 'store_3p%' AS is_3p,
    CASE WHEN order_state = 'delivered' THEN order_gmv_eur ELSE 0 END AS gmv,
    contribution_profit_eur AS cp1,
    contribution_profit_eur - COALESCE(order_demand_incentives_eur, 0) AS cp2,
    -- Bolt spend, BA number: demand incentives on the order itself (delivered orders, like GMV).
    CASE WHEN order_state = 'delivered' THEN COALESCE(order_demand_incentives_eur, 0) ELSE 0 END AS ba
  FROM main.ng_delivery.dim_order_delivery
  WHERE is_dine_in_order = FALSE
    AND provider_type = 'regular'
    AND country_name NOT IN ('Georgia', 'Tuvalu', 'Croatia')
    -- UTC date is the partition column: widen it by a day so the local-date window is complete.
    AND order_created_date >= date_sub(__FROM__, 1) AND order_created_date < date_add(__TO__, 1)
    AND order_created_date_local >= __FROM__ AND order_created_date_local < __TO__
),
s AS (
  SELECT
    order_id,
    SUM(bolt_spend) AS bolt_spend,
    SUM(provider_spend) AS provider_spend,
    SUM(CASE WHEN lower(spend_objective) IN ('activation', 'sp_activation') THEN bolt_spend ELSE 0 END) AS act,
    SUM(CASE WHEN lower(spend_objective) IN ('reactivation', 'sp_reactivation') THEN bolt_spend ELSE 0 END) AS react,
    SUM(CASE WHEN lower(spend_objective) IN ('engagement', 'sp_engagement') THEN bolt_spend ELSE 0 END) AS eng,
    SUM(CASE WHEN lower(spend_objective) = 'provider_campaign_elc_merchant' THEN bolt_spend ELSE 0 END) AS elc,
    SUM(CASE WHEN lower(spend_objective) IN ('provider_campaign_marketing', 'provider_marketing_calendar_global_event') THEN bolt_spend ELSE 0 END) AS mkt,
    SUM(CASE WHEN lower(spend_objective) IN (
      'provider_campaign_retail_growth', 'provider_campaign_manual_churn_prevention', 'provider_campaign_locations',
      'provider_campaign_retail_profitability', 'provider_campaign_obligations_commitments', 'provider_campaign_sales_benefit', 'provider_campaign_exclusivity_retention',
      'provider_campaign_commission_increase', 'provider_campaign_untested', 'provider_campaign_marketing_3rd_party_partnership',
      'provider_campaign_exclusivity_gain', 'provider_campaign_profit_generator', 'provider_campaign_exclusivity_prevention'
    ) THEN bolt_spend ELSE 0 END) AS am,
    SUM(CASE WHEN lower(spend_objective) = 'provider_campaign_churn_prevention' THEN bolt_spend ELSE 0 END) AS churn,
    SUM(CASE WHEN lower(spend_objective) IN ('bolt_plus_campaign', 'bolt_plus_tested', 'bolt_plus_untested') THEN bolt_spend ELSE 0 END) AS plus,
    -- 1P (Bolt Market) objectives: Bolt spend plus provider spend.
    SUM(CASE WHEN lower(spend_objective) LIKE '%bolt_market%' THEN bolt_spend + provider_spend ELSE 0 END) AS p1
  FROM main.ng_public.etl_delivery_campaign_order_metrics
  WHERE order_created_date >= date_sub(__FROM__, 1) AND order_created_date < date_add(__TO__, 1)
  GROUP BY order_id
)
SELECT
  CAST(o.day AS STRING) AS day,
  o.country_name,
  o.city_name,
  o.zone_cluster,
  ROUND(SUM(o.gmv), 2) AS gmv,
  ROUND(SUM(COALESCE(s.bolt_spend, 0) + CASE WHEN o.is_1p THEN COALESCE(s.provider_spend, 0) ELSE 0 END), 2) AS bolt,
  ROUND(SUM(COALESCE(s.act, 0)), 2) AS act,
  ROUND(SUM(COALESCE(s.react, 0)), 2) AS react,
  ROUND(SUM(COALESCE(s.eng, 0)), 2) AS eng,
  ROUND(SUM(o.cp1), 2) AS cp1,
  ROUND(SUM(o.cp2), 2) AS cp2,
  ROUND(SUM(o.ba), 2) AS ba,
  ROUND(SUM(COALESCE(s.elc, 0)), 2) AS elc,
  ROUND(SUM(COALESCE(s.mkt, 0)), 2) AS mkt,
  ROUND(SUM(COALESCE(s.am, 0)), 2) AS am,
  ROUND(SUM(COALESCE(s.churn, 0)), 2) AS churn,
  -- BDM 3P: AM + Marketing Bolt spend on 3P orders.
  ROUND(SUM(CASE WHEN o.is_3p THEN COALESCE(s.am, 0) + COALESCE(s.mkt, 0) ELSE 0 END), 2) AS bdm,
  ROUND(SUM(COALESCE(s.p1, 0)), 2) AS p1,
  ROUND(SUM(COALESCE(s.plus, 0)), 2) AS plus
FROM o
-- Spend only on delivered orders.
LEFT JOIN s ON o.order_id = s.order_id AND o.is_delivered
GROUP BY o.day, o.country_name, o.city_name, o.zone_cluster
ORDER BY o.day, o.country_name, o.city_name, o.zone_cluster
