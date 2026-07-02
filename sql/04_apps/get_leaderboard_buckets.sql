SELECT DISTINCT cohort_value
FROM `{{project}}.{{dataset}}.leaderboard`
WHERE cohort_type = @cohort_type
ORDER BY cohort_value
