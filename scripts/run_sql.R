require(DBI)
require(glue)
require(here)

source(here("scripts", "bq_config.R"))

# Read a SQL file into a single string
read_sql <- function(path) {
  if (!file.exists(path))
  {
    stop(paste("SQL file not found:", path))
  } 
  else 
  {
    paste(readLines(path, warn = FALSE), collapse = "\n")
  }
}

# Render SQL template placeholders ({{project}}, {{dataset}})
render_sql <- function(path, project = bq_project(), dataset = bq_dataset()) {
  query <- read_sql(path)
  glue(query, project = project, dataset = dataset, .open = "{{", .close = "}}")
}

# Execute a SQL file and log progress.
# When params is a named list, they are passed as BigQuery query parameters
# (used by parameterised MERGE statements in the mart layer).
run_sql_file <- function(connection, path, project = bq_project(), dataset = bq_dataset(), params = NULL) {
  message(glue("--- Executing: {path} ---"))
  query <- render_sql(path, project = project, dataset = dataset)

  if (is.null(params) || length(params) == 0) {
    rows_affected <- dbExecute(connection, query)
  } else {
    rows_affected <- dbExecute(connection, query, parameters = params)
  }
  message(glue("Success. Rows affected: {rows_affected}"))
}
