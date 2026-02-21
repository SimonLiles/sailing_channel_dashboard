/* ====================================================================
   Layer: 02_Staging
   Purpose: Clean and cast raw API data into usable formats.
   Note: This is a VIEW, so it reflects changes in 'raw_daily_ingest' 
         immediately without storing extra data.
==================================================================== */

CREATE OR REPLACE VIEW `yt-sailing-dashboard.yt_sailing_data.vw_stg_daily_metrics` AS
SELECT
    channel_id,
    channel_handle,
    TRIM(title) AS channel_title,
    TRIM(description) AS channel_description,
    -- Convert string date '2023-10-27' into a real DATE type
    SAFE.PARSE_DATETIME('%Y-%m-%d', join_date) AS join_date,
    -- Safely cast strings to Integers, returning NULL if they aren't numbers
    SAFE_CAST(view_count AS INT64) AS view_count,
    SAFE_CAST(subscriber_count AS INT64) AS subscriber_count,
    SAFE_CAST(video_count AS INT64) AS video_count,
    -- Safely cast strings to Booleans, return NULL if they are not BOOL
    SAFE_CAST(is_sub_count_hidden AS BOOLEAN) as is_sub_count_hidden
FROM 
    `yt-sailing-dashboard.yt_sailing_data.raw_daily_ingest`
-- Filter out records that are missing essential IDs
WHERE channel_id IS NOT NULL;