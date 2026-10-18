/* ====================================================================
   Layer: 00_Utils
   Purpose: Check whether a channel exists in channel dimensions.
   Logic:
    - Looks up a single channel by channel id.
    - Returns identity and active flag for admin channel management.
   Dialect: BigQuery Standard SQL with named params.
==================================================================== */

SELECT channel_id, channel_handle, is_active
FROM `{{project}}.{{dataset}}.channel_dimensions`
WHERE channel_id = @channel_id;
