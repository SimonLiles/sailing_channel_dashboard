/* ====================================================================
   Layer: 01_Raw (DDL)
   Purpose: Defines the structure for the landing zones and history tables.
   Dialect: Google BigQuery Standard SQL
==================================================================== */

-- 1. The Transient Ingest Table (Overwritten daily by the ETL R script)
-- Everything is a STRING to prevent API type-mismatch crashes.
CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.raw_daily_ingest` (
    channel_id STRING,
    channel_handle STRING,
    title STRING,
    description STRING,
    join_date STRING,
    view_count STRING,
    subscriber_count STRING,
    video_count STRING, 
    is_sub_count_hidden STRING,
    channel_keywords STRING,
    profile_pic STRING
);

-- 2. The Permanent Dimension Table (The "Master List")
CREATE TABLE IF NOT EXISTS `{{project}}.{{dataset}}.channel_dimensions` (
    channel_id STRING NOT NULL,
    channel_handle STRING NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    channel_title STRING,
    channel_description STRING,
    join_date DATE,
    is_sub_count_hidden BOOLEAN,
    channel_keywords STRING,
    profile_pic STRING,
    status STRING,
    type STRING,
    added_by STRING,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

-- 3. The Permanent Fact History Table
-- This is where the clean data from Staging finally lands.
CREATE TABLE IF NOT EXISTS `{{project}}.{{dataset}}.daily_metrics_history` (
    channel_id STRING NOT NULL,
    date DATE NOT NULL,
    view_count INT64,
    subscriber_count INT64,
    video_count INT64,
    created_at TIMESTAMP
)
PARTITION BY date;