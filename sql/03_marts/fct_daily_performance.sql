/* ====================================================================
   Layer: 03_Marts
   Purpose: Calculate analytical KPIs for the Shiny Dashboard.
   Logic: 
    - 7-Day Rolling Average: Smooths out weekend/weekday volatility.
    - Daily Growth: Calculates views gained since the previous day.
==================================================================== */

CREATE OR REPLACE TABLE `yt-sailing-dashboard.yt_sailing_data.fct_daily_performance` AS

WITH daily_diffs AS (
  SELECT 
    channel_id,
    date,
    view_count,
    video_count,
    subscriber_count,
    -- Calculate the "New Views" gained today by comparing to yesterday
    view_count - LAG(view_count) OVER (PARTITION BY channel_id ORDER BY date) AS daily_new_views,
    -- Calculate "New Subs"
    subscriber_count - LAG(subscriber_count) OVER (PARTITION BY channel_id ORDER BY date) AS daily_new_subs
    -- Calculate "New Videos" tracking activity by the channel
    video_count - LAG(video_count) OVER (PARTITION BY channel_id ORDER BY date) AS daily_new_videos
  FROM 
    `yt-sailing-dashboard.yt_sailing_data.daily_metrics_history`
)

SELECT 
  *,
  -- Stock Metrics
  -- Calculate Views Per Video
  SAFE_DIVIDE(view_count, video_count) AS lifetime_views_per_vid,
  -- Calculate Views Per Subscriber
  SAFE_DIVIDE(view_count, subscriber_count) AS lifetime_views_per_sub,
  -- Calculate Subscribers Per Video
  SAFE_DIVIDE(subscriber_count, video_count) AS lifetime_subs_per_vid,
  
  -- Flow metrics
  -- The "Smooth" Metric: 7-day moving average of new views
  AVG(daily_new_views) OVER (
      PARTITION BY channel_id 
      ORDER BY date 
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
  ) AS views_moving_avg_7d,
  
  -- Subscriber Velocity: New subs per 10,000 views
  SAFE_DIVIDE(daily_new_subs, daily_new_views) * 10000 AS sub_velocity_per_10k
FROM 
  daily_diffs;
