/* ====================================================================
   Layer: 04_Apps
   Purpose: Build a long-format leaderboard from the latest mart snapshot.
            Replaces the old leaderboard_30d (wide, single-window) with
            a multi-window, cohort-scoped, metric-oriented table.
            Each row is one (channel × metric × window × cohort) combo.

   Downstream: Downloaded to R by the ETL and cached to GCS as an RDS.
               The Shiny report builder filters/pivots this long table
               into the viewer's chosen view.

   Depends on: mart_channel_rankings (MERGE'd during ETL run)
               mart_channel_metrics_values (MERGE'd during ETL run)
               Both must be up-to-date for the latest snapshot_date.
   ==================================================================== */

CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.leaderboard` AS

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
LEFT JOIN `{{project}}.{{dataset}}.mart_channel_metrics_values` AS v
  ON r.snapshot_date = v.snapshot_date
  AND r.channel_id    = v.channel_id
  AND r.metric_name   = v.metric_name
  AND r.window_days   IS NOT DISTINCT FROM v.window_days

WHERE r.snapshot_date = (
  SELECT MAX(snapshot_date)
  FROM `{{project}}.{{dataset}}.mart_channel_rankings`
);
