/* ====================================================================
   Layer: 03_Marts
   Purpose: Calculate analytical KPIs for the Shiny Dashboard.
   Logic: 
    - 30 Day total views:
    - 30 Day total new subscribers:
    - 30 Day total of new videos:
    - 7 Day Rolling average of new views: This is just a capture of the 
      most recent snapshot.
      
    - Sub Conversion Rate: 30 Day rate of new subscriptions per 1000 views.
    - 30 Day Percent Growth in Subscribers: Subscriber growth as % of total 
      subscriber base.
    - Lifetime Views per Video: Lifetime Average Catalog Yield.
    - 30 Day Views per Video: 30 Day catalog yield.
    - 30 Day Views per Subscriber: 30 Day Audience Activation.
==================================================================== */
DECLARE start_date DATE;
DECLARE end_date DATE;
DECLARE window_days INT64;

make this a merge
MERGE  `yt-sailing-dashboard.yt_sailing_data.mart_channel_metrics_30d` AS T
USING (

) as S
ON T.channel_id = S.channel_id

WHEN MATCHED THEN 
  UPDATE SET ...
WHEN NOT MATCHED THEN 
  INSERT


CREATE OR REPLACE TABLE `yt-sailing-dashboard.yt_sailing_data.mart_channel_metrics_30d`
SELECT
  -- When the snapshot was taken
  m.date AS snapshot_date
  
  -- Channel dimensions
  d.channel_id,
  
  -- Rolling Window for derived metrics
  window_days AS window_days,
  
  -- Channel lifetime metrics
  ARRAY_LAST(ARRAY_AGG(m.subscriber_count ORDER BY date)) AS subscriber_count,
  ARRAY_LAST(ARRAY_AGG(m.view_count ORDER BY date)) AS view_count,
  ARRAY_LAST(ARRAY_AGG(m.video_count ORDER BY date)) AS video_count,

  -- 30-day sums
  SUM(m.daily_new_views) AS total_views_30d,
  SUM(m.daily_new_subs) AS total_subs_30d,
  
  -- New Videos in the past 30 days
  ARRAY_LAST(ARRAY_AGG(m.video_count ORDER BY date)) -
  ARRAY_FIRST(ARRAY_AGG(m.video_count ORDER BY date)) AS new_videos_30d,

  -- 7-day rolling average views (most recent value in window)
  ROUND(
      ARRAY_LAST(ARRAY_AGG(m.views_moving_avg_7d ORDER BY m.date))
  , 2) AS views_moving_avg_7d,

  -- Growth velocity: subscriber conversion efficiency
  SAFE_DIVIDE(SUM(m.daily_new_subs), SUM(m.daily_new_views)) * 1000 AS sub_conversion_rate,

  -- Most recent daily subs value in window
  ARRAY_LAST(ARRAY_AGG(m.daily_new_subs ORDER BY m.date)) AS daily_new_subs,

  -- 30-day sub growth as % of total subscriber base
  ROUND(
      SAFE_DIVIDE(SUM(m.daily_new_subs), MAX(m.subscriber_count)) * 100
  , 2) AS daily_new_subs_pct_growth,

  -- Lifetime views per video (most recent value in window)
  ARRAY_LAST(ARRAY_AGG(m.lifetime_views_per_vid ORDER BY m.date)) AS lifetime_views_per_vid,

  -- Algorithm performance: 30-day views spread across catalogue
  ROUND(SAFE_DIVIDE(SUM(m.daily_new_views), MAX(m.video_count)), 3) AS views_per_vid_30d,

  -- Audience activation: 30-day views relative to subscriber base
  ROUND(SAFE_DIVIDE(SUM(m.daily_new_views), MAX(m.subscriber_count)), 3) AS views_per_sub_30d

FROM
  `yt-sailing-dashboard.yt_sailing_data.fct_daily_performance` AS m
INNER JOIN
  `yt-sailing-dashboard.yt_sailing_data.channel_dimensions` AS d
  ON m.channel_id = d.channel_id
WHERE
  m.date >= DATE_SUB(CURRENT_DATE(), INTERVAL window_days DAY) AND
  WHERE m.date BETWEEN start_date AND end_date
GROUP BY
  1, 2