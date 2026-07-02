SELECT DISTINCT cohort_type, cohort_value
FROM `{{project}}.{{dataset}}.leaderboard`
ORDER BY cohort_type, cohort_value
