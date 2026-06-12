format_youtube_style <- function(n) {
  case_when(
    is.na(n)        ~ "N/A",
    n < 1000        ~ formatC(n, format = "d", big.mark = ","),
    n < 10000       ~ paste0(round(n / 1000, 2), "K"),
    n < 100000      ~ paste0(round(n / 1000, 1), "K"),
    n < 1000000     ~ paste0(round(n / 1000, 0), "K"),
    n < 10000000    ~ paste0(round(n / 1000000, 2), "M"),
    n < 100000000   ~ paste0(round(n / 1000000, 1), "M"),
    TRUE            ~ paste0(round(n / 1000000, 0), "M")
  )
}
