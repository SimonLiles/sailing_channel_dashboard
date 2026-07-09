/* ====================================================================
   Layer: 04_Apps
   Purpose: Fetch all benchmark data needed for the Growth Benchmarks
            page. This is a relatively small subset of the leaderboard
            data (only the metrics used in plots and value boxes).
            The result is cached as RDS in GCS during the ETL run.

   Metrics included (both 30-day and lifetime windows):
     total_views_window, views_moving_avg_7d, total_subs_window,
     views_per_vid_window, views_per_sub_window, lifetime_views_per_vid
==================================================================== */

SELECT
  r.channel_id,
  r.cohort_type,
  r.cohort_value,
  r.metric_name,
  r.window_days,
  v.metric_value,
  r.ranking,
  r.percentile
FROM `{{project}}.{{dataset}}.mart_channel_rankings` r
LEFT JOIN `{{project}}.{{dataset}}.mart_channel_metrics_values` v
  ON r.snapshot_date = v.snapshot_date
  AND r.channel_id = v.channel_id
  AND r.metric_name = v.metric_name
  AND r.window_days IS NOT DISTINCT FROM v.window_days
WHERE r.snapshot_date = (
  SELECT MAX(snapshot_date)
  FROM `{{project}}.{{dataset}}.mart_channel_rankings`
)
  AND r.metric_name IN (
    'total_views_window',
    'views_moving_avg_7d',
    'total_subs_window',
    'views_per_vid_window',
    'views_per_sub_window',
    'lifetime_views_per_vid'
  )
  AND (r.window_days = 30 OR r.window_days IS NULL)
