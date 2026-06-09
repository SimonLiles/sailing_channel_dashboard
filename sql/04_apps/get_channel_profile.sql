SELECT 
  channel_id, 
  channel_handle,
  channel_title, 
  channel_description, 
  channel_keywords, 
  profile_pic, 
  join_date,
  status,
  type
FROM `yt-sailing-dashboard.yt_sailing_data.channel_dimensions`
WHERE channel_id = @id;