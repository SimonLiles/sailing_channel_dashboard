/* ====================================================================
   Layer: 04_Apps
   Purpose: Provide top-level KPIs for the Dashboard Header.
   Logic: 
    - Identifies the most recent two days in the dataset.
    - Aggregates views and subs across ALL channels.
    - Calculates a Day-over-Day (DoD) percentage change.
==================================================================== */

WITH daily_aggregates AS (
    SELECT 
        date,
        SUM(daily_new_views) AS total_views,
        SUM(daily_new_subs) AS total_subs,
        COUNT(DISTINCT channel_id) AS active_channels
    FROM 
        `yt-sailing-dashboard.yt_sailing_data.fct_daily_performance`
    GROUP BY 1
),
ordered_days AS (
    SELECT 
        *,
        -- Look at the row exactly one day prior
        LAG(total_views) OVER (ORDER BY date) AS prev_day_views
    FROM 
        daily_aggregates
)
SELECT 
    date AS date,
    total_views AS latest_views,
    total_subs AS latest_subs,
    active_channels,
    -- Calculate Day-over-Day Growth %
    SAFE_DIVIDE(total_views - prev_day_views, prev_day_views) * 100 AS view_growth_pct
FROM 
    ordered_days
ORDER BY 
    date DESC; -- We only want the single latest snapshot
