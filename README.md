## ⛵ Sailing Channels: Data Pipeline & Analytics Dashboard

Live Dashboard: <https://sailing-creators.quantknot.com>

An automated end-to-end ETL pipeline and interactive dashboard monitoring 1,064 curated YouTube channels within the sailing niche. This project identifies growth benchmarks and algorithmic trends using daily performance metrics.

## 🚀 The Mission

The "Sailing" niche is a unique segment of YouTube characterized by high engagement and specialized audiences. This project was built to move beyond surface-level metrics, uncovering the "Algorithmic Floor"—a power law function correlating subscriber counts to baseline views-per-video.

Key Features

-   Niche Pulse: High-level macro trends across the entire sector.
-   Creator Explorer: Deep-dive search functionality for individual channel performance.
-   Leaderboard: Dynamic ranking by 30-day view velocity and subscriber growth.
-   Growth Benchmarks: Data-driven insights into how the YouTube algorithm rewards different tiers of creators.

## 🏗 Architecture & Data Lineage

The system follows a Medallion Architecture (Raw → Staging → Marts) built entirely within Google BigQuery.

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
    end

    subgraph Layer_04_Apps ["04_Apps (Dashboard UI Serving)"]
        direction TB
        App1([Global Summary])
        App2([30-Day Leaderboard])
        App3([Channel History & Trend])
    end

    %% Define Data Flow Connections
    API_Source[YouTube API / R Script] --> Ingest
    
    Ingest -->|Raw Strings| StgView
    
    StgView -->|MERGE: Updates & Inserts| Dim
    StgView -->|INSERT: NOT EXISTS| Hist
    
    Hist -->|Window Functions & Lags| FctPerf
    
    FctPerf -->|Aggregate| App1
    FctPerf -->|Join w/ Dims| App2
    FctPerf -->|Filter by @id| App3
    Dim --> App2
    Dim -->|Filter by @id| App3

    %% Styling
    classDef transient stroke:#333,stroke-width:2px,stroke-dasharray: 5 5;
    classDef permanent stroke:#28a745,stroke-width:2px;
    classDef view stroke:#007bff,stroke-width:2px;
    
    class Ingest transient;
    class Dim,Hist,FctPerf permanent;
    class StgView view;
```

### Data Model

The schema is optimized for time-series analysis of channel growth.

``` mermaid
%%{init: {'theme': 'dark'}}%%
erDiagram
    %% Entities and Attributes
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
        STRING added_by
        TIMESTAMP created_at
        TIMESTAMP updated_at
    }

    DAILY_METRICS_HISTORY {
        STRING channel_id PK, FK
        DATE date PK
        INT64 view_count
        INT64 subscriber_count
        INT64 video_count
        TIMESTAMP created_at
    }

    FCT_DAILY_PERFORMANCE {
        STRING channel_id PK, FK
        DATE date PK
        INT64 view_count
        INT64 video_count
        INT64 subscriber_count
        INT64 daily_new_views
        INT64 daily_new_subs
        FLOAT64 lifetime_views_per_vid
        FLOAT64 lifetime_views_per_sub
        FLOAT64 lifetime_subs_per_vid
        FLOAT64 views_moving_avg_7d
        FLOAT64 sub_velocity_per_10k
    }

    %% Relationships
    CHANNEL_DIMENSIONS ||--o{ DAILY_METRICS_HISTORY : "tracks daily metrics for"
    CHANNEL_DIMENSIONS ||--o{ FCT_DAILY_PERFORMANCE : "calculates performance for"
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

Local Setup

1.  Clone the repo.
2.  Ensure you have a service_account.json for GCP with BigQuery access.
3.  Use the provided Dockerfiles to build the environment:

``` bash
docker build -f etl/Dockerfile.etl -t yt-etl .
docker build -f shiny/Dockerfile.shiny -t yt-shiny .
```

### CI/CD Workflow

The project uses a deploy.yml GitHub Action to:

1.  Run R unit tests on the ETL logic.
2.  Build Docker images for the Writer (ETL) and Reader (Shiny).
3.  Push images to GCP Artifact Registry.
4.  Deploy to Cloud Run services automatically on merge to main.
