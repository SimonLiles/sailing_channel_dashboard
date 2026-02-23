SELECT 
    channel_id, 
    channel_title, 
    channel_handle, 
    profile_pic
FROM `yt-sailing-dashboard.yt_sailing_data.channel_dimensions`
WHERE is_active = TRUE
ORDER BY channel_title ASC;