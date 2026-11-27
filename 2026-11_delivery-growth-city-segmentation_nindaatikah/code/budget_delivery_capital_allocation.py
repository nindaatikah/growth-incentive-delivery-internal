# Databricks notebook source
import io
import urllib.request

import pandas as pd
from pyspark.sql import functions as F

# ── 1. Sheet coordinates ────────────────────────────────────────────
SHEET_ID = "<BUDGET_SHEET_ID>"  # id of the budget Google Sheet; it must be shared as "Anyone with the link can view"
GID = "0"

TARGET = "dev.dev_incentives.delivery_budget_capital_allocation"
# country rows have a blank city_name; segment rows have blank country/city and the label in final_segment
KEY = ["aggregation", "country_name", "city_name", "month", "final_segment"]

# ── 2. Read directly from Google Sheets as CSV ──────────────────────
# Needs the sheet shared as "Anyone with the link can view"; otherwise Google returns a sign-in page.
url = f"https://docs.google.com/spreadsheets/d/{SHEET_ID}/export?format=csv&gid={GID}"
raw = urllib.request.urlopen(url).read().decode("utf-8")
if raw.lstrip().lower().startswith("<!doctype html") or "<html" in raw[:200].lower():
    raise RuntimeError("Google returned a sign-in page: share the sheet as 'Anyone with the link can view'")

# Header is row 1 of the sheet: do not skip any rows. Read everything as text and clean below.
df_pd = pd.read_csv(io.StringIO(raw), dtype=str, keep_default_na=False)
df_pd.columns = [c.strip().replace(" ", "_").lower() for c in df_pd.columns]
# Keep every aggregation level (city, country, GLOBAL, segment); drop only fully empty rows
df_pd = df_pd[df_pd["aggregation"].str.strip() != ""]

print(f"Loaded {len(df_pd)} rows, {len(df_pd.columns)} columns")
df_pd.head(3)

# COMMAND ----------

# ── 3. Clean types: '1.01%' -> 0.0101, '4,819,830' -> 4819830, '' -> null ──
PCT_COLS = ["activation_spend", "reactivation_spend", "engagement_spend", "ulc_bolt_spend",
            "ulc_provider_spend", "total_ulc", "untested_spend",
            "new_city", "elc", "churn", "am", "marketing", "bdm_3p", "store_1p",
            "bolt_plus", "total_bolt_spend", "ba_total_spend"]
NUM_COLS = ["gmv_ds", "gmv_ba"]


def to_pct(s):
    s = s.str.strip().str.replace(",", "", regex=False)
    is_pct = s.str.endswith("%")
    n = pd.to_numeric(s.str.rstrip("%"), errors="coerce")
    return n.where(~is_pct, n / 100)


def to_num(s):
    return pd.to_numeric(s.str.replace(",", "", regex=False).str.strip(), errors="coerce")


for c in PCT_COLS:
    df_pd[c] = to_pct(df_pd[c])
for c in NUM_COLS:
    df_pd[c] = to_num(df_pd[c])
df_pd["month"] = pd.to_datetime(df_pd["month"]).dt.date
# NB: Series.replace("", None) forward-fills in pandas, so use mask to get real nulls.
for c in ["city_segment", "capital_allocation_group", "final_segment"]:
    df_pd[c] = df_pd[c].mask(df_pd[c].str.strip() == "", None)

df = (
    spark.createDataFrame(df_pd)
    .select("aggregation", "country_name", "city_name", "month", "city_segment",
            "capital_allocation_group", "final_segment", *PCT_COLS,
            F.col("gmv_ds").cast("bigint"), F.col("gmv_ba").cast("bigint"))
    .withColumn("_ingested_at", F.current_timestamp())
)
assert df.groupBy(*KEY).count().filter("count > 1").count() == 0, "duplicate keys in sheet"

# COMMAND ----------

# ── 4. Load into Delta: replaces the sheet's months, keeps older months, re-run safe ────────────────
spark.sql(f"""
CREATE TABLE IF NOT EXISTS {TARGET} (
  aggregation STRING, country_name STRING, city_name STRING, month DATE,
  city_segment STRING, capital_allocation_group STRING, final_segment STRING,
  activation_spend DOUBLE, reactivation_spend DOUBLE, engagement_spend DOUBLE,
  ulc_bolt_spend DOUBLE, ulc_provider_spend DOUBLE, total_ulc DOUBLE,
  untested_spend DOUBLE, gmv_ds BIGINT, gmv_ba BIGINT,
  _ingested_at TIMESTAMP
)
""")

# Add the new budget columns to an existing table (no-op once they exist)
existing = {f.name for f in spark.table(TARGET).schema.fields}
new_cols = [c for c in ["new_city", "elc", "churn", "am", "marketing", "bdm_3p", "store_1p",
                        "bolt_plus", "total_bolt_spend", "ba_total_spend"] if c not in existing]
if new_cols:
    spark.sql(f"ALTER TABLE {TARGET} ADD COLUMNS (" + ", ".join(f"{c} DOUBLE" for c in new_cols) + ")")

# Replace every month that is in the sheet (atomic, no duplicates if re-run); other months are kept as history.
months = sorted({m for m in df_pd["month"]})
cond = "month IN (" + ", ".join(f"DATE'{m}'" for m in months) + ")"
(df.write.format("delta").mode("overwrite")
   .option("replaceWhere", cond).option("mergeSchema", "true").saveAsTable(TARGET))


# COMMAND ----------

# MAGIC %sql
# MAGIC select country_name, ba_total_spend from dev.dev_incentives.delivery_budget_capital_allocation
# MAGIC where  month = date('2026-11-01')
# MAGIC and country_name = 'GLOBAL'
# MAGIC


# COMMAND ----------

# ── 5. City segmentation tab -> dev.dev_incentives.dev_incentive_city_segment ───────────────────────
# Same sheet as above, tab "city_segmentation" (gid 259247874). One row per city / zone cluster / month.
SEG_GID = "259247874"
SEG_TARGET = "dev.dev_incentives.dev_incentive_city_segment"
SEG_KEY = ["country_name", "city_name", "city_cluster", "month"]

seg_url = f"https://docs.google.com/spreadsheets/d/{SHEET_ID}/export?format=csv&gid={SEG_GID}"
seg_raw = urllib.request.urlopen(seg_url).read().decode("utf-8")
if seg_raw.lstrip().lower().startswith("<!doctype html") or "<html" in seg_raw[:200].lower():
    raise RuntimeError("Google returned a sign-in page: share the sheet as 'Anyone with the link can view'")

seg_pd = pd.read_csv(io.StringIO(seg_raw), dtype=str, keep_default_na=False)
seg_pd.columns = [c.strip().replace(" ", "_").lower() for c in seg_pd.columns]
seg_pd = seg_pd[["country_name", "city_name", "city_cluster", "month", "city_segment"]]
for c in seg_pd.columns:
    seg_pd[c] = seg_pd[c].str.strip()
seg_pd = seg_pd[seg_pd["country_name"] != ""]          # drop fully empty rows
seg_pd["month"] = pd.to_datetime(seg_pd["month"]).dt.date
seg_pd["city_cluster"] = seg_pd["city_cluster"].mask(seg_pd["city_cluster"] == "", None)
seg_pd["city_segment"] = seg_pd["city_segment"].mask(seg_pd["city_segment"] == "", None)

seg_df = spark.createDataFrame(seg_pd).withColumn("_ingested_at", F.current_timestamp())
assert seg_df.groupBy(*SEG_KEY).count().filter("count > 1").count() == 0, "duplicate keys in city_segmentation tab"
print(f"Loaded {len(seg_pd)} rows for months {sorted({str(m) for m in seg_pd['month']})}")

spark.sql(f"""
CREATE TABLE IF NOT EXISTS {SEG_TARGET} (
  country_name STRING, city_name STRING, city_cluster STRING, month DATE,
  city_segment STRING, _ingested_at TIMESTAMP
)
""")

# Replace every month that is in the tab (atomic, re-run safe); other months are kept as history.
seg_months = sorted({m for m in seg_pd["month"]})
seg_cond = "month IN (" + ", ".join(f"DATE'{m}'" for m in seg_months) + ")"
(seg_df.write.format("delta").mode("overwrite")
   .option("replaceWhere", seg_cond).option("mergeSchema", "true").saveAsTable(SEG_TARGET))

display(spark.sql(f"SELECT month, city_segment, COUNT(*) AS rows FROM {SEG_TARGET} GROUP BY 1, 2 ORDER BY 1, 2"))
