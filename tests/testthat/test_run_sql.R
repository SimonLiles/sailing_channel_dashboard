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