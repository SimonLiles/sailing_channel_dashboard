/* ====================================================================
   Layer: 03_Marts
   Purpose: Calculate ranks for KPIs for the Shiny Dashboard.
            Incrementally built via MERGE, supports backfill via
            start_date/end_date procedure parameters.
   
   Logic: 
    - 30 Day total views:
    - 30 Day total new subscribers:
    - 30 Day total of new videos:
    - 7 Day Rolling average of new views: This is just a capture of the 
      most recent snapshot.
      
    - Sub Conversion Rate: 30 Day rate of new subscriptions per 1000 views.
    - 30 Day Percent Growth in Subscribers: Subscriber growth as % of total 
      subscriber base.
    - Lifetime Views per Video: Lifetime Average Catalog Yield.
    - 30 Day Views per Video: 30 Day catalog yield.
    - 30 Day Views per Subscriber: 30 Day Audience Activation.
    
   Composite Key: snapshot_date + channel_id + metric_name + window_days
                  + cohort_type + cohort_value
   
   Match Behavior: UPDATE only when rank or percentile has drifted
                   (e.g. a late-arriving row corrects a prior snapshot).
   
   Parameters (passed by calling procedure):
     @start_date DATE -- First snapshot_date to process
     @end_date   DATE -- Last snapshot_date to process
==================================================================== */
MERGE `{{project}}.{{dataset}}.mart_channel_rankings` AS T

USING (
  -- Join the metric values table with the cohorts before ranking
  WITH combined_metrics_cohorts AS (
    SELECT
      m.snapshot_date,
      m.channel_id,
      m.metric_name,
      m.metric_value,
      m.window_days,
      c.cohort_type,
      c.cohort_value
    
    FROM `{{project}}.{{dataset}}.mart_channel_metrics_values` AS m
    
    INNER JOIN
      `{{project}}.{{dataset}}.mart_channel_cohorts` AS c
      ON m.snapshot_date = c.snapshot_date AND m.channel_id = c.channel_id
  )

  SELECT
    snapshot_date,
    
    channel_id,
    
    metric_name,
    window_days,
    
    cohort_type,
    cohort_value,

    DENSE_RANK() OVER (
      PARTITION BY
        snapshot_date,
        
        cohort_type, 
        cohort_value,
        
        metric_name,
        window_days
      ORDER BY metric_value DESC
    ) AS ranking,
    
    CAST(ROUND(
      (1 - PERCENT_RANK() OVER (
        PARTITION BY
        snapshot_date,
        
        cohort_type, 
        cohort_value,
        
        metric_name,
        window_days
      ORDER BY metric_value DESC
      )) * 100
    ) AS INT64) AS percentile

  FROM combined_metrics_cohorts

  WHERE snapshot_date BETWEEN @start_date AND @end_date
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY
      snapshot_date,
      channel_id,
      metric_name,
      window_days,
      cohort_type,
      cohort_value
    ORDER BY metric_value DESC
  ) = 1
) AS S

ON  T.snapshot_date = S.snapshot_date
AND T.channel_id    = S.channel_id
AND T.metric_name   = S.metric_name
AND T.window_days   IS NOT DISTINCT FROM S.window_days
AND T.cohort_type   = S.cohort_type
AND T.cohort_value  IS NOT DISTINCT FROM S.cohort_value

WHEN MATCHED AND (
  T.ranking       IS DISTINCT FROM S.ranking       OR
  T.percentile   IS DISTINCT FROM S.percentile
) THEN UPDATE SET
  T.ranking       = S.ranking,
  T.percentile   = S.percentile,
  T.updated_at   = CURRENT_TIMESTAMP()

WHEN NOT MATCHED THEN INSERT (
  snapshot_date,
  channel_id,
  metric_name,
  window_days,
  cohort_type,
  cohort_value,
  ranking,
  percentile,
  created_at,
  updated_at
) VALUES (
  S.snapshot_date,
  S.channel_id,
  S.metric_name,
  S.window_days,
  S.cohort_type,
  S.cohort_value,
  S.ranking,
  S.percentile,
  CURRENT_TIMESTAMP(),
  CURRENT_TIMESTAMP()
);

