# UI ----
footer_ui <- card(
  fluidRow(
    column(
      width = 4,
      a("Built by Simon Liles", href = "https://quantknot.com/about-simon-2/"),
      br(),
      a("Privacy", href = "https://quantknot.com/privacy-policy/")
    ),
    column(
      width = 4,
      p("Don't see your channel?"),
      a(
        "Request to add a channel here",
        href = "https://quantknot.com/sailing-creator-dashboard-new-channel-request/"
      )
    ),
    column(
      width = 4,
      p("Data updated daily via automated GCP pipeline."),
      a(
        "View source on Github.",
        href = "https://github.com/SimonLiles/sailing_channel_dashboard"
      ),
      p("Data provided by YouTube. Analysis & Metrics © 2026 Simon Liles."),
      a(
        "Methodology & Terms",
        href = "https://quantknot.com/sailing-creator-analytics-methodology-attribution/"
      )
    )
  )
)
