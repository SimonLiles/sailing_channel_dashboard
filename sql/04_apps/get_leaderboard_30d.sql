/* ====================================================================
   Layer: 04_Apps
   Purpose: Rank channels by performance over a rolling 30-day window.
   Logic:
    - Filters the Mart for the last 30 days.
    - Joins with Dimensions to get 'channel_title'.
    - Calculates growth metrics.
    - Ranks and calculates percentiles for each metric.

   CTEs:
    1. aggregated  — one place for all grouping and derived metric logic
    2. ranked      — applies DENSE_RANK / PERCENT_RANK against named columns
==================================================================== */

CREATE OR REPLACE TABLE `yt-sailing-dashboard.yt_sailing_data.leaderboard_30d` AS

WITH aggregated AS (
  SELECT
    -- Channel dimensions
    d.channel_id,
    d.profile_pic,
    d.channel_title,
    d.channel_handle,

    -- Channel lifetime metrics
    MAX(m.subscriber_count) AS subscriber_count,
    MAX(m.view_count) AS view_count,
    MAX(m.video_count) AS video_count,

    -- 30-day sums
    SUM(m.daily_new_views) AS total_views_30d,
    SUM(m.daily_new_subs) AS total_subs_30d,
    
    -- New Videos in the past 30 days
    ARRAY_LAST(ARRAY_AGG(video_count ORDER BY date)) -
    ARRAY_FIRST(ARRAY_AGG(video_count ORDER BY date)) AS new_videos_30d,

    -- Growth velocity: subscriber conversion efficiency
    SAFE_DIVIDE(SUM(m.daily_new_subs), SUM(m.daily_new_views)) * 1000 AS sub_conversion_rate,

    -- 7-day rolling average views (most recent value in window)
    ROUND(
        ARRAY_LAST(ARRAY_AGG(m.views_moving_avg_7d ORDER BY m.date))
    , 2) AS views_moving_avg_7d,

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
    m.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY
    1, 2, 3, 4
),

ranked AS (
  SELECT
    *,

    -- Subscriber count
    DENSE_RANK() OVER (ORDER BY subscriber_count DESC) AS sub_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY subscriber_count DESC)) * 100) AS sub_percentile,

    -- Lifetime views
    DENSE_RANK() OVER (ORDER BY view_count DESC) AS lifetime_view_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY view_count DESC)) * 100) AS lifetime_view_percentile,

    -- Video count
    DENSE_RANK() OVER (ORDER BY video_count DESC) AS video_count_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY video_count DESC)) * 100) AS video_count_percentile,
    
    -- 30-day views
    DENSE_RANK() OVER (ORDER BY total_views_30d DESC) AS view_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY total_views_30d DESC)) * 100) AS view_percentile,

    -- 7-day average views
    DENSE_RANK() OVER (ORDER BY views_moving_avg_7d DESC) AS view_7d_avg_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY views_moving_avg_7d DESC)) * 100) AS view_7d_avg_percentile,

    -- Views per video (30-day)
    DENSE_RANK() OVER (ORDER BY views_per_vid_30d DESC) AS views_per_vid_30d_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY views_per_vid_30d DESC)) * 100) AS views_per_vid_30d_percentile,

    -- Views per subscriber (30-day)
    DENSE_RANK() OVER (ORDER BY views_per_sub_30d DESC) AS views_per_sub_30d_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY views_per_sub_30d DESC)) * 100) AS views_per_sub_30d_percentile,

    -- 30-day new subscribers
    DENSE_RANK() OVER (ORDER BY total_subs_30d DESC) AS daily_sub_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY total_subs_30d DESC)) * 100) AS daily_sub_percentile,

    -- Subscriber growth % of base
    DENSE_RANK() OVER (ORDER BY daily_new_subs_pct_growth DESC) AS daily_sub_growth_pct_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY daily_new_subs_pct_growth DESC)) * 100) AS daily_sub_growth_pct_percentile,

    -- Videos published (30-day)
    DENSE_RANK() OVER (ORDER BY new_videos_30d DESC) AS new_videos_30d_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY new_videos_30d DESC)) * 100) AS new_videos_30d_percentile
      
  FROM aggregated
)

SELECT *
FROM ranked
ORDER BY view_rank ASC;