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
FROM `{{project}}.{{dataset}}.channel_dimensions`
WHERE channel_id = @id;