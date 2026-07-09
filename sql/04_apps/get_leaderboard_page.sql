/* ====================================================================
   Layer: 04_Apps
   Purpose: Return exactly one page of leaderboard rows using keyset
            pagination. Uses two steps:
              1. Find the channel_ids on the requested page, ordered
                 by the rank-by metric's ranking (with channel_id as
                 tiebreaker).
              2. Fetch all selected metrics for those channel_ids.

   Template placeholders:
     --METRIC_NAMES--     Quoted, comma-separated list of metric names
     --WINDOW_CLAUSE--    window_days filter (e.g. "window_days = 30
                          OR window_days IS NULL")
      --CURSOR_CONDITION-- Keyset WHERE clause, or "TRUE" for first page
      --ORDER_DIRECTION--  "ASC" for forward, "DESC" for backward
      --PAGE_SIZE--        Number of rows per page (inlined literal)

    Parameters:
      @cohort_type       STRING
      @cohort_value      STRING
      @rank_by_metric    STRING
      @window_days       INT64   (NULL for lifetime)
      @cursor_ranking    INT64   (NULL for first page)
      @cursor_channel_id STRING  (NULL for first page)
      @search_query      STRING  (NULL or '' for no search filter)
==================================================================== */

WITH matching_channels AS (
  SELECT channel_id
  FROM `{{project}}.{{dataset}}.channel_lookup`
  WHERE @search_query IS NULL
     OR @search_query = ''
     OR LOWER(channel_title) LIKE '%' || LOWER(@search_query) || '%'
     OR LOWER(channel_handle) LIKE '%' || LOWER(@search_query) || '%'
),

page_channel_ids AS (
  SELECT
    r.channel_id,
    r.ranking,
    r.percentile,
    r.prev_ranking,
    r.rank_change
  FROM `{{project}}.{{dataset}}.mart_channel_rankings` r
  INNER JOIN matching_channels mc
    ON r.channel_id = mc.channel_id
  WHERE r.snapshot_date = (
    SELECT MAX(snapshot_date)
    FROM `{{project}}.{{dataset}}.mart_channel_rankings`
  )
    AND r.cohort_type = @cohort_type
    AND r.cohort_value = @cohort_value
    AND r.metric_name = @rank_by_metric
    AND r.window_days IS NOT DISTINCT FROM @window_days
    AND (--CURSOR_CONDITION--)
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY r.channel_id
    ORDER BY r.ranking, r.channel_id
  ) = 1
  ORDER BY r.ranking --ORDER_DIRECTION--, r.channel_id --ORDER_DIRECTION--
  LIMIT --PAGE_SIZE--
)

SELECT
  r.channel_id,
  r.metric_name,
  r.window_days,
  r.cohort_type,
  r.cohort_value,
  v.metric_value,
  r.ranking,
  r.percentile,
  r.prev_ranking,
  r.rank_change
FROM `{{project}}.{{dataset}}.mart_channel_rankings` r
LEFT JOIN `{{project}}.{{dataset}}.mart_channel_metrics_values` v
  ON r.snapshot_date = v.snapshot_date
  AND r.channel_id = v.channel_id
  AND r.metric_name = v.metric_name
  AND r.window_days IS NOT DISTINCT FROM v.window_days
WHERE r.snapshot_date = (
  SELECT MAX(snapshot_date)
  FROM `{{project}}.{{dataset}}.mart_channel_rankings`
)
  AND r.channel_id IN (SELECT channel_id FROM page_channel_ids)
  AND r.cohort_type = @cohort_type
  AND r.cohort_value = @cohort_value
  AND r.metric_name IN (--METRIC_NAMES--)
  AND (--WINDOW_CLAUSE--)
