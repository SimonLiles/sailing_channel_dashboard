/* ====================================================================
   Layer: 04_Apps
   Purpose: Count the total number of distinct channels that match the
            leaderboard filters. Used to calculate the total page count
            for pagination UI.

   Parameters:
     @cohort_type      STRING
     @cohort_value     STRING
     @rank_by_metric   STRING
     @window_days      INT64   (NULL for lifetime)
     @search_query     STRING  (NULL or '' for no search filter)
==================================================================== */

SELECT COUNT(DISTINCT r.channel_id) AS total_channels
FROM `{{project}}.{{dataset}}.mart_channel_rankings` r
INNER JOIN `{{project}}.{{dataset}}.channel_lookup` c
  ON r.channel_id = c.channel_id
WHERE r.snapshot_date = (
  SELECT MAX(snapshot_date)
  FROM `{{project}}.{{dataset}}.mart_channel_rankings`
)
  AND r.cohort_type = @cohort_type
  AND r.cohort_value = @cohort_value
  AND r.metric_name = @rank_by_metric
  AND r.window_days IS NOT DISTINCT FROM @window_days
  AND (@search_query IS NULL
    OR @search_query = ''
    OR LOWER(c.channel_title) LIKE '%' || LOWER(@search_query) || '%'
    OR LOWER(c.channel_handle) LIKE '%' || LOWER(@search_query) || '%')
