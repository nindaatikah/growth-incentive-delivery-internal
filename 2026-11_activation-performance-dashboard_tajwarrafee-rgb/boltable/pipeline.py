"""Notebook logic from activation_performance_core_clean.ipynb, sections 2 to 8.

The helper functions below are copied from the notebook unchanged. build_outputs()
runs sections 8.1, 8.2 and 8.3 and returns the tables the notebook exported to
Google Sheets, without AQI, the expansion-adjusted expected rate and the OB
decomposition.
"""

import pandas as pd
import numpy as np

def coerce_numeric(df, cols):
    out = df.copy()
    for c in cols:
        if c in out.columns:
            out[c] = pd.to_numeric(out[c], errors="coerce")
    return out

def add_week(df, date_col="event_date", week_col="week"):
    out = df.copy()
    out[date_col] = pd.to_datetime(out[date_col])
    out[week_col] = out[date_col].dt.to_period("W").apply(lambda p: p.start_time)
    return out

SUM_COLS = [
    "signup_users","activated_users","activated_users_d0","activated_users_d14","activated_users_d14_plus",
    "first_order_gmv","first_order_discount","gmv_30d","discount_30d","orders_30d",
    "days_to_second_order","time_to_first_order_minutes","time_to_first_order_minutes_d0","power_users_7d","power_users_30d",
    "first_order_discount_bolt","discount_30d_bolt"

]


def safe_div(n, d):
    n = np.asarray(n, dtype="float64")
    d = np.asarray(d, dtype="float64")
    return np.where(d > 0, n / d, np.nan)

def aggregate_additive(df, dims=None, sum_cols=None, time_col="week"):
    if dims is None:
        dims = []
    if sum_cols is None:
        sum_cols = SUM_COLS
    group_cols = [time_col] + dims
    return df.groupby(group_cols, dropna=False)[sum_cols].sum().reset_index()

def add_core_kpis(df):
    out = df.copy()

    out["activation_rate"] = safe_div(out["activated_users"], out["signup_users"])
    out["same_day_activation_rate"] = safe_div(out["activated_users_d0"], out["signup_users"])
    out["d14_activation_rate"] = safe_div(out["activated_users_d14"], out["signup_users"])
    out["d14_plus_activation_rate"] = safe_div(out["activated_users_d14_plus"], out["signup_users"])

    out["power_user_rate_7d"] = safe_div(out["power_users_7d"], out["activated_users"])
    out["avg_orders_30d"] = safe_div(out["orders_30d"], out["activated_users"])

    out["first_order_discount_pct"] = safe_div(out["first_order_discount"], out["first_order_gmv"])
    out["discount_30d_pct"] = safe_div(out["discount_30d"], out["gmv_30d"])

    out["mean_time_to_first_order_minutes"] = safe_div(out["time_to_first_order_minutes"], out["activated_users"])
    out["mean_time_to_first_order_minutes_d0"] = safe_div(out["time_to_first_order_minutes_d0"], out["activated_users_d0"])
    out["mean_days_to_second_order"] = safe_div(out["days_to_second_order"], out["activated_users"])

    return out


def add_wow_yoy(
    df,
    kpi_cols=None,
    week_col="week",
    group_cols=None,
):
    out = df.copy()
    group_cols = list(group_cols) if group_cols else []

    if kpi_cols is None:
        kpi_cols = [
            "activation_rate",
            "same_day_activation_rate",
            "d14_activation_rate",
            "d14_plus_activation_rate"
        ]

    out[week_col] = pd.to_datetime(out[week_col])
    iso = out[week_col].dt.isocalendar()
    out["iso_year"] = iso.year.astype(int)
    out["iso_week"] = iso.week.astype(int)

    out = out.sort_values(group_cols + [week_col])

    # ---- WoW ----
    for c in kpi_cols:
        if group_cols:
            out[f"{c}_wow_abs"] = out.groupby(group_cols)[c].diff(1)
            prev_val = out.groupby(group_cols)[c].shift(1)
        else:
            out[f"{c}_wow_abs"] = out[c].diff(1)
            prev_val = out[c].shift(1)

        #out[f"{c}_wow_pct"] = safe_div(out[f"{c}_wow_abs"], prev_val)

    # ---- YoY ----
    join_keys = group_cols + ["iso_year", "iso_week"]

    prev = out[join_keys + kpi_cols].copy()
    prev["iso_year"] = prev["iso_year"] + 1

    out = out.merge(
        prev,
        on=join_keys,
        how="left",
        suffixes=("", "_yoy_base")
    )

    for c in kpi_cols:
        out[f"{c}_yoy_abs"] = out[c] - out[f"{c}_yoy_base"]
        #out[f"{c}_yoy_pct"] = safe_div(out[f"{c}_yoy_abs"],out[f"{c}_yoy_base"])

    out = out.loc[:, ~out.columns.str.contains("base")]
    return out


FILTER_COUNTRIES = [
    "Estonia", "Latvia", "Lithuania", "Slovakia", "Czech Republic", "Malta",
    "Romania", "Poland", "Portugal", "Ukraine", "Cyprus",
    "Bulgaria", "Azerbaijan", "Ghana", "Kenya"
]
DATE_CUTOFF = "2024-01-01"


def build_outputs(raw, today=None):
    """Sections 8.1 (global), 8.2 (country) and 8.3 (city) plus the section 10 counterfactuals."""
    with np.errstate(divide="ignore", invalid="ignore"):
        return _build_outputs(raw, today)


def _build_outputs(raw, today):
    df = add_week(raw["core_fact"])
    df = coerce_numeric(df, SUM_COLS)

    filtered = df[(df["event_date"] >= DATE_CUTOFF) & (df["country"].isin(FILTER_COUNTRIES))].copy()

    # 8.1) weekly global
    weekly_global = aggregate_additive(filtered, dims=[], sum_cols=SUM_COLS, time_col="week")
    weekly_global = add_core_kpis(weekly_global.copy()).sort_values(["week"])
    weekly_global = add_wow_yoy(weekly_global, group_cols=None)

    # 8.2) weekly country
    weekly_country = aggregate_additive(filtered, dims=["country"], sum_cols=SUM_COLS, time_col="week")
    weekly_country = add_core_kpis(weekly_country.copy()).sort_values(["country","week"])
    weekly_country = add_wow_yoy(weekly_country, group_cols=("country",))

    # 8.3) weekly city
    city_dims = ["country","city","is_new_city","is_local","media_group"]
    weekly_city = aggregate_additive(filtered, dims=city_dims, sum_cols=SUM_COLS, time_col="week")
    weekly_city = add_core_kpis(weekly_city.copy()).sort_values(["country","city","is_new_city","is_local","media_group","week"])
    weekly_city = add_wow_yoy(weekly_city, group_cols=(["country","city","is_new_city","is_local","media_group"]))

    FILTER_CITIES = raw["active_cities"]["city"].unique()
    today = pd.Timestamp.today().normalize() if today is None else pd.Timestamp(today).normalize()

    weekly_city = weekly_city[
        (weekly_city["city"].isin(FILTER_CITIES)) &
        (
            (weekly_city["week"] >= today - pd.Timedelta(weeks=12)) |
            (
                (weekly_city["week"] >= today - pd.Timedelta(weeks=64)) &
                (weekly_city["week"] <  today - pd.Timedelta(weeks=52))
            )
        )
    ]

    return {
        "weekly_global": weekly_global,
        "weekly_country": weekly_country,
        "weekly_city": weekly_city.reset_index(drop=True),
        "country_mix_impact": raw["country_mix_impact"],
        "city_mix_impact": raw["city_mix_impact"],
        "tourist_mix_impact": raw["tourist_mix_impact"],
        "marketing_mix_impact": raw["marketing_mix_impact"],
    }
