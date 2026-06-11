/* ====================================================================
   Layer: 03_Marts
   Purpose: Create view for other queries to view metric data in long format.
   Logic: 
    Pivot the metrics table long so that every metric is in the same column,
    the metric_name column is used to identify the metric. This data view is 
    used by ranking table so that new metrics are easily added to the ranking 
    logic.
==================================================================== */

CREATE OR REPLACE VIEW 
  `yt-sailing-dashboard.yt_sailing_data.mart_channel_metrics_values`
AS

SELECT
  snapshot_date,
  window_days,
  channel_id
  
FROM `yt-sailing-dashboard.yt_sailing_data.mart_channel_metrics`

UNPIVOT (
  metric_value
  FOR metric_name IN (
    subscriber_count,
    view_count,
    video_count,
    total_views_30d,
    total_subs_30d,
    new_videos_30d,
    views_moving_avg_7d,
    sub_conversion_rate,
    daily_new_subs,
    daily_new_subs_pct_growth,
    lifetime_views_per_vid,
    views_per_vid_30d,
    views_per_sub_30d
  )
);