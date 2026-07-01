#!/usr/bin/env Rscript
# Idempotent schema migration for BigQuery mart + apps layers.
# Creates mart tables (if not exist), rebuilds fact table, rebuilds apps layer.
# Safe to re-run — all operations are CREATE TABLE IF NOT EXISTS or
# CREATE OR REPLACE, matching what the daily ETL already uses.
#
# Auth strategy (same pattern as shiny/global.R and etl/main.R):
#   ETL_ENV=production     → bq_auth() with no path (ADC / Workload Identity)
#   ETL_SERVICE_ACCOUNT_PATH set → authenticate with service account JSON
#   Neither set            → bq_auth() defaults (gargle discovery)
#
# Usage:
#   DATASET=yt_sailing_data ETL_ENV=production Rscript scripts/migrate_schema.R

library(bigrquery)
library(DBI)
library(glue)
library(here)

source(here("scripts", "bq_config.R"))
source(here("scripts", "run_sql.R"))

# Authenticate ----------------------------------------------------------------
if (Sys.getenv("ETL_ENV") == "production") {
  bq_auth()
} else {
  sa_path <- Sys.getenv("ETL_SERVICE_ACCOUNT_PATH", unset = NA)
  if (!is.na(sa_path)) bq_auth(path = here(sa_path))
}

project <- bq_project()
dataset <- bq_dataset()

con <- dbConnect(
  bigrquery::bigquery(),
  project = project,
  dataset = dataset,
  billing = project
)

message(glue("--- Migration target: {project}.{dataset} ---"))

# Step 1 — Create mart tables (idempotent: CREATE TABLE IF NOT EXISTS)
message("--- Step 1: Mart DDL ---")
run_sql_file(con, here("sql", "03_marts", "ddl", "create_mart_tables.sql"))

# Step 2 — Rebuild fact table (CREATE OR REPLACE — full refresh)
message("--- Step 2: fct_daily_performance ---")
run_sql_file(con, here("sql", "03_marts", "fct_daily_performance.sql"))

# Step 3 — Rebuild apps layer tables (CREATE OR REPLACE)
message("--- Step 3: Apps layer ---")
for (f in c("get_leaderboard.sql", "get_global_summary.sql", "get_channel_lookup.sql")) {
  run_sql_file(con, here("sql", "04_apps", f))
}

dbDisconnect(con)
message("--- Migration complete ---")
