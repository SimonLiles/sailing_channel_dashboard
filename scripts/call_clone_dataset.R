# Wrapper to call the clone_dataset stored procedure from R.
# The procedure must already exist in the BigQuery dataset
# (created via BigQuery Studio — bigrquery dbExecute does not
#  properly finalise CREATE PROCEDURE jobs).
#
# Usage:
#   source(here("scripts", "call_clone_dataset.R"))
#   call_clone_dataset(
#     con,
#     source_project   = "yt-sailing-dashboard",
#     source_dataset   = "yt_sailing_data",
#     target_project   = "yt-sailing-dashboard",
#     target_dataset   = "yt_sailing_data_dev",
#     include_views    = FALSE,
#     include_routines = FALSE,
#     full_copy        = FALSE
#   )

require(DBI)
require(glue)
require(here)

source(here("scripts", "bq_config.R"))

call_clone_dataset <- function(
    connection,
    source_project   = bq_project(),
    source_dataset   = bq_dataset(),
    target_project   = bq_project(),
    target_dataset   = "clone_temp",
    include_views    = FALSE,
    include_routines = FALSE,
    full_copy        = FALSE
) {
  sql <- glue("
    CALL `{src_prj}.{src_ds}.clone_dataset`(
      '{src_prj}', '{src_ds}',
      '{tgt_prj}', '{tgt_ds}',
      {views}, {routines}, {copy}
    )
  ",
    src_prj  = source_project,
    src_ds   = source_dataset,
    tgt_prj  = target_project,
    tgt_ds   = target_dataset,
    views    = tolower(include_views),
    routines = tolower(include_routines),
    copy     = tolower(full_copy)
  )

  message(glue("--- Cloning {source_project}.{source_dataset} -> ",
               "{target_project}.{target_dataset} ---"))
  message(sql)

  # dbExecute may not properly finalise script-type jobs in bigrquery.
  # If it fails, paste the printed CALL statement into BigQuery Studio.
  tryCatch(
    {
      rows <- dbExecute(connection, sql)
      message(glue("Success. Rows affected: {rows}"))
    },
    error = function(e) {
      message("dbExecute failed. Paste the CALL statement above into BigQuery Studio.")
      message("Error: ", e$message)
    }
  )
}
