# Delivery Growth — Business Overview

| Field | Value |
|---|---|
| Owner | zbhutta |
| Date (created / last updated) | 2026-04 / 2026-11-04 |
| Status | live |
| Boltable page | growth-business-overview, https://business-overview.boltable.eu (internal: VPN + SSO) |
| Stakeholders / requested by | Delivery growth, Baltics, Malta and CEE |
| Region / vertical | Delivery, the countries in the dashboard filters |
| Keywords | delivery growth, business overview, GMV, ULC, SP ULC, fully funded, cost share, cohort, city budget, zone map, dim_order_delivery, etl_delivery_campaign_order_metrics, int_user_metrics_user_cohort |

## 1. Business question
How is delivery performing by country and city: GMV, orders, sessions, spend and contribution margin, and where is user-targeted spend (ULC) against the November plan? Which zones are ahead or behind last year?

## 2. TL;DR / key findings
- Three live pages: the business overview, city ULC against the November budget, and the zone year-on-year map.
- ULC actuals are Bolt user-targeted spend plus SP ULC. On the city page, SP activation, reactivation and engagement sit in those three columns.
- The country ULC target is the country-sheet total, not the average of the city rows. Romania's November total is 8.23% (activation 2.10, reactivation 1.69, occasional 4.44). Averaging the cities gives 8.6% because city activation blends to 2.46%.
- Fully funded spend is classified on each campaign-order record before it is aggregated. Classifying the aggregated bucket drops Bolt-only spend that shares a city and objective with any co-funded spend.
- The GMV denominator is order GMV from `dim_order_delivery` (`order_gmv_eur`), failed orders excluded. It does not change when the spend filters change.

## 3. Methodology
### Pages
- Business overview: monthly, weekly and daily. Scorecards, spend by segment and objective, cohort performance, city trends, contribution profit, supply health.
- City ULC vs budget: one row per city. Budget is the November proposal as a percent of forecast GMV. Actuals are last complete week, last 30 days and month to date, each as spend divided by order GMV in that window. The gap is percentage points versus the target rate.
- Zone map: year-on-year orders, spend and merchants by zone. City merchant counts are a city-level distinct count, not the sum of the zone distincts.

### ULC
User-targeted Bolt objectives are `activation`, `reactivation`, `engagement` and `churn`. SP ULC is `sp_activation`, `sp_reactivation`, `sp_engagement`, `sp_experiment`, `sp_fully_funded`, `sp_liquidity` and `sp_new_city_launch`. `new_city_launch` and `bolt_plus_campaign` are not ULC.

On an unfiltered country (or All), the target is the November country total. A segment or city filter uses the blend of the visible cities and is labelled as filtered.

### Fully funded
A record is fully funded when its own provider spend is 0, matching Looker's cost-share filter. The dashboard keeps that split through the daily, weekly and monthly grains.

### Cohorts
Weekly cohort points are the last eight complete weeks. The week before that is kept only so the oldest week has a week-on-week baseline. Daily cohort points are the last 30 days, with seven extra days held back so each day can be compared with the same weekday a week earlier.

## 4. Data sources
- `main.ng_delivery.dim_order_delivery`: orders and order GMV. Failed orders excluded.
- `main.ng_public.etl_delivery_campaign_order_metrics`: Bolt and provider spend by objective.
- `main.ng_delivery.int_user_metrics_user_cohort`: cohort labels. Large. The weekly and daily cohort queries are not part of the morning refresh.
- `main.ng_delivery.dim_session_user_delivery_mixpanel`: sessions, dine-in excluded.
- `main.ng_delivery.dim_provider_v2`, `main.ng_delivery.dim_delivery_city`: segment and country names.
- November city budget sheet for the ULC targets. The country total is the country sheet's TOTAL COUNTRY row, which Global Summary reads through.

Gotcha: a date filter written as a subquery on `int_user_metrics_user_cohort` does not prune. The predicate has to be inlined (`DATE_ADD` / `CURRENT_DATE`) or the scan does not stop at the window.

## 5. Files in this folder
- `queries/`: the SQL behind the three pages, in pipeline order. Same files as the live dashboard repo. The zone-map queries (`13_liquidity_zone_*.sql`) are templates; the generator fills the window and zone-column placeholders.
- The published pages and their gzip data stay in the Boltable repo `boltable/growth-business-overview`. They are generated output, not source, and are not copied here.

## 6. How to reproduce / refresh
1. Run `queries/` on the Shared Growth Analytics SQL endpoint. Catalogs are `main.ng_delivery` and `main.ng_public`.
2. The morning job republishes the business overview, the city ULC page and the zone map from the local extracts. It does not rerun the cohort queries.
3. Refresh cohorts on their own with `08_cohort_weekly_metrics.sql` and `08_cohort_daily_metrics.sql`. Do not add them to the morning job.
4. The same SQL is kept as a Databricks notebook and rebuilt from these files. The notebook is not scheduled.

## 7. Boltable details
- Business overview: https://business-overview.boltable.eu/index.html
- City ULC vs budget: https://business-overview.boltable.eu/ulc-budget.html
- Zone year-on-year map: https://business-overview.boltable.eu/liquidity-zone-yoy-map.html
- Access: Bolt SSO behind the NetBird VPN.
- Inputs: filters only (country, city, segment, objective, vertical, date, cost share). No user-entered data.

## 8. Related work
`2026-11_delivery-growth-incentive-city-segmentation_nindaatikah` is the capital-allocation view of incentive spend against budget, with status and month/week/day trends. This folder is the operating dashboard: scorecards, cohorts, the city ULC rate against the November country target, and the zone map. The two do not share a page.

## 9. Open questions / next steps
- Daily cohort chart still ends on 13 October until `08_cohort_daily_metrics.sql` is rerun. The query is updated so the cohort-table predicate prunes.
- The zone map is published from the Boltable repo. It is not stored in this folder.

## 10. Changelog
- 2026-11-04: added to growth-incentive-delivery-internal. Queries only. No generated data, and no workspace, cluster or sheet identifiers.
