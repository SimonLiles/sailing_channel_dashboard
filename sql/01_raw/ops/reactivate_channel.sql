/* ====================================================================
   Layer: 01_Raw / Ops
   Purpose: Reactivate a previously deactivated channel dimension row.
   Logic:
    - Sets the active flag back to true for the given channel id.
    - Guard on inactive rows only so active rows are never rewritten.
   Dialect: BigQuery Standard SQL with named params.
==================================================================== */

UPDATE `{{project}}.{{dataset}}.channel_dimensions`
SET is_active = TRUE, updated_at = CURRENT_TIMESTAMP()
WHERE channel_id = @channel_id AND is_active = FALSE;
