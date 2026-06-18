/* ====================================================================
   Layer: 03_Marts
   Purpose: Incrementally build historical snapshots of rolling-window
            channel metrics. Supports backfill via start_date/end_date
            procedure parameters.
   
   Composite Key: channel_id + snapshot_date + window_days
   
   Match Behavior: UPDATE only when any metric value has drifted
                   (e.g. a late-arriving row corrects a prior snapshot).
   
   Parameters (passed by calling procedure):
     @start_date  DATE  -- First snapshot_date to process
     @end_date    DATE  -- Last snapshot_date to process
     @window_days INT64 -- How many days to look back from each snapshot_date
==================================================================== */
DECLARE start_date DATE;
DECLARE end_date DATE;
DECLARE window_days DATE;

MERGE `yt-sailing-dashboard.yt_sailing_data.mart_channel_metrics` AS T

USING (
  SELECT
    -- Composite key
    anchor.date    AS snapshot_date,
    anchor.channel_id,
    @window_days   AS window_days,

    -- Channel lifetime metrics (most recent value in window)
    ARRAY_LAST(ARRAY_AGG(hist.subscriber_count      ORDER BY hist.date)) AS subscriber_count,
    ARRAY_LAST(ARRAY_AGG(hist.view_count            ORDER BY hist.date)) AS view_count,
    ARRAY_LAST(ARRAY_AGG(hist.video_count           ORDER BY hist.date)) AS video_count,

    -- 7-day rolling average views (most recent value in window)
    ROUND(
      ARRAY_LAST(ARRAY_AGG(hist.views_moving_avg_7d ORDER BY hist.date))
    , 2) AS views_moving_avg_7d,
    
    -- Lifetime views per video (most recent value in window)
    ARRAY_LAST(ARRAY_AGG(hist.lifetime_views_per_vid ORDER BY hist.date)) AS lifetime_views_per_vid,
    
    -- Rolling window sums
    SUM(hist.daily_new_views) AS total_views_window,
    SUM(hist.daily_new_subs)  AS total_subs_window,

    -- New videos published within window
    ARRAY_LAST(ARRAY_AGG(hist.video_count  ORDER BY hist.date)) -
    ARRAY_FIRST(ARRAY_AGG(hist.video_count ORDER BY hist.date)) AS new_videos_window,

    -- Subscriber conversion efficiency
    SAFE_DIVIDE(SUM(hist.daily_new_subs), SUM(hist.daily_new_views)) * 1000 AS sub_conversion_rate,

    -- Most recent daily subs value in window
    ARRAY_LAST(ARRAY_AGG(hist.daily_new_subs ORDER BY hist.date)) AS daily_new_subs,

    -- Sub growth as % of subscriber base
    ROUND(
      SAFE_DIVIDE(SUM(hist.daily_new_subs), MAX(hist.subscriber_count)) * 100
    , 2) AS subs_pct_growth,

    -- Algorithm performance: window views spread across catalogue
    ROUND(SAFE_DIVIDE(SUM(hist.daily_new_views), MAX(hist.video_count)),      3) AS views_per_vid_window,

    -- Audience activation: window views relative to subscriber base
    ROUND(SAFE_DIVIDE(SUM(hist.daily_new_views), MAX(hist.subscriber_count)), 3) AS views_per_sub_window

  FROM
    `yt-sailing-dashboard.yt_sailing_data.fct_daily_performance` AS anchor
  INNER JOIN
    `yt-sailing-dashboard.yt_sailing_data.fct_daily_performance` AS hist
      ON  hist.channel_id = anchor.channel_id
      AND hist.date BETWEEN DATE_SUB(anchor.date, INTERVAL @window_days DAY) AND anchor.date
  WHERE
    anchor.date BETWEEN @start_date AND @end_date
  GROUP BY
    anchor.date,
    anchor.channel_id

) AS S

ON  T.channel_id    = S.channel_id
AND T.snapshot_date = S.snapshot_date
AND T.window_days   = S.window_days

WHEN MATCHED AND (
    T.subscriber_count       IS DISTINCT FROM S.subscriber_count       OR
    T.view_count             IS DISTINCT FROM S.view_count             OR
    T.video_count            IS DISTINCT FROM S.video_count            OR
    T.total_views_window     IS DISTINCT FROM S.total_views_window     OR
    T.total_subs_window      IS DISTINCT FROM S.total_subs_window      OR
    T.new_videos_window      IS DISTINCT FROM S.new_videos_window      OR
    T.views_moving_avg_7d    IS DISTINCT FROM S.views_moving_avg_7d    OR
    T.sub_conversion_rate    IS DISTINCT FROM S.sub_conversion_rate    OR
    T.daily_new_subs         IS DISTINCT FROM S.daily_new_subs         OR
    T.subs_pct_growth        IS DISTINCT FROM S.subs_pct_growth        OR
    T.lifetime_views_per_vid IS DISTINCT FROM S.lifetime_views_per_vid OR
    T.views_per_vid_window   IS DISTINCT FROM S.views_per_vid_window   OR
    T.views_per_sub_window   IS DISTINCT FROM S.views_per_sub_window
) THEN UPDATE SET
    T.subscriber_count       = S.subscriber_count,
    T.view_count             = S.view_count,
    T.video_count            = S.video_count,
    T.total_views_window     = S.total_views_window,
    T.total_subs_window      = S.total_subs_window,
    T.new_videos_window      = S.new_videos_window,
    T.views_moving_avg_7d    = S.views_moving_avg_7d,
    T.sub_conversion_rate    = S.sub_conversion_rate,
    T.daily_new_subs         = S.daily_new_subs,
    T.subs_pct_growth        = S.subs_pct_growth,
    T.lifetime_views_per_vid = S.lifetime_views_per_vid,
    T.views_per_vid_window   = S.views_per_vid_window,
    T.views_per_sub_window   = S.views_per_sub_window,
    T.updated_at             = CURRENT_TIMESTAMP()

WHEN NOT MATCHED THEN INSERT (
    channel_id,
    snapshot_date,
    window_days,
    subscriber_count,
    view_count,
    video_count,
    total_views_window,
    total_subs_window,
    new_videos_window,
    views_moving_avg_7d,
    sub_conversion_rate,
    daily_new_subs,
    subs_pct_growth,
    lifetime_views_per_vid,
    views_per_vid_window,
    views_per_sub_window,
    created_at,
    updated_at
) VALUES (
    S.channel_id,
    S.snapshot_date,
    S.window_days,
    S.subscriber_count,
    S.view_count,
    S.video_count,
    S.total_views_window,
    S.total_subs_window,
    S.new_videos_window,
    S.views_moving_avg_7d,
    S.sub_conversion_rate,
    S.daily_new_subs,
    S.subs_pct_growth,
    S.lifetime_views_per_vid,
    S.views_per_vid_window,
    S.views_per_sub_window,
    CURRENT_TIMESTAMP(),
    CURRENT_TIMESTAMP()
);