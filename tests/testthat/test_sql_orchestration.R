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
  
  # 3. EXECUTION: Render a real ops script and verify substitution
  path_to_test_sql <- here("sql", "01_raw", "ops", "merge_channel_dims.sql")

  skip_if_not(file.exists(path_to_test_sql))

  rendered <- render_sql(path_to_test_sql, project = "test-proj", dataset = "test_ds")
  expect_false(grepl("\\{\\{", rendered))
  expect_match(rendered, "`test-proj.test_ds.channel_dimensions`")

  # Clean up
  dbDisconnect(mock_conn)
})