### How to read this dashboard
1. **Environment Summary**: observed performance. Signups, new users and activation rates, the country summary, and
   the counterfactual YoY tables that show how much of the change in same-day conversion comes from mix.
2. **Behaviour Summary**: activation quality. Are new users ordering again (2-in-7d, 2-in-30d, avg orders) and at
   what discount.
3. **Country tab**: what changed inside a country: activation, quality, channel, user type, city type, cities.

### Scope
Bolt Food delivery users in Estonia, Latvia, Lithuania, Slovakia, Czech Republic, Malta, Romania, Poland,
Portugal, Ukraine, Cyprus, Bulgaria, Azerbaijan, Ghana and Kenya, from 1 January 2024. Weeks start on Monday.
The logic is the notebook `activation_performance_core_clean.ipynb` with table names moved to the `main.` catalog.
AQI, the expansion-adjusted expected rate and the OB decomposition from the notebook are not part of this dashboard.

### Segments
| Segment | Definition |
|---|---|
| New city | The user signed up on or after the city's `food_delivery_launch_date` and within 16 weeks of the launch week (the Sheet's Read Me says 12 weeks; the query uses 16) |
| Channel (media group) | `app_install_channel_name`: `organic`, `RiderApp`, `social_Ads` (Google, TikTok, Facebook Ads), `rest` (everything else, including empty) |
| Local / tourist | Local when `phone_anonymized` equals the phone prefix of the home city's country |

### KPIs
Signups are counted in the week of signup, new users (activations) in the week of activation (`delivery_activation_ts`).

| KPI | Formula |
|---|---|
| Total activation rate | new users ÷ signups |
| Same-day activation rate | users activated on their signup day ÷ signups |
| Delayed activation rate (D1–D14) | users activated 1–14 days after signup ÷ signups |
| Late activation rate (D14+) | users activated more than 14 days after signup ÷ signups |
| 2-in-7d (power-user rate) | new users with 2+ orders in the 7 days after activation ÷ new users |
| 2-in-30d | new users with 2+ orders in the 30 days after activation ÷ new users |
| Avg orders (30d) | orders in the 30 days after activation ÷ new users |
| First-order discount % | first-order Bolt + provider campaign cost ÷ first-order GMV |
| 30-day discount % | Bolt + provider campaign cost ÷ GMV, 30 days after activation |
| WoW / YoY | relative change for counts, percentage points for rates; YoY = same ISO week last year |

† marks weeks where the 7-day or 30-day window has not closed yet, so the value will still rise.

### Counterfactual conversions YoY
Signup-week cohorts: same-day activation is the share of a week's signups who activated on their signup day, compared
with the week 52 weeks earlier. Mix impact = Σ (share − share last year) × rate last year. By segment: signup share
impact = Δ share × rate last year; activation rate impact = share × Δ rate.

### Known limitations
- The weekly activation rates divide activations dated in the week by signups dated in the week, so they mix
  cohorts. The counterfactual tables use signup-week cohorts, so their same-day rate differs slightly.
- 7-day and 30-day metrics (2-in-7d, 2-in-30d, avg orders, 30-day discount) read low until their windows close (†).
- Orders come from `etl_delivery_order_monetary_metrics` without an order-state filter.
- YoY on the KPI tables matches ISO week numbers; the counterfactual tables use 52 weeks earlier. They can differ by a
  week around year ends with an ISO week 53.
- Mean days to second order divides by all new users, including those without a second order, so it reads low.
- Segment and city tables only cover the last 12 weeks (plus the same weeks last year), as in the notebook export.

### Data sources
`main.ng_delivery.dim_user_delivery`, `main.ng_delivery.dim_delivery_city`, `main.ng_public.etl_delivery_order_monetary_metrics`,
`main.ng_public.user_user`, `main.ng_public.admin_system_country`.
