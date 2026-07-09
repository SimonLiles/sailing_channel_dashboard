SELECT DISTINCT cohort_value
FROM `{{project}}.{{dataset}}.mart_channel_cohorts`
WHERE snapshot_date = (
  SELECT MAX(snapshot_date)
  FROM `{{project}}.{{dataset}}.mart_channel_cohorts`
)
  AND channel_id = @channel_id
  AND cohort_type = @cohort_type
ORDER BY cohort_value
LIMIT 1
