SELECT DISTINCT cohort_value
FROM `{{project}}.{{dataset}}.leaderboard`
WHERE channel_id = @channel_id
  AND cohort_type = @cohort_type
ORDER BY cohort_value
LIMIT 1
