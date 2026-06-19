bq_project <- function() Sys.getenv("BQ_PROJECT", "yt-sailing-dashboard")

bq_dataset <- function() Sys.getenv("BQ_DATASET", "yt_sailing_data")
