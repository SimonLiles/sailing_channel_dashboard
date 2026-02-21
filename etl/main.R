# Script to collect, clean, and save channel data

message('Starting Up...')

# Load required libraries
require(bigrquery)
require(gargle)
require(DBI)
require(glue)

#0. Get helper functions
source("scripts/run_sql.R")

# 1. Connect to BigQuery ####

# Authenticate
service_account_path <- '.config/gcloud/yt-sailing-dashboard-1a37e4c18a27.json'
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

get_channel_ids_query <- read_sql("sql/get_channel_ids.sql")

channels <- dbGetQuery(connection, get_channel_ids_query)

message('Done')

# 3. YouTube Data Scrape ####
source("scripts/get_yt_data.R")

# Retrieve the key from the environment
yt_key <- Sys.getenv("YT_API_KEY")

if (yt_key == "") {
  stop("API Key not found! Ensure YT_API_KEY is set in environment.")
}

raw_yt_data_list <- laaply(channels, 
                           get_yt_data(yt_data_api_key = yt_key,
                                       channels$handle
                                       )
                           )

raw_yt_data <- as.data.frame(raw_yt_data_list)

# 4. Load the raw data into BigQuery ####

# 5. Clean the new data object ####
message('Cleaning Data...')

colnames(sailing_YT_channels) <- c("handle","id", "title", "description", "join_date", 
                                   "view_count", "video_count", "subscriber_count",
                                   "is_subcriber_count_hidden")

sailing_YT_channels$view_count <- as.numeric(sailing_YT_channels$view_count)
sailing_YT_channels$video_count <- as.numeric(sailing_YT_channels$video_count)
sailing_YT_channels$subscriber_count <- as.numeric(sailing_YT_channels$subscriber_count)

sailing_YT_channels$join_date <- gsub("T.*", "", sailing_YT_channels$join_date)
sailing_YT_channels$join_date <- as.Date(sailing_YT_channels$join_date,
                                         format = "%Y-%m-%d")


message('\tDone')



# Upload the data to BigQuery ##################################################

## Update the channel_dimensions table #########################################
message('Uploading new channel dimensions data to BigQuery')
channel_dimensions <- data.frame(handle = sailing_YT_channels$handle,
                                 id = sailing_YT_channels$id,
                                 title = sailing_YT_channels$title,
                                 description = sailing_YT_channels$description,
                                 join_date = sailing_YT_channels$join_date)

message('Creating channel_dimensions_staging table with new data')
# Create a staging table and upload the data
dbWriteTable(
  connection,
  'channel_dimensions_staging',
  channel_dimensions
)

message('Merging channel_dimensions_staging into channel_dimensions')
# Merge the staging table into the original table
merge_channel_dims_query <- read_sql("sql/merge_new_channel_dims.sql")

dbSendQuery(connection, merge_channel_dims_query)

message('Dropping channel_dimensions_staging table')
# Drop the staging table
dbSendQuery(connection,
            'DROP TABLE IF EXISTS channel_dimensions_staging'
            )

## Append to daily_metrics table ###############################################
message('Uploading new daily metrics data to BigQuery')
daily_metrics <- data.frame(
                            channel_id = sailing_YT_channels$id,
                            date = Sys.Date(),
                            view_count = sailing_YT_channels$view_count,
                            video_count = sailing_YT_channels$video_count,
                            subscriber_count = sailing_YT_channels$subscriber_count
                            )

# Create a staging table and upload the data
message('Creating daily_metrics_staging table with new data')
bigrquery::dbWriteTable(
  connection,
  'daily_metrics_staging',
  daily_metrics
)

# Merge the staging table to the original table
message('Merging channel_dimensions_staging into channel_dimensions')

insert_new_daily_metrics_query <- read_sql("sql/insert_new_daily_metrics.sql")
dbSendQuery(connection, insert_new_daily_metrics_query)

# Drop the staging table
message('Dropping daily_metrics_staging table')
dbSendQuery(connection,
            'DROP TABLE IF EXISTS daily_metrics_staging'
)

# Create the Calculated Metrics Table ##########################################
message('Calculating additional metrics...')


# Clean Up #####################################################################
message('Process Complete, cleaning up...')

message('Disconnecting from BigQuery...')
dbDisconnect(connection)
message('\tDisconnected')




