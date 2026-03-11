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
source(here("scripts", "run_sql.R"))

# 1. Connect to BigQuery ####

# Authenticate
service_account_path <- here(Sys.getenv("ETL_SERVICE_ACCOUNT_PATH"))
bq_auth(path = service_account_path)

project <- "yt-sailing-dashboard"
dataset <- "yt_sailing_data"

# Make connection
connection <- dbConnect(
  bigrquery::bigquery(),
  project = project,
  dataset = dataset,
  billing = project
)

# 2. Get Target IDs ####
message('Fetching channel list...')

get_channel_ids_query <- read_sql(here("sql", "00_utils", "get_channel_ids.sql"))

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
                        "SELECT COUNT(*) as cnt 
                        FROM `yt-sailing-dashboard.yt_sailing_data.raw_daily_ingest`"
                        )$cnt

if (row_check == 0) {
  stop("HALT: raw_daily_ingest is empty! Check the API response before proceeding.")
} else {
  message(paste("Success: Proceeding with", row_check, "rows of fresh data."))
}

# Define the sequence of operations
sql_ops_sequence <- c(
  here("sql", "01_raw", "ops", "merge_channel_dims.sql"),
  here("sql", "01_raw", "ops", "append_daily_metrics.sql"),
  here("sql", "03_marts", "fct_daily_performance.sql"),
  here("sql", "04_apps", "get_leaderboard_30d.sql"),
  here("sql", "04_apps", "get_global_summary.sql"),
  here("sql", "04_apps", "get_channel_lookup.sql")
)

# Execute in order
lapply(sql_ops_sequence, function(X) {
  run_sql_file(connection = connection,
               path = X)
})

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

# Helper: serialize to a temp file and upload
upload_as_rds <- function(data, gcs_name) {
  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp))
  saveRDS(data, tmp)
  gcs_upload(tmp, name = gcs_name, predefinedAcl = "bucketLevel")
  message(paste("\tUploaded:", gcs_name))
}

global_summary_cache  <- bq_table_download(bq_table(project, dataset, "global_summary"))
leaderboard_30d_cache <- bq_table_download(bq_table(project, dataset, "leaderboard_30d"))
channel_lookup_cache  <- bq_table_download(bq_table(project, dataset, "channel_lookup"))

upload_as_rds(global_summary_cache,  "cache/global_summary.rds")
upload_as_rds(leaderboard_30d_cache, "cache/leaderboard_30d.rds")
upload_as_rds(channel_lookup_cache,  "cache/channel_lookup.rds")

message("GCS cache write complete.")

# Clean Up #####################################################################
message('Process Complete, cleaning up...')

message('Disconnecting from BigQuery...')
dbDisconnect(connection)
message('\tDisconnected')




