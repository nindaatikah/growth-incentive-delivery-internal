"""Run the notebook queries against Databricks and return pandas DataFrames.

Deployed: a Databricks Service Principal from Portal Secrets
(DATABRICKS_CLIENT_ID, DATABRICKS_CLIENT_SECRET). Local: DATABRICKS_TOKEN.
"""

from __future__ import annotations

import decimal
import os
import time
from pathlib import Path

import pandas as pd
from databricks import sql

QUERY_DIR = Path(__file__).parent / "queries"

HOST = os.environ.get("DATABRICKS_HOST", "bolt-incentives.cloud.databricks.com")
HTTP_PATH = os.environ.get(
    "DATABRICKS_HTTP_PATH", "sql/protocolv1/o/2472566184436351/0505-112942-d3yviznw"
)

# Cloud fetch downloads large results straight from Databricks' S3 bucket, which
# networks outside Databricks can reset; inline results avoid that.
USE_CLOUD_FETCH = os.environ.get("DATABRICKS_USE_CLOUD_FETCH", "0") == "1"

FILTER_COUNTRIES = [
    "Estonia", "Latvia", "Lithuania", "Slovakia", "Czech Republic", "Malta",
    "Romania", "Poland", "Portugal", "Ukraine", "Cyprus",
    "Bulgaria", "Azerbaijan", "Ghana", "Kenya",
]
DATE_CUTOFF = "2024-01-01"

MIX_QUERIES = {
    "country_mix_impact": "country_mix_impact.sql",
    "city_mix_impact": "city_mix_impact.sql",
    "tourist_mix_impact": "tourist_mix_impact.sql",
    "marketing_mix_impact": "marketing_mix_impact.sql",
}


def has_credentials() -> bool:
    return bool(
        (os.environ.get("DATABRICKS_CLIENT_ID") and os.environ.get("DATABRICKS_CLIENT_SECRET"))
        or os.environ.get("DATABRICKS_TOKEN")
    )


def _connect():
    host = HOST.removeprefix("https://")
    client_id = os.environ.get("DATABRICKS_CLIENT_ID")
    client_secret = os.environ.get("DATABRICKS_CLIENT_SECRET")
    if client_id and client_secret:
        from databricks.sdk.core import Config, oauth_service_principal

        def credentials_provider():
            return oauth_service_principal(
                Config(host=f"https://{host}", client_id=client_id, client_secret=client_secret)
            )

        return sql.connect(
            server_hostname=host, http_path=HTTP_PATH, credentials_provider=credentials_provider,
            use_cloud_fetch=USE_CLOUD_FETCH,
        )
    token = os.environ.get("DATABRICKS_TOKEN")
    if not token:
        raise RuntimeError(
            "No Databricks credentials: set DATABRICKS_CLIENT_ID and DATABRICKS_CLIENT_SECRET "
            "(Service Principal) or DATABRICKS_TOKEN (local only)."
        )
    return sql.connect(server_hostname=host, http_path=HTTP_PATH, access_token=token,
                       use_cloud_fetch=USE_CLOUD_FETCH)


def _normalise_types(df: pd.DataFrame) -> pd.DataFrame:
    """Match what spark.sql(...).toPandas() gave the notebook: floats, naive timestamps."""
    for col in df.columns:
        if isinstance(df[col].dtype, pd.DatetimeTZDtype):
            df[col] = df[col].dt.tz_localize(None).astype("datetime64[ns]")
        elif df[col].dtype == object:
            sample = df[col].dropna()
            if not sample.empty and isinstance(sample.iloc[0], decimal.Decimal):
                df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


def run_query(query: str) -> pd.DataFrame:
    conn = _connect()
    try:
        with conn.cursor() as cur:
            cur.execute(query)
            return _normalise_types(cur.fetchall_arrow().to_pandas())
    finally:
        conn.close()


def read_query(name: str) -> str:
    return (QUERY_DIR / name).read_text()


def core_fact_query() -> str:
    # The notebook applies the date and country filter in pandas right after the pull;
    # applying the same filter here gives identical outputs with a far smaller transfer.
    countries = ", ".join("'" + c.replace("'", "''") + "'" for c in FILTER_COUNTRIES)
    return (
        f"SELECT * FROM (\n{read_query('core_fact.sql')}\n) core\n"
        f"WHERE core.event_date >= DATE '{DATE_CUTOFF}'\n"
        f"  AND core.country IN ({countries})"
    )


def extract_all(log=print) -> dict[str, pd.DataFrame]:
    raw: dict[str, pd.DataFrame] = {}
    jobs = {"core_fact": core_fact_query(), "active_cities": read_query("active_cities.sql")}
    jobs.update({name: read_query(path) for name, path in MIX_QUERIES.items()})
    for name, query in jobs.items():
        start = time.time()
        raw[name] = run_query(query)
        log(f"{name}: {len(raw[name]):,} rows in {time.time() - start:.0f}s")
    return raw
