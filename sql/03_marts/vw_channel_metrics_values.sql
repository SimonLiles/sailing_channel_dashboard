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

-- Unpivot the snapshot metrics
WITH snapshot_metrics AS (
  snapshot_date,
  channel_id,
  NULL AS window_days,
  metric_name,
  metric_value
  
  FROM `yt-sailing-dashboard.yt_sailing_data.fct_daily_performance`
  
  UNPIVOT (
    metric_value
    FOR metric_name IN (
      view_count,
      video_count,
      subscriber_count,
      
      daily_new_views,
      daily_new_subs,
      daily_new_videos,
      
      lifetime_views_per_vid,
      lifetime_views_per_sub,
      lifetime_subs_per_vid,
      
      views_moving_avg_7d,
      
      sub_velocity_per_10k
    )
  )
)

-- Unpivot derived metrics
WITH window_metrics AS (
  SELECT
  snapshot_date,
  channel_id,
  window_days
  
  FROM `yt-sailing-dashboard.yt_sailing_data.mart_channel_metrics`
  
  UNPIVOT (
    metric_value
    FOR metric_name IN (
      total_views_30d,
      total_subs_30d,
      new_videos_30d,
      sub_conversion_rate,
      daily_new_subs_pct_growth,
      lifetime_views_per_vid,
      views_per_vid_30d,
      views_per_sub_30d
    )
  )
)

-- Union all the metrics together
SELECT * FROM snapshot_metrics
UNION ALL
SELECT * FROM window_metrics;