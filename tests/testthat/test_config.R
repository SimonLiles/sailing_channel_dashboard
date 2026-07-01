library(testthat)
library(yaml)
library(here)

test_that("config.yml uses production project", {
  config <- yaml::read_yaml(here("config.yml"))
  expect_equal(config$project, "yt-sailing-dashboard")
})

test_that("config.yml uses production dataset", {
  config <- yaml::read_yaml(here("config.yml"))
  expect_equal(config$dataset, "yt_sailing_data")
})

test_that("config.yml has GCS cache bucket", {
  config <- yaml::read_yaml(here("config.yml"))
  expect_type(config$gcs_bucket, "character")
  expect_false(is.na(config$gcs_bucket))
})

test_that("config.yml has GCS cache prefix", {
  config <- yaml::read_yaml(here("config.yml"))
  expect_type(config$gcs_cache_prefix, "character")
  expect_false(is.na(config$gcs_cache_prefix))
})
