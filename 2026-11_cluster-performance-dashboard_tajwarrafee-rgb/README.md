# Cluster performance dashboard

| Field | Value |
|---|---|
| Owner | Tajwar Rafee / tajwarrafee-rgb |
| Date (created / last updated) | 2026-11-12 / 2026-11-12 |
| Status | draft |
| Boltable page | Cluster Performance Dashboard, not published yet. Planned URL: https://cluster-performance-dashboard.boltable.eu |
| Stakeholders / requested by | Tajwar Rafee, for the growth incentive team |
| Region / vertical | Delivery. Algarve, Baku, Bucharest, Kharkiv, Kyiv, Lisbon, Nairobi, Porto, Prague, Tallinn, Valletta, Vilnius, Warsaw |
| Keywords | cluster performance, delivery zone cluster, zone_cluster, Lisbon A-H, orders, GMV, Bolt spend, active merchants, GMV share, order share, segment, capital allocation, Maintain Share, Non Priority, Launch, Preparation, Monetise, Grow Share, Unclustered, dim_order_delivery, dim_delivery_zone_view, weekly, monthly, yearly |

## 1. Business question

Which delivery clusters in each clustered city are taking orders, GMV, and Bolt spend, and how does the latest complete week compare with the previous week and the same week last year? The page is for the team to check cluster health and the November 2026 capital-allocation segment without rebuilding the Lisbon workbook for every city.

## 2. TL;DR / key findings

Latest complete week is 2–8 November 2026. Figures below are delivered orders and GMV across that city’s clusters.

- Lisbon: 8 clusters, 52,351 orders, €1,242,087 GMV. Lisbon A and Lisbon G are Maintain Share. The other Lisbon clusters are Non Priority.
- Bucharest is the largest week in this set: 132,604 orders, €3,369,068 GMV, all four clusters Maintain Share.
- Tallinn is the only city here with an Unclustered cluster (five Bolt Market zones). The sheet leaves its segment blank.
- Valletta’s dormant cluster, named Valletta rather than A, B, or C, has no segment on the capital-allocation sheet.
- The other latest weeks: Algarve 1,615 orders / €38,802; Baku 42,005 / €615,170; Kharkiv 10,438 / €159,177; Kyiv 49,349 / €892,278; Nairobi 24,711 / €297,004; Porto 7,194 / €182,626; Prague 73,682 / €1,655,823; Tallinn 65,082 / €2,061,925; Valletta 78,384 / €2,313,051; Vilnius 57,454 / €1,660,069; Warsaw 20,796 / €538,475.

## 3. Methodology

A city is included when `dim_delivery_zone_view` has at least two named `zone_cluster` values other than Unclustered. Zones tagged Unclustered are kept as one extra cluster of that name. Orders are delivered orders, all delivery verticals, dated by the local creation date, from 1 January 2025. The order’s customer zone name is matched to the zone list, and the zone’s cluster becomes the cluster on the page.

The current week and the current month are excluded. Weekly compares with the previous week and the same ISO week last year. Monthly compares with the previous month and the same month last year. The yearly tab shows the full prior year and the current year through the last complete week, compared with the same dates last year. A percentage change is hidden when the prior value is zero. A change is marked unstable when the prior period had fewer than 30 orders.

GMV share and order share use that city’s total across its clusters in the same period. Active merchants are distinct providers with a delivered order in the cluster. A merchant can appear in more than one cluster, so the cluster counts do not add up to the city count. Segment is the November 2026 capital-allocation role and does not change with the selected period. Spend proposal is not shown.

Bubble position is the average delivery coordinate of the cluster across the history window. The letter on the bubble is the last character of the cluster name. Unclustered is shown as U.

## 4. Data sources

- `main.ng_delivery.dim_order_delivery` for delivered orders, GMV, Bolt spend, merchants, and coordinates.
- `main.ng_delivery.dim_delivery_zone_view` for `zone_cluster`, zone name, zone id, and polygon id.
- `main.ng_public.etl_delivery_campaign_order_metrics` for weekly objective spend.
- Segment: Google Sheet “[City Segmentation] Capital Allocation Demand Incentive - NOVEMBER 2026”, tab Cluster. https://docs.google.com/spreadsheets/d/10SEaMlh_ZuxN1pCb6IYWtLIz5_HmnvBNQ4PZ0JYX99c/edit?gid=1980248295

The extract in this folder was run on 12 November 2026 and stops at the week ending 8 November 2026. The page reads those saved files. It does not query Databricks when the browser is refreshed.

## 5. Files in this folder

- `queries/extract_cities.py` pulls the weekly, monthly, yearly, objective, and centroid aggregates for every city with two or more named clusters.
- `code/` is the Streamlit app: `app.py`, `payload.py`, and `dashboard_template.html`.
- `boltable/` is the bundle to publish: the same app plus `data/` for each city and `proposals.json` for segments.
- `outputs/` is a copy of those aggregate files.

## 6. How to reproduce / refresh

From a machine that can reach Databricks, with `DATABRICKS_TOKEN` set in the environment:

```bash
python3 queries/extract_cities.py
```

The script writes one folder per city under `data/`. Segment labels are maintained in `data/proposals.json` from the Cluster tab of the capital-allocation sheet. A Monday 10:00 Europe/Tallinn refresh is planned for the Boltable app and is not built yet.

## 7. Boltable details

Not published. Planned page name: Cluster Performance Dashboard. Planned URL: https://cluster-performance-dashboard.boltable.eu. The page has a city dropdown, weekly / monthly / yearly tabs, a map, a cluster panel, and a ranking table. Access should be an SSO email allowlist for the team. Until that list is saved, anyone on the company VPN can open a published Boltable app.

## 8. Related work

Checked `growth-incentive-delivery-internal` on 12 November 2026.

- `2026-11_delivery-growth-incentive-city-segmentation_nindaatikah` (Ninda, 4 November 2026, live at https://growth-incentive-delivery-internal.boltable.eu). Budget versus actual by country, city, and zone cluster. Different question: allocation tracking, not cluster orders, GMV, and maps.
- `2026-11_delivery-growth-business-overview_zbhutta` (Zeeshan, 4 November 2026, live at https://business-overview.boltable.eu). Business overview, including a zone year-on-year map. Different page and a wider operating view.

This folder is the cluster performance page. It was not started by extending either of those apps.

## 9. Open questions / next steps

- Publish to Boltable only after this folder is on the team repo.
- Turn on SSO and add the team’s emails before sending the link.
- Add the Monday 10:00 Europe/Tallinn extract once File Storage and a Databricks service principal are available. The app must not use a personal Databricks token.
- Segment still comes from the November sheet and will not move on the Monday order refresh.

## 10. Changelog

- 2026-11-12 tajwarrafee-rgb: First archive. Thirteen cities, week ending 8 November 2026, segment on the panel and ranking, spend proposal left out, definitions written for every city.
