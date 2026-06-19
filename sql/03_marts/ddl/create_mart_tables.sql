/* ====================================================================
   Layer: 03_Marts (DDL)
   Purpose: Defines the structure for incrementally maintained mart tables.
   Dialect: Google BigQuery Standard SQL
==================================================================== */

-- 1. Rolling-Window Channel Metric Snapshots
-- Composite key: channel_id + snapshot_date + window_days
-- Populated incrementally via MERGE in mart_channel_metrics.sql
CREATE TABLE IF NOT EXISTS `{{project}}.{{dataset}}.mart_channel_metrics` (
    channel_id STRING NOT NULL,
    snapshot_date DATE NOT NULL,
    window_days INT64 NOT NULL,
    subscriber_count INT64,
    view_count INT64,
    video_count INT64,
    total_views_window INT64,
    total_subs_window INT64,
    new_videos_window INT64,
    views_moving_avg_7d FLOAT64,
    sub_conversion_rate FLOAT64,
    daily_new_subs INT64,
    subs_pct_growth FLOAT64,
    lifetime_views_per_vid FLOAT64,
    views_per_vid_window FLOAT64,
    views_per_sub_window FLOAT64,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
)
PARTITION BY snapshot_date;

-- 2. Long-Format Channel Metric Values
-- Composite key: channel_id + snapshot_date + window_days + metric_name
-- Populated incrementally via MERGE in mart_channel_metrics_values.sql
CREATE TABLE IF NOT EXISTS `{{project}}.{{dataset}}.mart_channel_metrics_values` (
    snapshot_date DATE NOT NULL,
    channel_id STRING NOT NULL,
    window_days INT64,
    metric_name STRING NOT NULL,
    metric_value FLOAT64,
    updated_at TIMESTAMP
)
PARTITION BY snapshot_date;

-- 3. Channel Cohort Assignments
-- Composite key: snapshot_date + channel_id + cohort_type
-- Populated incrementally via MERGE in mart_channel_cohorts.sql
CREATE TABLE IF NOT EXISTS `{{project}}.{{dataset}}.mart_channel_cohorts` (
    snapshot_date DATE NOT NULL,
    channel_id STRING NOT NULL,
    cohort_type STRING NOT NULL,
    cohort_value STRING,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
)
PARTITION BY snapshot_date;
