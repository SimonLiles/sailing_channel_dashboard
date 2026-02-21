/* ====================================================================
   Layer: 01_Raw / Ops
   Purpose: Append cleaned daily metrics to the permanent history table.
   Logic: 
    - Pulls from the Staging View (vw_stg_daily_metrics) to get clean types.
    - Uses a "Not Exists" check to prevent duplicate rows for the same date.
==================================================================== */

INSERT INTO `yt-sailing-dashboard.yt_sailing_data.daily_metrics_history` (
    channel_id, 
    date, 
    view_count, 
    subscriber_count, 
    video_count, 
    created_at
)
SELECT 
    s.channel_id, 
    CURRENT_DATE() AS date, 
    s.view_count, 
    s.subscriber_count, 
    s.video_count, 
    CURRENT_TIMESTAMP() AS created_at
FROM `yt-sailing-dashboard.yt_sailing_data.vw_stg_daily_metrics` AS s
WHERE NOT EXISTS (
    -- This subquery prevents double-loading the same channel for the same day
    SELECT 1 
    FROM `yt-sailing-dashboard.yt_sailing_data.daily_metrics_history` AS h
    WHERE h.channel_id = s.channel_id 
      AND h.date = date
);
