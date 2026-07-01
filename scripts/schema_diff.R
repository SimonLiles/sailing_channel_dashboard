#!/usr/bin/env Rscript
# Compare schemas between two BigQuery datasets.
# Useful before a migration to see what changed in dev vs prod.
#
# Usage (defaults to dev → prod):
#   Rscript scripts/schema_diff.R
#
# Override with env vars:
#   SOURCE_DATASET=my_dev \
#   TARGET_DATASET=my_prod \
#   PROJECT=my-project \
#   Rscript scripts/schema_diff.R

library(bigrquery)
library(DBI)
library(glue)
library(here)

source(here("scripts", "bq_config.R"))

# Auth — use env var if set, otherwise default
sa_path <- Sys.getenv("ETL_SERVICE_ACCOUNT_PATH", unset = NA)
if (!is.na(sa_path)) bq_auth(path = here(sa_path))

project <- Sys.getenv("PROJECT", bq_project())
source_ds <- Sys.getenv("SOURCE_DATASET", "yt_sailing_data_dev")
target_ds <- Sys.getenv("TARGET_DATASET", "yt_sailing_data")

con <- dbConnect(
  bigrquery::bigquery(),
  project = project,
  billing = project
)

message(glue("Comparing {project}.{source_ds}  →  {project}.{target_ds}"))
message("")

# ---- Tables ----
message("=== TABLES ===")
tbl_sql <- glue("
  SELECT
    COALESCE(s.table_name, t.table_name) AS table_name,
    CASE
      WHEN s.table_name IS NULL THEN 'ONLY_IN_TARGET'
      WHEN t.table_name IS NULL THEN 'ONLY_IN_SOURCE'
      ELSE 'BOTH'
    END AS status
  FROM `{proj}.{src}.INFORMATION_SCHEMA.TABLES` s
  FULL JOIN `{proj}.{tgt}.INFORMATION_SCHEMA.TABLES` t
    USING (table_name)
  WHERE COALESCE(s.table_name, t.table_name) NOT LIKE '\\_%'
  ORDER BY status, table_name
",
  proj = project, src = source_ds, tgt = target_ds
)
print(dbGetQuery(con, tbl_sql))
message("")

# ---- Columns ----
message("=== COLUMNS ===")
col_sql <- glue("
  SELECT
    COALESCE(s.table_name, t.table_name)  AS table_name,
    COALESCE(s.column_name, t.column_name) AS column_name,
    CASE
      WHEN s.column_name IS NULL THEN 'ONLY_IN_TARGET'
      WHEN t.column_name IS NULL THEN 'ONLY_IN_SOURCE'
      WHEN s.data_type != t.data_type     THEN 'TYPE_MISMATCH'
      ELSE 'MATCH'
    END AS status,
    s.data_type AS source_type,
    t.data_type AS target_type
  FROM `{proj}.{src}.INFORMATION_SCHEMA.COLUMNS` s
  FULL JOIN `{proj}.{tgt}.INFORMATION_SCHEMA.COLUMNS` t
    USING (table_name, column_name)
  WHERE COALESCE(s.table_name, t.table_name) NOT LIKE '\\_%'
  ORDER BY status, table_name, column_name
",
  proj = project, src = source_ds, tgt = target_ds
)
print(dbGetQuery(con, col_sql))

dbDisconnect(con)
message("")
message("Done.")
