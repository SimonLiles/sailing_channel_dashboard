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

   Performance note: Historical snapshots are determined solely by
   window_days (only ~5 distinct values). We filter historical
   rankings by a small IN-list of dates rather than using a
   non-equi join (<=), which would explode across every (channel,
   metric, cohort) group.
   ==================================================================== */

CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.leaderboard` AS

WITH latest_snapshot AS (
  SELECT MAX(snapshot_date) AS snapshot_date
  FROM `{{project}}.{{dataset}}.mart_channel_rankings`
),

-- Current rankings (latest snapshot only, with metric values)
current_rankings AS (
  SELECT
    r.channel_id,
    r.metric_name,
    r.window_days,
    r.cohort_type,
    r.cohort_value,
    v.metric_value,
    r.ranking,
    r.percentile
  FROM `{{project}}.{{dataset}}.mart_channel_rankings` AS r
  CROSS JOIN latest_snapshot l
  LEFT JOIN `{{project}}.{{dataset}}.mart_channel_metrics_values` AS v
    ON r.snapshot_date = v.snapshot_date
    AND r.channel_id   = v.channel_id
    AND r.metric_name  = v.metric_name
    AND r.window_days  IS NOT DISTINCT FROM v.window_days
  WHERE r.snapshot_date = l.snapshot_date
),

-- Historical rankings at the target date for each distinct window_days.
-- Historical snapshot dates are the same for ALL channels in a given
-- window period, so we only need one target date per window_days value.
historical_rankings AS (
  SELECT
    r.channel_id,
    r.metric_name,
    r.window_days,
    r.cohort_type,
    r.cohort_value,
    r.ranking AS prev_ranking
  FROM `{{project}}.{{dataset}}.mart_channel_rankings` r
  WHERE r.snapshot_date IN (
    SELECT DISTINCT
      CASE
        WHEN window_days IS NOT NULL
          THEN DATE_SUB((SELECT snapshot_date FROM latest_snapshot),
                        INTERVAL window_days DAY)
        ELSE DATE_SUB((SELECT snapshot_date FROM latest_snapshot),
                      INTERVAL 1 DAY)
      END
    FROM current_rankings
  )
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
  h.prev_ranking,
  h.prev_ranking - c.ranking AS rank_change
FROM current_rankings c
LEFT JOIN historical_rankings h
  ON c.channel_id   = h.channel_id
  AND c.metric_name = h.metric_name
  AND c.window_days IS NOT DISTINCT FROM h.window_days
  AND c.cohort_type = h.cohort_type
  AND c.cohort_value IS NOT DISTINCT FROM h.cohort_value;
