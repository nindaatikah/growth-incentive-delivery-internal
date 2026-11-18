import os

import numpy as np
import pandas as pd
import plotly.graph_objects as go
import streamlit as st

st.set_page_config(page_title="Activation Performance", page_icon="⚡", layout="wide")

import charts  # noqa: E402  (bolt-viz template must be set after set_page_config)
import extract  # noqa: E402
import pipeline  # noqa: E402
import refresh  # noqa: E402
import storage  # noqa: E402

TABLES = [
    "weekly_global", "weekly_country", "weekly_city",
    "country_mix_impact", "city_mix_impact", "tourist_mix_impact", "marketing_mix_impact",
]
RATES = {
    "activation_rate": "Total activation rate",
    "same_day_activation_rate": "Same-day activation rate",
    "d14_activation_rate": "Delayed activation rate (D1–D14)",
    "d14_plus_activation_rate": "Late activation rate (D14+)",
}
CITY_METRICS = {
    "Signups": ("signup_users", "count"),
    "Activated users": ("activated_users", "count"),
    "Total activation rate": ("activation_rate", "rate"),
    "Same-day activation rate": ("same_day_activation_rate", "rate"),
    "Delayed activation rate (D1–D14)": ("d14_activation_rate", "rate"),
    "Late activation rate (D14+)": ("d14_plus_activation_rate", "rate"),
    "2-in-7d": ("power_user_rate_7d", "rate"),
    "Avg orders (30d)": ("avg_orders_30d", "num"),
    "First-order discount %": ("first_order_discount_pct", "rate"),
}


# ---------------------------------------------------------------- setup
@st.cache_resource
def _start_background_jobs():
    print(
        f"App started ({os.environ.get('BOLTABLE_GIT_SHA', 'unknown sha')}, "
        f"built {os.environ.get('BOLTABLE_BUILT_AT', 'unknown time')})",
        flush=True,
    )
    return refresh.start_scheduler()


@st.cache_data(show_spinner="Loading data...")
def _load(refreshed_at: str) -> dict:
    out = storage.load_outputs(TABLES)
    for df in out.values():
        if "week" in df:
            df["week"] = pd.to_datetime(df["week"])
    return out


def _can_refresh() -> bool:
    if not os.environ.get("BOLTABLE_GIT_SHA"):
        return True  # local run
    admins = {e.strip().lower() for e in os.environ.get("REFRESH_ADMINS", "").split(",") if e.strip()}
    email = (st.context.headers.get("X-User-Email") or "").lower()
    return bool(email) and email in admins


# ---------------------------------------------------------------- formatting
def is_na(v) -> bool:
    return v is None or (isinstance(v, float) and np.isnan(v)) or pd.isna(v)


def fmt(v, kind: str) -> str:
    if is_na(v):
        return "–"
    if kind == "count":
        return f"{v:,.0f}"
    if kind == "rate":
        return f"{v * 100:.1f}%"
    return f"{v:,.2f}"


def fmt_change(v, kind: str) -> str:
    if is_na(v) or (isinstance(v, float) and np.isinf(v)):
        return "–"
    if kind == "rate":
        return f"{v * 100:+.2f} pp"
    return f"{v * 100:+.1f}%"


def change(cur, base, kind: str):
    if is_na(cur) or is_na(base):
        return np.nan
    if kind == "rate":
        return cur - base
    return cur / base - 1 if base else np.nan


def pp(v) -> str:
    return "–" if is_na(v) else f"{v * 100:+.2f} pp"


def week_label(w) -> str:
    w = pd.Timestamp(w)
    return f"{w:%d %b %Y} (W{w.isocalendar().week:02d})"


def short_week(w) -> str:
    return f"{pd.Timestamp(w):%d %b}"


def monday_of(ts: pd.Timestamp) -> pd.Timestamp:
    ts = pd.Timestamp(ts).normalize()
    return ts - pd.Timedelta(days=ts.weekday())


def complete_weeks(weeks: pd.Series, as_of: pd.Timestamp) -> list:
    cutoff = monday_of(as_of)
    return sorted([w for w in pd.to_datetime(weeks).unique() if w < cutoff], reverse=True)


def same_week_last_year(w: pd.Timestamp) -> pd.Timestamp:
    iso = pd.Timestamp(w).isocalendar()
    return pd.Timestamp.fromisocalendar(iso.year - 1, min(iso.week, 52), 1)


def immature(w: pd.Timestamp, days: int, as_of: pd.Timestamp) -> bool:
    return days > 0 and pd.Timestamp(w) + pd.Timedelta(days=7 + days) > as_of


def table_style(df: pd.DataFrame):
    st.dataframe(df, hide_index=True, width="stretch")


# ---------------------------------------------------------------- building blocks
def week_table(df: pd.DataFrame, sel: pd.Timestamp, rows: list, as_of: pd.Timestamp, n: int = 8) -> pd.DataFrame:
    """Sheet-style table: one row per metric, the n weeks up to `sel`, then WoW and YoY.

    rows: (label, getter(row) -> value, kind, yoy_column or None, maturity_days)
    """
    idx = df.set_index("week")
    weeks = [sel - pd.Timedelta(weeks=k) for k in range(n - 1, -1, -1)]
    ly = same_week_last_year(sel)
    get_row = lambda w: idx.loc[w] if w in idx.index else None  # noqa: E731
    out = []
    for label, getter, kind, yoy_col, mature_days in rows:
        values = []
        for w in weeks:
            r = get_row(w)
            v = getter(r) if r is not None else np.nan
            cell = fmt(v, kind)
            if cell != "–" and immature(w, mature_days, as_of):
                cell += " †"
            values.append((v, cell))
        cur, prev = values[-1][0], values[-2][0]
        r_sel, r_ly = get_row(sel), get_row(ly)
        if yoy_col and r_sel is not None:
            yoy = r_sel.get(yoy_col, np.nan)
        else:
            yoy = change(cur, getter(r_ly) if r_ly is not None else np.nan, kind)
        out.append([label] + [c for _, c in values] + [fmt_change(change(cur, prev, kind), kind),
                                                        fmt_change(yoy, kind)])
    return pd.DataFrame(out, columns=["Metric"] + [short_week(w) for w in weeks] + ["WoW", "YoY"])


def activation_rows():
    return [
        ("Signups", lambda r: r["signup_users"], "count", None, 0),
        ("New users (activated)", lambda r: r["activated_users"], "count", None, 0),
        ("Same-day activations", lambda r: r["activated_users_d0"], "count", None, 0),
        ("Delayed activations (D1–D14)", lambda r: r["activated_users_d14"], "count", None, 0),
        ("Late activations (D14+)", lambda r: r["activated_users_d14_plus"], "count", None, 0),
    ] + [(label, (lambda k: lambda r: r[k])(k), "rate", f"{k}_yoy_abs", 0) for k, label in RATES.items()]


def quality_rows():
    return [
        ("2-in-7d (power-user rate)", lambda r: r["power_user_rate_7d"], "rate", None, 7),
        ("Avg orders (30d)", lambda r: r["avg_orders_30d"], "num", None, 30),
        ("2-in-30d", lambda r: r["power_users_30d"] / r["activated_users"] if r["activated_users"] else np.nan,
         "rate", None, 30),
        ("First-order discount % of GMV", lambda r: r["first_order_discount_pct"], "rate", None, 0),
        ("30-day discount % of GMV", lambda r: r["discount_30d_pct"], "rate", None, 30),
    ]


def aggregate_city(view: pd.DataFrame, dims: list) -> pd.DataFrame:
    with np.errstate(divide="ignore", invalid="ignore"):
        agg = pipeline.aggregate_additive(view, dims=dims, sum_cols=pipeline.SUM_COLS, time_col="week")
        agg = pipeline.add_core_kpis(agg)
        agg = pipeline.add_wow_yoy(agg, group_cols=dims)
    # weekly_city keeps the last 12 weeks plus the same weeks last year, so the row
    # before a week is not always the previous week.
    gap = agg.groupby(dims)["week"].diff() != pd.Timedelta(weeks=1)
    for k in RATES:
        agg.loc[gap, f"{k}_wow_abs"] = np.nan
    return agg


def mix_frame(mx: pd.DataFrame) -> pd.DataFrame:
    mx = mx.copy()
    mx["d_share"] = mx["signup_share"] - mx["signup_share_yoy"]
    mx["d_rate"] = mx["same_day_activation_rate"] - mx["same_day_activation_rate_yoy"]
    mx["share_impact"] = mx["d_share"] * mx["same_day_activation_rate_yoy"]
    mx["rate_impact"] = mx["signup_share"] * mx["d_rate"]
    return mx


def pct_cols(df: pd.DataFrame) -> dict:
    cfg = {}
    for c in df.columns:
        if c.endswith("%"):
            cfg[c] = st.column_config.NumberColumn(format="%.1f%%")
        elif c.endswith("pp"):
            cfg[c] = st.column_config.NumberColumn(format="%+.2f")
        elif c in ("Signups", "Activated", "Signups LY", "New users"):
            cfg[c] = st.column_config.NumberColumn(format="%d")
    return cfg


# ---------------------------------------------------------------- app
_start_background_jobs()
meta = storage.load_meta()

with st.sidebar:
    st.header("Activation Performance")
    st.caption("Bolt Food signups and first-order activations, 15 markets.")
    live = extract.has_credentials()
    if meta:
        refreshed = pd.Timestamp(meta["refreshed_at"])
        st.caption(f"Data refreshed {refreshed:%d %b %Y %H:%M} UTC. " +
                   ("Refreshes Mondays 10:00 Tallinn time." if live else
                    "Snapshot: the weekly refresh starts once the Databricks Service Principal is set up."))
    if refresh.STATUS["running"]:
        st.info("A refresh is running. It takes several minutes; reload the page afterwards.")
    if refresh.STATUS["last_error"]:
        st.error(f"Last refresh failed: {refresh.STATUS['last_error']}")
    if live and _can_refresh() and st.button("Refresh now", disabled=refresh.STATUS["running"]):
        refresh.refresh_in_background("manual")
        st.rerun()

if not meta:
    st.title("Activation Performance")
    st.info("The first data refresh is running. It pulls from Databricks and takes several minutes. "
            "Reload this page in a few minutes.")
    if refresh.STATUS["last_log"]:
        st.code("\n".join(refresh.STATUS["last_log"]))
    st.stop()

data = _load(meta["refreshed_at"])
as_of = pd.Timestamp(meta["refreshed_at"]).tz_convert(None)
wg = data["weekly_global"]
weeks_all = complete_weeks(wg["week"], as_of)

with st.sidebar:
    sel = st.selectbox("Latest week", weeks_all, format_func=week_label, key="sel_week",
                       help="Weeks start on Monday. Only complete weeks are listed.")
    st.caption("† = week not mature yet: users who activated that week have not had the full 7 or 30 days, "
               "so the value will still rise.")

tab_beh, tab_env, tab_country, tab_city, tab_defs = st.tabs(
    ["Behaviour Summary", "Environment Summary", "Country", "City explorer", "Definitions"])

# ================================================================ Behaviour Summary
with tab_beh:
    st.subheader("Activation quality")
    st.caption("Are new users good users? 2-in-7d and 30-day metrics need their window to close: † marks weeks "
               "that are still open.")
    table_style(week_table(wg, sel, quality_rows(), as_of))

    recent = lambda d: d[(d["week"] <= sel) & (d["week"] > sel - pd.Timedelta(weeks=26))]  # noqa: E731
    q = recent(wg).copy()
    q["power_user_rate_30d"] = q["power_users_30d"] / q["activated_users"]
    left, right = st.columns(2)
    with left:
        charts.show(charts.lines(q, "week", {"power_user_rate_7d": "2-in-7d", "power_user_rate_30d": "2-in-30d"},
                                 pct=True),
                    "Repeat ordering of new users", "Last 26 weeks, all 15 markets")
    with right:
        charts.show(charts.lines(q, "week", {"avg_orders_30d": "Avg orders (30d)"}),
                    "Orders per new user in the first 30 days", "Last 26 weeks, all 15 markets")

# ================================================================ Environment Summary
with tab_env:
    st.subheader("1. Activation performance")
    st.caption("Observed facts, no adjustment. WoW and YoY: relative change for counts, percentage points for rates. "
               "YoY compares with the same ISO week last year.")
    table_style(week_table(wg, sel, activation_rows(), as_of))

    st.subheader("Country summary")
    st.caption(f"Week of {week_label(sel)}. 2-in-7d uses the week before and the 30-day metrics use 4 weeks before, "
               "so every value is mature.")
    wc = data["weekly_country"]

    def country_snapshot(week: pd.Timestamp) -> pd.DataFrame:
        cur = wc[wc["week"] == week].set_index("country")
        w7 = wc[wc["week"] == week - pd.Timedelta(weeks=1)].set_index("country")
        w28 = wc[wc["week"] == week - pd.Timedelta(weeks=4)].set_index("country")
        out = pd.DataFrame({
            "Signups": cur["signup_users"],
            "New users": cur["activated_users"],
            **{label: cur[k] for k, label in RATES.items()},
            "2-in-7d": w7["power_users_7d"] / w7["activated_users"],
            "2-in-30d": w28["power_users_30d"] / w28["activated_users"],
            "Avg orders (30d)": w28["avg_orders_30d"],
        })
        return out

    now, before = country_snapshot(sel), country_snapshot(sel - pd.Timedelta(weeks=1))
    cs = pd.DataFrame({"Country": now.index})
    cs = cs.set_index("Country")
    cs["Signups"] = now["Signups"]
    cs["Signups WoW %"] = (now["Signups"] / before["Signups"] - 1) * 100
    cs["New users"] = now["New users"]
    for label in RATES.values():
        short = label.replace(" activation rate", "").replace("Total", "Activation")
        cs[f"{short} %"] = now[label] * 100
        cs[f"{short} WoW pp"] = (now[label] - before[label]) * 100
    cs["2-in-7d %"] = now["2-in-7d"] * 100
    cs["2-in-7d WoW pp"] = (now["2-in-7d"] - before["2-in-7d"]) * 100
    cs["2-in-30d %"] = now["2-in-30d"] * 100
    cs["Avg orders (30d)"] = now["Avg orders (30d)"]
    cs = cs.reset_index().sort_values("Signups", ascending=False)
    st.dataframe(cs, hide_index=True, width="stretch",
                 column_config={**pct_cols(cs), "Avg orders (30d)": st.column_config.NumberColumn(format="%.2f")})

    st.subheader("2. Counterfactual conversions YoY")
    st.caption("If behaviour had stayed as last year but the mix changed, how much of the YoY change in same-day "
               "conversion is mix? Mix impact = Σ (signup share − share last year) × rate last year. Diagnostic "
               "context only.")
    mixes = {
        "Country mix impact": ("country_mix_impact", "country"),
        "New vs old city mix impact": ("city_mix_impact", "is_new_city"),
        "Local vs tourist mix impact": ("tourist_mix_impact", "is_local"),
        "Marketing mix impact": ("marketing_mix_impact", "media_group"),
    }
    weeks8 = [sel - pd.Timedelta(weeks=k) for k in range(7, -1, -1)]
    cf = [["YoY same-day conversion change"] +
          [pp(wg.set_index("week")["same_day_activation_rate_yoy_abs"].get(w, np.nan)) for w in weeks8]]
    for label, (name, key) in mixes.items():
        m = mix_frame(data[name]).groupby("week")["share_impact"].sum(min_count=1)
        cf.append([label] + [pp(m.get(w, np.nan)) for w in weeks8])
    table_style(pd.DataFrame(cf, columns=["Metric"] + [short_week(w) for w in weeks8]))

    st.subheader("Mix and behaviour impact by segment")
    st.caption("Use only after a real behaviour effect is found: these say what broke, not whether it broke. "
               "Signup share impact = Δ share × rate last year; activation rate impact = share × Δ rate.")
    labels = {"is_new_city": {"True": "New city", "False": "Existing city", "1": "New city", "0": "Existing city"},
              "is_local": {"True": "Local", "False": "Tourist", "1": "Local", "0": "Tourist"}}
    for label, (name, key) in [("Country", mixes["Country mix impact"]),
                               ("City type", mixes["New vs old city mix impact"]),
                               ("User type", mixes["Local vs tourist mix impact"]),
                               ("Marketing channel", mixes["Marketing mix impact"])]:
        m = mix_frame(data[name])
        m = m[m["week"] == sel]
        seg = m[key].astype(str).map(lambda v: labels.get(key, {}).get(v, v))
        t = pd.DataFrame({
            label: seg,
            "Signup share %": m["signup_share"] * 100,
            "Share last year %": m["signup_share_yoy"] * 100,
            "Share YoY Δ pp": m["d_share"] * 100,
            "Same-day act. rate %": m["same_day_activation_rate"] * 100,
            "Rate last year %": m["same_day_activation_rate_yoy"] * 100,
            "Rate Δ pp": m["d_rate"] * 100,
            "Signup share impact pp": m["share_impact"] * 100,
            "Act. rate impact pp": m["rate_impact"] * 100,
        }).sort_values("Signup share %", ascending=False)
        with st.expander(f"{label}: mix and behaviour", expanded=(label == "Country")):
            st.dataframe(t, hide_index=True, width="stretch", column_config=pct_cols(t))

    left, right = st.columns(2)
    with left:
        charts.show(charts.lines(recent(wg), "week", RATES, pct=True), "Activation rates",
                    "Last 26 weeks, all 15 markets")
    with right:
        r = recent(wg)
        fig = go.Figure()
        fig.add_trace(go.Bar(x=r["week"], y=r["signup_users"], name="Signups"))
        fig.add_trace(go.Bar(x=r["week"], y=r["activated_users"], name="New users"))
        fig.update_layout(barmode="group", height=380)
        charts.show(fig, "Signups and new users", "Last 26 weeks, all 15 markets")

# ================================================================ Country
with tab_country:
    wc = data["weekly_country"]
    countries = sorted(wc["country"].unique())
    country = st.selectbox("Country", countries, key="country")
    wcc = wc[wc["country"] == country]

    st.subheader("1. Activation performance")
    table_style(week_table(wcc, sel, activation_rows(), as_of))
    st.subheader("2. Activation quality")
    table_style(week_table(wcc, sel, quality_rows(), as_of))

    wci = data["weekly_city"]
    wci_c = wci[wci["country"] == country]
    if sel < wci["week"].max() - pd.Timedelta(weeks=12):
        st.info("Segment and city tables cover the last 12 weeks only. Pick a more recent week in the sidebar.")
    else:
        st.subheader("3. Segment performance")
        st.caption(f"Week of {week_label(sel)}.")
        seg_labels = {"media_group": "Channel", "is_local": "User type", "is_new_city": "City type"}
        value_labels = {"is_local": {1: "Local", 0: "Tourist"}, "is_new_city": {1: "New city", 0: "Existing city"}}
        cols = st.columns(3)
        for col, (dim, label) in zip(cols, seg_labels.items()):
            agg = aggregate_city(wci_c, [dim])
            s = agg[agg["week"] == sel].copy()
            s[dim] = s[dim].map(lambda v: value_labels.get(dim, {}).get(v, v))
            t = pd.DataFrame({
                label: s[dim],
                "Signups": s["signup_users"],
                "Share %": s["signup_users"] / s["signup_users"].sum() * 100,
                "Activation %": s["activation_rate"] * 100,
                "Same-day %": s["same_day_activation_rate"] * 100,
                "Same-day WoW pp": s["same_day_activation_rate_wow_abs"] * 100,
                "Same-day YoY pp": s["same_day_activation_rate_yoy_abs"] * 100,
            }).sort_values("Signups", ascending=False)
            with col:
                st.dataframe(t, hide_index=True, width="stretch", column_config=pct_cols(t))

        st.subheader("City summary (top 15 by signups)")
        st.caption("2-in-7d is from the week before and avg orders (30d) from 4 weeks before, so both are mature.")
        cities = aggregate_city(wci_c, ["city"])
        cur = cities[cities["week"] == sel].set_index("city")
        w7 = cities[cities["week"] == sel - pd.Timedelta(weeks=1)].set_index("city")
        w28 = cities[cities["week"] == sel - pd.Timedelta(weeks=4)].set_index("city")
        top = cur.sort_values("signup_users", ascending=False).head(15)
        ct = pd.DataFrame({
            "City": top.index,
            "Signups": top["signup_users"].values,
            "New users": top["activated_users"].values,
            "Activation %": top["activation_rate"].values * 100,
            "Activation WoW pp": top["activation_rate_wow_abs"].values * 100,
            "Same-day %": top["same_day_activation_rate"].values * 100,
            "Same-day WoW pp": top["same_day_activation_rate_wow_abs"].values * 100,
            "Same-day YoY pp": top["same_day_activation_rate_yoy_abs"].values * 100,
            "2-in-7d %": w7["power_user_rate_7d"].reindex(top.index).values * 100,
            "Avg orders (30d)": w28["avg_orders_30d"].reindex(top.index).values,
            "1st-order discount %": top["first_order_discount_pct"].values * 100,
        })
        st.dataframe(ct, hide_index=True, width="stretch",
                     column_config={**pct_cols(ct), "Avg orders (30d)": st.column_config.NumberColumn(format="%.2f")})

        st.subheader("City trend")
        metric = st.selectbox("Metric", list(CITY_METRICS), index=3, key="city_metric")
        mcol, kind = CITY_METRICS[metric]
        weeks8 = [sel - pd.Timedelta(weeks=k) for k in range(7, -1, -1)]
        ly = same_week_last_year(sel)
        piv = cities.pivot_table(index="city", columns="week", values=mcol, aggfunc="first")
        trend = pd.DataFrame(index=top.index)
        for w in weeks8:
            trend[short_week(w)] = [fmt(piv.at[c, w], kind) if w in piv.columns and c in piv.index else "–"
                                    for c in top.index]
        trend["Last year"] = [fmt(piv.at[c, ly], kind) if ly in piv.columns and c in piv.index else "–"
                              for c in top.index]
        trend["YoY"] = [fmt_change(change(piv.at[c, sel] if sel in piv.columns else np.nan,
                                          piv.at[c, ly] if ly in piv.columns else np.nan, kind), kind)
                        for c in top.index]
        st.dataframe(trend.reset_index().rename(columns={"index": "City", "city": "City"}), hide_index=True,
                     width="stretch")

    charts.show(charts.lines(recent(wcc), "week", RATES, pct=True), f"Activation rates, {country}", "Last 26 weeks")

# ================================================================ City explorer
with tab_city:
    wci = data["weekly_city"]
    st.caption("Last 12 weeks, plus the same weeks last year for YoY. Cities with a food delivery launch date only.")
    f = st.columns(5)
    sel_country = f[0].multiselect("Country", sorted(wci["country"].unique()), key="ci_country")
    pool = wci[wci["country"].isin(sel_country)] if sel_country else wci
    sel_city = f[1].multiselect("City", sorted(pool["city"].unique()), key="ci_city")
    sel_new = f[2].multiselect("City type", [0, 1], format_func=lambda v: "New city" if v else "Existing city",
                               key="ci_new")
    sel_local = f[3].multiselect("User type", [1, 0], format_func=lambda v: "Local" if v else "Tourist",
                                 key="ci_local")
    sel_media = f[4].multiselect("Channel", sorted(pool["media_group"].dropna().unique()), key="ci_media")
    view = pool
    for col, vals in [("city", sel_city), ("is_new_city", sel_new), ("is_local", sel_local), ("media_group", sel_media)]:
        if vals:
            view = view[view[col].isin(vals)]

    breakdowns = {"City": ["country", "city"], "Country": ["country"],
                  "City × segment (as exported)": ["country", "city", "is_new_city", "is_local", "media_group"]}
    breakdown = st.radio("Rows", list(breakdowns), horizontal=True, key="ci_breakdown")
    dims = breakdowns[breakdown]
    if view.empty:
        st.info("No rows for this selection.")
    else:
        agg = aggregate_city(view, dims)
        recent_weeks = [w for w in complete_weeks(agg["week"], as_of) if w >= as_of - pd.Timedelta(weeks=13)]
        wk = st.selectbox("Week", recent_weeks, format_func=week_label, key="ci_week")
        s = agg[agg["week"] == wk]
        t = s[dims].copy()
        t["Signups"] = s["signup_users"]
        t["New users"] = s["activated_users"]
        for k, label in [("activation_rate", "Activation"), ("same_day_activation_rate", "Same-day")]:
            t[f"{label} %"] = s[k] * 100
            t[f"{label} WoW pp"] = s[f"{k}_wow_abs"] * 100
            t[f"{label} YoY pp"] = s[f"{k}_yoy_abs"] * 100
        t["2-in-7d %"] = s["power_user_rate_7d"] * 100
        t["Avg orders (30d)"] = s["avg_orders_30d"]
        t["1st-order discount %"] = s["first_order_discount_pct"] * 100
        t = t.sort_values("Signups", ascending=False)
        st.dataframe(t, hide_index=True, width="stretch",
                     column_config={**pct_cols(t), "Avg orders (30d)": st.column_config.NumberColumn(format="%.2f")})
        if breakdown != "City × segment (as exported)":
            keys = t.head(8)[dims].astype(str).agg(" / ".join, axis=1).tolist()
            agg["label"] = agg[dims].astype(str).agg(" / ".join, axis=1)
            tr = agg[agg["label"].isin(keys) & (agg["week"] >= as_of - pd.Timedelta(weeks=13))
                     & (agg["week"] < monday_of(as_of))]
            charts.show(charts.lines_by(tr, "week", "same_day_activation_rate", "label", pct=True),
                        f"Same-day activation rate, top {len(keys)} by signups", "Last 12 weeks")
        st.caption("† Values for the latest weeks of 7-day and 30-day metrics are not mature yet.")

# ================================================================ Definitions
with tab_defs:
    with open(os.path.join(os.path.dirname(__file__), "DEFINITIONS.md")) as f:
        st.markdown(f.read())
    st.caption(f"Latest refresh: {meta['refreshed_at']} ({meta.get('triggered_by')}, {meta.get('duration_s')}s). "
               f"Build {os.environ.get('BOLTABLE_GIT_SHA', 'local')[:12]}.")
