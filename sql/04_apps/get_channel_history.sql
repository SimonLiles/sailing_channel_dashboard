SELECT 
  date, 
  view_count, 
  video_count,
  subscriber_count, 
  daily_new_views, 
  daily_new_subs, 
  views_moving_avg_7d
FROM `{{project}}.{{dataset}}.fct_daily_performance`
WHERE channel_id = @id
ORDER BY date ASC;