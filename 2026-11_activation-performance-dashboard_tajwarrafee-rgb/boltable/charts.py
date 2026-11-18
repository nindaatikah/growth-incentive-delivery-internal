"""Chart helpers. Uses the Bolt card from bolt-viz when it is installed (Boltable builds),
plain Plotly otherwise (local runs without access to the Bolt package index)."""

from __future__ import annotations

import numpy as np
import pandas as pd
import plotly.graph_objects as go
import streamlit as st
import streamlit.components.v1 as components

try:
    from bolt_viz import bolt_fragment, finalize, use_bolt_template

    use_bolt_template()
    HAS_BOLT_VIZ = True
except ImportError:
    HAS_BOLT_VIZ = False

PALETTE = ["#2A9C64", "#0C2C1C", "#F5A623", "#5B8DEF", "#D0021B", "#9B59B6", "#7F8C8D", "#16A085"]


def _plain(values):
    if values is None or isinstance(values, (str, int, float)):
        return values
    s = pd.Series(np.asarray(values))
    if pd.api.types.is_datetime64_any_dtype(s):
        return s.dt.strftime("%Y-%m-%d").tolist()
    return [None if pd.isna(v) else v for v in s.tolist()]


def _with_plain_data(fig: go.Figure) -> go.Figure:
    # bolt-viz tests trace data for truthiness, which fails on numpy arrays. Plotly keeps an attribute an array once
    # it is one, so the traces are rebuilt from plain lists rather than updated.
    out = go.Figure(layout=fig.layout)
    for trace in fig.data:
        spec = trace.to_plotly_json()
        spec.update(x=_plain(trace.x), y=_plain(trace.y))
        out.add_trace(type(trace)(spec))
    return out


def show(fig: go.Figure, title: str, subtitle: str, summary: str = "") -> None:
    fig = _with_plain_data(fig)
    fig.update_layout(height=fig.layout.height or 380, hovermode="x unified")
    if HAS_BOLT_VIZ:
        finalize(fig, title=title, subtitle=subtitle)
        html = bolt_fragment(fig, summary or subtitle, embed_spec=False, backdrop=False)
        components.html(html, height=fig.layout.height + 74, scrolling=False)
    else:
        fig.update_layout(
            title=dict(text=f"<b>{title}</b><br><sup>{subtitle}</sup>"),
            colorway=PALETTE,
            template="plotly_white",
            margin=dict(t=70, l=10, r=10, b=10),
            legend=dict(orientation="h", y=-0.15),
        )
        st.plotly_chart(fig, width="stretch")
        if summary:
            st.caption(summary)


def lines(df: pd.DataFrame, x: str, cols: dict[str, str], pct: bool = False, height: int = 380) -> go.Figure:
    fig = go.Figure()
    for col, label in cols.items():
        if col in df:
            fig.add_trace(go.Scatter(x=df[x], y=df[col], name=label, mode="lines+markers"))
    if pct:
        fig.update_yaxes(tickformat=".1%")
    fig.update_layout(height=height)
    return fig


def lines_by(df: pd.DataFrame, x: str, y: str, by: str, pct: bool = False, height: int = 380) -> go.Figure:
    fig = go.Figure()
    for key, g in df.groupby(by, sort=True):
        g = g.sort_values(x)
        fig.add_trace(go.Scatter(x=g[x], y=g[y], name=str(key), mode="lines+markers"))
    if pct:
        fig.update_yaxes(tickformat=".1%")
    fig.update_layout(height=height)
    return fig


def bars_by(df: pd.DataFrame, x: str, y: str, by: str, pct: bool = False, stacked: bool = True,
            height: int = 380) -> go.Figure:
    fig = go.Figure()
    for key, g in df.groupby(by, sort=True):
        g = g.sort_values(x)
        fig.add_trace(go.Bar(x=g[x], y=g[y], name=str(key)))
    fig.update_layout(barmode="relative" if stacked else "group", height=height)
    if pct:
        fig.update_yaxes(tickformat=".2%")
    return fig
