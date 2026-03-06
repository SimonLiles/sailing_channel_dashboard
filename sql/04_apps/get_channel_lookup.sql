/* ====================================================================
   Layer: 04_Apps
   Purpose: Provide lookup table for all active hannels
   Logic: 
    - Retrieve identifying channel dimenions for active channels.
==================================================================== */
CREATE OR REPLACE TABLE `yt-sailing-dashboard.yt_sailing_data.channel_loookup` AS
SELECT 
  channel_id, 
  channel_title, 
  channel_handle, 
  profile_pic
FROM `yt-sailing-dashboard.yt_sailing_data.channel_dimensions`
WHERE is_active = TRUE
ORDER BY channel_title ASC;