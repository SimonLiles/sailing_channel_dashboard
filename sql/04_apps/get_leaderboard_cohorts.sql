SELECT DISTINCT cohort_type, cohort_value
FROM `{{project}}.{{dataset}}.mart_channel_cohorts`
WHERE snapshot_date = (
  SELECT MAX(snapshot_date)
  FROM `{{project}}.{{dataset}}.mart_channel_cohorts`
)
ORDER BY cohort_type, cohort_value
