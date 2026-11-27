-- Segment of every city zone cluster per month (the "city_segmentation" tab of the budget sheet).
-- A city can have clusters in different segments (e.g. Valletta: Cluster A Monetise, B and C Grow Share).
-- Targets stay at city level; this table only decides which segment each cluster's numbers count under.
-- month is cast to text so it always reads as 'YYYY-MM-DD'.
SELECT country_name, city_name, city_cluster, city_segment, CAST(month AS STRING) AS month, CAST(_ingested_at AS STRING) AS _ingested_at
FROM dev.dev_incentives.dev_incentive_city_segment
WHERE month >= DATE'2026-10-01'
  AND COALESCE(country_name, '') NOT IN ('Georgia', 'Tuvalu', 'Croatia')
