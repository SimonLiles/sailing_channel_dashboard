# Script to collect, clean, and save channel data

message('Starting Up...')

# Load required libraries
require(bigrquery)
require(gargle)
require(DBI)
require(glue)
require(here)
require(googleCloudStorageR)

#0. Get helper functions
source(here("scripts", "bq_config.R"))
source(here("scripts", "run_sql.R"))

# 1. Connect to BigQuery ####

# Authenticate
service_account_path <- here(Sys.getenv("ETL_SERVICE_ACCOUNT_PATH"))
bq_auth(path = service_account_path)

project <- bq_project()
dataset <- bq_dataset()

# Make connection
connection <- dbConnect(
  bigrquery::bigquery(),
  project = project,
  dataset = dataset,
  billing = project
)

# 2. Get Target IDs ####
message('Fetching channel list...')

get_channel_ids_query <- render_sql(here("sql", "00_utils", "get_channel_ids.sql"))

channels <- dbGetQuery(connection, get_channel_ids_query)

message('Done')

# 3. YouTube Data Scrape ####
source(here("scripts", "get_yt_data.R"))

raw_yt_data_list <- lapply(channels$channel_id, get_yt_data)

raw_yt_data <- do.call(rbind, raw_yt_data_list)

colnames(raw_yt_data) <- c("channel_handle",
                           "channel_id",
                           "title",
                           "description",
                           "join_date",
                           "view_count",
                           "video_count",
                           "subscriber_count",
                           "is_sub_count_hidden",
                           "channel_keywords",
                           "profile_pic"
                           )

# Batch Load the data into the raw_daily_ingest table
message("Uploading Raw API data to BigQuery...")
dbWriteTable(
  conn = connection,
  name = "raw_daily_ingest",
  value = raw_yt_data,
  overwrite = TRUE,
  append = FALSE
)
message("Raw data upload complete!")

# 4. Clean data and calculate additional metrics

row_check <- dbGetQuery(connection, 
                        glue("SELECT COUNT(*) as cnt 
                        FROM `{{project}}.{{dataset}}.raw_daily_ingest`",
                             project = project,
                             dataset = dataset,
                             .open = "{{", .close = "}}")
                        )$cnt

if (row_check == 0) {
  stop("HALT: raw_daily_ingest is empty! Check the API response before proceeding.")
} else {
  message(paste("Success: Proceeding with", row_check, "rows of fresh data."))
}

# Define the sequence of SQL operations (no params)
sql_ops_sequence <- c(
  here("sql", "01_raw", "ops", "merge_channel_dims.sql"),
  here("sql", "01_raw", "ops", "append_daily_metrics.sql"),
  here("sql", "03_marts", "fct_daily_performance.sql")
)

# Execute the fixed ops sequence first
lapply(sql_ops_sequence, function(X) {
  run_sql_file(connection = connection,
               path = X)
})

# Mart layer: incremental MERGE with BigQuery query parameters.
# These must run after fct_daily_performance (the fact table they depend on)
# and before the 04_Apps tables.
today <- Sys.Date()

windows <- unique(as.integer(unlist(config_get("window_days", 30))))
message(glue("--- Mart Layer: channel metrics ({paste(windows, collapse = ', ')} days) ---"))
for (wd in windows) {
  run_sql_file(connection,
               here("sql", "03_marts", "mart_channel_metrics.sql"),
               params = list(
                 start_date  = today,
                 end_date    = today,
                 window_days = wd
               ))
}

run_sql_file(connection,
             here("sql", "03_marts", "mart_channel_cohorts.sql"),
             params = list(start_date = today, end_date = today))

run_sql_file(connection,
             here("sql", "03_marts", "mart_channel_metrics_values.sql"),
             params = list(start_date = today, end_date = today))

run_sql_file(connection,
             here("sql", "03_marts", "mart_channel_rankings.sql"),
             params = list(start_date = today, end_date = today))

# 04_Apps layer: parameterless CREATE OR REPLACE tables
message("--- 04_Apps Layer ---")
run_sql_file(connection, here("sql", "04_apps", "get_leaderboard.sql"))
run_sql_file(connection, here("sql", "04_apps", "get_global_summary.sql"))
run_sql_file(connection, here("sql", "04_apps", "get_channel_lookup.sql"))

# 5. Write cache files to GCS ####
message("Writing cache files to GCS...")

if (Sys.getenv("ETL_ENV") == "production") {
  bq_auth()
  googleAuthR::gar_gce_auth()
} else {
  service_account_path <- here(Sys.getenv("ETL_SERVICE_ACCOUNT_PATH"))
  bq_auth(path = service_account_path)
  gcs_auth(json_file = service_account_path)
}

gcs_global_bucket(config_get("gcs_bucket", "yt-sailing-dashboard-cache"))

# Helper: serialize to a temp file and upload
upload_as_rds <- function(data, gcs_name) {
  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp))
  saveRDS(data, tmp)
  gcs_upload(tmp, name = gcs_name, predefinedAcl = "bucketLevel")
  message(paste("\tUploaded:", gcs_name))
}

# Free stale collected data before the memory-heavy cache phase
rm(raw_yt_data, raw_yt_data_list, channels)
gc()

# Download + upload each cache table sequentially, freeing memory between
# NOTE: leaderboard is NOT cached here — the Shiny app queries BigQuery
# directly for filtered slices to avoid loading the full table into R memory.
gcs_prefix <- config_get("gcs_cache_prefix", "cache")
cache_tables <- list(
  list(bq_name = "global_summary",  gcs_name = paste0(gcs_prefix, "/global_summary.rds")),
  list(bq_name = "channel_lookup",  gcs_name = paste0(gcs_prefix, "/channel_info.rds"))
)
for (tbl in cache_tables) {
  data <- bq_table_download(bq_table(project, dataset, tbl$bq_name))
  upload_as_rds(data, tbl$gcs_name)
  rm(data); gc()
}

message("GCS cache write complete.")

# Clean Up #####################################################################
message('Process Complete, cleaning up...')

message('Disconnecting from BigQuery...')
dbDisconnect(connection)
message('\tDisconnected')




