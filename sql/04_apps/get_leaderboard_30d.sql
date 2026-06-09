/* ====================================================================
   Layer: 04_Apps
   Purpose: Rank channels by performance over a rolling 30-day window.
   Logic: 
    - Filters the Mart for the last 30 days.
    - Joins with Dimensions to get 'channel_title'.
    - Calculates growth metrics.
    - Ranks and calcualtes percentiles for each metric.
==================================================================== */

CREATE OR REPLACE TABLE `yt-sailing-dashboard.yt_sailing_data.leaderboard_30d` AS
SELECT
    -- channel dimensions
    d.channel_id,
    d.profile_pic,
    d.channel_title,
    d.channel_handle,

    -- Channel Lifetime metrics
    MAX(m.subscriber_count) AS subscriber_count,
    MAX(m.view_count) AS view_count,
    MAX(m.video_count) AS video_count,
    
    -- 30 day sums
    SUM(m.daily_new_views) AS total_views_30d,
    SUM(m.daily_new_subs) AS total_subs_30d,
    
    -- Growth Velocity: How efficient is this channel at converting views?
    SAFE_DIVIDE(SUM(m.daily_new_subs), SUM(m.daily_new_views)) * 1000 AS sub_conversion_rate,
    
    ROUND(
      ARRAY_LAST(
        ARRAY_AGG(m.views_moving_avg_7d ORDER BY m.date)
    ), 2) AS views_moving_avg_7d,
    
    ARRAY_LAST(
      ARRAY_AGG(m.daily_new_subs ORDER BY m.date)
    ) AS daily_new_subs,
    
    ROUND(
      (SAFE_DIVIDE(
        SUM(m.daily_new_subs), 
        MAX(m.subscriber_count)
    )) * 100, 2) AS daily_new_subs_pct_growth,
    
    -- Views per video
    ARRAY_LAST(
      ARRAY_AGG(m.lifetime_views_per_vid ORDER BY m.date)
    ) AS lifetime_views_per_vid,
    
    -- Algorithm Performance
    ROUND(SAFE_DIVIDE(SUM(m.daily_new_views), MAX(m.video_count)), 3) AS views_per_vid_30d,
    
    -- Audience Activation
    ROUND(SAFE_DIVIDE(SUM(m.daily_new_views), MAX(m.subscriber_count)), 3) AS views_per_sub_30d,
    
    -- Ranking and percentile for subscriber count
    DENSE_RANK() OVER (ORDER BY MAX(m.subscriber_count) DESC) AS sub_rank,
    ROUND((1- PERCENT_RANK() OVER (ORDER BY MAX(m.subscriber_count) DESC)) * 100) AS sub_percentile,
    
    -- Ranking and percentile for lifetime views
    DENSE_RANK() OVER (ORDER BY MAX(m.view_count) DESC) AS lifetime_view_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY MAX(m.view_count) DESC)) * 100 ) AS lifetime_view_percentile,

    -- Ranking and percentile for video count
    DENSE_RANK() OVER (ORDER BY MAX(m.video_count) DESC) AS video_count_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY MAX(m.video_count) DESC)) * 100) AS video_count_percentile,
    
    -- Ranking and percentile for daily views
    DENSE_RANK() OVER (ORDER BY SUM(m.daily_new_views) DESC) AS view_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY SUM(m.daily_new_views) DESC)) * 100) AS view_percentile,
    
    -- Ranking and percentile for 7d average views
    DENSE_RANK() OVER (
      ORDER BY ARRAY_LAST(
        ARRAY_AGG(m.views_moving_avg_7d ORDER BY m.date)
      ) DESC) AS view_7d_avg_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY 
      ARRAY_LAST(
        ARRAY_AGG(m.views_moving_avg_7d ORDER BY m.date)
      ) DESC)) * 100) AS view_7d_avg_percentile,
    
    -- Ranking and percentile for 30 day views per video
    DENSE_RANK() OVER (
      ORDER BY SAFE_DIVIDE(SUM(m.daily_new_views), MAX(m.video_count)) 
      DESC) AS views_per_vid_30d_rank,
    ROUND((1 - PERCENT_RANK() OVER (
      ORDER BY SAFE_DIVIDE(SUM(m.daily_new_views), MAX(m.daily_new_videos)) 
      DESC)) * 100) AS views_per_vid_30d_percentile,
      
    -- Ranking and percentile for Audience Activation
    DENSE_RANK() OVER (
      ORDER BY SAFE_DIVIDE(SUM(m.daily_new_views), MAX(m.subscriber_count)) 
      DESC) AS views_per_sub_30d_rank,
    ROUND((1 - PERCENT_RANK() OVER (
      ORDER BY SAFE_DIVIDE(SUM(m.daily_new_views), MAX(m.subscriber_count)) 
      DESC)) * 100) AS views_per_sub_30d_percentile,

    -- Ranking and perecentile for daily subs
    DENSE_RANK() OVER (ORDER BY SUM(m.daily_new_subs) DESC) AS daily_sub_rank,
    ROUND((1 - PERCENT_RANK() OVER (ORDER BY SUM(m.daily_new_subs) DESC)) * 100) AS daily_sub_percentile,
    
    -- Ranking and percentile for daily sub growth percentage
    DENSE_RANK() OVER (
      ORDER BY ROUND(
        SAFE_DIVIDE(
          SUM(m.daily_new_subs),
          MAX(m.subscriber_count)
      ), 2) DESC
    ) AS daily_sub_growth_pct_rank,
    ROUND((1 - PERCENT_RANK() OVER (
      ORDER BY ROUND(
        SAFE_DIVIDE(
          SUM(m.daily_new_subs),
          MAX(m.subscriber_count)
      ), 2) DESC
    )) * 100) AS daily_sub_growth_pct_percentile
FROM 
    `yt-sailing-dashboard.yt_sailing_data.fct_daily_performance` AS m
INNER JOIN 
    `yt-sailing-dashboard.yt_sailing_data.channel_dimensions` AS d 
    ON m.channel_id = d.channel_id
WHERE 
    m.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 
    1, 2, 3, 4
ORDER BY 
    view_rank ASC;
