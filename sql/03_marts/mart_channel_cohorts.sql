/* ====================================================================
   Layer: 03_Marts
   Purpose: Assign cohort values for every channel for descriptive metrics
   Logic: 
    - Global: simple label applied to all channels to mark the global
      scope for ranking. 
    - Subscriber Count: Bucket channels based on subscriber count using 
      power law rules. 
    - Video Count: Bucket Channels based on size of content catalog. 
    - Channel Age: Bucket Based on how long the channel has been around.
    - Lifetime View Count: Bucket based on lifetime views. 
    - Upload Frequency: Bucket based on montlhy or weekly frequency 
      of uploads. 
    - Content Category: This label may exist in the channel dimensions,
      it is forwarded here. 
    - Geography: New label thet likely will live in channel dimensions.
==================================================================== */

SELECT
  snapshot_date,
  channel_id,
  
  'global' AS cohort_type,
  
  'global' AS cohort_value
  
FROM `yt-sailing-dashboard.yt_sailing_data.mart_channel_metrics_30d`

UNION ALL

SELECT
  snapshot_date,
  channel_id,
  
  'subscriber_count' AS cohort_type,
  
  CASE
    WHEN subscriber_count <  1000 THEN '<1K'
    WHEN subscriber_count >= 1000    AND subscriber_count < 10000    THEN '1k- 10K'
    WHEN subscriber_count >= 10000   AND subscriber_count < 100000   THEN '10K - 100k'
    WHEN subscriber_count >= 100000  AND subscriber_count < 500000   THEN '100K - 500k'
    WHEN subscriber_count >= 500000  AND subscriber_count < 1000000  THEN '500K - 1M'
    WHEN subscriber_count >= 1000000 AND subscriber_count < 10000000 THEN '1M - 10M'
    ELSE '10M+'
  END AS cohort_value
  
FROM `yt-sailing-dashboard.yt_sailing_data.mart_channel_metrics_30d;