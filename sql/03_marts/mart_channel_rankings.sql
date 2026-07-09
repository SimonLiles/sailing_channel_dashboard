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
    
    prev_ranking and rank_change:
      Windowed metrics (30/90/180/365 days): compare current rank
        to rank at (snapshot_date - window_days).
      Lifetime metrics (window_days IS NULL): compare to previous
        day's snapshot.
      rank_change = prev_ranking - current_ranking
        (positive = moved up in rank).
   
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
  ),

  ranked AS (
    SELECT
      snapshot_date,
      channel_id,
      metric_name,
      window_days,
      cohort_type,
      cohort_value,
      metric_value,

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
  )

  -- Join with historical rankings to compute rank change
  SELECT
    r.snapshot_date,
    r.channel_id,
    r.metric_name,
    r.window_days,
    r.cohort_type,
    r.cohort_value,
    r.ranking,
    r.percentile,
    h.ranking AS prev_ranking,
    h.ranking - r.ranking AS rank_change
  FROM ranked r
  LEFT JOIN (
    SELECT * EXCEPT(rn) FROM (
      SELECT *,
        ROW_NUMBER() OVER (
          PARTITION BY snapshot_date, channel_id, metric_name,
                       window_days, cohort_type, cohort_value
        ) AS rn
      FROM `{{project}}.{{dataset}}.mart_channel_rankings`
    ) WHERE rn = 1
  ) h
    ON  h.channel_id    = r.channel_id
    AND h.metric_name   = r.metric_name
    AND h.window_days   IS NOT DISTINCT FROM r.window_days
    AND h.cohort_type   = r.cohort_type
    AND h.cohort_value  IS NOT DISTINCT FROM r.cohort_value
    AND h.snapshot_date = CASE
      WHEN r.window_days IS NOT NULL
        THEN DATE_SUB(r.snapshot_date, INTERVAL r.window_days DAY)
      ELSE DATE_SUB(r.snapshot_date, INTERVAL 1 DAY)
    END
) AS S

ON  T.snapshot_date = S.snapshot_date
AND T.channel_id    = S.channel_id
AND T.metric_name   = S.metric_name
AND T.window_days   IS NOT DISTINCT FROM S.window_days
AND T.cohort_type   = S.cohort_type
AND T.cohort_value  IS NOT DISTINCT FROM S.cohort_value

WHEN MATCHED AND (
  T.ranking       IS DISTINCT FROM S.ranking       OR
  T.percentile    IS DISTINCT FROM S.percentile    OR
  T.prev_ranking  IS DISTINCT FROM S.prev_ranking  OR
  T.rank_change   IS DISTINCT FROM S.rank_change
) THEN UPDATE SET
  T.ranking      = S.ranking,
  T.percentile   = S.percentile,
  T.prev_ranking = S.prev_ranking,
  T.rank_change  = S.rank_change,
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
  prev_ranking,
  rank_change,
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
  S.prev_ranking,
  S.rank_change,
  CURRENT_TIMESTAMP(),
  CURRENT_TIMESTAMP()
);
