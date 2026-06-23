#!/usr/bin/env Rscript
# Backfill mart tables for a given date range.
#
# Usage:
#   Rscript scripts/backfill_marts.R \
#     --start_date=2024-01-01 \
#     --end_date=2024-12-31 \
#     [--window_days=30,90,180,365] \
#     [--rebuild_fct=TRUE]

require(bigrquery)
require(DBI)
require(glue)
require(here)

source(here("scripts", "config.R"))
source(here("scripts", "bq_config.R"))
source(here("scripts", "run_sql.R"))

# -------------------------------------------------------------------
# 0. Parse command-line arguments
# -------------------------------------------------------------------
parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  defaults <- list(
    start_date  = NULL,
    end_date    = NULL,
    window_days = config_get("window_days", 30),
    rebuild_fct = TRUE
  )

  parsed <- defaults
  for (arg in args) {
    kv <- strsplit(arg, "=", fixed = TRUE)[[1]]
    if (length(kv) == 2) {
      key <- gsub("^--", "", kv[1])
      value <- kv[2]
      if (key == "rebuild_fct") value <- as.logical(value)
      if (key == "window_days") value <- as.integer(strsplit(value, ",")[[1]])
      parsed[[key]] <- value
    }
  }

  if (is.null(parsed$start_date) || is.null(parsed$end_date)) {
    stop(
      "Both --start_date and --end_date are required.\n",
      "Usage: Rscript scripts/backfill_marts.R ",
      "--start_date=2024-01-01 --end_date=2024-12-31 [--window_days=30,90,180,365] [--rebuild_fct=TRUE]"
    )
  }

  parsed
}

# -------------------------------------------------------------------
# 1. Execute a mart SQL file with BigQuery parameterised query
# -------------------------------------------------------------------
backfill_mart_file <- function(connection, path, params = list(),
                               project = bq_project(),
                               dataset = bq_dataset()) {
  message(glue("--- Executing: {path} ---"))

  query <- render_sql(path, project = project, dataset = dataset)
  rows_affected <- dbExecute(connection, query, params = params)

  message(glue("Success. Rows affected: {rows_affected}"))
}

# -------------------------------------------------------------------
# 3. Main
# -------------------------------------------------------------------
cli <- parse_args()

message(glue("Starting mart backfill: {cli$start_date} -> {cli$end_date}"))
message(glue("  window_days  = {paste(cli$window_days, collapse = ', ')}"))
message(glue("  rebuild_fct  = {cli$rebuild_fct}"))

# Authenticate (uses ETL_SERVICE_ACCOUNT_PATH env var when set)
service_account_path <- Sys.getenv("ETL_SERVICE_ACCOUNT_PATH", unset = NA)
if (!is.na(service_account_path)) {
  bq_auth(path = here(service_account_path))
}

project <- bq_project()
dataset <- bq_dataset()

connection <- dbConnect(
  bigrquery::bigquery(),
  project = project,
  dataset = dataset,
  billing = project
)

# Step A – fct_daily_performance (full refresh, no date parameters)
if (cli$rebuild_fct) {
  message("--- Rebuilding fct_daily_performance (full refresh) ---")
  run_sql_file(connection, here("sql", "03_marts", "fct_daily_performance.sql"))
}

# Step B – mart_channel_metrics (MERGE, once per window_days value)
for (wd in cli$window_days) {
  backfill_mart_file(
    connection,
    here("sql", "03_marts", "mart_channel_metrics.sql"),
    params = list(
      start_date  = as.Date(cli$start_date),
      end_date    = as.Date(cli$end_date),
      window_days = wd
    )
  )
}

# Step C – mart_channel_cohorts (MERGE, depends on mart_channel_metrics)
backfill_mart_file(
  connection,
  here("sql", "03_marts", "mart_channel_cohorts.sql"),
  params = list(
    start_date = as.Date(cli$start_date),
    end_date   = as.Date(cli$end_date)
  )
)

# Step D – mart_channel_metrics_values (MERGE, depends on fct_daily_performance
#          and mart_channel_metrics)
backfill_mart_file(
  connection,
  here("sql", "03_marts", "mart_channel_metrics_values.sql"),
  params = list(
    start_date = as.Date(cli$start_date),
    end_date   = as.Date(cli$end_date)
  )
)

# Step E – mart_channel_rankings (MERGE, depends on mart_channel_metrics_values
#          and mart_channel_cohorts)
backfill_mart_file(
  connection,
  here("sql", "03_marts", "mart_channel_rankings.sql"),
  params = list(
    start_date = as.Date(cli$start_date),
    end_date   = as.Date(cli$end_date)
  )
)

message("Disconnecting from BigQuery...")
dbDisconnect(connection)

message("Mart backfill complete.")
