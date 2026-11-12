"""Extract cluster metrics for every city with two or more named clusters.

Uses the same order rules as the Lisbon extract: delivered orders, local
creation date, complete weeks and months, and the zone name joined to
dim_delivery_zone_view. Zones marked Unclustered are kept as one
cluster named Unclustered. Aggregates only.
"""

from __future__ import annotations

import importlib.util
import json
import os
import shutil
import sys
from datetime import date, timedelta

import pandas as pd

sys.path.insert(0, os.path.expanduser("~/.databricks"))
from query_helper import query as run_query

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
STAGING = os.path.join(ROOT, "data", "_build")
LISBON_EXTRACT = (
    "/Users/tajwar.rafee/Desktop/work/Tajwar Rafee-Personal/"
    "lisbon_cluster_performance/queries/run_all_queries.py"
)


def _load_lisbon():
    spec = importlib.util.spec_from_file_location("lisbon_extract", LISBON_EXTRACT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _sql_str(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _slug(city: str) -> str:
    cleaned = "".join(ch if ch.isalnum() else "-" for ch in city.lower())
    return "-".join(part for part in cleaned.split("-") if part)


def _member_label(zone_name: str) -> str:
    if " - " in zone_name:
        return zone_name.split(" - ", 1)[1]
    return zone_name


def _orders_cte(cities: list[str], history_start: date, history_end: date) -> str:
    city_list = ", ".join(_sql_str(city) for city in cities)
    city_lower = ", ".join(_sql_str(city.lower()) for city in cities)
    return f"""
cluster_map AS (
    SELECT city_name, zone_name, zone_cluster AS cluster_name
    FROM main.ng_delivery.dim_delivery_zone_view
    WHERE city_name IN ({city_list})
      AND zone_cluster IS NOT NULL
      AND TRIM(zone_cluster) <> ''
),
orders AS (
    SELECT
        m.city_name AS city,
        o.order_id,
        o.provider_id,
        m.cluster_name AS zone_name,
        CAST(o.order_gmv_eur AS DOUBLE) AS gmv_eur,
        CAST(COALESCE(o.campaign_spend_bolt_eur, 0) AS DOUBLE) AS bolt_spend_eur,
        CAST(o.delivery_lat AS DOUBLE) AS delivery_lat,
        CAST(o.delivery_lng AS DOUBLE) AS delivery_lng,
        o.order_created_date_local AS order_date
    FROM main.ng_delivery.dim_order_delivery o
    INNER JOIN cluster_map m
        ON TRIM(o.user_delivery_zone_name) = m.zone_name
       AND LOWER(TRIM(o.city_name)) = LOWER(m.city_name)
    WHERE LOWER(TRIM(o.city_name)) IN ({city_lower})
      AND o.order_delivered_ts IS NOT NULL
      AND o.order_created_date_local >= DATE '{history_start.isoformat()}'
      AND o.order_created_date_local <= DATE '{history_end.isoformat()}'
)
"""


def _discover(lisbon) -> tuple[list[str], dict[str, dict[str, list[str]]]]:
    raw = run_query(
        """
        SELECT city_name, zone_cluster, zone_name
        FROM main.ng_delivery.dim_delivery_zone_view
        WHERE zone_cluster IS NOT NULL
          AND TRIM(zone_cluster) <> ''
        """
    )
    named = raw[raw["zone_cluster"] != "Unclustered"]
    counts = named.groupby("city_name")["zone_cluster"].nunique()
    cities = sorted(counts[counts >= 2].index.tolist(), key=lambda name: (name != "Lisbon", name))
    members: dict[str, dict[str, list[str]]] = {}
    chosen = raw[raw["city_name"].isin(cities)]
    for row in chosen.itertuples(index=False):
        city_members = members.setdefault(row.city_name, {})
        city_members.setdefault(row.zone_cluster, [])
        label = _member_label(row.zone_name)
        if label not in city_members[row.zone_cluster]:
            city_members[row.zone_cluster].append(label)
    for city_members in members.values():
        for labels in city_members.values():
            labels.sort()
    print(f"Cities with 2+ named clusters: {', '.join(cities)}", flush=True)
    return cities, members


def _weekly_sql(cte: str, week_start: date, week_end: date) -> str:
    return f"""
WITH {cte}
SELECT
    city,
    CAST(DATE_TRUNC('WEEK', order_date) AS DATE) AS period_start,
    zone_name,
    COUNT(DISTINCT order_id) AS orders,
    SUM(gmv_eur) AS gmv_eur,
    SUM(bolt_spend_eur) AS bolt_spend_eur,
    COUNT(DISTINCT provider_id) AS active_merchants,
    GROUPING(zone_name) AS is_city_total
FROM orders
WHERE order_date >= DATE '{week_start.isoformat()}'
  AND order_date <= DATE '{week_end.isoformat()}'
GROUP BY GROUPING SETS (
    (city, CAST(DATE_TRUNC('WEEK', order_date) AS DATE), zone_name),
    (city, CAST(DATE_TRUNC('WEEK', order_date) AS DATE))
)
"""


def _monthly_sql(cte: str, history_start: date, month_end: date) -> str:
    return f"""
WITH {cte}
SELECT
    city,
    CAST(DATE_TRUNC('MONTH', order_date) AS DATE) AS period_start,
    zone_name,
    COUNT(DISTINCT order_id) AS orders,
    SUM(gmv_eur) AS gmv_eur,
    SUM(bolt_spend_eur) AS bolt_spend_eur,
    COUNT(DISTINCT provider_id) AS active_merchants,
    GROUPING(zone_name) AS is_city_total
FROM orders
WHERE order_date >= DATE '{history_start.isoformat()}'
  AND order_date <= DATE '{month_end.isoformat()}'
GROUP BY GROUPING SETS (
    (city, CAST(DATE_TRUNC('MONTH', order_date) AS DATE), zone_name),
    (city, CAST(DATE_TRUNC('MONTH', order_date) AS DATE))
)
"""


def _yearly_sql(cte: str, history_start: date, current_year_end: date) -> str:
    current_year = current_year_end.year
    prior_year = current_year - 1
    aligned_prior_end = date(prior_year, current_year_end.month, current_year_end.day)
    return f"""
WITH {cte},
periods AS (
    SELECT '{prior_year}' AS period_key, DATE '{prior_year}-01-01' AS period_start,
           DATE '{prior_year}-12-31' AS period_end, '{prior_year}' AS period_label,
           0 AS is_ytd, 0 AS comparison_only
    UNION ALL
    SELECT '{current_year}', DATE '{current_year}-01-01', DATE '{current_year_end.isoformat()}',
           '{current_year} YTD', 1, 0
    UNION ALL
    SELECT '{prior_year}_aligned', DATE '{prior_year}-01-01', DATE '{aligned_prior_end.isoformat()}',
           '{prior_year} aligned', 0, 1
)
SELECT
    o.city,
    p.period_key,
    p.period_start,
    p.period_end,
    p.period_label,
    p.is_ytd,
    p.comparison_only,
    o.zone_name,
    COUNT(DISTINCT o.order_id) AS orders,
    SUM(o.gmv_eur) AS gmv_eur,
    SUM(o.bolt_spend_eur) AS bolt_spend_eur,
    COUNT(DISTINCT o.provider_id) AS active_merchants,
    GROUPING(o.zone_name) AS is_city_total
FROM orders o
INNER JOIN periods p
    ON o.order_date BETWEEN p.period_start AND p.period_end
GROUP BY GROUPING SETS (
    (o.city, p.period_key, p.period_start, p.period_end, p.period_label, p.is_ytd, p.comparison_only, o.zone_name),
    (o.city, p.period_key, p.period_start, p.period_end, p.period_label, p.is_ytd, p.comparison_only)
)
"""


def _objective_sql(cte: str, week_start: date, week_end: date) -> str:
    partition_start = week_start - timedelta(days=2)
    partition_end = week_end + timedelta(days=2)
    return f"""
WITH {cte},
zone_orders AS (
    SELECT order_id, MAX(city) AS city, MAX(zone_name) AS zone_name, MAX(order_date) AS order_date
    FROM orders
    GROUP BY order_id
)
SELECT
    z.city,
    CAST(DATE_TRUNC('WEEK', z.order_date) AS DATE) AS period_start,
    z.zone_name,
    COALESCE(NULLIF(TRIM(c.spend_objective), ''), 'Unknown') AS spend_objective,
    SUM(CAST(c.bolt_spend AS DOUBLE)) AS bolt_spend_eur
FROM main.ng_public.etl_delivery_campaign_order_metrics c
INNER JOIN zone_orders z
    ON c.order_id = z.order_id
WHERE c.order_created_date >= DATE '{partition_start.isoformat()}'
  AND c.order_created_date <= DATE '{partition_end.isoformat()}'
GROUP BY
    z.city,
    CAST(DATE_TRUNC('WEEK', z.order_date) AS DATE),
    z.zone_name,
    COALESCE(NULLIF(TRIM(c.spend_objective), ''), 'Unknown')
"""


def _centroid_sql(cte: str) -> str:
    return f"""
WITH {cte}
SELECT
    city,
    zone_name,
    AVG(delivery_lat) AS lat,
    AVG(delivery_lng) AS lng,
    COUNT(*) AS centroid_orders
FROM orders
WHERE delivery_lat IS NOT NULL
  AND delivery_lng IS NOT NULL
GROUP BY city, zone_name
"""


def _city_frame(frame: pd.DataFrame, city: str) -> pd.DataFrame:
    subset = frame.loc[frame["city"] == city].drop(columns=["city"]).copy()
    return subset


def _objectives_for(raw: pd.DataFrame, city: str) -> pd.DataFrame:
    columns = [
        "city",
        "period_start",
        "period_end",
        "zone_name",
        "spend_objective",
        "bolt_spend_eur",
        "objective_share_pct",
    ]
    subset = raw.loc[raw["city"] == city].copy() if not raw.empty else raw
    if subset.empty:
        return pd.DataFrame(columns=columns)
    subset["period_start"] = subset["period_start"].map(lambda value: pd.to_datetime(value).date())
    subset["bolt_spend_eur"] = pd.to_numeric(subset["bolt_spend_eur"])
    subset = subset[subset["bolt_spend_eur"].fillna(0) != 0].copy()
    if subset.empty:
        return pd.DataFrame(columns=columns)
    zone_total = subset.groupby(["period_start", "zone_name"])["bolt_spend_eur"].transform("sum")
    subset = subset[zone_total != 0].copy()
    zone_total = subset.groupby(["period_start", "zone_name"])["bolt_spend_eur"].transform("sum")
    subset["objective_share_pct"] = subset["bolt_spend_eur"] / zone_total * 100
    subset["city"] = city
    subset["period_end"] = subset["period_start"].map(lambda value: value + timedelta(days=6))
    subset["bolt_spend_eur"] = subset["bolt_spend_eur"].round(2)
    subset["objective_share_pct"] = subset["objective_share_pct"].round(2)
    return subset[columns]


def _write_city(
    lisbon,
    city: str,
    members: dict[str, list[str]],
    metrics: pd.DataFrame,
    objectives: pd.DataFrame,
    today: date,
    week_start: date,
    week_end: date,
    last_month_end: date,
) -> None:
    folder = os.path.join(STAGING, _slug(city))
    os.makedirs(folder, exist_ok=True)
    metrics = lisbon._round_output(metrics)
    metrics = metrics[lisbon.OUTPUT_COLUMNS].sort_values(
        ["city", "grain", "period_start", "orders", "zone_name"],
        ascending=[True, True, True, False, True],
    )
    metrics.to_csv(os.path.join(folder, "cluster_metrics.csv"), index=False, na_rep="")
    objectives.sort_values(
        ["period_start", "zone_name", "bolt_spend_eur", "spend_objective"],
        ascending=[True, True, False, True],
    ).to_csv(os.path.join(folder, "cluster_objective_spend.csv"), index=False)
    meta = {
        "generated_on": today.isoformat(),
        "cities": [city],
        "cluster_zones": members,
        "history_start": lisbon.HISTORY_START.isoformat(),
        "weekly_start": week_start.isoformat(),
        "weekly_end": week_end.isoformat(),
        "monthly_start": lisbon.HISTORY_START.isoformat(),
        "monthly_end": last_month_end.isoformat(),
        "yearly_current_end": week_end.isoformat(),
        "yearly_prior_aligned_end": date(week_end.year - 1, week_end.month, week_end.day).isoformat(),
        "unstable_prior_orders": lisbon.UNSTABLE_PRIOR_ORDERS,
        "zone_count": int(metrics["zone_name"].nunique()),
        "metric_rows": int(len(metrics)),
    }
    with open(os.path.join(folder, "meta.json"), "w", encoding="utf-8") as handle:
        json.dump(meta, handle)
    latest = metrics[metrics["grain"] == "week"]
    latest_start = latest["period_start"].max()
    latest = latest[latest["period_start"] == latest_start]
    print(
        f"{city}: {metrics['zone_name'].nunique()} clusters, "
        f"latest week orders {int(latest['city_orders'].iloc[0])}, "
        f"GMV {float(latest['city_gmv_eur'].iloc[0]):.0f}",
        flush=True,
    )


def _publish() -> None:
    data_dir = os.path.join(ROOT, "data")
    for name in os.listdir(STAGING):
        source = os.path.join(STAGING, name)
        if not os.path.isdir(source):
            continue
        target = os.path.join(data_dir, name)
        if os.path.isdir(target):
            shutil.rmtree(target)
        shutil.move(source, target)
    shutil.rmtree(STAGING, ignore_errors=True)


def main() -> None:
    lisbon = _load_lisbon()
    today = date.today()
    week_start, week_end = lisbon.complete_week_bounds(today, lisbon.HISTORY_START)
    last_month_end = lisbon.complete_month_end(today)
    print(f"Weekly {week_start} to {week_end}; monthly through {last_month_end}", flush=True)
    cities, members = _discover(lisbon)
    if os.path.isdir(STAGING):
        shutil.rmtree(STAGING)
    os.makedirs(STAGING, exist_ok=True)

    print("Querying weekly metrics...", flush=True)
    weekly_raw = lisbon._prepare_raw(run_query(_weekly_sql(
        _orders_cte(cities, lisbon.HISTORY_START, week_end), week_start, week_end
    )))
    print(f"  weekly rows {len(weekly_raw)}", flush=True)
    print("Querying monthly metrics...", flush=True)
    monthly_raw = lisbon._prepare_raw(run_query(_monthly_sql(
        _orders_cte(cities, lisbon.HISTORY_START, last_month_end), lisbon.HISTORY_START, last_month_end
    )))
    print(f"  monthly rows {len(monthly_raw)}", flush=True)
    print("Querying yearly metrics...", flush=True)
    yearly_raw = lisbon._prepare_raw(run_query(_yearly_sql(
        _orders_cte(cities, lisbon.HISTORY_START, week_end), lisbon.HISTORY_START, week_end
    )))
    print(f"  yearly rows {len(yearly_raw)}", flush=True)
    print("Querying objective spend...", flush=True)
    objectives_raw = run_query(_objective_sql(
        _orders_cte(cities, week_start, week_end), week_start, week_end
    ))
    print(f"  objective rows {len(objectives_raw)}", flush=True)
    print("Querying centroids...", flush=True)
    centroids = run_query(_centroid_sql(_orders_cte(cities, lisbon.HISTORY_START, week_end)))
    centroids["lat"] = pd.to_numeric(centroids["lat"])
    centroids["lng"] = pd.to_numeric(centroids["lng"])
    print(f"  centroid rows {len(centroids)}", flush=True)

    saved = []
    skipped = []
    for city in cities:
        try:
            weekly = _city_frame(weekly_raw, city)
            monthly = _city_frame(monthly_raw, city)
            yearly = _city_frame(yearly_raw, city)
            if weekly.empty or monthly.empty or yearly.empty:
                skipped.append(f"{city}: no delivered orders in the window")
                continue
            lisbon._check_week_alignment(weekly)
            weekly = lisbon.build_weekly(weekly)
            lisbon._reconcile(weekly, f"{city} week")
            monthly = lisbon.build_monthly(monthly)
            lisbon._reconcile(monthly, f"{city} month")
            yearly = lisbon.build_yearly(yearly)
            metrics = pd.concat([weekly, monthly, yearly], ignore_index=True)
            metrics["city"] = city
            city_centroids = centroids.loc[centroids["city"] == city, ["zone_name", "lat", "lng"]]
            metrics = metrics.merge(city_centroids, on="zone_name", how="left")
            objectives = _objectives_for(objectives_raw, city)
            _write_city(
                lisbon, city, members[city], metrics, objectives,
                today, week_start, week_end, last_month_end,
            )
            saved.append(city)
        except Exception as exc:
            skipped.append(f"{city}: {exc}")
            print(f"Skipped {city}: {exc}", flush=True)
    if not saved:
        raise RuntimeError("No cities were saved.\n" + "\n".join(skipped))
    _publish()
    print("Saved: " + ", ".join(saved), flush=True)
    if skipped:
        print("Skipped:\n" + "\n".join(skipped), flush=True)


if __name__ == "__main__":
    main()
