# YouTube Data API reports subscriber counts rounded to 3 significant
# figures for channels with >= 1,000 subscribers. A windowed delta of 0
# therefore means "below the API resolution", not necessarily true zero.
#
# Resolution unit for a channel of size N (old leaderboard behaviour):
#   10 ^ (floor(log10(N)) - 2)
# e.g. 10,000 -> 100, 1,000,000 -> 10,000.
youtube_resolution <- function(sub_count) {
  if (is.na(sub_count) || is.null(sub_count) || sub_count < 1000 || sub_count <= 0) {
    return(NA_real_)
  }
  10 ^ (floor(log10(sub_count)) - 2)
}

# Format a windowed/snapshot subscriber delta for display.
# - NA        -> NA (reactable renders empty, as with generic colFormat)
# - sub < 1K  -> exact count (API reports these exactly)
# - value 0   -> "< {resolution}" (below API resolution)
# - otherwise -> "~{value}" (rounded inputs, per footnote)
format_subs_change <- function(value, sub_count) {
  if (is.na(value) || is.null(value)) {
    return(NA_character_)
  }
  if (is.na(sub_count) || is.null(sub_count) || sub_count < 1000) {
    return(formatC(value, format = "d", big.mark = ","))
  }
  if (value == 0) {
    threshold <- youtube_resolution(sub_count)
    return(paste0("< ", formatC(threshold, format = "d", big.mark = ",")))
  }
  paste0("~", formatC(value, format = "d", big.mark = ","))
}
