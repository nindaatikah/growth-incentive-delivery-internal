# Delivery Growth Incentive - City Segmentation

| Field | Value |
|---|---|
| Owner | nindaatikah |
| Date (created / last updated) | 2026-11-03 / 2026-11-04 |
| Status | live |
| Boltable page | growth-incentive-delivery-internal, https://growth-incentive-delivery-internal.boltable.eu (internal: VPN + SSO; the app is tied to its repo name, so it can only be renamed by creating a new Boltable repo) |
| Stakeholders / requested by | Delivery growth and incentives team |
| Region / vertical | Delivery (Food and Market) in all European markets plus Ghana and Kenya; Georgia, Tuvalu and Croatia excluded |
| Keywords | delivery growth incentive, city segmentation, capital allocation, budget vs actual, Bolt spend, ULC, activation, reactivation, engagement, ELC, AM, BDM 3P, 1P, Bolt Plus, CP L1, CP L2, contribution profit, WoW, DoD, YoY, run rate, red yellow green status, dim_order_delivery, etl_delivery_campaign_order_metrics, delivery_budget_capital_allocation, Boltable |

## 1. Business question
How are Delivery incentives performing against budget by country, city segment (Monetise, Grow Share, ...), city and zone cluster?
For GMV, Bolt spend (GA and BA), spend by objective and contribution profit: where are we ahead or behind target, how
do we compare with last month and last year, and which markets need attention this week?

## 2. TL;DR / key findings
- One Boltable page with Monthly (MoM, YoY, vs target, run-rate), Weekly trend (WoW) and Daily trend (DoD or WoW) tabs, all with country, city and segment filters and an auto-generated Insights box.
- Every Monthly row has a red / yellow / green status from three checks: GMV vs target, Bolt spend vs target, GMV YoY (thresholds below).
- GMV and CP L1 / CP L2 for October 2026 match the Delivery Business Review dashboard, which is the single source of truth (SSOT) for these numbers.
- Segments follow each month's budget, so a city that changes segment is compared like for like.
- Most spend lines land close to budget; ELC, Marketing, AM and 1P differ more, which may mean the budget was set on another basis than the objective lists used here.
- A blank budget cell is treated as no target, not a target of 0 (this caused a wrong "vs target" until fixed).

## 3. Methodology
### Metric definitions
All metrics: regular providers, not dine-in, excl. Georgia, Tuvalu, Croatia (`main.ng_delivery.dim_order_delivery`),
by local date (`order_created_date_local`). GMV and spend: delivered orders only. Spend is the GA number, including VAT.
Ratios are % of GMV; MoM / YoY / vs target are percentage points for ratios and relative % for GMV and EUR values.

| Metric | Definition | Spend objectives (`spend_objective`) | Source | Target (`delivery_budget_capital_allocation`) |
|---|---|---|---|---|
| GMV | Order GMV (EUR) | | `dim_order_delivery.order_gmv_eur` | `gmv_ba` |
| Bolt Spend | `bolt_spend`, plus `provider_spend` on `store_1p` orders (Bolt carries it) | all | `etl_delivery_campaign_order_metrics` | `total_bolt_spend`, country rows (GLOBAL = total) and segment rows |
| Bolt Spend (BA) | Demand incentives on the order | | `dim_order_delivery.order_demand_incentives_eur` | `ba_total_spend`, country rows |
| CP L1 | `contribution_profit_eur`, all order states (failed orders' negative CP included, as in the SSOT) | | `dim_order_delivery` | none |
| CP L2 | CP L1 − `order_demand_incentives_eur` (= SSOT "CP without demand incentives") | | `dim_order_delivery` | none |
| ULC Spend | Activation + Reactivation + Engagement | those three | | sum of the three targets (= `ulc_bolt_spend`) |
| Activation | Bolt spend of activation campaigns | `activation`, `sp_activation` | `etl_delivery_campaign_order_metrics.bolt_spend` | `activation_spend` |
| Reactivation | Bolt spend of reactivation campaigns | `reactivation`, `sp_reactivation` | same | `reactivation_spend` |
| Engagement | Bolt spend of engagement campaigns | `engagement`, `sp_engagement` | same | `engagement_spend` |
| ELC | Bolt spend of ELC merchant campaigns | `provider_campaign_elc_merchant` | same | `elc`, country rows |
| Marketing | Bolt spend of marketing campaigns | `provider_campaign_marketing`, `provider_marketing_calendar_global_event` | same | `marketing`, country rows |
| AM | Bolt spend of account-management campaigns | `provider_campaign_` + `retail_growth`, `manual_churn_prevention`, `locations`, `retail_profitability`, `obligations_commitments`, `sales_benefit`, `exclusivity_retention`, `commission_increase`, `untested`, `marketing_3rd_party_partnership`, `exclusivity_gain`, `profit_generator`, `exclusivity_prevention` | same | `am`, country rows |
| Churn | Bolt spend of churn-prevention campaigns | `provider_campaign_churn_prevention` | same | `churn`, country rows |
| BDM 3P | AM + Marketing `bolt_spend` on 3P orders (`delivery_vertical` `store_3p_ent`, `store_3p_mm_smb`) | the AM and Marketing objectives | same + `dim_order_delivery.delivery_vertical` | `bdm_3p`, country rows |
| 1P (Bolt Market) | `bolt_spend` + `provider_spend` of Bolt Market campaigns | any objective containing `bolt_market` | same | `store_1p`, country rows |
| Bolt Plus | Bolt spend of Bolt Plus campaigns | `bolt_plus_campaign`, `bolt_plus_tested`, `bolt_plus_untested` | same | `bolt_plus`, country rows |

#### Status (red / yellow / green)
Each Monthly row has a status dot: the worst of three checks (rows without a target use the checks they have;
hover a dot for the detail). Thresholds are `STATUS_RULES` in `src/lib/model.ts`.

| Check | Green | Yellow | Red |
|---|---|---|---|
| GMV vs target (relative) | ≥ −2% | ≥ −10% | below −10% |
| Bolt spend as % of GMV vs the target ratio (relative overspend) | up to +5% | up to +15% | above +15% |
| GMV YoY | ≥ +10% | ≥ 0% | below 0% |

The same tables (metrics, objectives, thresholds) are in the page, under "Metric, column and status definitions".

#### Column definitions
| Column | What it shows |
|---|---|
| % of GMV (or € with the € switch) | The row's own value: spend divided by the row's own GMV. GMV, CP L1 and CP L2 follow the same switch. |
| MoM / YoY | Change vs the same days of the previous month / the same month last year (or the full month in run-rate view). Percentage points for % values, relative % for GMV and EUR values. Each month is compared on that month's segments. |
| vs Target | Actual minus target, in the same unit (pp for % of GMV, relative % for GMV and EUR). Targets come from the budget table, pro-rated for a month in progress. A dash means no target (or a blank budget cell). |
| % of global GMV | The row's spend divided by the GMV of everything shown (all countries and segments, or the filtered selection). How many points of the total spend rate the row adds, so country rows add up to the TOTAL row. |
| % of country GMV | The row's spend divided by the GMV of its country (country table only). A country row shows its own spend rate; a segment, city or cluster row shows how many points of its country's rate it adds, so the rows under a country add up to the country row. |
| Status | Red / yellow / green: the worst of GMV vs target, Bolt spend ratio vs target and GMV YoY. |

#### Targets
- Budget rows: `aggregation` = `city`, `country` (`GLOBAL` = total) or `segment`. Spend budgets are shares of GMV;
  EUR target = share × the same row's `gmv_ba`. Targets are pro-rated by elapsed days (full month in run-rate view).
- Country rows and TOTAL (GLOBAL): all metrics. Segment table: segment rows (GMV, ULC, Activation, Reactivation,
  Engagement, Bolt spend); TOTAL there is GLOBAL. City rows: sums of city targets for GMV, ULC, Activation,
  Reactivation and Engagement. Zone-cluster rows (inside the Country / Segment / City / Cluster table) have none.
- A blank budget cell means "no target" (shown as "–"), not a target of 0.
- A country/segment row's target is only used while no filter narrows it (a city or segment filter makes the
  country target not apply, a country or city filter makes the segment target not apply); the row then falls back to
  city sums, and objective / BA metrics show "–".
- The budget table is loaded by the Databricks notebook `budget_delivery_capital_allocation` from the budget sheet:
  re-run it after the sheet changes (the app reads the table at its daily refresh).

#### Other rules
- Current month is month-to-date: MoM and YoY compare the same day range, targets are pro-rated.
- Weekly WoW compares a (partial) week with the same days of the week before. Daily: DoD or same weekday last week.
- Cluster = zone cluster (`user_delivery_zone_cluster`, "Unclustered" when empty).
- Segment = `city_segment` from the budget table, month by month: October numbers use October segments,
  November uses November (MoM/YoY windows use the segment of the month they are compared to).


## 4. Data sources
- `main.ng_delivery.dim_order_delivery`: orders, GMV, contribution profit, demand incentives, vertical. Daily; local date column `order_created_date_local`.
- `main.ng_public.etl_delivery_campaign_order_metrics`: Bolt and provider spend by campaign objective, per order.
- `dev.dev_incentives.delivery_budget_capital_allocation`: budget by city, country (GLOBAL = total) and segment, loaded from the budget Google Sheet by the notebook in `code/`.
- Delivery Business Review dashboard in Looker (SSOT) for validation.
- Gotchas: the budget sheet must be shared as "Anyone with the link can view" for the notebook; the UTC partition column of `dim_order_delivery` is widened by a day so the local-date window is complete.

## 5. Files in this folder
- `queries/daily_city.sql`: daily actuals by city and zone cluster (GMV, spend by objective, CP). `queries/budget.sql`: budget at all levels. Copies of the files inside `boltable/queries/`; keep them identical.
- `code/budget_delivery_capital_allocation.py`: Databricks notebook that loads the budget sheet into the budget table (replaces the sheet's months, keeps older months). Sheet id is a placeholder.
- `boltable/`: the full app (Express + TypeScript server, React + Vite page). `server/routes/data.ts` loads and refreshes the data, `src/lib/model.ts` holds the aggregation, targets and status logic, `src/pages/Dashboard.tsx` the page. Not included: the lock file and the internal npm registry settings (they point at Bolt's internal package registry; `npm install` creates a new lock file) and the vendored agent skills from the Boltable template.

## 6. How to reproduce / refresh
1. Update the budget sheet, then run the notebook in `code/` (set `SHEET_ID`) to refresh the budget table.
2. In the app, click "Refresh targets" (re-reads only the budget), or wait for the daily refresh (08:00 UTC, setting `REFRESH_HOUR_UTC`). The app also re-reads the budget on every start.
3. Local run with synthetic data: `cd boltable && npm install && MOCK_DATA=1 npm run dev`.
4. Deploy: create a repo from the Boltable fullstack template, copy `boltable/` into it, set the Portal Secret `DATABRICKS_TOKEN` and the settings `DATABRICKS_HOST` and `DATABRICKS_HTTP_PATH` (an all-purpose cluster), push to main. Optional: `S3_BUCKET` for a snapshot that survives restarts.

## 7. Boltable details
- Page: growth-incentive-delivery-internal. Tabs: Monthly (Insights, segment and country tables (the spend groups Bolt Spend, BA, ULC, Activation, Reactivation and Engagement also show % of global GMV and, in the country table, % of country GMV), each split into performance and spend-by-objective), Weekly trend, Daily trend (tables with WoW / DoD, line charts with data labels). Definitions are on the page under "Metric, column and status definitions".
- Inputs: none from the user except filters (month(s), through-date, same days or run rate, country, city, segment, dates and metric on trend tabs).
- Access: Bolt SSO behind the NetBird VPN.

## 8. Related work
The top right corner of the page links to the Business Overview dashboards (Business Overview, City ULC vs Budget, Zone YoY Performance Map) at https://business-overview.boltable.eu; see `2026-11_delivery-growth-business-overview_zbhutta`. They are separate apps, so these are links.

Checked growth-incentive-delivery-internal on 2026-11-04 (repo was empty): nothing similar found. Terms searched: delivery, incentive, city segmentation, capital allocation, budget, Bolt spend, ULC, Boltable.

## 9. Open questions / next steps
- Confirm the objective lists for ELC, Marketing, AM and 1P against how the budget is built.
- Confirm the status thresholds with the stakeholders (they live in `STATUS_RULES` in `src/lib/model.ts`).
- November segment rows in the budget have no Bolt spend target yet.

## 10. Changelog
- 2026-11-03: first version.
- 2026-11-03: background incremental refresh, optional S3 snapshot, query timing logs.
- 2026-11-03: switched to the AB scorecard cluster connection (token only, no SQL warehouse).
- 2026-11-04: daily refresh; date/country/city/segment filters; global-by-segment tables; Cluster tab (zone
  clusters) replaces the By cluster toggle; Tuvalu and Croatia excluded.
- 2026-11-04: Bolt spend includes provider spend on store_1p orders.
- 2026-11-04: aligned with the business review dashboard: local dates, CP includes failed orders; month picker follows the data.
- 2026-11-04: month multi-select; segments per month; GA/VAT note; renamed to City Segmentation.
- 2026-11-04: country table (Bolt spend GA / BA / ELC / Marketing / AM / Churn / BDM 3P / 1P vs country targets, with TOTAL); segment table targets from segment rows; WoW / DoD on weekly and daily with line charts; metric definitions in the page and README.
- 2026-11-04: objective logic aligned with the Capital Allocation notebook: churn, AM (incl. sales_benefit), 1P by Bolt Market objective, BDM 3P = AM + Marketing on 3P orders.
- 2026-11-04: Cluster tab removed (cluster rows stay in the main table); red/yellow/green status (GMV vs target, Bolt spend vs target, YoY); Insights box on the Monthly tab.
- 2026-11-04: one table with all metrics in the agreed order (country table merged in), same metrics in the segment table; Bolt Plus added; spend objectives and status thresholds in the definitions; fix: budget month read as text (targets were empty), duplicate budget rows de-duplicated.
- 2026-11-04: segments always come from `city_segment` (segment target rows too); `final_segment` is only a fallback.
- 2026-11-04: readable first column when scrolling; ELC onwards in separate tables; WoW/DoD in titles and change bars under the trend charts.
- 2026-11-04: trend charts: change panel removed, data labels added (total / all lines / off); WoW / DoD colours in the tables; Refresh targets button.
- 2026-11-04: a blank budget cell is no target, not 0 (BA vs target showed the full value when ba_total_spend was blank).
- 2026-11-04: budget re-read on every start (a restart onto a saved snapshot kept old targets); header shows when targets were read; /api/status shows budget row counts.
- 2026-11-04: daily refresh moved to 08:00 UTC (10:00 Estonia in winter).
- 2026-11-04: added to growth-incentive-delivery-internal (sanitized copy: no workspace, cluster or sheet identifiers).
- 2026-11-04: links to the Business Overview dashboards in the top right corner.
- 2026-11-04: Boltable app renamed to delivery-growth-incentive-internal (new URL: https://delivery-growth-incentive-internal.boltable.eu).
- 2026-11-04: Boltable app renamed to delivery-growth-city-segmentation (https://delivery-growth-city-segmentation.boltable.eu); this folder renamed from 2026-11_delivery-growth-incentive-city-segmentation_nindaatikah.
- 2026-11-04: renaming the Boltable repo broke the app (Boltable ties the app and URL to the repo name), so it was renamed back to growth-incentive-delivery-internal; the URL above is the working one.
- 2026-11-04: Where the money goes tables: Bolt Spend, Bolt Spend (BA) and ULC as EUR, % of country / segment GMV, % of total GMV and share of total spend.
- 2026-11-04: Where the money goes tables removed; Bolt Spend shows % of global GMV and % of country GMV inside the performance tables.
- 2026-11-04: % of global / country GMV for all spend groups; column group lines removed; column definitions added to the page and README.
- 2026-11-04: a divider line between metric groups (only between metrics, not inside a group).
- 2026-11-05: Daily trend defaults to the 1st of the ongoing month, Weekly trend to the last 12 weeks (ranges kept per tab); the page shows the error instead of a blank screen if it crashes; the server loads data from 2026-07-01.
- 2026-11-05: Daily trend can compare with the same date last month and last year; Weekly trend gets a YoY option; history loads from 2025-07-01 for YoY.
