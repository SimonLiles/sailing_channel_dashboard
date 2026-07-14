## ⛵ Sailing Channels: Data Pipeline & Analytics Dashboard

Live Dashboard: <https://sailing-creators.quantknot.com>

An automated end-to-end ETL pipeline and interactive dashboard monitoring over 1,200 curated YouTube channels within the sailing niche. This project identifies growth benchmarks and algorithmic trends using daily performance metrics.

## 🚀 The Mission

The "Sailing" niche is a unique segment of YouTube characterized by high engagement and specialized audiences. This project was built to move beyond surface-level metrics, uncovering the "Algorithmic Floor"—a power law function correlating subscriber counts to baseline views-per-video.

Key Features

-   Niche Pulse: High-level macro trends across the entire sector.
-   Creator Explorer: Deep-dive search functionality for individual channel performance.
-   Leaderboard: Dynamic ranking by 30-day view velocity and subscriber growth.
-   Growth Benchmarks: Data-driven insights into how the YouTube algorithm rewards different tiers of creators.

## 🏗 Architecture & Data Lineage

The system follows a Medallion Architecture (Raw → Staging → Marts → Apps) built entirely within Google BigQuery.

### Data Flow

``` mermaid
%%{init: {'theme': 'dark'}}%%

flowchart LR
    %% Define Subgraphs for Medallion Layers
    
    subgraph Layer_01_Raw ["01_Raw (Landing & History)"]
        direction TB
        Ingest[(raw_daily_ingest\n*Transient*)]
        Dim[(channel_dimensions\n*SCD Type 1*)]
        Hist[(daily_metrics_history\n*Partitioned Fact*)]
    end

    subgraph Layer_02_Staging ["02_Staging (Transform & Cast)"]
        direction TB
        StgView{{vw_stg_daily_metrics}}
    end

    subgraph Layer_03_Marts ["03_Marts (Business Logic)"]
        direction TB
        FctPerf[(fct_daily_performance)]
        MartMetrics[(mart_channel_metrics\n*Rolling Windows*)]
        MartValues[(mart_channel_metrics_values\n*Long-Format*)]
        MartCohorts[(mart_channel_cohorts\n*Buckets*)]
        MartRanks[(mart_channel_rankings\n*Rankings*)]
    end

    subgraph Layer_04_Apps ["04_Apps (Dashboard UI Serving)"]
        direction TB
        App1[(channel_lookup)]
        App2[(global_summary)]
        App3[(leaderboard_30d)]
        App4[(leaderboard)]
        App5([Channel Profile, Trend & History])
    end

    %% Define Data Flow Connections
    API_Source[YouTube API / R Script] --> Ingest
    
    Ingest -->|Raw Strings| StgView
    
    StgView -->|MERGE: Updates & Inserts| Dim
    StgView -->|INSERT: NOT EXISTS| Hist
    
    Hist -->|Window Functions & Lags| FctPerf
    
    FctPerf -->|Self-Join, Rolling Windows| MartMetrics
    FctPerf -->|UNPIVOT Snapshot Metrics| MartValues
    MartMetrics -->|UNPIVOT Window Metrics| MartValues
    MartMetrics -->|Bucket Channels| MartCohorts
    MartValues -->|INNER JOIN| MartRanks
    MartCohorts -->|INNER JOIN| MartRanks

    Dim -->|Active Channels| App1
    FctPerf -->|Latest Lifetime Stats| App1
    FctPerf -->|Daily Aggregates| App2
    FctPerf -->|Join w/ Dims, 30d Window| App3
    Dim -->|Channel Metadata| App3
    MartRanks -->|SELECT Latest Snapshot| App4
    MartValues -->|LEFT JOIN Metric Values| App4
    Dim -->|Filter by @id| App5
    FctPerf -->|Filter by @id| App5

    %% Styling
    classDef transient stroke:#333,stroke-width:2px,stroke-dasharray: 5 5;
    classDef permanent stroke:#28a745,stroke-width:2px;
    classDef view stroke:#007bff,stroke-width:2px;
    
    class Ingest transient;
    class Dim,Hist,FctPerf,MartMetrics,MartValues,MartCohorts,MartRanks,App1,App2,App3,App4 permanent;
    class StgView view;
```

### Data Model

The schema is optimized for time-series analysis of channel growth.

``` mermaid
%%{init: {'theme': 'dark'}}%%
erDiagram
    %% ====== 01_RAW ======
    RAW_DAILY_INGEST {
        STRING channel_id
        STRING channel_handle
        STRING title
        STRING view_count
        STRING subscriber_count
        STRING video_count
    }

    CHANNEL_DIMENSIONS {
        STRING channel_id PK
        STRING channel_handle "NOT NULL"
        BOOLEAN is_active "DEFAULT TRUE"
        STRING channel_title
        STRING channel_description
        DATE join_date
        BOOLEAN is_sub_count_hidden
        STRING channel_keywords
        STRING profile_pic
        STRING status
        STRING type
        STRING added_by
        TIMESTAMP created_at
        TIMESTAMP updated_at
    }

    DAILY_METRICS_HISTORY {
        STRING channel_id PK
        DATE date PK "partition key"
        INT64 view_count
        INT64 subscriber_count
        INT64 video_count
        TIMESTAMP created_at
    }

    %% ====== 02_STAGING ======
    VW_STG_DAILY_METRICS {
        STRING channel_id
        STRING channel_handle
        STRING channel_title
        DATE join_date
        INT64 view_count
        INT64 subscriber_count
        INT64 video_count
        BOOLEAN is_sub_count_hidden
    }

    %% ====== 03_MARTS ======
    FCT_DAILY_PERFORMANCE {
        STRING channel_id PK
        DATE date PK
        INT64 view_count
        INT64 video_count
        INT64 subscriber_count
        INT64 daily_new_views
        INT64 daily_new_subs
        INT64 daily_new_videos
        FLOAT64 lifetime_views_per_vid
        FLOAT64 lifetime_views_per_sub
        FLOAT64 lifetime_subs_per_vid
        FLOAT64 views_moving_avg_7d
        FLOAT64 sub_velocity_per_10k
    }

    MART_CHANNEL_METRICS {
        STRING channel_id PK
        DATE snapshot_date PK "partition key"
        INT64 window_days PK
        INT64 subscriber_count
        INT64 total_views_window
        INT64 total_subs_window
        FLOAT64 views_moving_avg_7d
        FLOAT64 sub_conversion_rate
        FLOAT64 views_per_vid_window
        FLOAT64 views_per_sub_window
    }

    MART_CHANNEL_METRICS_VALUES {
        DATE snapshot_date PK "partition key"
        STRING channel_id PK
        INT64 window_days PK
        STRING metric_name PK
        FLOAT64 metric_value
    }

    MART_CHANNEL_COHORTS {
        DATE snapshot_date PK "partition key"
        STRING channel_id PK
        STRING cohort_type PK
        STRING cohort_value
    }

    MART_CHANNEL_RANKINGS {
        DATE snapshot_date PK "partition key"
        STRING channel_id PK
        STRING metric_name PK
        INT64 window_days PK
        STRING cohort_type PK
        STRING cohort_value PK
        INT64 ranking
        INT64 percentile
    }

    %% ====== 04_APPS ======
    CHANNEL_LOOKUP {
        STRING channel_id PK
        STRING channel_title
        STRING channel_handle
        STRING profile_pic
        INT64 subscriber_count
        INT64 view_count
        INT64 video_count
    }

    GLOBAL_SUMMARY {
        DATE date PK
        INT64 latest_views
        INT64 latest_subs
        INT64 active_channels
        FLOAT64 avg_daily_views
        FLOAT64 avg_daily_subs
        FLOAT64 views_moving_avg_7d
        FLOAT64 view_growth_pct
    }

    LEADERBOARD {
        STRING channel_id PK
        STRING metric_name PK
        INT64 window_days PK
        STRING cohort_type PK
        STRING cohort_value PK
        FLOAT64 metric_value
        INT64 ranking
        INT64 percentile
    }

    %% ====== RELATIONSHIPS ======
    RAW_DAILY_INGEST ||--o{ VW_STG_DAILY_METRICS : "SELECT with casts"
    VW_STG_DAILY_METRICS ||--o{ CHANNEL_DIMENSIONS : "MERGE SCD Type 1"
    VW_STG_DAILY_METRICS ||--o{ DAILY_METRICS_HISTORY : "INSERT NOT EXISTS"
    DAILY_METRICS_HISTORY ||--o{ FCT_DAILY_PERFORMANCE : "window functions and LAG"
    FCT_DAILY_PERFORMANCE ||--o{ MART_CHANNEL_METRICS : "rolling windows"
    FCT_DAILY_PERFORMANCE ||--o{ MART_CHANNEL_METRICS_VALUES : "unpivot snapshot metrics"
    MART_CHANNEL_METRICS ||--o{ MART_CHANNEL_METRICS_VALUES : "unpivot window metrics"
    MART_CHANNEL_METRICS ||--o{ MART_CHANNEL_COHORTS : "bucket channels"
    MART_CHANNEL_METRICS_VALUES ||--o{ MART_CHANNEL_RANKINGS : "metric values"
    MART_CHANNEL_COHORTS ||--o{ MART_CHANNEL_RANKINGS : "cohort scoping"
    CHANNEL_DIMENSIONS ||--o{ CHANNEL_LOOKUP : "active channels"
    FCT_DAILY_PERFORMANCE ||--o{ CHANNEL_LOOKUP : "latest lifetime stats"
    FCT_DAILY_PERFORMANCE ||--o{ GLOBAL_SUMMARY : "daily aggregates"
    MART_CHANNEL_RANKINGS ||--o{ LEADERBOARD : "ranks and percentiles"
    MART_CHANNEL_METRICS_VALUES ||--o{ LEADERBOARD : "metric values"
```

## 🛠 Tech Stack

| Layer | Technology | Purpose |
|-------------------|------------------------------|-----------------------|
| Language | R (tidyverse, Shiny) | ETL Orchestration & UI Development |
| Database | Google BigQuery | Scalable data warehousing & SQL transformations |
| Compute | Google Cloud Run | Serverless execution of ETL and Shiny App |
| CI/CD | GitHub Actions | Automated testing and container deployment |
| Container | Docker | Environment parity across local and production |

## 📈 Key Insight: The Algorithmic Floor

By analyzing 1,000+ channels, the Growth Benchmarks page visualizes a power law relationship between subscriber base and views-per-video. This allows creators to see if they are performing above or below the "floor" for their specific size.

## 💻 Development & Deployment

### Local Setup

1.  Clone the repo.
2.  Ensure you have a service_account.json for GCP with BigQuery access.
3.  Use the provided Dockerfiles to build the environment:

``` bash
docker build -f etl/Dockerfile.etl -t yt-etl .
docker build -f shiny/Dockerfile.shiny -t yt-shiny .
```

### CI/CD Workflow

The project uses `.github/workflows/deploy.yml`, triggered on push to `main`. It runs 5 jobs in sequence:

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart LR
    test[test\nRun R unit tests] --> build-etl[build-etl\nBuild ETL image]
    test --> build-shiny[build-shiny\nBuild Shiny image]
    build-etl --> migrate[migrate\nSchema + Backfill]
    migrate --> deploy[deploy\nCloud Run]
    build-shiny --> deploy
```

| Job | What it does |
|-----|-------------|
| **test** | Runs R unit tests (`tests/testthat.R`) with `testthat` |
| **build-etl** | Builds `etl/Dockerfile.etl`, pushes to Artifact Registry with commit SHA + `latest` tags |
| **build-shiny** | Builds `shiny/Dockerfile.shiny`, pushes to Artifact Registry with commit SHA + `latest` tags |
| **migrate** | Pins ETL Cloud Run Job to the new image, takes a pre-migration dataset snapshot, runs `migrate_schema.R` (DDL + apps), backfills mart tables (2024-01-01 to today), rebuilds apps, runs initial ETL to warm GCS cache |
| **deploy** | Deploys Shiny to Cloud Run (`yt-sailing-shiny`, unauthenticated), updates ETL Cloud Run Job image |
