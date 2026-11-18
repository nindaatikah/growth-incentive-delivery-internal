# Activation Performance (Bolt Food)

Streamlit dashboard on Boltable that replaces the "Activation Performance" Google Sheet. It runs the logic of
`activation_performance_core_clean.ipynb` against Databricks every Monday and shows the Sheet's views:
Behaviour Summary, Environment Summary, Country, a City explorer and Definitions.

Do not edit or remove the `Procfile`: the platform needs it as it is.

## Files

| File | What it does |
|---|---|
| `queries/*.sql` | The notebook's SQL. Only table names changed (`ng_delivery_spark.` → `main.ng_delivery.`, `ng_public_spark.` → `main.ng_public.`). |
| `extract.py` | Runs the queries. Service Principal in production, `DATABRICKS_TOKEN` locally. |
| `pipeline.py` | The notebook's helper functions, copied unchanged, and `build_outputs()` (notebook sections 8.1–8.3 and 10). |
| `refresh.py` | Weekly refresh (Mondays 10:00 Europe/Tallinn), plus a refresh at startup when the saved data is over 7 days old. |
| `storage.py` | Saves and loads the output tables as parquet in S3 (`DATA_BUCKET`), or a local folder. |
| `data/` | Snapshot of the output tables (weekly aggregates). The app shows it until a refresh has saved a full set. |
| `app.py`, `charts.py`, `DEFINITIONS.md` | The dashboard. |

Without Databricks credentials the app skips refreshes and shows the `data/` snapshot. Once the Service Principal
secrets are added, the next start refreshes (the snapshot is more than 7 days old by then) and the Monday schedule
takes over.

## Configuration (Boltable Portal)

| Setting | Where | Value |
|---|---|---|
| `DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET` | Secrets | From the Databricks Service Principal ticket |
| `DATABRICKS_HOST` | Secrets (optional) | Default `bolt-incentives.cloud.databricks.com` |
| `DATABRICKS_HTTP_PATH` | Secrets | The SQL warehouse the Service Principal may use |
| `DATA_BUCKET` | Secrets | Bucket name shown after enabling File Storage (S3) |
| `REFRESH_ADMINS` | Secrets (optional) | Comma-separated emails that see the "Refresh now" button (needs SSO on) |
| File Storage (S3) | Configuration | On |
| Application resources | Configuration → Compute | At least 4 GB memory: a refresh peaks at about 2.1 GB |
| SSO | Configuration → Access | On, with the viewer allowlist |

## Run locally

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt   # bolt-viz needs a JFrog token in ~/.netrc; without it the charts fall back to plain Plotly
export DATABRICKS_TOKEN=...       # personal token, local use only
streamlit run app.py
```

Data goes to `./local_data/outputs` (gitignored). The first start runs a full refresh, about 6 minutes.
