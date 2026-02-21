MERGE `yt-sailing-dashboard.yt_sailing_data.channel_dimensions` AS T
USING (
  SELECT DISTINCT 
    channel_id, channel_handle, channel_title, channel_description, join_date, 
    is_sub_count_hidden 
  FROM `yt-sailing-dashboard.yt_sailing_data.vw_stg_daily_metrics`
) AS S
ON T.channel_id = S.channel_id

-- UPDATE logic: Check if ANY field is different
WHEN MATCHED AND (
    T.channel_handle != S.channel_handle OR 
    T.channel_title != S.channel_title OR 
    T.channel_description != S.channel_description OR
    T.join_date != S.join_date OR 
    T.is_sub_count_hidden != S.is_sub_count_hidden
) THEN
  UPDATE SET 
    T.channel_handle = S.channel_handle,
    T.channel_title = S.channel_title,
    T.channel_description = S.channel_description,
    T.join_date = S.join_date,
    T.is_sub_count_hidden = S.is_sub_count_hidden,
    T.updated_at = CURRENT_TIMESTAMP()

-- INSERT logic: Brand new channel
WHEN NOT MATCHED THEN
  INSERT (channel_id, channel_handle, channel_title, channel_description, 
          join_date, is_sub_count_hidden,
          is_active, added_by, created_at, updated_at)
  VALUES (S.channel_id, S.channel_handle, S.channel_title, S.channel_description, 
          S.join_date, S.is_sub_count_hidden, 
          TRUE, 'ETL_Process_API', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());
