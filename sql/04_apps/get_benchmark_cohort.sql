SELECT channel_id, metric_name, metric_value, ranking, percentile
FROM `{{project}}.{{dataset}}.leaderboard`
WHERE cohort_type = @cohort_type
  AND cohort_value = @cohort_value
  AND (--WINDOW_CLAUSE--)
  AND (@exclude_metric IS NULL OR metric_name != @exclude_metric)
