read_rds_from_gcs <- function(gcs_name) {
  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp))
  gcs_get_object(gcs_name, saveToDisk = tmp, overwrite = TRUE)
  readRDS(tmp)
}
