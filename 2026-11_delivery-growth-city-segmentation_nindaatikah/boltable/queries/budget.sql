-- Budget at every level (aggregation = city | country | segment; GLOBAL is a country row).
-- Spend columns are ratios (share of GMV); gmv_ba is the GMV target in EUR.
-- SELECT * so the app still loads before the newer columns (elc, churn, ... total_bolt_spend, ba_total_spend)
-- exist in the table: missing ones just mean "no target".
-- month is cast to text so it always reads as 'YYYY-MM-DD'.
SELECT * EXCEPT (month), CAST(month AS STRING) AS month
FROM dev.dev_incentives.delivery_budget_capital_allocation
WHERE month >= DATE'2026-10-01'
  AND COALESCE(country_name, '') NOT IN ('Georgia', 'Tuvalu', 'Croatia')
