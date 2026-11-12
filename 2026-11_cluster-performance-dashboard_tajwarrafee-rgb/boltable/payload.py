"""Turn the cluster extracts into the payload the HTML dashboard expects."""

from __future__ import annotations

import math
from datetime import date, datetime

import pandas as pd


def _missing(value: object) -> bool:
    if value is None:
        return True
    if isinstance(value, str) and value.strip() == "":
        return True
    if isinstance(value, (float, int)) and not isinstance(value, bool):
        return bool(isinstance(value, float) and math.isnan(value))
    return bool(pd.isna(value))


def _num(value: object) -> float | int | None:
    if _missing(value):
        return None
    number = round(float(value), 4)
    if number.is_integer():
        return int(number)
    return number


def _text(value: object) -> str | None:
    if _missing(value):
        return None
    return str(value)


def _flag(value: object) -> bool:
    if _missing(value):
        return False
    if isinstance(value, str):
        return value.strip().lower() == "true"
    return bool(value)


def _iso(value: object) -> str | None:
    if _missing(value):
        return None
    if isinstance(value, datetime):
        return value.date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    return str(value)[:10]


def short_name(zone_name: str, city: str) -> str:
    """Use the cluster letter as the map label."""
    if zone_name == "Unclustered":
        return "U"
    prefix = f"{city} "
    if zone_name.startswith(prefix) and len(zone_name) == len(prefix) + 1:
        return zone_name[len(prefix):]
    return zone_name


def _comparison(row: pd.Series, prefix: str, city: bool = False) -> dict | None:
    source = f"city_{prefix}" if city else prefix
    orders_abs = _num(row[f"{source}_orders_abs"])
    gmv_abs = _num(row[f"{source}_gmv_abs"])
    spend_abs = _num(row[f"{source}_spend_abs"])
    merchants_abs = _num(row[f"{source}_merchants_abs"])
    if all(value is None for value in (orders_abs, gmv_abs, spend_abs, merchants_abs)):
        return None
    payload = {
        "label": _text(row[f"{prefix}_label"]),
        "start": _iso(row[f"{prefix}_period_start"]),
        "end": _iso(row[f"{prefix}_period_end"]),
        "ordersAbs": orders_abs,
        "ordersPct": _num(row[f"{source}_orders_pct"]),
        "gmvAbs": gmv_abs,
        "gmvPct": _num(row[f"{source}_gmv_pct"]),
        "spendAbs": spend_abs,
        "spendPct": _num(row[f"{source}_spend_pct"]),
        "merchantsAbs": merchants_abs,
        "merchantsPct": _num(row[f"{source}_merchants_pct"]),
        "unstable": _flag(row[f"{prefix}_unstable"]) if not city else False,
    }
    if not city:
        payload["gmvSharePp"] = _num(row[f"{prefix}_gmv_share_pp"])
        payload["orderSharePp"] = _num(row[f"{prefix}_order_share_pp"])
    return payload


def _zone_record(row: pd.Series) -> dict:
    return {
        "name": row["zone_name"],
        "short": short_name(row["zone_name"], row["city"]),
        "lat": _num(row["lat"]),
        "lng": _num(row["lng"]),
        "orders": _num(row["orders"]) or 0,
        "orderShare": _num(row["order_share_pct"]) or 0,
        "gmv": _num(row["gmv_eur"]) or 0,
        "gmvShare": _num(row["gmv_share_pct"]) or 0,
        "spend": _num(row["bolt_spend_eur"]) or 0,
        "spendOfCityGmv": _num(row["bolt_spend_pct_of_city_gmv"]) or 0,
        "spendToGmv": _num(row["bolt_spend_to_gmv_pct"]),
        "merchants": _num(row["active_merchants"]) or 0,
        "aov": _num(row["aov_eur"]),
        "spendPerOrder": _num(row["spend_per_order_eur"]),
        "ordersPerMerchant": _num(row["orders_per_active_merchant"]),
        "pop": _comparison(row, "pop"),
        "yoy": _comparison(row, "yoy"),
    }


def build_objectives(frame: pd.DataFrame) -> dict:
    """Nest weekly objective spend by period and cluster."""
    objectives: dict = {}
    ordered = frame.sort_values(
        ["period_start", "zone_name", "bolt_spend_eur", "spend_objective"],
        ascending=[True, True, False, True],
    )
    for row in ordered.itertuples(index=False):
        period = _iso(row.period_start)
        objectives.setdefault(period, {}).setdefault(row.zone_name, []).append(
            {
                "objective": row.spend_objective,
                "spend": _num(row.bolt_spend_eur) or 0,
                "share": _num(row.objective_share_pct) or 0,
            }
        )
    return objectives


def _city_payload(metrics: pd.DataFrame, objectives: pd.DataFrame) -> dict:
    grains = {}
    for grain, grain_frame in metrics.groupby("grain", sort=False):
        periods = []
        for period_start, period in grain_frame.groupby("period_start", sort=True):
            first = period.iloc[0]
            periods.append(
                {
                    "start": _iso(period_start),
                    "end": _iso(first["period_end"]),
                    "label": first["period_label"],
                    "isYtd": bool(first["is_ytd"]),
                    "city": {
                        "orders": _num(first["city_orders"]),
                        "gmv": _num(first["city_gmv_eur"]),
                        "spend": _num(first["city_bolt_spend_eur"]),
                        "merchants": _num(first["city_active_merchants"]),
                        "pop": _comparison(first, "pop", city=True),
                        "yoy": _comparison(first, "yoy", city=True),
                    },
                    "zones": [_zone_record(row) for _, row in period.iterrows()],
                }
            )
        grains[grain] = {"periods": periods}
    centroids = (
        metrics[["zone_name", "lat", "lng"]]
        .drop_duplicates("zone_name")
        .sort_values("zone_name")
    )
    return {
        "centroids": {
            row["zone_name"]: [_num(row["lat"]), _num(row["lng"])]
            for _, row in centroids.iterrows()
        },
        "grains": grains,
        "objectives": build_objectives(objectives),
    }


def build_payload(metrics: pd.DataFrame, meta: dict, objectives: pd.DataFrame) -> dict:
    """Turn the flat metric extract into one payload per city."""
    cities = list(dict.fromkeys(metrics["city"].tolist()))
    return {
        "meta": meta,
        "cities": cities,
        "byCity": {
            city: _city_payload(
                metrics[metrics["city"] == city],
                objectives[objectives["city"] == city],
            )
            for city in cities
        },
    }
