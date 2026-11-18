# Activation Performance dashboard (Bolt Food)

| Field | Value |
|---|---|
| Owner | Tajwar Rafee / tajwarrafee-rgb |
| Date (created / last updated) | 2026-11-18 / 2026-11-18 |
| Status | live (18 November 2026 snapshot until the Databricks Service Principal is set up) |
| Boltable page | Activation Performance, https://activation-performance.boltable.eu (repo https://github.com/boltable/activation-performance) |
| Stakeholders / requested by | Tajwar Rafee, for the growth incentive delivery team (readers of the Activation Performance Sheet) |
| Region / vertical | Delivery (Bolt Food). Estonia, Latvia, Lithuania, Slovakia, Czech Republic, Malta, Romania, Poland, Portugal, Ukraine, Cyprus, Bulgaria, Azerbaijan, Ghana, Kenya |
| Keywords | activation performance, activation rate, same-day activation, D0 conversion, delayed activation D1–D14, late activation D14+, new users, signups, power users, repeat orders, 2-in-7d, 2-in-30d, avg orders 30d, first-order discount, new city, counterfactual, mix impact, rate impact, country mix, marketing mix, media group, local vs tourist, dim_user_delivery, delivery_activation_ts, etl_delivery_order_monetary_metrics, Boltable, Streamlit |

## 1. Business question
Are new Bolt Food users activating, how fast, and are they good users? Each week the team reads observed activation
(signups, new users, same-day / delayed / late activation), user quality (2-in-7d, 2-in-30d, orders and discount in
the first 30 days), how much of the YoY change in same-day conversion comes from mix (country, city type, user type,
channel), and what changed inside each country. The page replaces the "Activation Performance" Google Sheet fed by a
Databricks notebook.

## 2. TL;DR / key findings
Week of 9 November 2026 (ISO week 46), the 15 markets, data refreshed 18 November 2026:

- 89,562 signups (−2.9% YoY) and 56,326 new users. Activation rate 62.9% (+5.6 pp YoY).
- Same-day activation 29.4% (−0.41 pp WoW, +1.04 pp YoY); late activation (D14+) 25.0%.
- Quality: 2-in-7d was 24.9% in the week of 2 November, the latest week whose 7-day window has closed. Weeks
  whose windows are still open are marked † on the page.
- Against the Sheet, 2024–2025 weeks match within 0.1–0.3%. Weeks close to the Sheet's last refresh (late July 2026)
  differ by 1–3% because of later data revisions in `dim_user_delivery`.
- AQI, the expansion-adjusted expected rate, the OB decomposition and the country contribution table from the Sheet
  were dropped on request.

## 3. Methodology
The logic is the notebook `code/activation_performance_core_clean.ipynb`, unchanged. Only table names moved from
`ng_delivery_spark.` / `ng_public_spark.` to `main.ng_delivery.` / `main.ng_public.`; the `_spark` schemas no longer
resolve on the SQL warehouse.

- Grain: one row per day × country × city × new city × media group × local, additive counts and sums, rolled up to
  Monday weeks in pandas.
- Signups are counted on the signup date; new users (activations) on `delivery_activation_ts`. Rates divide the two.
  Same-day = activated on the signup day, delayed = 1–14 days, late = more than 14 days.
- New city: signed up within 16 weeks of the city's `food_delivery_launch_date`. The Sheet's Read Me says 12 weeks;
  the query uses 16.
- Media group: `organic`, `RiderApp`, `social_Ads` (Google, TikTok, Facebook Ads), `rest`. Local: `phone_anonymized`
  equals the home city country's phone prefix.
- 2-in-7d / 2-in-30d: new users with 2+ orders in 7 / 30 days after activation. Avg orders (30d) per new user.
  Discount = Bolt + provider campaign cost ÷ GMV.
- Counterfactual YoY (signup-week cohorts vs 52 weeks earlier): mix impact = Σ Δ share × rate last year; by segment,
  share impact = Δ share × rate last year, rate impact = share × Δ rate (Sheet formulas).
- Maturity: country and city summaries take 2-in-7d from the previous week and 30-day metrics from 4 weeks earlier,
  like the Sheet. The 8-week tables show every week and mark immature cells with †.
- Not included: the notebook's AQI, expansion-adjusted expected rate and OB decomposition. They were removed from the
  pipeline and the page.

Known limitations (also on the page):
- Weekly activation rates mix cohorts (activations in the week ÷ signups in the week).
- Orders have no order-state filter.
- YoY on KPI tables is by ISO week; the counterfactual tables use 52 weeks earlier.
- Mean days to second order divides by all new users, so it reads low.
- City and segment tables cover the last 12 weeks plus the same weeks last year, as in the notebook export.
- The local/tourist split changed for 2026 weeks against the Sheet (week of 22 June 2026: 83.6% local now vs 77.6% in
  the Sheet). The old `ng_public_spark.user_user` no longer exists, so the difference can't be traced. It is most
  likely later updates to users' home city or phone fields.

Sheet issue found while porting: the Behaviour Summary and the per-country tabs point at fixed column letters of the
export tabs. The notebook later added `first_order_discount_bolt` and `discount_30d_bolt` in the middle of the export,
so references to the right of them read the wrong metric. In the Behaviour Summary, "AQI" shows same-day mean time to
first order, "Power User Rate" shows the D1–14 activation rate, "Avg Orders" the D14+ rate, and the YoY cells read WoW
columns. The dashboard looks columns up by name.

## 4. Data sources
- `main.ng_delivery.dim_user_delivery`: signups (`created_ts`), activation (`delivery_activation_ts`), install channel, city.
- `main.ng_delivery.dim_delivery_city`: country, city, `food_delivery_launch_date`.
- `main.ng_public.etl_delivery_order_monetary_metrics`: orders, GMV, Bolt and provider campaign cost.
- `main.ng_public.user_user`, `main.ng_public.admin_system_country`: local vs tourist (phone prefix vs home country).
- Previous output: Google Sheet "Activation Performance",
  https://docs.google.com/spreadsheets/d/1nOB9mk_mRJesDuvnyAYGZoCEaasgQLG5CI_l-WjsV90 (last notebook export late July 2026).

Freshness: the core query scans all of `etl_delivery_order_monetary_metrics` (no date filter in the notebook). It takes
about 200 s on the warehouse and returns 1.44M rows; a full refresh is about 6 minutes.

## 5. Files in this folder
- `queries/`: the six notebook queries (`core_fact`, `active_cities`, four `*_mix_impact`), table names updated.
- `code/activation_performance_core_clean.ipynb`: the original notebook, outputs stripped.
- `boltable/`: the app as deployed. `extract.py` (Databricks), `pipeline.py` (notebook functions),
  `refresh.py` (weekly scheduler), `storage.py` (S3 or local parquet), `app.py` + `charts.py` + `DEFINITIONS.md` (UI),
  `data/` (the 18 November 2026 snapshot of the output tables, weekly aggregates, shown until a refresh runs).
- `outputs/`: aggregated output tables from the 18 November 2026 refresh (weekly global, weekly country, four mix tables), CSV.

## 6. How to reproduce / refresh
Until the Databricks Service Principal secrets are in the Portal, the page shows the `boltable/data/` snapshot from
18 November 2026 and skips refreshes. With the secrets, the app refreshes itself on Mondays at 10:00 Europe/Tallinn,
and at startup when the saved data is over 7 days old. The "Refresh now" button (for emails in `REFRESH_ADMINS`)
runs one on demand. To update the snapshot by hand, refresh locally and copy `local_data/outputs/*` into `data/`.
Locally:

```bash
cd boltable
python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
export DATABRICKS_TOKEN=...    # local only; the app uses a Service Principal
python -c "import refresh; refresh.refresh_now('manual')"   # writes ./local_data/outputs
streamlit run app.py
```

To change the market list or start date, edit `FILTER_COUNTRIES` / `DATE_CUTOFF` in both `extract.py` and `pipeline.py`.

## 7. Boltable details
- Page: Activation Performance, https://activation-performance.boltable.eu (repo https://github.com/boltable/activation-performance).
- Tabs: Behaviour Summary (quality 8-week table, repeat-order and 30-day order charts);
  Environment Summary (activation 8-week table, country summary, counterfactual conversions YoY, mix and behaviour by
  country / city type / user type / channel); Country (per-country activation, quality, channel /
  user type / city type, top-15 cities, city trend for a chosen metric); City explorer (filters and breakdowns over the
  12-week city export); Definitions.
- Inputs: a sidebar week picker (complete weeks only). No uploads.
- Config: Secrets `DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET`, `DATABRICKS_HTTP_PATH`, `DATA_BUCKET`,
  optional `REFRESH_ADMINS`; File Storage (S3) on; at least 4 GB memory (a refresh peaks at about 2.1 GB).
- Access: SSO with an email allowlist (to be set).

## 8. Related work
Checked growth-incentive-delivery-internal on 18 November 2026 (terms: activation rate / performance / quality,
same-day, AQI, Oaxaca, expansion-adjusted, power user, tourist, `dim_user_delivery`, `delivery_activation_ts`).
- `2026-11_delivery-growth-business-overview_zbhutta` (zbhutta): `queries/14_daily_signups.sql` and
  `queries/17_user_type_daily.sql` count daily signups and local / tourist / unknown activations from the same
  `dim_user_delivery`. No quality metrics or counterfactual mix tables. Its local rule differs (country calling
  code table, plus an "unknown" bucket).
- `2026-11_delivery-growth-city-segmentation_nindaatikah` (nindaatikah): activation campaign spend vs budget.
  Spend, not user activation.
- `2026-11_cluster-performance-dashboard_tajwarrafee-rgb` (on its PR branch): same Streamlit-on-Boltable pattern,
  different topic.

## 9. Open questions / next steps
- Databricks Service Principal ticket for the app (tables above), then Secrets in the Portal.
- New city window: 16 weeks in the query vs 12 weeks in the Sheet's Read Me. Which is intended?
- Fix or retire the Google Sheet's summary tabs (column-shift issue above) once the page is live.
- Optional: filter orders by state, and push the date filter into the orders scan to cut refresh time.

## 10. Changelog
- 2026-11-18 tajwarrafee-rgb: first version. Notebook ported to a Boltable Streamlit app with a weekly Databricks
  refresh, table names moved to `main.`, Sheet views rebuilt, validated against the Sheet. AQI, expansion-adjusted
  expected rate, OB decomposition and country contribution left out on request.
- 2026-11-18 tajwarrafee-rgb: Published to https://activation-performance.boltable.eu with the 18 November 2026 data snapshot.
- 2026-11-18 tajwarrafee-rgb: Fixed charts failing on Boltable (bolt-viz needs plain lists, not numpy arrays). App memory set to 1 GB in the Portal (256 MB crashed on page load).
