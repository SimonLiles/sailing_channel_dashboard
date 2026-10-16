# ====================================================================
# Cold-Start Helpers — Creator Explorer Crash Fix
# ====================================================================
# Helper functions for gracefully rendering a channel that has been
# added but not yet enriched by ETL (cold start: 0–1 history rows,
# profile fields may be NULL or all NA).
#
# Architecture: Domain layer helpers — zero framework dependencies.
# Sourced by shiny/global.R; imported by creator_explorer.R.
# ====================================================================


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


#' Return the last element of a vector safely.
#'
#' Given a vector or scalar, return its final value (unnamed) or
#' `NA_real_` when absent. Intended for stock metrics (counts,
#' averages) that may be empty on brand-new channels.
#'
#' @param x Vector or scalar (length >= 0).
#' @return The last element unnamed, or `NA_real_` for `NULL`/empty/
#'   `NA` input.
#' @family cold-start
#' @examples
#' safe_tail1(c(a=1, b=2, c=3))  # returns 3 (unnamed numeric)
#' safe_tail1(NULL)              # returns NA_real_
#'
#' @family cold-start
safe_tail1 <- function(x) {
  if (is.null(x)) return(NA_real_)
  if (length(x) == 0) return(NA_real_)
  out <- unname(x[length(x)])
  if (isTRUE(is.na(out))) return(NA_real_)
  out
}


#' Evaluate a "negative trailing average" notice condition safely.
#'
#' The original crash came from:
#'
#'     if (any(c(tail(subs,1), tail(daily_views,1), tail(video,1),
#'                 tail(views_7d,1)) < 0)) {
#'
#' when `tail(..., 1)` yields `NA`, `any()` returns `NA` (no TRUE
#' present), and `if (NA)` throws.
#'
#' Use `show_negative_note()` to decide whether the footnote should
#' appear: the notice fires only when history exists (`n > 0`) AND
#' at least one of the four metrics is numerically negative (ignoring
#' `NA`).
#'
#' @param data A list with elements named:
#'   - `subscriber_count` (numeric or NULL)
#'   - `daily_new_views`
#'   - `video_count`
#'   - `views_moving_avg_7d`
#' @return `TRUE` if the negative-average footnote should render,
#'   `FALSE` otherwise. Never returns `NA`.
#' @family cold-start
#' @examples
#' show_negative_note(list(
#'   subscriber_count = 1000,
#'   daily_new_views  = c(10, 5, 2),
#'   video_count      = c(5, 3, 2),
#'   views_moving_avg_7d = c(5, 5, 5)
#' ))  # FALSE
#' show_negative_note(list(
#'   subscriber_count = 1000,
#'   daily_new_views  = c(10, -5, 2),   # negative entry
#'   video_count      = c(5, 3, 2),
#'   views_moving_avg_7d = c(5, 5, 5)
#' ))  # TRUE
#' show_negative_note(list())  # FALSE (empty input guard)
#'
#' @family cold-start
show_negative_note <- function(data) {
  if (length(data) == 0) return(FALSE)
  vals <- c(
    safe_tail1(data$subscriber_count),
    safe_tail1(data$daily_new_views),
    safe_tail1(data$video_count),
    safe_tail1(data$views_moving_avg_7d)
  )
  isTRUE(any(vals < 0, na.rm = TRUE))
}


#' Format a count metric for display, NA-safely.
#'
#' Integer-style formatting (`formatC` with thousands separators) that
#' renders `"N/A"` for `NULL`/empty/`NA` input instead of `"NA"` or
#' `character(0)`. Intended for stock metrics (subscriber/video counts,
#' daily new views) in value boxes.
#'
#' @param x A single numeric value (or `NULL`/`NA`/empty).
#' @return Formatted string, or `"N/A"` when no value is available.
#' @family cold-start
#' @examples
#' format_count_safe(1234567)  # "1,234,567"
#' format_count_safe(NA_real_)  # "N/A"
#'
#' @family cold-start
format_count_safe <- function(x) {
  if (is.null(x)) return("N/A")
  if (length(x) == 0) return("N/A")
  if (isTRUE(is.na(x))) return("N/A")
  formatC(x, format = "d", big.mark = ",")
}


#' Test whether a history series is plottable.
#'
#' A series is plottable only when it exists, is non-empty, and holds
#' at least one non-`NA` value. Single-row cold-start histories carry
#' `NULL`/all-`NA` flow metrics (`daily_new_views`,
#' `views_moving_avg_7d`) that must not reach `plot_ly` as-is.
#'
#' @param col A history column vector (or `NULL`).
#' @return `TRUE` when the series has at least one plottable value.
#' @family cold-start
#' @examples
#' has_series(c(1, 2, 3))  # TRUE
#' has_series(c(NA, NA))   # FALSE
#' has_series(NULL)        # FALSE
#'
#' @family cold-start
has_series <- function(col) {
  if (is.null(col)) return(FALSE)
  if (length(col) == 0) return(FALSE)
  any(!is.na(col))
}


#' Test whether flow metrics are still pending ETL enrichment.
#'
#' A cold-start channel has stock rows but no usable flow metrics yet:
#' both `daily_new_views` and `views_moving_avg_7d` are `NULL`, empty,
#' or all-`NA` (the `LAG()` diffs behind them need at least two daily
#' observations). Callers show the "metrics populating" notice when
#' this returns `TRUE`.
#'
#' @param hist History data frame (or `NULL`), with `daily_new_views`
#'   and `views_moving_avg_7d` columns when present.
#' @return `TRUE` when flow metrics are pending, `FALSE` otherwise.
#' @family cold-start
#' @examples
#' flows_pending(data.frame(daily_new_views = NA_real_,
#'                          views_moving_avg_7d = NA_real_))  # TRUE
#' flows_pending(data.frame(daily_new_views = c(10, 5),
#'                          views_moving_avg_7d = c(8, 7)))    # FALSE
#'
#' @family cold-start
flows_pending <- function(hist) {
  if (is.null(hist)) return(TRUE)
  if (is.null(nrow(hist)) || nrow(hist) == 0) return(TRUE)
  views <- tryCatch(hist$daily_new_views, error = function(e) NULL)
  avg7 <- tryCatch(hist$views_moving_avg_7d, error = function(e) NULL)
  views_missing <- is.null(views) || length(views) == 0 || all(is.na(views))
  avg7_missing <- is.null(avg7) || length(avg7) == 0 || all(is.na(avg7))
  isTRUE(views_missing && avg7_missing)
}


#' Coalesce a profile field with a fallback value.
#'
#' Handles three empty states uniformly:
#'   - `NULL` from a 0-row profile query
#'   - `NA` from a single-row profile with missing data
#'   - empty character vector (length 0) from parsing edge cases
#'
#' Returns the field value if valid (non-`NA`, non-`NULL`, length >= 1),
#' otherwise the provided `fallback` (default `"N/A"`).
#'
#' @param x The field value (can be `NULL`, `NA`, character, numeric,
#'   or an empty character vector).
#' @param fallback Default return when `x` is empty/missing.
#' @return Coalesced value suitable for display.
#' @family cold-start
#' @examples
#' coalesce_profile_field("Hello")           # "Hello"
#' coalesce_profile_field(NA_character_)     # "N/A"
#' coalesce_profile_field(NULL)              # "N/A"
#' coalesce_profile_field(character(0))      # "N/A"
#' coalesce_profile_field(NA_character_, 0)  # 0
#'
#' @family cold-start
coalesce_profile_field <- function(x, fallback = "N/A") {
  if (is.null(x)) return(fallback)
  if (length(x) == 0) return(fallback)
  if (isTRUE(is.na(x))) return(fallback)
  x
}
