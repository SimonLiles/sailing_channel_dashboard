/* ====================================================================
   Layer: 03_Marts
   Purpose: Create mart for other queries to view metric data in long format.
   Logic: 
    Pivot the metrics table long so that every metric is in the same column,
    the metric_name column is used to identify the metric. This data view is 
    used by ranking table so that new metrics are easily added to the ranking 
    logic.
==================================================================== */

MERGE `{{project}}.{{dataset}}.mart_channel_metrics_values` AS T

USING (
  -- Unpivot the snapshot metrics
  WITH snapshot_metrics AS (
    SELECT
      snapshot_date,
      channel_id,
      NULL AS window_days,
      metric_name,
      metric_value
    
    FROM (
      SELECT
        date AS snapshot_date,
        channel_id,
        
        CAST(view_count             AS FLOAT64) AS view_count,
        CAST(video_count            AS FLOAT64) AS video_count,
        CAST(subscriber_count       AS FLOAT64) AS subscriber_count,
        
        CAST(daily_new_views        AS FLOAT64) AS daily_new_views,
        CAST(daily_new_subs         AS FLOAT64) AS daily_new_subs,
        CAST(daily_new_videos       AS FLOAT64) AS daily_new_videos,
        
        CAST(lifetime_views_per_vid AS FLOAT64) AS lifetime_views_per_vid,
        CAST(lifetime_views_per_sub AS FLOAT64) AS lifetime_views_per_sub,
        CAST(lifetime_subs_per_vid  AS FLOAT64) AS lifetime_subs_per_vid,
        
        CAST(views_moving_avg_7d    AS FLOAT64) AS views_moving_avg_7d,
        
        CAST(sub_velocity_per_10k   AS FLOAT64) AS sub_velocity_per_10k

        FROM `{{project}}.{{dataset}}.fct_daily_performance`
    )
    
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
  ),
  
  -- Unpivot derived metrics
  window_metrics AS (
    SELECT
    snapshot_date,
    channel_id,
    window_days,
    metric_name,
    metric_value
    
    FROM (
      SELECT
        snapshot_date,
        channel_id,
        window_days,

        CAST(total_views_30d        AS FLOAT64) AS total_views_30d,
        CAST(total_subs_30d         AS FLOAT64) AS total_subs_30d,
        CAST(new_videos_30d         AS FLOAT64) AS new_videos_30d,
        
        CAST(sub_conversion_rate    AS FLOAT64) AS sub_conversion_rate,
        
        daily_new_subs_pct_growth,

        CAST(lifetime_views_per_vid AS FLOAT64) AS lifetime_views_per_vid,
        CAST(views_per_vid_30d      AS FLOAT64) AS views_per_vid_30d,
        
        CAST(views_per_sub_30d      AS FLOAT64) AS views_per_sub_30d

      FROM `{{project}}.{{dataset}}.mart_channel_metrics`
    )
    
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
  SELECT * FROM window_metrics

) AS S

ON  T.channel_id    = S.channel_id
AND T.snapshot_date = S.snapshot_date
AND T.window_days   = S.window_days
AND T.metric_name   = S.metric_name

WHEN MATCHED AND (
  T.metric_value IS DISTINCT FROM S.metric_value
) THEN UPDATE SET
  T.metric_name  = S.metric_name,
  T.metric_value = S.metric_value,
  T.updated_at   = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT
(
  snapshot_date,
  channel_id,
  window_days,
  metric_name,
  metric_value,
  updated_at
) VALUES (
  S.snapshot_date,
  S.channel_id,
  S.window_days,
  S.metric_name,
  S.metric_value,
  CURRENT_TIMESTAMP()
);

