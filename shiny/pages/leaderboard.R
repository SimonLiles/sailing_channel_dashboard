# UI ----
leaderboard_ui <- nav_panel(
  "The Leaderboard",

  radioButtons(
    "leaderboard_rank_by",
    label = "Rank By:",
    choices = c(
      "Subscribers", "Total Views", "Videos", "New Videos (30d)",
      "Views (30d)", "7D Avg Views", "Sub Growth (30d)",
      "Sub % Growth (30d)", "Views/Video (30d)", "Views/Sub (30d)"
    ),
    inline = TRUE,
    selected = "Views (30d)"
  ),
  uiOutput("leaderboard_reactable")
)

# Server ----
leaderboard_server <- function(input, output, session) {

  # Column sets ----
  channel_dim_cols <- c(
    "profile_pic", "channel_title", "channel_handle",
    "subscriber_count", "view_count", "video_count",
    "new_videos_30d", "total_views_30d", "views_moving_avg_7d",
    "total_subs_30d", "daily_new_subs_pct_growth",
    "views_per_vid_30d", "views_per_sub_30d"
  )

  rank_col_sets <- list(
    "Subscribers"          = c("sub_rank",                   channel_dim_cols),
    "Total Views"          = c("lifetime_view_rank",         channel_dim_cols),
    "Videos"               = c("video_count_rank",           channel_dim_cols),
    "New Videos (30d)"     = c("new_videos_30d_rank",        channel_dim_cols),
    "Views (30d)"          = c("view_rank",                  channel_dim_cols),
    "7D Avg Views"         = c("view_7d_avg_rank",           channel_dim_cols),
    "Sub Growth (30d)"     = c("daily_sub_rank",             channel_dim_cols),
    "Sub % Growth (30d)"   = c("daily_sub_growth_pct_rank",  channel_dim_cols),
    "Views/Video (30d)"    = c("views_per_vid_30d_rank",     channel_dim_cols),
    "Views/Sub (30d)"      = c("views_per_sub_30d_rank",     channel_dim_cols)
  )

  rank_col_names <- list(
    "Subscribers"          = "sub_rank",
    "Total Views"          = "lifetime_view_rank",
    "Videos"               = "video_count_rank",
    "New Videos (30d)"     = "new_videos_30d_rank",
    "Views (30d)"          = "view_rank",
    "7D Avg Views"         = "view_7d_avg_rank",
    "Sub Growth (30d)"     = "daily_sub_rank",
    "Sub % Growth (30d)"   = "daily_sub_growth_pct_rank",
    "Views/Video (30d)"    = "views_per_vid_30d_rank",
    "Views/Sub (30d)"      = "views_per_sub_30d_rank"
  )

  # Build the leaderboard table ----
  output$leaderboard_reactable <- renderUI({
    column_selection <- rank_col_sets[[input$leaderboard_rank_by]]
    rank_col         <- rank_col_names[[input$leaderboard_rank_by]]

    leaderboard_30d_sorted <- leaderboard_30d %>%
      select(all_of(column_selection)) %>%
      arrange(pick(1))

    channel_dimensions_colDefs <- list(
      profile_pic = colDef(
        name = "",
        maxWidth = 60,
        cell = function(value) {
          tags$img(
            src = value,
            height = "40px",
            width = "40px",
            style = "border-radius: 50%; object-fit: cover;"
          )
        }
      ),
      channel_title = colDef(name = "Creator", minWidth = 150),
      channel_handle = colDef(
        name = "Handle",
        minWidth = 120,
        style = list(whiteSpace = "nowrap"),
        cell = function(value) {
          tags$a(
            href = paste0("https://www.youtube.com/", value),
            target = "_blank",
            value
          )
        }
      ),
      subscriber_count = colDef(
        name = "Subscribers",
        align = "right",
        cell = function(value) {
          if (value < 1000) {
            formatC(value, format = "d", big.mark = ",")
          } else {
            paste0("~", format_youtube_style(value))
          }
        }
      ),
      view_count          = colDef(name = "Total Views",       format = colFormat(separators = TRUE)),
      video_count         = colDef(name = "Videos",            format = colFormat(separators = TRUE)),
      new_videos_30d      = colDef(name = "New Videos (30d)",  format = colFormat(separators = TRUE)),
      total_views_30d     = colDef(name = "Views (30d)",       format = colFormat(separators = TRUE)),
      views_moving_avg_7d = colDef(name = "7D Avg Views",      format = colFormat(separators = TRUE)),
      total_subs_30d = colDef(
        name = "Sub Growth (30d)",
        align = "right",
        cell = function(value, index) {
          sub_count <- leaderboard_30d_sorted$subscriber_count[index]
          if (sub_count < 1000) {
            formatC(value, format = "d", big.mark = ",")
          } else if (value == 0) {
            paste0("< ", formatC(
              10 ^ (floor(log10(sub_count)) - 2),
              format = "d", big.mark = ","
            ))
          } else {
            paste0("~", formatC(value, format = "d", big.mark = ","))
          }
        }
      ),
      daily_new_subs_pct_growth = colDef(
        name = "Sub % Growth (30d)",
        align = "right",
        cell = function(value, index) {
          paste0(value, "%")
        }
      ),
      views_per_vid_30d = colDef(name = "Views/Video (30d)", format = colFormat(separators = TRUE)),
      views_per_sub_30d = colDef(name = "Views/Sub (30d)",   format = colFormat(separators = TRUE))
    )

    leaderboard_colDefs <- c(
      setNames(
        list(colDef(name = "Rank", maxWidth = 100)),
        rank_col
      ),
      channel_dimensions_colDefs
    )

    output$leaderboard_table <- renderReactable({
      reactable(
        leaderboard_30d_sorted,
        columns = leaderboard_colDefs,
        highlight = TRUE,
        striped = TRUE,
        searchable = TRUE,
        filterable = FALSE,
        showPageSizeOptions = TRUE,
        compact = FALSE,
      )
    })

    tagList(
      reactableOutput("leaderboard_table"),
      tags$p(
        class = "text-muted fst-italic mt-2 px-1 small",
        "† Subscriber Count and Sub Growth (30d) are subject to YouTube's API
       resolution limits. Values are shown as reported and marked with ~ to
       indicate potential rounding. Channels with fewer than 1,000 subscribers
       are reported exactly. All other columns reflect precise values."
      ),
      tags$p(
        class = "text-muted fst-italic mt-2 px-1 small",
        "†† Negative trailing averages indicate significant recent content removal,
       which affects rolling calculations. This may reflect a channel
       restructuring or content strategy change."
      )
    )
  })
}
