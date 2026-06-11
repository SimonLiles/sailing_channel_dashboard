MERGE `yt-sailing-dashboard.yt_sailing_data.channel_dimensions` AS T
USING (
  SELECT DISTINCT 
    channel_id, 
    channel_handle, 
    channel_title, 
    channel_description, 
    join_date, 
    is_sub_count_hidden, 
    channel_keywords, 
    profile_pic
  FROM `yt-sailing-dashboard.yt_sailing_data.vw_stg_daily_metrics`
) AS S
ON T.channel_id = S.channel_id

-- UPDATE logic: Check if ANY field is different
WHEN MATCHED AND (
    T.channel_handle IS DISTINCT FROM S.channel_handle OR 
    T.channel_title IS DISTINCT FROM S.channel_title OR 
    T.channel_description IS DISTINCT FROM S.channel_description OR
    T.join_date IS DISTINCT FROM S.join_date OR 
    T.is_sub_count_hidden IS DISTINCT FROM S.is_sub_count_hidden OR
    T.channel_keywords IS DISTINCT FROM S.channel_keywords OR
    T.profile_pic IS DISTINCT FROM S.profile_pic
) THEN
  UPDATE SET 
    T.channel_handle = S.channel_handle,
    T.channel_title = S.channel_title,
    T.channel_description = S.channel_description,
    T.join_date = DATE(S.join_date),
    T.is_sub_count_hidden = S.is_sub_count_hidden,
    T.channel_keywords = S.channel_keywords,
    T.profile_pic = S.profile_pic,
    T.updated_at = CURRENT_TIMESTAMP()

-- INSERT logic: Brand new channel
WHEN NOT MATCHED THEN
  INSERT (channel_id, channel_handle, channel_title, channel_description, 
          join_date, is_sub_count_hidden, channel_keywords, profile_pic,
          is_active, added_by, created_at, updated_at)
  VALUES (S.channel_id, S.channel_handle, S.channel_title, S.channel_description, 
          DATE(S.join_date), S.is_sub_count_hidden, S.channel_keywords, S.profile_pic, 
          TRUE, 'ETL_Process_API', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());
