source(here::here("scripts", "config.R"))

bq_project <- function() config_get("project", "yt-sailing-dashboard")
bq_dataset <- function() config_get("dataset", "yt_sailing_data")
