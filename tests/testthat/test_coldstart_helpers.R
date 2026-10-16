# ====================================================================
# Cold-Start Helpers — Test Suite
# ====================================================================
# Tests for the cold-start helper functions in
# shiny/utils/coldstart_helpers.R.
#
# Canonical gate: Rscript tests/testthat.R
# ====================================================================
source(here("shiny", "utils", "coldstart_helpers.R"))

# --- safe_tail1 ---

test_that("safe_tail1 returns last element of non-empty vector", {
  expect_equal(safe_tail1(c(a = 1, b = 2, c = 3)), 3)
  expect_equal(safe_tail1(c("first", "second", "third")), "third")
  expect_equal(safe_tail1(42L), 42L)
})

test_that("safe_tail1 strips names from the returned element", {
  expect_equal(names(safe_tail1(c(a = 1, b = 2, c = 3))), NULL)
})

test_that("safe_tail1 returns NA_real_ on NULL input", {
  expect_equal(safe_tail1(NULL), NA_real_)
  expect_type(safe_tail1(NULL), "double")
})

test_that("safe_tail1 returns NA_real_ on empty vector", {
  expect_equal(safe_tail1(character(0)), NA_real_)
  expect_equal(safe_tail1(numeric(0)), NA_real_)
})

test_that("safe_tail1 returns NA_real_ when last element is NA", {
  expect_equal(safe_tail1(c(1, 2, NA_real_)), NA_real_)
})

# --- show_negative_note ---

test_that("show_negative_note evaluates FALSE when all inputs are NULL", {
  result <- show_negative_note(list(
    subscriber_count = NULL,
    daily_new_views = NULL,
    video_count = NULL,
    views_moving_avg_7d = NULL
  ))
  expect_true(isFALSE(result))
})

test_that("show_negative_note evaluates FALSE on empty vectors", {
  result <- show_negative_note(list(
    subscriber_count = numeric(0),
    daily_new_views = numeric(0),
    video_count = numeric(0),
    views_moving_avg_7d = numeric(0)
  ))
  expect_true(isFALSE(result))
})

test_that("show_negative_note returns FALSE on empty input", {
  expect_true(isFALSE(show_negative_note(list())))
})

test_that("show_negative_note evaluates TRUE when trailing value is negative", {
  result <- show_negative_note(list(
    subscriber_count = 1000,
    daily_new_views = -50, # negative trailing value
    video_count = 50,
    views_moving_avg_7d = 10
  ))
  expect_true(isTRUE(result))
})

test_that("show_negative_note evaluates TRUE when trailing vector element is negative", {
  result <- show_negative_note(list(
    subscriber_count = 1000,
    daily_new_views = c(10, 5, -2), # negative trailing element
    video_count = c(5, 3, 2),
    views_moving_avg_7d = c(5, 5, 5)
  ))
  expect_true(isTRUE(result))
})

test_that("show_negative_note ignores interior negatives, checks trailing only", {
  # Matches the original tail(..., 1) semantics: only the last element
  # of each series feeds the predicate.
  result <- show_negative_note(list(
    subscriber_count = 1000,
    daily_new_views = c(10, -5, 2), # interior negative, trailing positive
    video_count = c(5, 3, 2),
    views_moving_avg_7d = c(5, 5, 5)
  ))
  expect_true(isFALSE(result))
})

test_that("show_negative_note evaluates FALSE when all trailing values are positive or NA", {
  result <- show_negative_note(list(
    subscriber_count = 1000,
    daily_new_views = c(10, 5, 2),
    video_count = c(5, 3, 2),
    views_moving_avg_7d = c(5, NA, 5) # trailing element positive
  ))
  expect_true(isFALSE(result))
})

test_that("show_negative_note never returns NA", {
  result <- show_negative_note(list(
    subscriber_count = NA_real_,
    daily_new_views = NA_real_,
    video_count = NA_real_,
    views_moving_avg_7d = NA_real_
  ))
  expect_true(isFALSE(result))
  expect_true(is.logical(result))
})

test_that("original footnote expression throws on NA, helper does not", {
  # Regression test for the reported crash:
  # "Warning: Error in if: missing value where TRUE/FALSE needed".
  expect_error(if (any(c(NA_real_) < 0)) TRUE)
  expect_true(isFALSE(show_negative_note(list(
    subscriber_count = NA_real_,
    daily_new_views = NA_real_,
    video_count = NA_real_,
    views_moving_avg_7d = NA_real_
  ))))
})

# --- format_count_safe ---

test_that("format_count_safe formats counts with thousands separators", {
  expect_equal(format_count_safe(1234567), "1,234,567")
  expect_equal(format_count_safe(42), "42")
})

test_that("format_count_safe returns N/A on missing input", {
  expect_equal(format_count_safe(NULL), "N/A")
  expect_equal(format_count_safe(numeric(0)), "N/A")
  expect_equal(format_count_safe(NA_real_), "N/A")
})

# --- has_series ---

test_that("has_series is TRUE for plottable input", {
  expect_true(has_series(c(1, 2, 3)))
  expect_true(has_series(c(NA, 5, NA)))
  expect_true(has_series(10))
})

test_that("has_series is FALSE for missing input", {
  expect_false(has_series(NULL))
  expect_false(has_series(numeric(0)))
  expect_false(has_series(c(NA, NA)))
  expect_false(has_series(NA_real_))
})

# --- flows_pending ---

test_that("flows_pending is TRUE on NULL or empty history", {
  expect_true(flows_pending(NULL))
  expect_true(flows_pending(data.frame()))
})

test_that("flows_pending is TRUE on single-row all-NA flow metrics", {
  hist <- data.frame(daily_new_views = NA_real_, views_moving_avg_7d = NA_real_)
  expect_true(flows_pending(hist))
})

test_that("flows_pending is FALSE once flow metrics exist", {
  hist <- data.frame(
    daily_new_views = c(NA_real_, 10, 5),
    views_moving_avg_7d = c(NA_real_, NA_real_, 7)
  )
  expect_false(flows_pending(hist))
})

test_that("flows_pending is FALSE when only one flow metric exists", {
  hist <- data.frame(
    daily_new_views = c(10, 5),
    views_moving_avg_7d = c(NA_real_, NA_real_)
  )
  expect_false(flows_pending(hist))
})

# --- coalesce_profile_field ---

test_that("coalesce_profile_field preserves non-empty, non-NA values", {
  expect_equal(coalesce_profile_field("Hello"), "Hello")
  expect_equal(coalesce_profile_field("Description text"), "Description text")
  expect_equal(coalesce_profile_field(c("Tag1", "Tag2")), c("Tag1", "Tag2"))
})

test_that("coalesce_profile_field returns fallback on NULL input", {
  expect_equal(coalesce_profile_field(NULL), "N/A")
  expect_equal(coalesce_profile_field(NULL, fallback = "<MISSING>"), "<MISSING>")
})

test_that("coalesce_profile_field returns fallback on empty vector", {
  expect_equal(coalesce_profile_field(character(0)), "N/A")
  expect_equal(coalesce_profile_field(character(0), fallback = 0), 0)
})

test_that("coalesce_profile_field returns fallback on NA values", {
  expect_equal(coalesce_profile_field(NA_character_), "N/A")
  expect_equal(coalesce_profile_field(NA_real_), "N/A")
  expect_equal(coalesce_profile_field(NA), "N/A")
  expect_equal(coalesce_profile_field(NA_character_, fallback = 0), 0)
})
