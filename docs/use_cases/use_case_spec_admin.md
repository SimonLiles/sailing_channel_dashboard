# Sailing Channel Dashboard — Administration System

## Use Case Specification

**Document Status:** Draft  
**Version:** 1.0  
**Date:** August 17, 2026  
**Source Document:** Sailing Channel Dashboard — Administration System (v1.0, August 7, 2026)

---

# 1. Introduction

This document defines the formal Use Case specification for the Sailing Channel Dashboard Administration System. It is derived from the Administration System Product Specification and covers all V1 functional capabilities.

Each use case specifies actors, preconditions, triggers, main flow, alternative flows, exception flows, postconditions, and traceability to business rules and source specification sections.

---

# 2. Actors

| Actor | Description |
|-------|-------------|
| **Owner** | Highest-level administrative role. Exactly one Owner exists at all times. Has all administrative capabilities. Cannot be deleted, suspended, or demoted. |
| **Super Admin** | Broad administrative privileges. Subordinate to Owner. May manage users, assign roles, manage channels, view analytics, view health, view audit log. |
| **Channel Manager** | Responsible for maintaining the tracked channel inventory. May view, add, bulk-import, deactivate, and reactivate channels. |
| **Analyst** | Read-only operational/analytics user. May view usage analytics, channel-interest analytics, and system health. |
| **System** | Internal system components (YouTube Data API, BigQuery, CloudSQL, ETL process) that participate in use case flows but are not primary actors. |

## 2.1 RBAC Capability Matrix

| Capability | Owner | Super Admin | Channel Manager | Analyst |
|---|:---:|:---:|:---:|:---:|
| View admin home | ✓ | ✓ | ✓ | ✓ |
| View channel inventory | ✓ | ✓ | ✓ | — |
| Add channel | ✓ | ✓ | ✓ | — |
| Bulk import channels | ✓ | ✓ | ✓ | — |
| Deactivate channel | ✓ | ✓ | ✓ | — |
| Reactivate channel | ✓ | ✓ | ✓ | — |
| View usage analytics | ✓ | ✓ | — | ✓ |
| View system health | ✓ | ✓ | ✓ | ✓ |
| Manage admin users | ✓ | ✓ | — | — |
| Assign roles | ✓ | ✓ | — | — |
| Transfer ownership | ✓ | — | — | — |
| View audit log | ✓ | ✓ | — | — |

*Source: §8, §55*

---

# 3. Use Case Index

| ID | Name | Domain | Primary Actor |
|----|------|--------|---------------|
| UC-1.1 | Authenticate Administrator | Authentication & Authorization | Authenticated User |
| UC-1.2 | Authorize Administrator | Authentication & Authorization | System |
| UC-1.3 | Provision Administrator | Authentication & Authorization | Owner / Super Admin |
| UC-1.4 | Suspend Administrator | Authentication & Authorization | Owner / Super Admin |
| UC-1.5 | Deprovision Administrator | Authentication & Authorization | Owner / Super Admin |
| UC-1.6 | Assign Role | Authentication & Authorization | Owner / Super Admin |
| UC-1.7 | Change Role | Authentication & Authorization | Owner / Super Admin |
| UC-1.8 | Transfer Ownership | Authentication & Authorization | Owner |
| UC-2.1 | View Channel Inventory | Channel Management | Owner / Super Admin / Channel Manager |
| UC-2.2 | Add Channel | Channel Management | Owner / Super Admin / Channel Manager |
| UC-2.3 | Deactivate Channel | Channel Management | Owner / Super Admin / Channel Manager |
| UC-2.4 | Reactivate Channel | Channel Management | Owner / Super Admin / Channel Manager |
| UC-2.5 | Bulk Import Channels | Channel Management | Owner / Super Admin / Channel Manager |
| UC-2.6 | Review Bulk Import | Channel Management | Owner / Super Admin / Channel Manager |
| UC-2.7 | Review Import Results | Channel Management | Owner / Super Admin / Channel Manager |
| UC-3.1 | View Admin Home Dashboard | Monitoring | All authenticated users |
| UC-3.2 | View Usage Analytics | Monitoring | Owner / Super Admin / Analyst |
| UC-3.3 | View ETL Health | Monitoring | Owner / Super Admin / Channel Manager / Analyst |
| UC-3.4 | View Data Freshness | Monitoring | Owner / Super Admin / Channel Manager / Analyst |
| UC-3.5 | View Dashboard Health | Monitoring | Owner / Super Admin / Channel Manager / Analyst |
| UC-3.6 | View Channel Interest Analytics | Monitoring | Owner / Super Admin / Analyst |
| UC-4.1 | View Audit Log | Audit | Owner / Super Admin |

---

# 4. Domain 1 — Authentication & Authorization

---

## UC-1.1 — Authenticate Administrator

**Domain:** Authentication & Authorization  
**Primary Actor:** Authenticated User (Google Identity)  
**Secondary Actor:** System (Google OAuth / Firebase Authentication)  
**Source Spec:** §7.1, §7.2, §7.3, §7.4, §45, §57 (items 1–2)

### Preconditions

1. The Administration System is deployed and operational.
2. Google OAuth or Firebase Authentication is configured.
3. The user possesses a valid Google identity (individual or Workspace).

### Triggers

The user navigates to the Administration System URL and initiates sign-in.

### Main Flow

1. System presents the sign-in page.
2. User initiates Google authentication.
3. System redirects to Google identity provider.
4. User authenticates with Google credentials.
5. Google returns an authenticated identity (identity provider ID, email).
6. System receives the authenticated identity.
7. System looks up the identity provider identifier in CloudSQL administrative accounts.
8. **If** an active administrative account matches the identity provider identifier:
   - System establishes an authenticated session.
   - System proceeds to UC-1.2 (Authorize Administrator).
9. **If** no matching administrative account exists:
   - System denies access (UC-1.2 Exception Flow).
   - System displays an "access denied" message.

### Alternative Flows

**AF-1: Workspace Domain Restriction (Future)**  
The architecture shall permit future restriction of administrative access to the organization's Google Workspace domain. Not implemented in V1.

### Exception Flows

**EF-1: Google Authentication Failure**  
If Google authentication fails (invalid credentials, cancelled flow, network error), system displays an appropriate error and does not create a session.

**EF-2: Unprovisioned User**  
If the Google identity is valid but no corresponding administrative account exists, system denies access. Successful Google authentication does not automatically create an administrative account.

### Postconditions

1. An authenticated session is established if and only if the identity matches an active provisioned administrative account.
2. No session is created for unprovisioned users.

### Business Rules

- **BR-005** — Successful Google authentication does not automatically create an administrative account.
- **NFR-001** — The system shall enforce authenticated access to all administrative capabilities.

---

## UC-1.2 — Authorize Administrator

**Domain:** Authentication & Authorization  
**Primary Actor:** System  
**Secondary Actor:** Authenticated Administrator  
**Source Spec:** §8, §45, §57 (item 3)

### Preconditions

1. The administrator has successfully authenticated (UC-1.1).
2. An active administrative account exists in CloudSQL.

### Triggers

Successful completion of UC-1.1.

### Main Flow

1. System retrieves the authenticated user's administrative account from CloudSQL.
2. System reads the assigned role for the account.
3. System evaluates the role's permitted capabilities against the requested resource or action.
4. **If** the role permits the requested capability:
   - System grants access.
   - System renders the UI elements and navigation appropriate to the role.
5. **If** the role does not permit the requested capability:
   - System denies access to the resource.
   - System does not render UI elements for unauthorized capabilities.

### Alternative Flows

**AF-1: Role Change During Session**  
If the administrator's role is changed by another administrator during an active session, authorization is re-evaluated on the next request. The session is not automatically terminated but capabilities are adjusted immediately.

### Exception Flows

**EF-1: Suspended Account**  
If the administrative account is suspended, system denies access and terminates the session.

**EF-2: Deprovisioned Account**  
If the administrative account has been deprovisioned, system denies access and terminates the session.

### Postconditions

1. The administrator can only access capabilities permitted by their assigned role.
2. UI elements for unauthorized capabilities are not presented.

### Business Rules

- **BR-004** — Administrators cannot grant themselves greater privileges.
- **NFR-001** — The system shall enforce role-based access to all administrative capabilities.
- **NFR-002** — Every administrative mutation shall be traceable to an authenticated administrator.

---

## UC-1.3 — Provision Administrator

**Domain:** Authentication & Authorization  
**Primary Actor:** Owner / Super Admin  
**Secondary Actor:** System (CloudSQL, Google Identity Provider)  
**Source Spec:** §7.2, §9, §57 (items 4–5)

### Preconditions

1. The provisioning administrator is authenticated and authorized (Owner or Super Admin).
2. The target user possesses a Google identity (individual or Workspace account).

### Triggers

The administrator navigates to the Administration / Users page and selects "Provision New Administrator."

### Main Flow

1. System displays a provisioning form.
2. Administrator enters the target user's Google identity information (email or identity provider identifier).
3. Administrator selects a role for the new account.
4. System validates the input:
   - Verifies the identity is not already provisioned.
   - Verifies the role is valid.
   - **If** the provisioning administrator is a Super Admin, verifies they are not assigning the Owner role.
5. System creates the administrative account in CloudSQL with:
   - Identity provider identifier.
   - Email address (as attribute).
   - Assigned role.
   - Status: Active.
6. System records an audit event: Administrator created, with actor, target, role, and timestamp.
7. System displays a confirmation to the provisioning administrator.
8. The target user can now authenticate and access the system per their assigned role (UC-1.1, UC-1.2).

### Alternative Flows

**AF-1: Super Admin Cannot Create Owner**  
A Super Admin may not create an Owner account. The Owner role is only achievable through ownership transfer (UC-1.8).

### Exception Flows

**EF-1: Duplicate Identity**  
If the Google identity is already provisioned as an administrative account, system informs the administrator and takes no action.

**EF-2: Invalid Input**  
If required fields are missing or the role is invalid, system displays a validation error and retains form state.

### Postconditions

1. A new active administrative account exists in CloudSQL.
2. The account has the specified role.
3. The operation is recorded in the audit log.

### Business Rules

- **BR-005** — Successful Google authentication does not automatically create an administrative account.
- **BR-004** — Administrators cannot grant themselves greater privileges (Super Admin cannot create Owner).

---

## UC-1.4 — Suspend Administrator

**Domain:** Authentication & Authorization  
**Primary Actor:** Owner / Super Admin  
**Secondary Actor:** System (CloudSQL)  
**Source Spec:** §9, §10, §45, §57 (items 4–5)

### Preconditions

1. The suspending administrator is authenticated and authorized (Owner or Super Admin).
2. The target administrative account exists and is active.
3. The target is **not** the Owner.

### Triggers

The administrator navigates to the Administration / Users page, selects a target administrator, and selects "Suspend."

### Main Flow

1. System displays the target administrator's account details.
2. System prompts the administrator to confirm suspension.
3. Administrator confirms the suspension.
4. System sets the target account status to "Suspended" in CloudSQL.
5. System terminates any active session for the suspended administrator.
6. System records an audit event: Administrator suspended, with actor, target, previous status, and timestamp.
7. System displays a confirmation.

### Alternative Flows

**AF-1: Owner Protection**  
The Owner cannot be suspended. If the target is the Owner, the suspend action is not available in the UI and is rejected by the system.

### Exception Flows

**EF-1: Target Is Owner**  
System rejects the operation and displays an error: "The Owner account cannot be suspended."

**EF-2: Target Already Suspended**  
System informs the administrator that the account is already suspended.

### Postconditions

1. The target account status is "Suspended."
2. The target cannot authenticate or access the system.
3. Historical audit records associated with the account are preserved.
4. The operation is recorded in the audit log.

### Business Rules

- **BR-003** — The Owner cannot be deleted, suspended, or demoted through ordinary administrative operations.
- **NFR-002** — Every administrative mutation shall be traceable.

---

## UC-1.5 — Deprovision Administrator

**Domain:** Authentication & Authorization  
**Primary Actor:** Owner / Super Admin  
**Secondary Actor:** System (CloudSQL)  
**Source Spec:** §9, §10, §45, §57 (items 4–5)

### Preconditions

1. The deprovisioning administrator is authenticated and authorized (Owner or Super Admin).
2. The target administrative account exists.
3. The target is **not** the Owner.

### Triggers

The administrator navigates to the Administration / Users page, selects a target administrator, and selects "Deprovision."

### Main Flow

1. System displays the target administrator's account details.
2. System warns that deprovisioning is permanent and prompts for explicit confirmation.
3. Administrator confirms the deprovisioning.
4. System sets the target account status to "Deprovisioned" in CloudSQL.
5. System terminates any active session for the deprovisioned administrator.
6. System preserves the account record and associated audit history.
7. System records an audit event: Administrator deprovisioned, with actor, target, and timestamp.
8. System displays a confirmation.

### Alternative Flows

**AF-1: Owner Protection**  
The Owner cannot be deprovisioned. If the target is the Owner, the deprovision action is not available.

### Exception Flows

**EF-1: Target Is Owner**  
System rejects the operation and displays an error: "The Owner account cannot be deprovisioned."

**EF-2: Target Already Deprovisioned**  
System informs the administrator that the account is already deprovisioned.

### Postconditions

1. The target account status is "Deprovisioned."
2. The target cannot authenticate or access the system.
3. The account record and associated audit history are preserved (not destroyed).
4. The operation is recorded in the audit log.

### Business Rules

- **BR-003** — The Owner cannot be deleted, suspended, or demoted through ordinary administrative operations.
- **NFR-002** — Every administrative mutation shall be traceable.

---

## UC-1.6 — Assign Role

**Domain:** Authentication & Authorization  
**Primary Actor:** Owner / Super Admin  
**Secondary Actor:** System (CloudSQL)  
**Source Spec:** §8, §9, §45, §57 (items 4–5)

### Preconditions

1. The assigning administrator is authenticated and authorized (Owner or Super Admin).
2. The target administrative account exists and is active.
3. The target is **not** the Owner (Owner role is assigned only through ownership transfer).

### Triggers

The administrator navigates to the Administration / Users page, selects a target administrator, and selects "Change Role."

### Main Flow

1. System displays the target administrator's current account details and role.
2. System presents available roles.
3. Administrator selects a new role.
4. System validates:
   - The new role is different from the current role.
   - The assigning administrator has authority to assign the selected role (Super Admin cannot assign Owner).
5. System updates the target account's role in CloudSQL.
6. The role change takes effect immediately or on the next authorization evaluation.
7. System records an audit event: Administrator role changed, with actor, target, previous role, new role, and timestamp.
8. System displays a confirmation.

### Alternative Flows

**AF-1: Same Role**  
If the administrator selects the same role, system informs them no change is needed.

### Exception Flows

**EF-1: Super Admin Cannot Assign Owner**  
A Super Admin may not assign the Owner role. Owner role is only achievable through ownership transfer (UC-1.8).

**EF-2: Target Is Owner**  
The Owner's role cannot be changed through ordinary role-management operations.

### Postconditions

1. The target account has the new role.
2. The capability set available to the target changes accordingly.
3. The operation is recorded in the audit log.

### Business Rules

- **BR-003** — The Owner cannot be demoted through ordinary administrative operations.
- **BR-004** — Administrators cannot grant themselves greater privileges.

---

## UC-1.7 — Change Role

**Domain:** Authentication & Authorization  
**Primary Actor:** Owner / Super Admin  
**Secondary Actor:** System (CloudSQL)  
**Source Spec:** §8, §9, §45, §57 (items 4–5)

### Preconditions

1. The changing administrator is authenticated and authorized (Owner or Super Admin).
2. The target administrative account exists and is active.
3. The target is **not** the Owner.

### Triggers

The administrator initiates a role change on the Administration / Users page.

### Main Flow

1. System displays the target administrator's current role.
2. Administrator selects a new role from the available options.
3. System validates the change against authorization rules.
4. System updates the role in CloudSQL.
5. The change takes effect immediately or on the next authorization evaluation.
6. System records an audit event with previous and new role.
7. System displays a confirmation.

### Alternative Flows

**AF-1: Immediate Effect**  
The role change takes effect immediately. If the target user has an active session, their capabilities are adjusted on the next request.

### Exception Flows

**EF-1: Self-Elevation Prevention**  
An administrator cannot elevate their own role. System rejects the operation.

### Postconditions

1. The target account reflects the new role.
2. Authorization is re-evaluated based on the new role.
3. The operation is recorded in the audit log.

### Business Rules

- **BR-004** — Administrators cannot grant themselves greater privileges.
- **NFR-002** — Every administrative mutation shall be traceable.

---

## UC-1.8 — Transfer Ownership

**Domain:** Authentication & Authorization  
**Primary Actor:** Owner  
**Secondary Actor:** System (CloudSQL)  
**Source Spec:** §10, §45, §57 (items 4–5)

### Preconditions

1. The Owner is authenticated.
2. Exactly one Owner exists in the system.
3. A target administrator exists, is active, and is not the current Owner.

### Triggers

The Owner navigates to the Administration / Users page and selects "Transfer Ownership."

### Main Flow

1. System displays the ownership transfer interface.
2. Owner selects the target administrator to receive ownership.
3. System displays a prominent warning explaining:
   - Ownership will be transferred.
   - The current Owner will become a Super Admin (unless otherwise specified).
   - The operation is irreversible through ordinary operations.
4. Owner explicitly confirms the transfer.
5. System atomically:
   - Sets the current Owner's role to Super Admin.
   - Sets the target's role to Owner.
6. System enforces the invariant: exactly one Owner exists.
7. System records an audit event: Ownership transferred, with previous Owner, new Owner, and timestamp.
8. System displays a confirmation.
9. The current Owner's session continues with Super Admin capabilities.

### Alternative Flows

**AF-1: Specified Post-Transfer Role**  
The current Owner may specify a role other than Super Admin for themselves following transfer. This must be a valid role.

### Exception Flows

**EF-1: Target Is Current Owner**  
System rejects the operation: cannot transfer ownership to yourself.

**EF-2: Confirmation Not Provided**  
If the Owner does not explicitly confirm, system takes no action.

### Postconditions

1. Exactly one Owner exists.
2. The previous Owner is no longer Owner.
3. The new Owner has all Owner capabilities.
4. The previous Owner's role is Super Admin (or as specified).
5. The operation is recorded in the audit log.
6. Ownership transfer is fully audited.

### Business Rules

- **BR-001** — There must always be exactly one Owner.
- **BR-002** — Ownership may be transferred by the current Owner.
- **BR-003** — The Owner cannot be deleted, suspended, or demoted through ordinary administrative operations (but ownership transfer is an explicit exception).

---

# 5. Domain 2 — Channel Management

---

## UC-2.1 — View Channel Inventory

**Domain:** Channel Management  
**Primary Actor:** Owner / Super Admin / Channel Manager  
**Secondary Actor:** System (BigQuery `channel_dimensions`)  
**Source Spec:** §19, §43, §57 (items 7–8)

### Preconditions

1. The administrator is authenticated and authorized (Owner, Super Admin, or Channel Manager).

### Triggers

The administrator navigates to the Channel Inventory page.

### Main Flow

1. System queries BigQuery `channel_dimensions` for all tracked channels.
2. System displays the Channel Inventory page with all channels (active and inactive).
3. For each channel, system displays:
   - Channel title.
   - Channel handle.
   - Channel ID.
   - Active/inactive status.
   - Date added.
   - Added by.
   - Last updated.
   - Relevant data/ETL status where available.
4. Administrator may filter or search the inventory.
5. Actions available are determined by the administrator's role.

### Alternative Flows

**AF-1: Filtering**  
Administrator may filter by status (active/inactive), date range, or other supported criteria.

**AF-2: Search**  
Administrator may search by channel title, handle, or channel ID.

### Exception Flows

**EF-1: Data Source Unavailable**  
If BigQuery is unavailable, system displays an appropriate error message.

### Postconditions

1. The administrator has visibility into the complete channel inventory.
2. Channel metadata is read-only.

### Business Rules

- **BR-006** — `channel_id` is the authoritative channel identity.
- **BR-008** — Administrators cannot manually edit YouTube-derived channel metadata.

---

## UC-2.2 — Add Channel

**Domain:** Channel Management  
**Primary Actor:** Owner / Super Admin / Channel Manager  
**Secondary Actor:** System (YouTube Data API, BigQuery `channel_dimensions`)  
**Source Spec:** §11, §12, §13, §14, §15, §57 (items 9–13)

### Preconditions

1. The administrator is authenticated and authorized (Owner, Super Admin, or Channel Manager).

### Triggers

The administrator navigates to the Add Channel page and enters a YouTube channel handle.

### Main Flow

1. System displays the Add Channel form.
2. Administrator enters a YouTube channel handle.
3. System validates the handle format.
4. System resolves the handle to a YouTube `channel_id` via the YouTube Data API.
5. System checks `channel_dimensions` in BigQuery for an existing record:
   - **If** no existing record: system retrieves YouTube-derived metadata (title, description, join date, subscriber visibility, keywords, profile picture).
   - **If** existing active record: system informs the administrator that the channel is already being tracked. No further action (see UC-2.2 AF-1).
   - **If** existing inactive record: system informs the administrator the channel is inactive and requests explicit confirmation before reactivating (see UC-2.2 AF-2).
6. System displays the channel information for administrator review.
7. Administrator explicitly confirms the addition.
8. System inserts the channel into BigQuery `channel_dimensions` with `is_active = TRUE`.
9. The channel becomes eligible for collection by the next scheduled ETL execution.
10. System records an audit event: Channel added, with actor, channel_id, channel handle, and timestamp.

### Alternative Flows

**AF-1: Existing Active Channel**  
System informs the administrator the channel is already tracked and active. No duplicate channel is created. No further action.

**AF-2: Existing Inactive Channel**  
System informs the administrator the channel exists but is inactive. System requests explicit confirmation before reactivating. If confirmed:
- `is_active` is set to `TRUE`.
- Historical data remains intact.
- The channel resumes data collection on the next ETL run.
- The operation is audited.

**AF-3: YouTube Handle Lookup**  
The handle is used as a convenient lookup mechanism. The system resolves it to the authoritative `channel_id` via the YouTube Data API before adding.

### Exception Flows

**EF-1: Invalid Handle**  
If the handle is invalid or nonexistent, system displays an appropriate error and takes no action.

**EF-2: YouTube API Error**  
If the YouTube Data API returns an error (non-quota), system displays the error and preserves sufficient information to distinguish error types.

**EF-3: YouTube API Quota Error**  
If the YouTube Data API quota is exceeded, system displays a quota-specific error.

**EF-4: Network/API Failure**  
Other YouTube API failures are reported with sufficient detail for the administrator to understand the outcome.

### Postconditions

1. The new channel exists in BigQuery `channel_dimensions` with `is_active = TRUE`.
2. The channel will be collected by the next scheduled ETL run.
3. The operation is recorded in the audit log.
4. No ETL is triggered by this operation.

### Business Rules

- **BR-006** — `channel_id` is the authoritative channel identity.
- **BR-007** — Channel handles are a lookup mechanism, not authoritative identity.
- **BR-008** — Administrators cannot manually edit YouTube-derived channel metadata.
- **BR-012** — Newly activated channels are collected by the next scheduled ETL execution.

---

## UC-2.3 — Deactivate Channel

**Domain:** Channel Management  
**Primary Actor:** Owner / Super Admin / Channel Manager  
**Secondary Actor:** System (BigQuery `channel_dimensions`)  
**Source Spec:** §17, §45, §57 (items 15–17)

### Preconditions

1. The administrator is authenticated and authorized (Owner, Super Admin, or Channel Manager).
2. The target channel exists in `channel_dimensions` and is currently active.

### Triggers

The administrator selects a channel from the Channel Inventory and chooses "Deactivate."

### Main Flow

1. System displays the channel details and a deactivation warning.
2. System warns that:
   - The channel will be excluded from the active public dashboard.
   - Future ETL collection will cease for this channel.
   - Historical analytical data will be preserved.
   - The channel dimension record will be preserved.
3. Administrator explicitly confirms the deactivation.
4. System sets `channel_dimensions.is_active` to `FALSE`.
5. The channel is excluded from the active public dashboard product.
6. Future ETL collection is prevented for the inactive channel.
7. Historical analytical data is preserved.
8. The channel dimension record is preserved.
9. System records an audit event: Channel deactivated, with actor, channel_id, and timestamp.
10. System displays a confirmation.

### Alternative Flows

None.

### Exception Flows

**EF-1: Channel Not Found**  
If the channel does not exist in `channel_dimensions`, system displays an error.

**EF-2: Channel Already Inactive**  
If the channel is already inactive, system informs the administrator and takes no action.

**EF-3: Confirmation Not Provided**  
If the administrator does not confirm, system takes no action.

### Postconditions

1. The channel's `is_active` flag is `FALSE`.
2. The channel is excluded from the public dashboard.
3. Future ETL runs skip this channel.
4. Historical analytical data is preserved.
5. The operation is recorded in the audit log.

### Business Rules

- **BR-009** — Channel deletion means setting `is_active = FALSE`.
- **BR-010** — Channel deactivation never deletes historical analytical data.
- **BR-013** — ETL or YouTube API failures do not automatically deactivate channels.

---

## UC-2.4 — Reactivate Channel

**Domain:** Channel Management  
**Primary Actor:** Owner / Super Admin / Channel Manager  
**Secondary Actor:** System (BigQuery `channel_dimensions`)  
**Source Spec:** §18, §57 (item 16)

### Preconditions

1. The administrator is authenticated and authorized (Owner, Super Admin, or Channel Manager).
2. The target channel exists in `channel_dimensions` and is currently inactive.

### Triggers

The administrator selects an inactive channel from the Channel Inventory and chooses "Reactivate."

### Main Flow

1. System displays the channel details and a reactivation prompt.
2. System requests explicit administrator confirmation before reactivating.
3. Administrator confirms the reactivation.
4. System sets `channel_dimensions.is_active` to `TRUE`.
5. Historical data is preserved.
6. The channel will be picked up by the next scheduled ETL run.
7. System records an audit event: Channel reactivated, with actor, channel_id, and timestamp.
8. System displays a confirmation.

### Alternative Flows

None.

### Exception Flows

**EF-1: Channel Not Found**  
If the channel does not exist, system displays an error.

**EF-2: Channel Already Active**  
If the channel is already active, system informs the administrator and takes no action.

**EF-3: Confirmation Not Provided**  
If the administrator does not confirm, system takes no action. The channel remains inactive.

### Postconditions

1. The channel's `is_active` flag is `TRUE`.
2. Historical data is intact.
3. The channel will be collected by the next ETL run.
4. The operation is recorded in the audit log.

### Business Rules

- **BR-011** — Inactive channels require explicit administrator confirmation before reactivation.
- **BR-012** — Newly activated channels are collected by the next scheduled ETL execution.

---

## UC-2.5 — Bulk Import Channels

**Domain:** Channel Management  
**Primary Actor:** Owner / Super Admin / Channel Manager  
**Secondary Actor:** System (YouTube Data API, BigQuery `channel_dimensions`)  
**Source Spec:** §20, §21, §22, §23, §25, §57 (items 18–21)

### Preconditions

1. The administrator is authenticated and authorized (Owner, Super Admin, or Channel Manager).
2. The administrator has a CSV or XLSX file containing channel handles.

### Triggers

The administrator navigates to the Bulk Import page and uploads a spreadsheet.

### Main Flow

1. System accepts the uploaded CSV or XLSX file.
2. System parses the spreadsheet.
3. System validates all rows:
   - Validates handle format.
   - Resolves valid handles to YouTube `channel_id` values via the YouTube Data API.
   - Detects duplicate rows within the spreadsheet.
   - Checks each resolved channel against the existing inventory in `channel_dimensions`.
4. System classifies each row into one of the defined outcome categories (§22).
5. System displays a preview of the import:
   - Each row with its classification (new, existing active, existing inactive, invalid, error, duplicate).
   - For existing inactive channels: administrator must explicitly select/confirm reactivation for each.
6. Administrator reviews the preview.
7. Administrator explicitly confirms the bulk import.
8. System commits valid changes independently:
   - Each valid channel operation is committed independently.
   - One failed row does not cause successful rows to roll back.
9. System generates a results report (UC-2.7).
10. System records an audit event: Bulk import performed, with import identifier, file type, row count, successful count, failed count, and per-row outcomes.

### Alternative Flows

**AF-1: Inactive Channel Reactivation in Bulk**  
An inactive channel encountered during bulk import is **not** automatically reactivated. The administrator must explicitly select/confirm reactivation for each inactive channel in the preview. This prevents old spreadsheets from unintentionally reactivating channels.

**AF-2: Partial Success**  
Valid independent operations succeed even when other rows fail. One failed row does not cause successful rows to roll back.

### Exception Flows

**EF-1: Invalid File Format**  
If the file is not a valid CSV or XLSX, system displays an error and takes no action.

**EF-2: Empty Spreadsheet**  
If the spreadsheet contains no valid rows, system informs the administrator.

**EF-3: YouTube API Quota Exceeded**  
If the API quota is exhausted during resolution, system reports the quota error with sufficient rows resolved.

**EF-4: YouTube API Errors**  
Individual API failures are reported per-row without aborting the entire import.

### Postconditions

1. Valid new channels are inserted into BigQuery `channel_dimensions`.
2. Confirmed inactive channels are reactivated.
3. Invalid and failed rows are reported.
4. A results report is displayed.
5. The operation is fully audited.

### Business Rules

- **BR-006** — `channel_id` is the authoritative channel identity.
- **BR-011** — Inactive channels require explicit administrator confirmation before reactivation.
- **BR-014** — Bulk imports require validation and administrator confirmation before modifications occur.
- **BR-015** — A failure affecting one bulk-import row does not invalidate otherwise successful rows.
- **NFR-006** — Administrative operations shall not corrupt or duplicate the canonical BigQuery channel inventory.

---

## UC-2.6 — Review Bulk Import

**Domain:** Channel Management  
**Primary Actor:** Owner / Super Admin / Channel Manager  
**Secondary Actor:** System  
**Source Spec:** §21 (steps 6–9)

### Preconditions

1. A bulk import has been uploaded and validated (UC-2.5 steps 1–5).
2. The import preview is displayed.

### Triggers

Completion of bulk import validation (UC-2.5 step 5).

### Main Flow

1. System displays the import preview with each row classified:
   - New channel — will be added.
   - Existing active channel — no action.
   - Existing inactive channel — requires explicit reactivation decision.
   - Invalid handle.
   - YouTube API error.
   - YouTube API quota error.
   - Other API/processing error.
   - Duplicate spreadsheet entry.
2. Administrator reviews each classification.
3. For existing inactive channels, administrator explicitly selects whether to reactivate each.
4. Administrator confirms the import to proceed.

### Alternative Flows

**AF-1: Row-Level Detail**  
System provides sufficient row-level information for the administrator to understand the outcome for each row.

### Exception Flows

**EF-1: All Rows Invalid**  
If all rows are invalid or duplicates, system informs the administrator and the commit step is not available.

### Postconditions

1. The administrator has reviewed and confirmed the import plan.
2. No channel modifications have occurred during validation or preview.

### Business Rules

- **BR-014** — Bulk imports require validation and administrator confirmation before modifications occur.

---

## UC-2.7 — Review Import Results

**Domain:** Channel Management  
**Primary Actor:** Owner / Super Admin / Channel Manager  
**Secondary Actor:** System  
**Source Spec:** §24

### Preconditions

1. A bulk import has been confirmed and committed (UC-2.5 steps 8–9).

### Triggers

Completion of bulk import commit (UC-2.5 step 8).

### Main Flow

1. System generates a results report summarizing:
   - Total rows.
   - Successfully added.
   - Successfully reactivated.
   - Already active.
   - Invalid handles.
   - API errors.
   - Other errors.
   - Duplicate rows.
2. System displays the report to the administrator.
3. System provides row-level detail for unsuccessful operations.

### Alternative Flows

**AF-1: Downloadable Report (Future)**  
A downloadable report is not required for V1 but may be supported in future versions.

### Exception Flows

None.

### Postconditions

1. The administrator has visibility into the import outcomes.
2. Unsuccessful operations are identifiable at the row level.

### Business Rules

None directly. Supports BR-014 and BR-015 indirectly.

---

# 6. Domain 3 — Monitoring

---

## UC-3.1 — View Admin Home Dashboard

**Domain:** Monitoring  
**Primary Actor:** All authenticated users  
**Secondary Actor:** System (BigQuery, Google Analytics, ETL metadata, Cloud Run)  
**Source Spec:** §42, §43, §57 (items 22–24, 28–29)

### Preconditions

1. The user is authenticated and authorized.

### Triggers

The administrator navigates to the Administration System home page.

### Main Flow

1. System displays the Admin Home Dashboard.
2. The dashboard answers: **"Is the Sailing Channel Dashboard operating correctly right now?"**
3. System displays concise indicators for:
   - **Dashboard:** Visitor activity, sessions, unique users, recent page activity, popular channels.
   - **ETL:** Last execution, last successful execution, data freshness, processing status, recent failures.
   - **System:** Dashboard availability, relevant application health, significant recent errors.
4. The home page is an operational overview, not a replacement for detailed analytics.

### Alternative Flows

**AF-1: Mobile Presentation**  
Home health indicators are easily readable on mobile devices.

**AF-2: Data Unavailable**  
If a data source is temporarily unavailable, system displays an appropriate indicator rather than failing the entire page.

### Exception Flows

**EF-1: Partial Data**  
If only some data sources are available, system displays what is available with appropriate status indicators for unavailable sources.

### Postconditions

1. The administrator has a concise operational overview of the system's current state.

### Business Rules

- **NFR-003** — Core operational workflows shall be usable on mobile devices.
- **NFR-010** — The Administration System shall not become the authoritative analytical data store.

---

## UC-3.2 — View Usage Analytics

**Domain:** Monitoring  
**Primary Actor:** Owner / Super Admin / Analyst  
**Secondary Actor:** System (Google Analytics)  
**Source Spec:** §31, §32, §33, §34, §35, §37, §57 (items 25–28)

### Preconditions

1. The administrator is authenticated and authorized (Owner, Super Admin, or Analyst).
2. Google Analytics is configured as the data source.

### Triggers

The administrator navigates to the Usage Analytics page.

### Main Flow

1. System queries Google Analytics for aggregated usage data.
2. System displays usage analytics including:
   - Unique users.
   - Sessions.
   - Page views.
   - Geographic information (country, region/state where available, city where appropriate).
   - Device/technology information (desktop/mobile/tablet, browser, operating system).
   - Acquisition source (direct, search, social, referral sites).
3. System supports standard predefined time ranges and, where practical, a custom date range.
4. Google Analytics reporting latency is acceptable; real-time analytics are not required.

### Alternative Flows

**AF-1: Custom Date Range**  
Where practical, administrator may specify a custom date range.

**AF-2: Mobile Presentation**  
Analytics are presented in a mobile-appropriate format.

### Exception Flows

**EF-1: Google Analytics Unavailable**  
If Google Analytics data is unavailable, system displays an appropriate error.

### Postconditions

1. The administrator has aggregated visibility into public dashboard usage.
2. No visitor-level PII is exposed.

### Business Rules

- **BR-018** — Visitor analytics exposed to administrators are aggregated and do not expose visitor-level PII.
- **NFR-008** — Administrative analytics shall not expose visitor-level personally identifiable information.

---

## UC-3.3 — View ETL Health

**Domain:** Monitoring  
**Primary Actor:** Owner / Super Admin / Channel Manager / Analyst  
**Secondary Actor:** System (ETL metadata, BigQuery)  
**Source Spec:** §27, §42, §57 (item 22)

### Preconditions

1. The administrator is authenticated and authorized.
2. ETL operational metadata is available.

### Triggers

The administrator navigates to the System Health page or views the ETL section on the Admin Home Dashboard.

### Main Flow

1. System retrieves ETL operational health data.
2. System displays:
   - Last scheduled execution.
   - Last successful execution.
   - Execution duration.
   - Data freshness.
   - Number of channels processed.
   - Number of successful channels.
   - Number of failed channels.
   - Relevant error information.
3. System does **not** provide controls to trigger, cancel, retry, or modify ETL configuration.

### Alternative Flows

**AF-1: Mobile Presentation**  
ETL health information is accessible on mobile devices.

### Exception Flows

**EF-1: ETL Metadata Unavailable**  
If ETL metadata is unavailable, system displays an appropriate indicator.

### Postconditions

1. The administrator has visibility into ETL operational health.
2. No ETL execution controls are exposed.

### Business Rules

- **BR-019** — The Administration System observes ETL health but does not control ETL execution in V1.
- **NFR-010** — The Administration System shall not become the ETL processing engine.

---

## UC-3.4 — View Data Freshness

**Domain:** Monitoring  
**Primary Actor:** Owner / Super Admin / Channel Manager / Analyst  
**Secondary Actor:** System (BigQuery)  
**Source Spec:** §29, §57 (item 23)

### Preconditions

1. The administrator is authenticated and authorized.

### Triggers

The administrator navigates to the System Health page.

### Main Flow

1. System queries BigQuery for analytical data freshness indicators.
2. System displays:
   - Most recent available analytical date.
   - Whether data is current relative to the expected ETL schedule.
   - Whether recent ETL execution successfully populated the product.
   - Whether significant channel-processing failures occurred.

### Alternative Flows

**AF-1: Mobile Presentation**  
Data freshness information is accessible on mobile devices.

### Exception Flows

**EF-1: Data Unavailable**  
If freshness data cannot be determined, system displays an appropriate indicator.

### Postconditions

1. The administrator can determine whether the analytical data product is current and healthy.

### Business Rules

- **BR-020** — BigQuery remains authoritative for analytical product data.

---

## UC-3.5 — View Dashboard Health

**Domain:** Monitoring  
**Primary Actor:** Owner / Super Admin / Channel Manager / Analyst  
**Secondary Actor:** System (Cloud Run, YouTube Data API)  
**Source Spec:** §28, §30, §57 (item 24)

### Preconditions

1. The administrator is authenticated and authorized.

### Triggers

The administrator navigates to the System Health page.

### Main Flow

1. System retrieves application health indicators for the public dashboard.
2. System displays:
   - Availability.
   - Recent request errors.
   - HTTP error status information.
   - Relevant latency indicators.
   - Recent application failures.
3. Where useful, system exposes significant YouTube Data API failures affecting the data product:
   - Authentication/authorization failures.
   - Quota failures.
   - Request failures.
   - Channel lookup failures.
   - Other relevant API errors.
4. System distinguishes error types when the underlying API provides sufficient information.

### Alternative Flows

**AF-1: Mobile Presentation**  
Dashboard health information is accessible on mobile devices.

### Exception Flows

**EF-1: Health Data Unavailable**  
If health data cannot be retrieved, system displays an appropriate indicator.

### Postconditions

1. The administrator can determine whether the public dashboard is operating normally.
2. Significant YouTube API issues are surfaced.

### Business Rules

- **NFR-007** — External API failures shall not result in unintended destructive changes.

---

## UC-3.6 — View Channel Interest Analytics

**Domain:** Monitoring  
**Primary Actor:** Owner / Super Admin / Analyst  
**Secondary Actor:** System (Google Analytics / analytics events)  
**Source Spec:** §36, §37, §57 (item 27)

### Preconditions

1. The administrator is authenticated and authorized (Owner, Super Admin, or Analyst).
2. Channel interest analytics events are being collected.

### Triggers

The administrator navigates to the Usage Analytics page and views the Channel Interest section.

### Main Flow

1. System retrieves channel interest analytics.
2. For V1, channel interest is defined as: a user looking up a channel through Channel Explorer or Growth Benchmarks.
3. System displays aggregated channel interest data.
4. The analytics event conceptually contains: Channel ID, originating dashboard context/page.
5. Selecting a channel from a leaderboard does **not** count as channel interest in V1.

### Alternative Flows

**AF-1: Extensible Event Taxonomy**  
The analytics event taxonomy remains extensible so additional interactions can be added later without redesigning the analytics system.

### Exception Flows

**EF-1: No Interest Data**  
If no channel interest data is available, system displays an appropriate message.

### Postconditions

1. The administrator has visibility into which channels are generating interest.
2. Analytics are aggregated and privacy-preserving.

### Business Rules

- **BR-018** — Visitor analytics exposed to administrators are aggregated and do not expose visitor-level PII.

---

# 7. Domain 4 — Audit

---

## UC-4.1 — View Audit Log

**Domain:** Audit  
**Primary Actor:** Owner / Super Admin  
**Secondary Actor:** System (CloudSQL audit records)  
**Source Spec:** §38, §39, §40, §41, §57 (items 29–31)

### Preconditions

1. The administrator is authenticated and authorized (Owner or Super Admin).
2. Audit records exist in CloudSQL.

### Triggers

The administrator navigates to the Audit Log page.

### Main Flow

1. System queries CloudSQL for administrative audit records.
2. System displays the audit log with entries containing:
   - Actor.
   - Actor role at the time of action.
   - Timestamp.
   - Action.
   - Target entity type.
   - Target identifier.
   - Outcome.
   - Relevant before state.
   - Relevant after state.
   - Error information (where applicable).
   - Operation/import identifier (where applicable).
3. For bulk operations, additional information is displayed:
   - Import identifier.
   - File type.
   - Row count.
   - Successful count.
   - Failed count.
   - Per-row outcomes.
4. Audit records are append-only from the application perspective.
5. Audit records cannot be edited or deleted through the Administration System.

### Alternative Flows

**AF-1: Filtering**  
Administrator may filter the audit log by actor, action, date range, or target entity.

**AF-2: Mobile Presentation**  
Audit log is presented in a mobile-appropriate format.

### Exception Flows

**EF-1: Audit Data Unavailable**  
If audit data cannot be retrieved, system displays an appropriate error.

**EF-2: Unauthorized Access Attempt**  
If a Channel Manager or Analyst attempts to access the audit log, system denies access.

### Postconditions

1. The administrator has visibility into all administrative mutations.
2. The audit log is immutable through the application.
3. Audit history is retained indefinitely for V1.

### Business Rules

- **BR-016** — Administrative audit events cannot be edited or deleted through the application.
- **BR-017** — Audit history is retained indefinitely for V1.
- **NFR-002** — Every administrative mutation shall be traceable to an authenticated administrator.

---

# 8. Business Rules Reference

| ID | Rule |
|----|------|
| BR-001 | There must always be exactly one Owner. |
| BR-002 | Ownership may be transferred by the current Owner. |
| BR-003 | The Owner cannot be deleted, suspended, or demoted through ordinary administrative operations. |
| BR-004 | Administrators cannot grant themselves greater privileges. |
| BR-005 | Successful Google authentication does not automatically create an administrative account. |
| BR-006 | `channel_id` is the authoritative channel identity. |
| BR-007 | Channel handles are a lookup mechanism and are not authoritative identity. |
| BR-008 | Administrators cannot manually edit YouTube-derived channel metadata. |
| BR-009 | Channel deletion means setting `is_active = FALSE`. |
| BR-010 | Channel deactivation never deletes historical analytical data. |
| BR-011 | Inactive channels require explicit administrator confirmation before reactivation. |
| BR-012 | Newly activated channels are collected by the next scheduled ETL execution. |
| BR-013 | ETL or YouTube API failures do not automatically deactivate channels. |
| BR-014 | Bulk imports require validation and administrator confirmation before modifications occur. |
| BR-015 | A failure affecting one bulk-import row does not invalidate otherwise successful rows. |
| BR-016 | Administrative audit events cannot be edited or deleted through the application. |
| BR-017 | Audit history is retained indefinitely for V1. |
| BR-018 | Visitor analytics exposed to administrators are aggregated and do not expose visitor-level PII. |
| BR-019 | The Administration System observes ETL health but does not control ETL execution in V1. |
| BR-020 | BigQuery remains authoritative for analytical product data; CloudSQL remains authoritative for application-control data. |

---

# 9. Non-Functional Requirements Reference

| ID | Requirement |
|----|-------------|
| NFR-001 | The system shall enforce authenticated, role-based access to all administrative capabilities. |
| NFR-002 | Every administrative mutation shall be traceable to an authenticated administrator. |
| NFR-003 | Core operational workflows shall be usable on mobile devices. |
| NFR-004 | The system shall maintain clear separation between authentication/authorization, channel management, analytics, system health, and audit functionality. |
| NFR-005 | The authorization model shall support future customers, organizations, and entitlements without requiring replacement of the administrative identity model. |
| NFR-006 | Administrative operations shall not corrupt or duplicate the canonical BigQuery channel inventory. |
| NFR-007 | External API failures shall not result in unintended destructive changes. |
| NFR-008 | Administrative analytics shall not expose visitor-level personally identifiable information. |
| NFR-009 | Administrative operations and significant failures shall be sufficiently observable to support troubleshooting. |
| NFR-010 | The Administration System shall not become the authoritative analytical data store or ETL processing engine. |

---

# 10. Source Specification Traceability

| Use Case | Source Spec Sections |
|----------|---------------------|
| UC-1.1 | §7.1, §7.2, §7.3, §7.4, §45, §57 |
| UC-1.2 | §8, §45, §57 |
| UC-1.3 | §7.2, §9, §57 |
| UC-1.4 | §9, §10, §45, §57 |
| UC-1.5 | §9, §10, §45, §57 |
| UC-1.6 | §8, §9, §45, §57 |
| UC-1.7 | §8, §9, §45, §57 |
| UC-1.8 | §10, §45, §57 |
| UC-2.1 | §19, §43, §57 |
| UC-2.2 | §11, §12, §13, §14, §15, §57 |
| UC-2.3 | §17, §45, §57 |
| UC-2.4 | §18, §57 |
| UC-2.5 | §20, §21, §22, §23, §25, §57 |
| UC-2.6 | §21 |
| UC-2.7 | §24 |
| UC-3.1 | §42, §43, §57 |
| UC-3.2 | §31, §32, §33, §34, §35, §37, §57 |
| UC-3.3 | §27, §42, §57 |
| UC-3.4 | §29, §57 |
| UC-3.5 | §28, §30, §57 |
| UC-3.6 | §36, §37, §57 |
| UC-4.1 | §38, §39, §40, §41, §57 |
