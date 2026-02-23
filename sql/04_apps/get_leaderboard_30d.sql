/* ====================================================================
   Layer: 04_Apps
   Purpose: Rank channels by performance over a rolling 30-day window.
   Logic: 
    - Filters the Mart for the last 30 days.
    - Joins with Dimensions to get 'channel_title'.
    - Calculates growth velocity (subs per 1k views).
==================================================================== */

SELECT
    RANK() OVER (ORDER BY SUM(m.daily_new_views) DESC) AS view_rank,
    d.profile_pic,
    d.channel_title,
    d.channel_handle,
    SUM(m.daily_new_views) AS total_views_30d,
    SUM(m.daily_new_subs) AS total_subs_30d,
    -- Growth Velocity: How efficient is this channel at converting views?
    SAFE_DIVIDE(SUM(m.daily_new_subs), SUM(m.daily_new_views)) * 1000 AS sub_conversion_rate,
FROM 
    `yt-sailing-dashboard.yt_sailing_data.fct_daily_performance` AS m
INNER JOIN 
    `yt-sailing-dashboard.yt_sailing_data.channel_dimensions` AS d 
    ON m.channel_id = d.channel_id
WHERE 
    m.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 
    2, 3, 4
ORDER BY 
    view_rank ASC;
