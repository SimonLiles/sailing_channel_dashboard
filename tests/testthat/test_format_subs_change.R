library(testthat)
library(here)

source(here("shiny", "utils", "format_subs_change.R"))

test_that("youtube_resolution follows 10^(digits-2)", {
  expect_equal(youtube_resolution(10000), 100)
  expect_equal(youtube_resolution(1000000), 10000)
  expect_equal(youtube_resolution(1500), 10)
  expect_true(is.na(youtube_resolution(999)))
  expect_true(is.na(youtube_resolution(NA_real_)))
})

test_that("zero delta on rounded channel shows below-resolution threshold", {
  expect_equal(format_subs_change(0, 10000), "< 100")
  expect_equal(format_subs_change(0, 1000000), "< 10,000")
})

test_that("small channels report exact zeros", {
  expect_equal(format_subs_change(0, 500), "0")
  expect_equal(format_subs_change(0, 999), "0")
})

test_that("nonzero deltas get tilde prefix, small channels exact", {
  expect_equal(format_subs_change(1234, 50000), "~1,234")
  expect_equal(format_subs_change(25, 500), "25")
  expect_equal(format_subs_change(-5, 50000), "~-5")
})

test_that("NA value stays NA for reactable default rendering", {
  expect_true(is.na(format_subs_change(NA_real_, 50000)))
})

test_that("missing subscriber count falls back to exact formatting", {
  expect_equal(format_subs_change(0, NA_real_), "0")
})
