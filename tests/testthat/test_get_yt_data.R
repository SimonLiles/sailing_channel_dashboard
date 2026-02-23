# tests/testthat/test_get_yt_data.R
library(testthat)
library(here)

source(here("scripts", "get_yt_data.R"))

test_that("get_yt_data fails gracefully without an API key", {
  # Temporarily remove the API key from the environment
  original_key <- Sys.getenv("YT_API_KEY")
  Sys.setenv(YT_API_KEY = "")
  
  # We expect the function to throw our custom error message
  expect_error(
    get_yt_data("UC_x5XG1OV2P6uZZ5FSM9Ttw"), 
    regexp = "API Key not found"
  )
  
  # Restore the key for the next test
  Sys.setenv(YT_API_KEY = original_key)
})

test_that("get_yt_data returns a correctly formatted data frame from the live API", {
  # Skip this test if we are running locally without an API key
  skip_if(Sys.getenv("YT_API_KEY") == "", message = "No API key found. Skipping live API test.")
  
  # Query the official YouTube Creators channel ID
  test_channel_id <- "UCkRfArvrzheW2E7b6SVT7vQ" 
  
  result <- get_yt_data(test_channel_id)
  
  # 1. Did it return a data frame?
  expect_s3_class(result, "data.frame")
  
  # 2. Did it return exactly 1 row?
  expect_equal(nrow(result), 1)
  
  # 3. Are all 11 expected columns present?
  expected_cols <- 11
  expect_equal(ncol(result), expected_cols)
  
  # 4. Did the JSON parser correctly map the ID?
  expect_equal(result[[2]], test_channel_id) 
})