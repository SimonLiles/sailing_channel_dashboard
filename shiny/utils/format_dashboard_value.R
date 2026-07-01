format_dashboard_value <- function(n, decimals = 2, is_pct = FALSE) {
  if (is.na(n) || is.null(n)) return("N/A")
  formatted <- formatC(round(n, decimals), format = "f", digits = decimals, big.mark = ",")
  if (is_pct) {
    paste0(formatted, "%")
  } else {
    formatted
  }
}
