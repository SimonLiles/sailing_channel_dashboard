gcs_cache_last_modified <- function(gcs_name) {
  meta <- gcs_get_object(gcs_name, meta = TRUE)
  meta$updated
}
