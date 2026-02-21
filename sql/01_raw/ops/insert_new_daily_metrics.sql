INSERT INTO daily_metrics 
  (channel_id,
  date,
  view_count,
  video_count,
  subscriber_count)
SELECT
  channel_id,
  date,
  view_count,
  video_count,
  subscriber_count
FROM daily_metrics_staging;