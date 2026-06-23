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
