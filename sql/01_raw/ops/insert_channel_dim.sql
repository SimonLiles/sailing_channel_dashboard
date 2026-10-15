/* ====================================================================
   Layer: 01_Raw / Ops
   Purpose: Insert a new channel dimension row for admin channel creation.
   Logic:
    - Inserts one row keyed by channel id with active flag set on create.
    - Caller supplies identity and metadata values via named params.
   Dialect: BigQuery Standard SQL with named params.
==================================================================== */

INSERT INTO `{{project}}.{{dataset}}.channel_dimensions` (
    channel_id,
    channel_handle,
    is_active,
    status,
    type,
    added_by,
    created_at,
    updated_at
)
VALUES (
    @channel_id,
    @channel_handle,
    TRUE,
    @status,
    @type,
    @added_by,
    CURRENT_TIMESTAMP(),
    CURRENT_TIMESTAMP()
);
