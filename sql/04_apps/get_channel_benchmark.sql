/* ====================================================================
   Layer: 04_Apps
   Purpose: Fetch benchmark data for a single channel in the specified
            cohort. Used by the Growth Benchmarks page to display
            a selected channel's metrics alongside the cohort.

   Parameters:
     @channel_id    STRING
     @cohort_type   STRING
     @cohort_value  STRING
==================================================================== */

SELECT
  r.channel_id,
  r.metric_name,
  r.window_days,
  r.cohort_type,
  r.cohort_value,
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
  AND r.channel_id = @channel_id
  AND r.cohort_type = @cohort_type
  AND r.cohort_value = @cohort_value
  AND r.metric_name IN (
    'total_views_window',
    'views_moving_avg_7d',
    'total_subs_window',
    'views_per_vid_window',
    'views_per_sub_window',
    'lifetime_views_per_vid'
  )
  AND (r.window_days = 30 OR r.window_days IS NULL)
