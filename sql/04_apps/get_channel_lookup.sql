/* ====================================================================
   Layer: 04_Apps
   Purpose: Lookup table for all active channels with lifetime stats.
            The subscriber_count, view_count, and video_count columns
            are used by Growth Benchmarks scatter plots and by the
            cohort selector in the Leaderboard report builder.
   Logic:
    - Retrieve active channel dimensions.
    - Join the latest lifetime stats from fct_daily_performance.
==================================================================== */
CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.channel_lookup` AS
WITH latest_fct AS (
  SELECT
    channel_id,
    subscriber_count,
    view_count,
    video_count
  FROM `{{project}}.{{dataset}}.fct_daily_performance`
  WHERE date = (SELECT MAX(date) FROM `{{project}}.{{dataset}}.fct_daily_performance`)
)
SELECT
  d.channel_id,
  d.channel_title,
  d.channel_handle,
  d.profile_pic,
  f.subscriber_count,
  f.view_count,
  f.video_count
FROM `{{project}}.{{dataset}}.channel_dimensions` AS d
LEFT JOIN latest_fct AS f
  ON d.channel_id = f.channel_id
WHERE d.is_active = TRUE
ORDER BY d.channel_title ASC;