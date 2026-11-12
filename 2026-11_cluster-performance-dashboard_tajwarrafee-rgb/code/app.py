"""Cluster performance dashboard.

The page is the Lisbon HTML dashboard, with a city dropdown. Each city is a
folder under data/ with meta.json, cluster_metrics.csv, and
cluster_objective_spend.csv.
"""

from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import streamlit as st

from payload import build_payload

DATA_DIR = Path(__file__).parent / "data"
PROPOSALS_PATH = DATA_DIR / "proposals.json"
TEMPLATE_PATH = Path(__file__).parent / "dashboard_template.html"
DATA_SCRIPT = '<script src="dashboard_data.js"></script>'
PAGE_CSS = """
<style>
  .stApp { background: #f3f1eb; }
  header[data-testid="stHeader"] { display: none; }
  .block-container { padding: 0; max-width: 100%; }
  iframe { border: 0; }
</style>
"""


def discover_cities() -> list[tuple[str, str]]:
    found = []
    if not DATA_DIR.exists():
        return found
    for folder in sorted(path for path in DATA_DIR.iterdir() if path.is_dir()):
        if all((folder / name).exists() for name in ("meta.json", "cluster_metrics.csv", "cluster_objective_spend.csv")):
            meta = json.loads((folder / "meta.json").read_text())
            found.append((folder.name, meta["cities"][0]))
    return found


def load_city(slug: str) -> tuple[dict, pd.DataFrame, pd.DataFrame]:
    folder = DATA_DIR / slug
    meta = json.loads((folder / "meta.json").read_text())
    metrics = pd.read_csv(folder / "cluster_metrics.csv")
    objectives = pd.read_csv(folder / "cluster_objective_spend.csv")
    for frame in (metrics, objectives):
        frame["period_start"] = frame["period_start"].astype(str).str.slice(0, 10)
    return meta, metrics, objectives


def _zones_by_city(meta: dict) -> dict:
    city = meta["cities"][0]
    raw = meta.get("cluster_zones") or {}
    if raw and all(isinstance(value, list) for value in raw.values()):
        return {city: raw}
    return {city: raw.get(city, {})}


def load_all() -> tuple[dict, pd.DataFrame, pd.DataFrame]:
    cities = discover_cities()
    cities.sort(key=lambda item: (item[1] != "Lisbon", item[1]))
    metas = []
    metrics = []
    objectives = []
    for slug, _display in cities:
        meta, metric, objective = load_city(slug)
        metas.append(meta)
        metrics.append(metric)
        objectives.append(objective)
    combined = dict(metas[0])
    combined["cities"] = [meta["cities"][0] for meta in metas]
    zones = {}
    for meta in metas:
        zones.update(_zones_by_city(meta))
    combined["cluster_zones"] = zones
    combined["zone_count"] = sum(len(value) for value in zones.values())
    if PROPOSALS_PATH.exists():
        proposals = json.loads(PROPOSALS_PATH.read_text())
        combined["proposals"] = proposals["cities"]
        combined["proposal_source"] = proposals["source"]
    return combined, pd.concat(metrics, ignore_index=True), pd.concat(objectives, ignore_index=True)


def dashboard_html(meta: dict, metrics: pd.DataFrame, objectives: pd.DataFrame) -> str:
    payload = build_payload(metrics, meta, objectives)
    payload["cities"] = meta["cities"]
    data = json.dumps(payload, separators=(",", ":")).replace("<", "\\u003c")
    template = TEMPLATE_PATH.read_text()
    if DATA_SCRIPT not in template:
        raise RuntimeError("Dashboard template is missing the data script tag.")
    return template.replace(DATA_SCRIPT, f"<script>window.DASHBOARD_DATA = {data};</script>", 1)


def render() -> None:
    st.set_page_config(page_title="Cluster performance", layout="wide")
    st.markdown(PAGE_CSS, unsafe_allow_html=True)
    if not discover_cities():
        st.error("No city data found. Add a folder under data/ with the cluster files.")
        st.stop()
    meta, metrics, objectives = load_all()
    st.iframe(
        dashboard_html(meta, metrics, objectives),
        width="stretch",
        height=1880,
    )


if __name__ == "__main__":
    render()
