# Script to collect, clean, and save channel data

message('Starting Up...')

# Load required libraries
require(bigrquery)
require(gargle)
require(DBI)
require(glue)
require(here)

#0. Get helper functions
source(here("scripts", "run_sql.R"))

# 1. Connect to BigQuery ####

# Authenticate
service_account_path <- 'app/secrets/yt-sailing-dashboard-1a37e4c18a27.json'
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
source("scripts", "get_yt_data.R")

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
  here("sql", "03_marts", "fct_daily_performance.sql")
)

# Execute in order
lapply(sql_ops_sequence, function(X) {
  run_sql_file(connection = connection,
               path = X)
})

# Clean Up #####################################################################
message('Process Complete, cleaning up...')

message('Disconnecting from BigQuery...')
dbDisconnect(connection)
message('\tDisconnected')




