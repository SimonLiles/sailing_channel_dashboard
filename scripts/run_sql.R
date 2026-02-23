require(DBI)
require(glue)

# Read a SQL file into a single string
read_sql <- function(path) {
  if (!file.exists(path))
  {
    stop(message("SQL file not found:", path))
  } 
  else 
  {
    paste(readLines(path, warn = FALSE), collapse = "\n")
  }
}

# Execute a SQL file and log progress
run_sql_file <- function(connection, path) {
  message(glue("--- Executing: {path} ---"))
  query <- read_sql(path)
  
  # Using dbExecute for DML (INSERT, MERGE, CREATE)
  # It returns the number of rows affected
  rows_affected <- dbExecute(connection, query)
  message(glue("Success. Rows affected: {rows_affected}"))
}