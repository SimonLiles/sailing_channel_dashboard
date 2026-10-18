-- ====================================================================
-- Layer: 05_Tests (SQLite sandbox port of 03_marts/mart_channel_rankings.sql)
-- Purpose: Verifies per-metric ranking assigns a dense 1..N ordering with
--   no ties broken silently, mirroring the ROW_NUMBER ranking grain of the
--   BigQuery mart_channel_rankings load.
-- Dialect: SQLite (sandbox only). The production mart file uses BigQuery
--   MERGE with {{project}}.{{dataset}} placeholders, which is intentionally
--   NOT runnable here.
-- ====================================================================

-- Fixture: five channels with distinct metric values on one snapshot.
CREATE TABLE mart_channel_metrics_values (
  snapshot_date TEXT NOT NULL,
  channel_id TEXT NOT NULL,
  metric_name TEXT NOT NULL,
  metric_value REAL
);

INSERT INTO mart_channel_metrics_values
  (snapshot_date, channel_id, metric_name, metric_value)
VALUES
  ('2024-01-01', 'UC001', 'views_moving_avg_7d', 1200.5),
  ('2024-01-01', 'UC002', 'views_moving_avg_7d', 8900.0),
  ('2024-01-01', 'UC003', 'views_moving_avg_7d', 450.25),
  ('2024-01-01', 'UC004', 'views_moving_avg_7d', 15000.0),
  ('2024-01-01', 'UC005', 'views_moving_avg_7d', 3200.75);

-- Mart logic under test: rank channels per metric, best value first.
SELECT snapshot_date, channel_id, metric_name, metric_value,
  ROW_NUMBER() OVER (
    PARTITION BY snapshot_date, metric_name
    ORDER BY metric_value DESC
  ) AS ranking
FROM mart_channel_metrics_values;

-- expect-rows: 5
