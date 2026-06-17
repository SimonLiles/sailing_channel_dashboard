/* ====================================================================
   Layer: 03_Marts
   Purpose: Calculate ranks for KPIs for the Shiny Dashboard.
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
==================================================================== */
DECLARE start_date DATE;
DECLARE end_date DATE;

-- Join the metric values table with the cohorts before trying to do the ranking
WITH combined_metrics_cohorts AS (

SELECT
  m.snapshot_date,
  m.channel_id,
  m.metric_name,
  m.metric_value,
  m.window_days,
  c.cohort_type,
  c.cohort_value

FROM `yt-sailing-dashboard.yt_sailing_data.mart_channel_metrics_values` as m

INNER JOIN
  `yt-sailing-dashboard.yt_sailing_data.vw_channel_metrics_values` as c
  ON m.snapshot_date = c.snapshot_date AND m.channel_id = c.channel_id;

)

SELECT
  snapshot_date,
  
  channel_id,
  
  metric_name,
  window_days,
  
  scope_type,
  scope_value

  DENSE_RANK() OVER (
    PARTITION BY
      snapshot_date,
      
      scope_type, 
      scope_value,
      
      metric_name
    ORDER BY metric_value DESC
  ) AS rank
  
  percentile
FROM combined_metrics_cohorts

WHERE snapshot_date BETWEEN start_date AND end_date

