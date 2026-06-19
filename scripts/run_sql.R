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

# Execute a SQL file and log progress
run_sql_file <- function(connection, path, project = bq_project(), dataset = bq_dataset()) {
  message(glue("--- Executing: {path} ---"))
  query <- render_sql(path, project = project, dataset = dataset)
  
  # Using dbExecute for DML (INSERT, MERGE, CREATE)
  # It returns the number of rows affected
  rows_affected <- dbExecute(connection, query)
  message(glue("Success. Rows affected: {rows_affected}"))
}
