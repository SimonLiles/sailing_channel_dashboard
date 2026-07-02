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
source(here("scripts", "bq_config.R"))
source(here("scripts", "run_sql.R"))

# Load utility functions
source(paste("utils", "format_youtube_style.R", sep = "/"))
source(paste("utils", "format_dashboard_value.R", sep = "/"))
source(paste("utils", "read_rds_from_gcs.R", sep = "/"))
source(paste("utils", "gcs_cache_last_modified.R", sep = "/"))
source(paste("utils", "run_channel_query.R", sep = "/"))
source(paste("utils", "run_leaderboard_query.R", sep = "/"))

# BigQuery connection constants
project <- bq_project()
dataset <- bq_dataset()

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
gcs_global_bucket(config_get("gcs_bucket", "yt-sailing-dashboard-cache"))
message("\tAuthenticated")

# Load initial data from GCS cache
message("Loading data from GCS cache...")
gcs_prefix <- config_get("gcs_cache_prefix", "cache")
global_summary       <- read_rds_from_gcs(paste0(gcs_prefix, "/global_summary.rds"))
channel_info         <- read_rds_from_gcs(paste0(gcs_prefix, "/channel_info.rds"))
today <- as.Date(global_summary$date[1])
message("Data loaded.")
