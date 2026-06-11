source(paste("pages", "niche_pulse.R", sep = "/"))
source(paste("pages", "creator_explorer.R", sep = "/"))
source(paste("pages", "leaderboard.R", sep = "/"))
source(paste("pages", "growth_benchmarks.R", sep = "/"))
source(paste("pages", "footer.R", sep = "/"))

ui <- page_navbar(
  theme = bs_theme(
    version = 5,
    bootswatch = "yeti",
    primary = "#002B5B"
  ),

  tags$head(
    tags$link(rel = "icon", type = "image/png", href = "favicon.png"),
    tags$meta(property = "og:title", content = "Sailing Creator Analytics"),
    tags$meta(property = "og:description", content = "Track and compare 1,064 sailing YouTube channels. Powered by BigQuery and updated daily."),
    tags$meta(property = "og:image", content = "https://sailing-creators.quantknot.com/og-image.png"),
    tags$meta(property = "og:url", content = "https://sailing-creators.quantknot.com"),
    tags$meta(property = "og:type", content = "website"),
    tags$link(rel = "stylesheet", type = "text/css", href = "styles.css")
  ),

  title = "Sailing Creator Analytics",
  fillable = FALSE,

  niche_pulse_ui,
  creator_explorer_ui,
  leaderboard_ui,
  growth_benchmarks_ui,

  footer = footer_ui
)
