# Sailing Channel Dashboard — Administration System
## Product/System Specification

**Document Status:** Draft  
**Version:** 1.0  
**Date:** August 7, 2026  
**System:** Sailing Channel Dashboard Administration System  
**Primary Implementation Language:** Python  
**Deployment:** Google Cloud Run  
**Production Host:** `admin.example.com` (proposed)

---

# 1. Purpose

The Sailing Channel Dashboard Administration System provides a secure administrative control plane for operating, monitoring, and governing the Sailing Channel Dashboard data product.

The system will allow authorized personnel to:

- Manage administrative users and their roles.
- Manage the curated set of YouTube channels tracked by the data product.
- Monitor dashboard usage and channel interest.
- Monitor the health and freshness of the analytical data product.
- Monitor selected health indicators for the public dashboard and supporting services.
- Maintain a comprehensive audit trail of administrative activity.

The system is intended to provide a substantially more convenient operational interface than directly interacting with Google Cloud services, BigQuery, or application data.

The system is also intended to establish the identity and authorization foundation for future customer-facing capabilities, including authenticated users, organizations, channel entitlements, API access, custom reporting, and billing.

---

# 2. Product Context

The Sailing Channel Dashboard is an analytical data product based on YouTube channel data.

The existing architecture uses:

- YouTube Data API v3 as an external data source.
- Google BigQuery as the analytical data platform and data product.
- Cloud Run Job for ETL processing.
- Cloud Scheduler for scheduled ETL execution.
- Cloud Storage for application cache.
- Cloud Run Service hosting the public Shiny dashboard.
- GitHub for source control and CI/CD.

The existing data model establishes `channel_dimensions` in BigQuery as the canonical channel dimension. `channel_id` is its primary key and `is_active` controls whether a channel is active in the product. Channel metadata is populated from the analytical ingestion process rather than manually maintained by administrators. 

The existing component architecture establishes the ETL as a scheduled Cloud Run Job and the public dashboard as a separate Cloud Run Service. The ETL reads and writes BigQuery and the dashboard queries BigQuery and its supporting cache. 

The Administration System is a new, separate Cloud Run Service.

---

# 3. System Boundary

The Administration System is a **control plane**, not another analytical data platform.

Its primary responsibilities are:

1. Authentication and authorization of administrative users.
2. Administrative user and role management.
3. Channel inventory management.
4. Administrative audit logging.
5. Dashboard usage analytics presentation.
6. Data-product and application health monitoring.

The system does **not** become the authoritative source for analytical channel data.

## 3.1 Data Ownership Principle

The system shall follow this governing principle:

> **BigQuery contains the data product that the business sells. CloudSQL contains application-control data that determines who may use, administer, and eventually access portions of that product.**

### BigQuery owns:

- Channel dimensions.
- YouTube-derived channel metadata.
- Historical channel metrics.
- Analytical facts and marts.
- Dashboard-facing analytical datasets.
- Other data constituting the analytical product.

### CloudSQL owns or will own:

- Administrative identities.
- Roles.
- Permissions.
- Administrative account state.
- Future customer identities.
- Future organizations.
- Future channel entitlements.
- Administrative audit records.
- Other application-control data.

CloudSQL may contain references to BigQuery `channel_id` values for authorization or future customer-entitlement purposes. Such references do not make CloudSQL authoritative for the channel itself.

---

# 4. Goals

## 4.1 Primary Goals

The system shall:

- Restrict administrative access to explicitly authorized individuals.
- Enforce role-based capabilities.
- Provide a secure and auditable administrative interface.
- Allow administrators to add and deactivate channels without directly manipulating BigQuery.
- Support individual and bulk channel management.
- Provide clear validation and confirmation before modifying the channel inventory.
- Preserve historical analytical data when channels are deactivated.
- Provide operational visibility into ETL and dashboard health.
- Provide useful visibility into public dashboard usage.
- Be practical to use from a mobile device.
- Establish an extensible identity and authorization foundation for future customer functionality.

## 4.2 Secondary Goals

The system should:

- Reduce the need to use the Google Cloud Console for routine operational tasks.
- Reduce the need to perform direct BigQuery queries for channel inventory management.
- Make administrative activity traceable.
- Make common operational checks possible from a phone.
- Allow the administrative product to evolve independently from the public dashboard.

---

# 5. Non-Goals

The following are explicitly outside the scope of the initial system:

- Customer account management.
- Customer self-service registration.
- Organization management.
- Customer channel entitlements.
- Public API access.
- API key management.
- Custom report builder.
- Customer-specific dashboards.
- Billing and subscription management.
- Direct ETL triggering.
- ETL cancellation.
- ETL retry controls.
- Full replacement of Google Cloud Monitoring.
- Manual editing of YouTube-derived channel metadata.
- Deletion of historical analytical data.
- Real-time visitor analytics.
- Visitor-level personally identifiable information.

These capabilities may be supported by the underlying architecture in the future but are not V1 functionality.

---

# 6. Actors

## 6.1 Owner

The highest-level administrative actor.

There shall always be exactly one Owner.

The Owner:

- Has all administrative capabilities.
- May designate other Super Admins.
- May manage administrative accounts and roles.
- May view the audit log.
- May manage channels.
- May view usage analytics.
- May view system health.
- May transfer ownership.

The Owner cannot be:

- Deleted.
- Suspended.
- Demoted.
- Duplicated.

Ownership is transferable, but there must never be zero or more than one Owner.

When ownership is transferred, the previous Owner becomes a Super Admin unless otherwise specified by a subsequent authorized operation.

---

## 6.2 Super Admin

A Super Admin has broad administrative privileges but is subordinate to the Owner.

A Super Admin may:

- Manage administrative users.
- Assign roles subject to authorization restrictions.
- Manage channels.
- View usage analytics.
- View system health.
- View the audit log.

A Super Admin may not:

- Grant themselves Owner privileges.
- Modify or remove the Owner.
- Create a second Owner.
- Circumvent authorization restrictions.

---

## 6.3 Channel Manager

A Channel Manager is responsible for maintaining the tracked channel inventory.

A Channel Manager may:

- View the channel inventory.
- Add channels.
- Perform bulk channel imports.
- Deactivate channels.
- Reactivate channels.
- View relevant channel status.
- View appropriate system-health information.

A Channel Manager may not:

- Manage administrative users.
- Assign roles.
- View the administrative audit log.
- Modify channel metadata.
- Control ETL execution.

---

## 6.4 Analyst

An Analyst is a read-only operational/analytics user.

An Analyst may:

- View dashboard usage analytics.
- View channel-interest analytics.
- View appropriate system-health information.

An Analyst may not:

- Add or remove channels.
- Modify administrative accounts.
- Change roles.
- View the administrative audit log unless explicitly granted a future permission.
- Control ETL execution.

---

## 6.5 Future Customer/User Actor

The system architecture shall remain extensible to authenticated customers.

Future customer capabilities may include:

- Authenticated reporting.
- Custom dashboards.
- API access.
- Organization membership.
- Channel entitlements.

These capabilities are not implemented by the initial Administration System.

---

# 7. Authentication and Identity

## 7.1 Authentication Provider

Administrative users shall authenticate using a Google identity-based authentication mechanism.

The exact implementation, including Google OAuth versus Firebase Authentication, shall be determined during architecture/design.

The system shall not implement its own password-based administrator authentication.

## 7.2 Administrative Provisioning

Administrative accounts shall be explicitly provisioned by an authorized administrator.

The system shall not automatically create an administrative account merely because a user successfully authenticates with Google.

The intended workflow is:

1. Authorized administrator creates/provisions an administrative account.
2. Administrator assigns a role.
3. User authenticates with the approved Google identity.
4. System associates the authenticated identity with the provisioned account.
5. Authorization is evaluated.
6. Access is granted according to role.

## 7.3 External Google Accounts

The system shall support designation of external Google accounts.

The architecture shall permit future restriction of administrative access to the organization's Google Workspace domain if business requirements change.

## 7.4 Identity Representation

Administrative identity shall be associated with a stable identity-provider identifier rather than relying exclusively on email address as the immutable identity.

Email address shall be treated as an account attribute that may change.

---

# 8. Role-Based Access Control

The system shall use Role-Based Access Control (RBAC).

Authorization shall be based on the authenticated user's assigned role and the permissions associated with that role.

The initial role model is:

| Capability | Owner | Super Admin | Channel Manager | Analyst |
|---|---:|---:|---:|---:|
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
| Modify YouTube metadata | — | — | — | — |
| Trigger ETL | — | — | — | — |

The underlying authorization model should be extensible to more granular permissions in future versions.

---

# 9. Administrative Account Lifecycle

Administrative accounts shall support at least:

- Active.
- Suspended.
- Deprovisioned/removed.

Deprovisioning shall disable access without destroying historical audit information associated with the account.

An administrator's role change shall take effect immediately or on the next authorization evaluation.

Role changes shall be audited.

An administrator shall not be able to elevate their own privileges.

---

# 10. Ownership Rules

The following invariants shall always hold:

1. Exactly one Owner exists.
2. The Owner may transfer ownership.
3. Ownership transfer creates exactly one new Owner.
4. The previous Owner ceases to be Owner as part of the same operation.
5. The previous Owner becomes a Super Admin following transfer unless otherwise specified by a future business rule.
6. The Owner cannot be deleted.
7. The Owner cannot be suspended.
8. The Owner cannot be demoted through ordinary role-management operations.
9. A second Owner cannot be created.
10. Ownership transfer is explicitly confirmed by the current Owner.
11. Ownership transfer is fully audited.

---

# 11. Channel Management

## 11.1 Channel Identity

`channel_id` is the authoritative identity of a YouTube channel.

The channel handle is not authoritative identity.

The handle is used by administrators as a convenient lookup mechanism because it is easier to obtain and enter than the underlying YouTube channel ID.

The Administration System shall resolve the handle to a channel ID through the YouTube Data API before adding a new channel.

---

# 12. Adding an Individual Channel

The administrator shall be able to enter a YouTube channel handle.

The workflow shall be:

1. Administrator enters handle.
2. System validates the handle.
3. System resolves the handle to a YouTube `channel_id`.
4. System determines whether the channel already exists in `channel_dimensions`.
5. If the channel does not exist, the system retrieves the relevant YouTube-derived metadata.
6. System displays the channel information for administrator review.
7. Administrator explicitly confirms the addition.
8. System adds the channel to the BigQuery channel dimension.
9. The channel becomes available to the next scheduled ETL run.
10. The operation is audited.

The system shall not trigger the ETL as a result of the addition.

---

# 13. Channel Validation Outcomes

The system shall distinguish different validation outcomes.

At minimum:

- Valid new channel.
- Invalid/nonexistent handle.
- Existing active channel.
- Existing inactive channel.
- YouTube API error.
- YouTube API quota error.
- Other identifiable YouTube API failure.

Where the YouTube Data API provides distinct error codes/messages, the system shall preserve sufficient information to distinguish those outcomes in the user-facing results and audit information.

---

# 14. Existing Active Channel

If the resolved channel already exists and is active:

> The system shall inform the administrator that the channel is already being tracked and shall take no further action.

No duplicate channel shall be created.

---

# 15. Existing Inactive Channel

If the resolved channel already exists but is inactive:

> The system shall inform the administrator that the channel is already tracked but inactive and shall request explicit administrator confirmation before reactivating it.

The system shall not automatically reactivate the channel.

If confirmed:

- `is_active` shall be changed to `TRUE`.
- Historical data shall remain intact.
- The channel shall resume data collection on the next ETL run.
- The operation shall be audited.

---

# 16. Channel Metadata

Administrators shall not manually edit YouTube-derived channel metadata.

The following are examples of data that shall remain controlled by the analytical ingestion process:

- Channel title.
- Description.
- Join date.
- Subscriber visibility.
- Keywords.
- Profile picture.
- Other YouTube-derived metadata.

This preserves the analytical integrity of the data product.

The Administration System may display this metadata for identification and confirmation purposes.

---

# 17. Channel Deactivation

"Deleting" a channel means deactivating it.

Deactivation shall:

1. Set `channel_dimensions.is_active` to `FALSE`.
2. Cause the channel to be excluded from the active public dashboard product.
3. Prevent future ETL collection for the inactive channel.
4. Preserve historical analytical data.
5. Preserve the channel dimension record.
6. Create an audit event.

Deactivation shall not physically delete the channel or its historical analytical data.

---

# 18. Channel Reactivation

A deactivated channel may be reactivated by an authorized administrator.

Reactivation shall:

1. Set `channel_dimensions.is_active` to `TRUE`.
2. Preserve historical data.
3. Allow the channel to be picked up by the next ETL run.
4. Create an audit event.

---

# 19. Channel Inventory

The Administration System shall provide a dedicated Channel Inventory page.

The page shall display all tracked channels by default, including both active and inactive channels.

The inventory shall support filtering and searching.

At minimum, administrators should be able to view:

- Channel title.
- Channel handle.
- Channel ID.
- Active/inactive status.
- Date added.
- Added by.
- Last updated.
- Relevant data/ETL status where available.

The page shall provide appropriate actions based on the user's role.

Channel metadata shall be read-only.

---

# 20. Bulk Channel Import

The system shall support channel imports from:

- CSV.
- XLSX.

The initial spreadsheet schema shall contain a channel handle.

Additional import fields may be supported in future versions.

---

# 21. Bulk Import Workflow

Bulk import shall follow this workflow:

1. Upload spreadsheet.
2. Parse spreadsheet.
3. Validate all rows.
4. Resolve valid handles to channel IDs.
5. Detect duplicate rows.
6. Check channels against existing inventory.
7. Classify each row.
8. Display a preview.
9. Require explicit administrator confirmation.
10. Commit valid changes independently.
11. Generate a results report.

No channel modifications shall occur during validation or preview.

---

# 22. Bulk Import Outcomes

The system shall distinguish at least:

- New channel — will be added.
- Existing active channel — no action.
- Existing inactive channel — requires explicit reactivation decision.
- Invalid handle.
- YouTube API error.
- YouTube API quota error.
- Other API/processing error.
- Duplicate spreadsheet entry.

The system shall allow valid independent operations to succeed even when other rows fail.

One failed row shall not cause successful rows to roll back.

---

# 23. Bulk Reactivation

An inactive channel encountered during a bulk import shall not automatically be reactivated.

The administrator shall explicitly select/confirm reactivation.

This requirement prevents an old spreadsheet from unintentionally reactivating channels.

---

# 24. Bulk Import Results Report

After a bulk operation, the system shall display a results report.

The report shall summarize:

- Total rows.
- Successfully added.
- Successfully reactivated.
- Already active.
- Invalid handles.
- API errors.
- Other errors.
- Duplicate rows.

The report shall provide sufficient row-level information for the administrator to understand unsuccessful operations.

A downloadable report is not required for V1.

---

# 25. Transaction and Consistency Requirements

Each valid channel operation shall be independently committed.

The system shall not require the entire batch to succeed.

The system shall enforce consistency at the data/service level rather than relying exclusively on pre-operation UI validation.

For example, if two administrators simultaneously attempt to add the same channel, only one shall successfully create the channel record.

The second operation shall receive an appropriate "already exists" result rather than creating a duplicate.

---

# 26. ETL Relationship

The existing ETL process remains responsible for collecting channel data.

The Administration System shall not become an ETL orchestration service.

The current architecture uses Cloud Scheduler to trigger the ETL Cloud Run Job. 

When a new channel is added:

> The channel becomes eligible for collection by the next scheduled ETL execution.

The Administration System shall not trigger ETL execution in V1.

---

# 27. ETL Health Monitoring

The Administration System shall display ETL operational health.

At minimum, the system should expose:

- Last scheduled execution.
- Last successful execution.
- Execution duration.
- Data freshness.
- Number of channels processed.
- Number of successful channels.
- Number of failed channels.
- Relevant error information.

The Administration System shall not provide controls to:

- Trigger ETL.
- Cancel ETL.
- Retry ETL.
- Modify ETL configuration.

Those remain responsibilities of the existing orchestration and operational infrastructure.

---

# 28. Dashboard/Application Health

The Administration System shall expose selected application health information sufficient for an administrator to determine whether the public dashboard is operating normally.

This may include:

- Availability.
- Recent request errors.
- HTTP error status information.
- Relevant latency indicators.
- Recent application failures.

The Administration System is not intended to replace Google Cloud Monitoring or provide a complete infrastructure-monitoring console.

---

# 29. Data Product Health

The system shall expose analytical data freshness and related indicators.

At minimum, administrators should be able to determine:

- Most recent available analytical date.
- Whether data is current relative to the expected ETL schedule.
- Whether recent ETL execution successfully populated the product.
- Whether significant channel-processing failures occurred.

---

# 30. YouTube API Health

Where useful, system health shall expose significant YouTube Data API failures affecting the data product.

This may include:

- Authentication/authorization failures.
- Quota failures.
- Request failures.
- Channel lookup failures.
- Other relevant API errors.

The system shall distinguish error types when the underlying API provides sufficient information.

---

# 31. Public Dashboard Usage Analytics

The Administration System shall provide aggregated analytics describing how visitors use the public dashboard.

Google Analytics shall initially be the source of truth.

The system shall not attempt to create an independent visitor analytics system in V1.

---

# 32. Usage Metrics

The initial usage analytics should include:

- Unique users.
- Sessions.
- Page views.
- Geographic information.
- Device/technology information.
- Acquisition source.
- Channel interest.

Analytics shall support useful time ranges including standard predefined ranges and, where practical, a custom date range.

Google Analytics reporting latency is acceptable.

The system does not require real-time analytics.

---

# 33. Geographic Analytics

The Administration System shall display aggregated geographic information.

Examples include:

- Country.
- Region/state where available.
- City where appropriate and supported.

The system shall not expose individual visitor location information.

---

# 34. Technology Analytics

The Administration System shall provide aggregated information about how visitors access the dashboard.

This may include:

- Desktop/mobile/tablet.
- Browser.
- Operating system.
- Other relevant GA4 technology dimensions.

---

# 35. Acquisition Analytics

The Administration System shall provide aggregated information about how visitors arrive at the dashboard.

This may include:

- Direct traffic.
- Search.
- Social.
- Referral sites.
- Other available acquisition-source categories.

---

# 36. Channel Interest

For V1, **channel interest** is defined as:

> A user looking up a channel through Channel Explorer or Growth Benchmarks.

Channel interest shall be represented by an extensible analytics event.

The initial event shall conceptually contain:

- Channel ID.
- Originating dashboard context/page.

For V1, selecting a channel from a leaderboard shall not count as channel interest because the current product does not provide that interaction.

The analytics event taxonomy shall deliberately remain extensible so additional interactions can be added later without redesigning the analytics system.

---

# 37. Privacy Boundary

Administrative analytics shall expose aggregated visitor information.

The system shall not expose visitor-level personally identifiable information.

The Administration System shall not provide administrators with:

- Individual visitor identities.
- Individual IP addresses.
- Individual browsing histories.
- Other visitor-level PII.

The purpose of analytics is operational and product analysis, not individual visitor surveillance.

---

# 38. Administrative Audit Trail

Every administrative mutation shall be audited.

The audit system shall be append-only from the application perspective.

Audit records shall not be editable or deletable through the Administration System.

Audit records shall be retained indefinitely unless a future legal, regulatory, or business requirement establishes a retention policy.

---

# 39. Audit Event Information

Audit events shall capture, as appropriate:

- Actor.
- Actor role at the time of action.
- Timestamp.
- Action.
- Target entity type.
- Target identifier.
- Outcome.
- Relevant before state.
- Relevant after state.
- Error information.
- Operation/import identifier where applicable.

Bulk operations shall additionally capture:

- Import identifier.
- File type.
- Row count.
- Successful count.
- Failed count.
- Per-row outcomes.

---

# 40. Audit Log Access

The audit log shall be restricted to the highest-level administrative roles.

V1 access shall be available to:

- Owner.
- Super Admin.

Channel Managers and Analysts shall not have access.

---

# 41. Administrative Audit Examples

Examples of auditable operations include:

- Administrator created.
- Administrator suspended.
- Administrator deprovisioned.
- Administrator role changed.
- Ownership transferred.
- Channel added.
- Channel deactivated.
- Channel reactivated.
- Bulk import performed.
- Bulk import partially failed.
- Other future administrative mutations.

Read-only operations do not necessarily need individual audit events unless specifically required by a future policy.

---

# 42. Admin Home Page

The Administration System shall open to an operational dashboard.

The home page should answer:

> **"Is the Sailing Channel Dashboard operating correctly right now?"**

The page should provide concise indicators for:

### Dashboard

- Visitor activity.
- Sessions.
- Unique users.
- Recent page activity.
- Popular channels.

### ETL

- Last execution.
- Last successful execution.
- Data freshness.
- Processing status.
- Recent failures.

### System

- Dashboard availability.
- Relevant application health.
- Significant recent errors.

The home page is an operational overview rather than a replacement for detailed analytics or Google Cloud Console.

---

# 43. Administrative Navigation

The application shall provide dedicated pages for major administrative functions.

The initial conceptual navigation should include:

1. **Home**
2. **Channel Inventory**
3. **Add Channel**
4. **Bulk Import**
5. **Usage Analytics**
6. **System Health**
7. **Administration / Users**
8. **Audit Log**

Pages and capabilities shall be conditionally available according to the authenticated user's role.

---

# 44. Mobile Usability

Mobile use is a primary operational requirement.

The Administration System shall be responsive and shall support the major operational workflows from a mobile device.

At minimum:

- Home health indicators shall be easily readable on mobile.
- Channel inventory shall be usable on mobile.
- Channel addition shall be usable on mobile.
- Channel deactivation/reactivation shall be usable on mobile.
- Important system-health information shall not require desktop-only interactions.
- The UI shall not rely on hover interactions for critical functionality.
- Large tabular datasets shall have mobile-appropriate presentation.

The system is intended to provide operational visibility that is more convenient than the Google Cloud mobile application for this specific product.

---

# 45. Security Requirements

The Administration System shall:

- Require authentication.
- Require explicit authorization.
- Deny access to authenticated but unprovisioned users.
- Prevent privilege escalation.
- Protect the Owner account from ordinary administrative deletion/demotion.
- Maintain an immutable administrative audit trail.
- Separate administrative identity from future customer identity where appropriate.
- Avoid exposing analytical or visitor data beyond the user's authorized capabilities.
- Use least-privilege access to Google Cloud resources.
- Keep administrative credentials and secrets out of source code.

---

# 46. Administrative Service Isolation

The Administration System shall be deployed as a separate Cloud Run Service from the public dashboard.

The public dashboard shall not use the Administration System as its authentication or authorization mechanism.

Future customer-facing authenticated services should likewise have their own appropriate authentication boundary.

The architecture shall allow administrative identity and customer identity to remain distinct even if they share common underlying application infrastructure or CloudSQL resources.

---

# 47. Environment Requirements

V1 production shall use one production Cloud Run service.

Development shall initially run locally.

Development data shall be sufficiently separated from production data to prevent accidental modification of the production analytical product.

Separate BigQuery datasets may be used for development and production.

A dedicated production admin service is required; a continuously deployed development admin Cloud Run service is not required for V1.

---

# 48. Availability and Failure Handling

Administrative operations shall fail safely.

A failed operation shall not result in partial unintended changes.

For batch operations, independent rows may succeed or fail independently as explicitly defined by the bulk-import workflow.

Transient external-service failures shall not cause destructive state changes.

In particular:

> A YouTube API failure shall not automatically deactivate a channel.

Channel activation state shall be changed only through an authorized administrative operation.

---

# 49. Extensibility Requirements

The system shall be designed so that future versions can support:

## Customer Identity

- Customer users.
- Customer organizations.
- Organization membership.

## Entitlements

- Organization/channel relationships.
- User/channel permissions.
- Paid/private datasets.
- Report access.

## Reporting

- Custom report builder.
- Customer-specific dashboards.
- Saved reports.

## API

- API credentials.
- API permissions.
- Usage tracking.
- Customer-specific API access.

## Commercial Functions

- Subscription status.
- Billing.
- Plan-based entitlements.

These future capabilities shall not be implemented in V1.

The architectural model shall nevertheless permit CloudSQL to reference BigQuery `channel_id` values as part of future authorization and entitlement relationships.

---

# 50. Future Customer Architecture Principle

The intended future model is conceptually:

```text
Organization
    │
    ├── Users
    │
    └── Channel Entitlements
             │
             └── BigQuery channel_id
```

CloudSQL determines **who may access what**.

BigQuery determines **what the analytical data is**.

This distinction shall be preserved as the customer-facing product evolves.

---

# 51. Alerting

Automated alerting is outside the scope of V1.

The Administration System shall display health information but shall not initially implement its own alert-delivery mechanism.

Future alerting may use Google Cloud Monitoring and/or other notification infrastructure.

Potential future alerts include:

- ETL failure.
- Data becoming stale.
- Dashboard elevated error rate.
- Significant API failures.
- Other operational conditions.

---

# 52. Business Rules Summary

The following business rules are normative requirements.

### BR-001 — Single Owner

There must always be exactly one Owner.

### BR-002 — Transferable Ownership

Ownership may be transferred by the current Owner.

### BR-003 — Owner Protection

The Owner cannot be deleted, suspended, or demoted through ordinary administrative operations.

### BR-004 — No Self-Elevation

Administrators cannot grant themselves greater privileges.

### BR-005 — Explicit Provisioning

Successful Google authentication does not automatically create an administrative account.

### BR-006 — Channel Identity

`channel_id` is the authoritative channel identity.

### BR-007 — Handle Lookup

Channel handles are an administrative lookup mechanism and are not authoritative identity.

### BR-008 — No Manual Metadata Editing

Administrators cannot manually edit YouTube-derived channel metadata.

### BR-009 — Soft Deactivation

Channel deletion means setting `is_active = FALSE`.

### BR-010 — Historical Preservation

Channel deactivation never deletes historical analytical data.

### BR-011 — Explicit Reactivation

Inactive channels require explicit administrator confirmation before reactivation.

### BR-012 — Scheduled Collection

Newly activated channels are collected by the next scheduled ETL execution.

### BR-013 — No Automatic Deactivation

ETL or YouTube API failures do not automatically deactivate channels.

### BR-014 — Bulk Confirmation

Bulk imports require validation and administrator confirmation before modifications occur.

### BR-015 — Independent Batch Processing

A failure affecting one bulk-import row does not invalidate otherwise successful rows.

### BR-016 — Immutable Audit

Administrative audit events cannot be edited or deleted through the application.

### BR-017 — Indefinite Audit Retention

Audit history is retained indefinitely for V1.

### BR-018 — Aggregated Visitor Analytics

Visitor analytics exposed to administrators are aggregated and do not expose visitor-level PII.

### BR-019 — ETL Separation

The Administration System observes ETL health but does not control ETL execution in V1.

### BR-020 — Data Ownership

BigQuery remains authoritative for analytical product data; CloudSQL remains authoritative for application-control data.

---

# 53. Non-Functional Requirements

## NFR-001 — Security

The system shall enforce authenticated, role-based access to all administrative capabilities.

## NFR-002 — Auditability

Every administrative mutation shall be traceable to an authenticated administrator.

## NFR-003 — Mobile Usability

Core operational workflows shall be usable on mobile devices.

## NFR-004 — Maintainability

The system shall maintain clear separation between authentication/authorization, channel management, analytics, system health, and audit functionality.

## NFR-005 — Extensibility

The authorization model shall support future customers, organizations, and entitlements without requiring replacement of the administrative identity model.

## NFR-006 — Data Integrity

Administrative operations shall not corrupt or duplicate the canonical BigQuery channel inventory.

## NFR-007 — Failure Safety

External API failures shall not result in unintended destructive changes.

## NFR-008 — Privacy

Administrative analytics shall not expose visitor-level personally identifiable information.

## NFR-009 — Observability

Administrative operations and significant failures shall be sufficiently observable to support troubleshooting.

## NFR-010 — Separation of Concerns

The Administration System shall not become the authoritative analytical data store or ETL processing engine.

---

# 54. Conceptual System Architecture

The system can be represented at the conceptual level as:

```text
                         ┌──────────────────────┐
                         │      Admin User      │
                         └──────────┬───────────┘
                                    │
                              Google Identity
                                    │
                                    ▼
                    ┌────────────────────────────┐
                    │   Administration Service   │
                    │        Cloud Run            │
                    │                            │
                    │  Authentication            │
                    │  Authorization / RBAC      │
                    │  Channel Management        │
                    │  Usage Analytics           │
                    │  System Health              │
                    │  Audit Interface            │
                    └───────┬───────────┬────────┘
                            │           │
                            │           │
                       Control Data     │ Analytics /
                       & Audit          │ Product Data
                            │           │
                            ▼           ▼
                    ┌────────────┐  ┌─────────────┐
                    │ CloudSQL   │  │  BigQuery   │
                    │            │  │             │
                    │ IAM        │  │ Channel     │
                    │ Roles      │  │ Dimensions  │
                    │ Audit      │  │ Metrics     │
                    │ Future     │  │ Marts       │
                    │ Entitle-   │  │ Dashboard   │
                    │ ments      │  │ Data        │
                    └────────────┘  └──────┬──────┘
                                           │
                                           │
                         ┌─────────────────┴──────────────┐
                         │                                │
                         ▼                                ▼
                  Public Dashboard                     ETL
                  Cloud Run Service               Cloud Run Job
                                                        ▲
                                                        │
                                                Cloud Scheduler
```

This diagram is conceptual and does not prescribe the eventual implementation of authentication, database schemas, network architecture, or service-to-service authorization.

---

# 55. Primary V1 Use-Case Domains

The eventual Use Case model should be organized around the following domains.

## Authentication & Authorization

- Authenticate Administrator.
- Authorize Administrator.
- Provision Administrator.
- Suspend Administrator.
- Deprovision Administrator.
- Assign Role.
- Change Role.
- Transfer Ownership.

## Channel Management

- View Channel Inventory.
- Search/Filter Channel Inventory.
- Add Channel.
- Validate Channel Handle.
- Resolve Channel ID.
- Confirm Channel Addition.
- Deactivate Channel.
- Reactivate Channel.
- Bulk Import Channels.
- Review Bulk Import.
- Confirm Bulk Import.
- Review Import Results.

## Monitoring

- View Admin Dashboard.
- View Dashboard Usage Analytics.
- View Channel Interest.
- View ETL Health.
- View Data Freshness.
- View Dashboard Health.
- View Application Errors.

## Audit

- View Audit Log.

The final Use Case diagram should distinguish between **user-facing goals** and internal system steps. For example, "Resolve Channel ID" is likely an `<<include>>` behavior of "Add Channel" rather than a standalone actor goal.

---

# 56. Requirements Traceability to Existing Product

The Administration System shall preserve the existing analytical architecture.

The current BigQuery model already defines:

- `channel_dimensions`
- `daily_metrics_history`
- analytical fact tables
- metric marts
- ranking tables
- application-facing tables

and establishes relationships between the channel dimension and downstream analytical products. 

The current application architecture already establishes:

- BigQuery as the analytical data store.
- Cloud Run Job for ETL.
- Cloud Run Service for the public Shiny application.
- Cloud Scheduler for daily ETL orchestration.
- YouTube Data API integration.
- Cloud Storage application caching. 

The Administration System shall extend this architecture without changing those fundamental responsibilities.

---

# 57. V1 Definition of Done

The Administration System shall be considered functionally complete for V1 when an authorized Owner/Super Admin/Channel Manager/Analyst can perform the capabilities assigned to their role and the following workflows operate correctly:

1. Administrator authenticates using the approved Google identity mechanism.
2. Unprovisioned Google users are denied access.
3. Roles determine available capabilities.
4. Owner invariants are enforced.
5. Administrators can be provisioned and deprovisioned.
6. Administrative role changes are audited.
7. Administrator can view the complete channel inventory.
8. Administrator can filter/search the inventory.
9. Administrator can add a valid new channel.
10. Invalid handles are rejected without modification.
11. Existing active channels are reported without modification.
12. Existing inactive channels require explicit confirmation before reactivation.
13. New channels are inserted into the canonical BigQuery channel dimension.
14. Administrators cannot edit YouTube-derived metadata.
15. Administrators can deactivate channels.
16. Administrators can reactivate channels.
17. Deactivation preserves historical data.
18. Administrators can upload CSV and XLSX channel lists.
19. Bulk uploads undergo validation and preview before modification.
20. Bulk operations permit independent row-level success/failure.
21. Bulk results are presented clearly.
22. ETL health is visible.
23. Data freshness is visible.
24. Selected dashboard/application health is visible.
25. Google Analytics usage metrics are visible.
26. Channel-interest analytics are visible.
27. Technology and acquisition analytics are visible.
28. Visitor analytics are aggregated and privacy-preserving.
29. Administrative mutations are recorded in the audit log.
30. Audit records cannot be modified or deleted through the application.
31. Owner/Super Admin can view the audit log.
32. Core operational workflows function on mobile devices.
33. The system does not provide ETL execution controls.
34. The system does not implement customer accounts, API access, custom reporting, or billing in V1.

---

# 58. Design Principles

The following principles should guide subsequent architecture and implementation work.

### Principle 1 — BigQuery is the Product

Do not duplicate analytical ownership in the administrative system.

### Principle 2 — CloudSQL is the Control Plane

Use CloudSQL for identity, authorization, administrative state, and future customer access-control relationships.

### Principle 3 — Channel ID is Truth

Handles facilitate discovery; channel IDs establish identity.

### Principle 4 — Metadata Comes From the Source

Administrators control which channels are included, not what YouTube-derived metadata says about them.

### Principle 5 — Deactivation Is Not Deletion

Historical analytical data is valuable and should be preserved.

### Principle 6 — Explicit Administrative Intent

Actions with meaningful consequences should require explicit confirmation.

### Principle 7 — Fail Safely

External failures must not silently alter product state.

### Principle 8 — Audit Everything That Changes State

Every administrative mutation must be attributable and reconstructable.

### Principle 9 — Mobile Is a First-Class Operational Interface

The system should make routine operational monitoring and management practical from a phone.

### Principle 10 — Design for the Future, Build for V1

The identity and authorization architecture should accommodate future customers, organizations, entitlements, APIs, reports, and billing without implementing those capabilities prematurely.