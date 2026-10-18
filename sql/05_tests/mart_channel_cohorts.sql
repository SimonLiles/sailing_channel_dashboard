-- ====================================================================
-- Layer: 05_Tests (SQLite sandbox port of 03_marts/mart_channel_cohorts.sql)
-- Purpose: Verifies the subscriber-count cohort bucket CASE assigns every
--   channel to exactly one bucket plus the global cohort, mirroring the
--   UNION ALL shape of the BigQuery MERGE source query.
-- Dialect: SQLite (sandbox only). The production mart file uses BigQuery
--   MERGE with {{project}}.{{dataset}} placeholders and @start_date /
--   @end_date params, which are intentionally NOT runnable here.
-- ====================================================================

-- Fixture: one snapshot of mart_channel_metrics spanning every bucket.
CREATE TABLE mart_channel_metrics (
  snapshot_date TEXT NOT NULL,
  channel_id TEXT NOT NULL,
  subscriber_count INTEGER
);

INSERT INTO mart_channel_metrics
  (snapshot_date, channel_id, subscriber_count)
VALUES
  ('2024-01-01', 'UC001', 500),
  ('2024-01-01', 'UC002', 5000),
  ('2024-01-01', 'UC003', 50000),
  ('2024-01-01', 'UC004', 250000),
  ('2024-01-01', 'UC005', 750000),
  ('2024-01-01', 'UC006', 5000000),
  ('2024-01-01', 'UC007', 20000000),
  ('2024-01-01', 'UC008', 15000);

-- Mart logic under test: global cohort plus subscriber-count buckets.
SELECT DISTINCT snapshot_date, channel_id,
  'global' AS cohort_type,
  'global' AS cohort_value
FROM mart_channel_metrics
UNION ALL
SELECT DISTINCT snapshot_date, channel_id,
  'subscriber_count' AS cohort_type,
  CASE
    WHEN subscriber_count < 1000 THEN '<1K'
    WHEN subscriber_count >= 1000 AND subscriber_count < 10000 THEN '1k- 10K'
    WHEN subscriber_count >= 10000 AND subscriber_count < 100000 THEN '10K - 100k'
    WHEN subscriber_count >= 100000 AND subscriber_count < 500000 THEN '100K - 500k'
    WHEN subscriber_count >= 500000 AND subscriber_count < 1000000 THEN '500K - 1M'
    WHEN subscriber_count >= 1000000 AND subscriber_count < 10000000 THEN '1M - 10M'
    ELSE '10M+'
  END AS cohort_value
FROM mart_channel_metrics;

-- expect-rows: 16
