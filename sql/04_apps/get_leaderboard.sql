/* ====================================================================
   Layer: 04_Apps
   Purpose: Build a long-format leaderboard from the latest mart snapshot.
             Each row is one (channel × metric × window × cohort) combo.
             Includes rank change (Δ) compared to the start of the
             selected window so the Shiny app can show upward/downward
             movement arrows.

   Downstream: Downloaded to R by the ETL and cached to GCS as an RDS.
                The Shiny report builder filters/pivots this long table
                into the viewer's chosen view.

   Depends on: mart_channel_rankings (MERGE'd during ETL run)
                mart_channel_metrics_values (MERGE'd during ETL run)
                Both must be up-to-date for the latest snapshot_date.

   Rank change logic:
     - Windowed metrics (30/90/180/365 days): compare current rank
       to rank at (latest_snapshot - window_days).
     - Lifetime metrics (window_days IS NULL): compare to previous
       day's snapshot.
     - rank_change = prev_ranking - current_ranking
       (positive = moved up in rank).
   ==================================================================== */

CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.leaderboard` AS

WITH latest_snapshot AS (
  SELECT MAX(snapshot_date) AS snapshot_date
  FROM `{{project}}.{{dataset}}.mart_channel_rankings`
),

-- Current rankings with metric values and historical target date
current_rankings AS (
  SELECT
    r.channel_id,
    r.metric_name,
    r.window_days,
    r.cohort_type,
    r.cohort_value,
    v.metric_value,
    r.ranking,
    r.percentile,
    CASE
      WHEN r.window_days IS NOT NULL
        THEN DATE_SUB(l.snapshot_date, INTERVAL r.window_days DAY)
      ELSE DATE_SUB(l.snapshot_date, INTERVAL 1 DAY)
    END AS historical_target_date
  FROM `{{project}}.{{dataset}}.mart_channel_rankings` AS r
  CROSS JOIN latest_snapshot l
  LEFT JOIN `{{project}}.{{dataset}}.mart_channel_metrics_values` AS v
    ON r.snapshot_date = v.snapshot_date
    AND r.channel_id   = v.channel_id
    AND r.metric_name  = v.metric_name
    AND r.window_days  IS NOT DISTINCT FROM v.window_days
  WHERE r.snapshot_date = l.snapshot_date
),

-- Nearest available snapshot_date at or before each target date
-- (handles gaps where the ETL did not run on a given day)
historical_snapshot_dates AS (
  SELECT
    c.metric_name,
    c.window_days,
    c.cohort_type,
    c.cohort_value,
    MAX(h.snapshot_date) AS historical_snapshot_date
  FROM current_rankings c
  LEFT JOIN `{{project}}.{{dataset}}.mart_channel_rankings` h
    ON c.metric_name  = h.metric_name
    AND c.window_days IS NOT DISTINCT FROM h.window_days
    AND c.cohort_type = h.cohort_type
    AND c.cohort_value IS NOT DISTINCT FROM h.cohort_value
    AND h.snapshot_date <= c.historical_target_date
  GROUP BY
    c.metric_name,
    c.window_days,
    c.cohort_type,
    c.cohort_value
)

SELECT
  c.channel_id,
  c.metric_name,
  c.window_days,
  c.cohort_type,
  c.cohort_value,
  c.metric_value,
  c.ranking,
  c.percentile,
  h.ranking AS prev_ranking,
  h.ranking - c.ranking AS rank_change
FROM current_rankings c
LEFT JOIN historical_snapshot_dates hs
  ON c.metric_name  = hs.metric_name
  AND c.window_days IS NOT DISTINCT FROM hs.window_days
  AND c.cohort_type = hs.cohort_type
  AND c.cohort_value IS NOT DISTINCT FROM hs.cohort_value
LEFT JOIN `{{project}}.{{dataset}}.mart_channel_rankings` h
  ON c.channel_id   = h.channel_id
  AND c.metric_name = h.metric_name
  AND c.window_days IS NOT DISTINCT FROM h.window_days
  AND c.cohort_type = h.cohort_type
  AND c.cohort_value IS NOT DISTINCT FROM h.cohort_value
  AND h.snapshot_date = hs.historical_snapshot_date;
