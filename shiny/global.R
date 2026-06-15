library(shiny)
library(reactable)
library(bslib)
library(shinycssloaders)

# Data retrieval and handling
library(bigrquery)
library(bigrquerystorage)
library(DBI)
library(googleCloudStorageR)
library(pool)
library(tidyverse)

# Plotting
library(ggplot2)
library(plotly)
library(ggthemes)
library(scales)

library(here)

# Load shared scripts
source(here("scripts", "run_sql.R"))

# Load utility functions
source(paste("utils", "format_youtube_style.R", sep = "/"))
source(paste("utils", "read_rds_from_gcs.R", sep = "/"))
source(paste("utils", "gcs_cache_last_modified.R", sep = "/"))
source(paste("utils", "run_channel_query.R", sep = "/"))

# BigQuery connection constants
project <- "yt-sailing-dashboard"
dataset <- "yt_sailing_data"

# Authenticate
message("Authenticating...")
if (Sys.getenv("SHINY_ENV") == "production") {
  bq_auth()
  googleAuthR::gar_gce_auth()
} else {
  service_account_path <- here(Sys.getenv("SHINY_SERVICE_ACCOUNT_PATH"))
  bq_auth(path = service_account_path)
  gcs_auth(json_file = service_account_path)
}
gcs_global_bucket("yt-sailing-dashboard-cache")
message("\tAuthenticated")

# Load initial data from GCS cache
message("Loading data from GCS cache...")
global_summary  <- read_rds_from_gcs("cache/global_summary.rds")
leaderboard_30d <- read_rds_from_gcs("cache/leaderboard_30d.rds")
channel_lookup  <- read_rds_from_gcs("cache/channel_lookup.rds")
today <- as.Date(global_summary$date[1])
message("Data loaded.")
