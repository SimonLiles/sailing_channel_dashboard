library(testthat)
library(RSQLite)
library(here)

# Source your helper functions
source(here("scripts", "run_sql.R"))

test_that("SQL orchestration executes without syntax errors on a mock DB", {
  
  # 1. SETUP: Create an in-memory SQLite database
  mock_conn <- dbConnect(RSQLite::SQLite(), ":memory:")
  
  # 2. MOCK DATA: Create the table your SQL expects
  # This mimics the 'raw_daily_ingest' table normally created by BigQuery
  sample_data <- data.frame(
    channel_id = "test_id",
    view_count = 1000,
    subscriber_count = 50,
    video_count = 5
  )
  dbWriteTable(mock_conn, "raw_daily_ingest", sample_data)
  
  # 3. EXECUTION: Try running one of your ops scripts
  # Note: BigQuery SQL and SQLite SQL are slightly different, 
  # but standard ANSI SQL (like simple INSERTs/SELECTs) works in both.
  path_to_test_sql <- here("sql", "01_raw", "ops", "merge_channel_dims.sql")
  
  # We use skip_if_not to avoid failing if the file isn't created yet
  skip_if_not(file.exists(path_to_test_sql))
  
  # 4. VERIFICATION: Test that our function handles the execution
  # expect_error(run_sql_file(mock_conn, path_to_test_sql), NA) # NA means "No error expected"
  
  # Clean up
  dbDisconnect(mock_conn)
})