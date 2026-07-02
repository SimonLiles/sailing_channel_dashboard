SELECT *
FROM `{{project}}.{{dataset}}.leaderboard`
WHERE cohort_type = @cohort_type
  AND cohort_value = @cohort_value
  AND metric_name IN (--METRIC_NAMES--)
  AND (--WINDOW_CLAUSE--)
