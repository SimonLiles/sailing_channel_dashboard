library(testthat)
library(here)
library(RSQLite)

# Source the functions
source(here("scripts", "run_sql.R"))

# --- Tests for read_sql ---

test_that("read_sql correctly reads and joins multi-line SQL", {
  # 1. Setup: Create a temp SQL file
  tmp_sql <- tempfile(fileext = ".sql")
  writeLines(c("SELECT *", "FROM table;"), tmp_sql)
  
  # 2. Execution
  result <- read_sql(tmp_sql)
  
  # 3. Validation: Verify lines are collapsed with a newline
  expect_equal(result, "SELECT *\nFROM table;")
  
  # Cleanup
  unlink(tmp_sql)
})

test_that("read_sql throws a clear error if the file is missing", {
  expect_error(read_sql("non_existent_file.sql"), "SQL file not found")
})

# --- Tests for render_sql ---

test_that("render_sql substitutes project and dataset placeholders", {
  tmp_sql <- tempfile(fileext = ".sql")
  writeLines(
    "SELECT * FROM `{{project}}.{{dataset}}.my_table` WHERE id = @id;",
    tmp_sql
  )

  result <- render_sql(tmp_sql, project = "my-proj", dataset = "my_ds")

  expect_equal(
    result,
    "SELECT * FROM `my-proj.my_ds.my_table` WHERE id = @id;"
  )

  unlink(tmp_sql)
})

test_that("render_sql leaves BigQuery @ params untouched", {
  tmp_sql <- tempfile(fileext = ".sql")
  writeLines(
    c(
      "SELECT * FROM `{{project}}.{{dataset}}.fct_daily_performance`",
      "WHERE channel_id = @channel_id AND date >= @start_date;"
    ),
    tmp_sql
  )

  result <- render_sql(tmp_sql, project = "p", dataset = "d")

  expect_match(result, "@channel_id")
  expect_match(result, "@start_date")
  expect_false(grepl("\\{\\{", result))

  unlink(tmp_sql)
})

test_that("render_sql smoke test on real ops SQL leaves no placeholders", {
  path <- here("sql", "01_raw", "ops", "merge_channel_dims.sql")
  skip_if_not(file.exists(path))

  result <- render_sql(path, project = "test-proj", dataset = "test_ds")

  expect_false(grepl("\\{\\{", result))
  expect_match(result, "`test-proj.test_ds.channel_dimensions`")
})

# --- Tests for run_sql_file ---

test_that("run_sql_file executes SQL and logs the path", {
  # 1. Setup: Mock SQLite DB and a simple SQL file
  mock_conn <- dbConnect(RSQLite::SQLite(), ":memory:")
  tmp_sql <- tempfile(fileext = ".sql")
  writeLines("CREATE TABLE test_log (id INTEGER);", tmp_sql)
  
  # 2. Execution & Validation
  # We use capture_messages to ensure the "Executing: ..." message is printed
  msgs <- capture_messages(run_sql_file(mock_conn, tmp_sql))
  
  expect_match(msgs[1], "Executing:")
  expect_match(msgs[2], "Success")
  
  # Verify the table actually exists in our mock DB
  expect_true(dbExistsTable(mock_conn, "test_log"))
  
  # Cleanup
  dbDisconnect(mock_conn)
  unlink(tmp_sql)
})