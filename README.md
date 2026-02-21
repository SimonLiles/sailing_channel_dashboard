# YouTube Sailing Niche Analytics Dashboard 
A production-grade data pipeline and interactive dashboard tracking performance metrics for YouTube creators in the sailing space.

## 🏗 Architecture Overview This project demonstrates a modern "Cloud-Native" approach to data science, prioritizing the separation of concerns, data security, and computational efficiency.

Orchestration: R-based ETL containerized with Docker and executed via Google Cloud Run Jobs, scheduled with Cloud Scheduler.

Data Warehouse: Google BigQuery serves as the analytical engine.

Transformation Layer: A "SQL Pushdown" strategy where complex analytical metrics (rolling averages, growth rates) are calculated within BigQuery using Window Functions and CTEs, rather than in the application layer.

UI Layer: An R Shiny dashboard containerized and hosted on Google Cloud Run, providing a high-performance interface for end-users.

## 🔐 Security & Identity Following the Principle of Least Privilege, this architecture utilizes two distinct GCP Service Accounts:

etl-writer: Granted BigQuery Data Editor permissions to write raw and transformed data.

shiny-reader: Granted strictly BigQuery Data Viewer permissions, ensuring the dashboard environment cannot modify the underlying warehouse. Note: Authentication is handled via Identity-based Service Accounts attached to Cloud Run, avoiding the use of local JSON key files in production.

## 📈 The "SQL Pushdown" Strategy To ensure the dashboard remains "snappy" as the dataset grows (currently adding \~1k rows/day), all heavy math is handled by BigQuery.

Example of the pre-calculated metrics in the fct_daily_stats table:

Subscribers per Video: Calculated as SubsPerVideo= Videos Subscribers ​\
to normalize channel size.

7-Day Rolling Average: Smooths out daily volatility in creator uploads to show true performance trends.

WoW Growth: Calculates Week-over-Week changes in viewership using SQL LAG() window functions.

## 📁 Repository Structure
```
├── etl/
│   ├── main.R            # YouTube API orchestration logic
│   └── Dockerfile.etl    # Writer image configuration
├── shiny/
│   ├── app.R             # UI and Server logic
│   └── Dockerfile.shiny  # Reader image configuration
├── sql/
│   ├── schema_setup.sql  # Initial DDL
│   └── transformations.sql # MERGE and Window Function logic
└── cloud_deploy.sh       # GCP deployment automation
```
