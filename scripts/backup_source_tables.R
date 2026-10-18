# BackupSourceTables
#
# Server-side Parquet backup for the two source tables that feed the marts.
# Runs as ETL step 6, after the mart rebuild and the GCS cache write, so the
# backup reflects a consistent post-run state. The caller keeps failures
# isolated (see etl/main.R step 6): a failed backup only logs, it never
# aborts the ETL run. Statements are read-only EXPORT DATA calls; the script
# issues no table writes of its own.
#
# ## Properties
# * backup_tables: character vector. The two source tables covered by backup.
#
# ## Methods
# * backup_prefix(backup_date): character. Shared GCS prefix for both tables.
# * backup_export_template(table, bucket, date_prefix): character. Per-table statement text.
# * run_backup(connection, project, dataset, backup_date, bucket): invisible character. Render + run both.
#
# Sourcing this file is side-effect free: it only defines helpers. All live
# work happens inside run_backup(), called from etl/main.R.

# Shared GCS prefix for both table backups.
#
# ## Parameters
# * backup_date: Date. Backup day; defaults to the current UTC date.
#
# ## Returns
# * character. Prefix of the form backups/YYYY-MM-DD.
backup_prefix <- function(backup_date = as.Date(format(Sys.time(), tz = "UTC"), tz = "UTC")) {
  paste0("backups/", format(backup_date, "%Y-%m-%d"))
}

# The two source tables covered by the daily backup.
backup_tables <- c("channel_dimensions", "daily_metrics_history")

# Per-table EXPORT DATA statement text with project/dataset placeholders.
#
# ## Parameters
# * table: character. Source table name.
# * bucket: character. Destination GCS bucket.
# * date_prefix: character. Shared prefix from backup_prefix().
#
# ## Returns
# * character. Statement text rendered for render_sql().
backup_export_template <- function(table, bucket, date_prefix) {
  paste0(
    "EXPORT DATA OPTIONS (uri='gs://", bucket, "/", date_prefix, "/", table, "/*.parquet', ",
    "format='PARQUET', overwrite=true) AS ",
    "SELECT * FROM `{{project}}.{{dataset}}.", table, "`;"
  )
}

# Render and run the Parquet backup for both source tables.
#
# ## Parameters
# * connection: DBIConnection. Open BigQuery connection (reused, never reopened).
# * project: character. GCP project for the EXPORT statements.
# * dataset: character. BigQuery dataset holding the source tables.
# * backup_date: Date. Backup day; defaults to the current UTC date.
# * bucket: character. Destination GCS bucket.
#
# ## Returns
# * invisible character. The shared prefix used for both tables.
run_backup <- function(connection,
                       project = bq_project(),
                       dataset = bq_dataset(),
                       backup_date = as.Date(format(Sys.time(), tz = "UTC"), tz = "UTC"),
                       bucket = config_get("gcs_bucket", "yt-sailing-dashboard-cache")) {
  date_prefix <- backup_prefix(backup_date)
  for (table in backup_tables) {
    sql_file <- tempfile(fileext = ".sql")
    writeLines(backup_export_template(table, bucket, date_prefix), sql_file)
    rendered <- render_sql(sql_file, project = project, dataset = dataset)
    message(rendered)
    run_sql_file(connection, sql_file, project = project, dataset = dataset)
    unlink(sql_file)
  }
  invisible(date_prefix)
}
