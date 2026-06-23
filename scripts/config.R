require(yaml)

.config <- NULL

load_config <- function() {
  if (is.null(.config)) {
    cfg_path <- Sys.getenv("CONFIG_PATH", here::here("config.yml"))
    if (!file.exists(cfg_path)) {
      .config <<- list()
    } else {
      .config <<- yaml::read_yaml(cfg_path)
    }
  }
  invisible(.config)
}

config_get <- function(key, default = NULL) {
  cfg <- load_config()

  env_var <- Sys.getenv(toupper(key), unset = NA)
  if (!is.na(env_var)) {
    val <- tryCatch(
      as.integer(strsplit(env_var, ",")[[1]]),
      warning = function(w) env_var
    )
    return(val)
  }

  if (key %in% names(cfg)) cfg[[key]] else default
}
