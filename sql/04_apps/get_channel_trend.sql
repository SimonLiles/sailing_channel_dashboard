/* ====================================================================
   Layer: 04_Apps
   Purpose: Serve time-series data for a specific channel to the UI.
   Injection Points: @channel_id, @start_date
==================================================================== */

SELECT 
    date,
    views_moving_avg_7d,
    view_count,
    video_count,
    subscriber_count,
    daily_new_views,
    daily_new_subs,
    lifetime_views_per_vid,
    lifetime_views_per_sub,
    lifetime_subs_per_vid,
    sub_velocity_per_10k
FROM 
    `{{project}}.{{dataset}}.fct_daily_performance`
WHERE 
    channel_id = @channel_id  -- Injection Point 1
    AND date >= @start_date   -- Injection Point 2
ORDER BY 
    date ASC;
