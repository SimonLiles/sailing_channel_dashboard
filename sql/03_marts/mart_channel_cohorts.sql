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
DECLARE start_date DATE;
DECLARE end_date DATE;

MERGE `{{project}}.{{dataset}}.mart_channel_cohorts` AS T

USING (
  -- Global Cohort
  SELECT
    snapshot_date,
    channel_id,
    'global' AS cohort_type,
    'global' AS cohort_value
  FROM `{{project}}.{{dataset}}.mart_channel_metrics_30d`
  WHERE snapshot_date BETWEEN @start_date AND @end_date

  UNION ALL

  -- Subscriber Count Cohorts
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
  FROM `{{project}}.{{dataset}}.mart_channel_metrics_30d`
  WHERE snapshot_date BETWEEN @start_date AND @end_date

) AS S

ON  T.snapshot_date = S.snapshot_date
AND T.channel_id    = S.channel_id
AND T.cohort_type   = S.cohort_type

WHEN MATCHED AND (
  T.cohort_value IS DISTINCT FROM S.cohort_value
) THEN UPDATE SET
  T.cohort_value = S.cohort_value,
  T.updated_at   = CURRENT_TIMESTAMP()

WHEN NOT MATCHED THEN INSERT (
  snapshot_date,
  channel_id,
  cohort_type,
  cohort_value,
  created_at,
  updated_at
) VALUES (
  S.snapshot_date,
  S.channel_id,
  S.cohort_type,
  S.cohort_value,
  CURRENT_TIMESTAMP(),
  CURRENT_TIMESTAMP()
);
