# TASK-005.2: Permission Engine V1 Architecture

## Firestore Structure

```text
organizations/{organizationId}
  roles/{roleId}
  memberships/{userId}
  audit_logs/{auditLogId}
```

## Roles Collection

Path: `organizations/{organizationId}/roles/{roleId}`

Each role belongs to exactly one organization. The document ID must equal the
`roleId` field.

### Required Role Fields

- `roleId: string`
- `roleName: map<string,string>` - localized names keyed by language code.
- `description: map<string,string>` - localized role description.
- `permissions: list<string>` - sorted, unique permission keys.
- `isSystemRole: boolean`
- `createdAt: timestamp`
- `updatedAt: timestamp`

Example:

```text
organizations/org_001/roles/financialReviewer

roleId: "financialReviewer"
roleName: { ar: "المراجع المالي", en: "Financial Reviewer" }
description: { ar: "...", en: "Reviews submitted receipts" }
permissions: [
  "payments.read",
  "payments.approve",
  "payments.reject",
  "audit.read"
]
isSystemRole: true
createdAt: timestamp
updatedAt: timestamp
```

## System Roles

Organizations are initially seeded with these system roles:

- `chairman`
- `financialManager`
- `financialReviewer`
- `secretary`
- `member`

System roles provide stable defaults. Their permissions may be updated only by
trusted administrators with the required management permissions. A system role
cannot be deleted or converted into a custom role.

Platform-wide `superAdmin` access remains separate from organization roles. It
must not be granted by creating or editing an organization role.

## Permission Naming Convention

### Format

```text
<resource>.<action>
<module>.<resource>.<action>
```

Rules:

- Use lowercase ASCII letters.
- Use plural resource names where the Firestore resource is plural.
- Separate segments with a period.
- The final segment is always an action.
- Permission keys are case-sensitive.
- Permission checks use exact registered keys.
- V1 does not support client-defined keys or wildcard permissions.
- Permission arrays must be unique and stored in sorted order.

### Standard Actions

- `read`
- `create`
- `update`
- `delete`
- `approve`
- `reject`
- `review`
- `send`
- `manage`

`manage` is a registered permission bundle for one exact resource. During
snapshot synchronization, it expands into the registered atomic permissions
for that resource. It does not automatically grant permissions to other or
child resources.

For example, `rentals.manage` may expand to:

- `rentals.read`
- `rentals.create`
- `rentals.update`
- `rentals.delete`
- `rentals.approve`
- `rentals.reject`

## Permission Registry V1

Only keys from the server-controlled permission registry may be assigned to a
role.

### Members

- `members.read`
- `members.create`
- `members.update`
- `members.delete`
- `members.approve`
- `members.suspend`

### Payments and Receipts

- `payments.read`
- `payments.create`
- `payments.update`
- `payments.approve`
- `payments.reject`
- `payments.refund`
- `receipts.read`
- `receipts.review`
- `receipts.ocr.review`

### Rentals

- `rentals.read`
- `rentals.create`
- `rentals.update`
- `rentals.delete`
- `rentals.approve`
- `rentals.reject`
- `rentals.manage`

### Community

- `community.posts.read`
- `community.posts.create`
- `community.posts.update`
- `community.posts.delete`
- `community.posts.review`
- `community.events.manage`
- `community.announcements.manage`

### Notifications

- `notifications.send`

### Organization Administration

- `settings.manage`
- `roles.manage`
- `organization.manage`
- `audit.read`

Adding a permission to the registry does not grant it to any existing role.
Roles must be updated explicitly and audited.

## Membership Permission Snapshot

Path: `organizations/{organizationId}/memberships/{userId}`

Relevant fields:

- `roleId: string`
- `permissionsSnapshot: list<string>`
- `status: string`

`roleId` references a role in the same organization. `permissionsSnapshot` is a
sorted, unique, resolved copy of the role's effective atomic permissions.
Registered `manage` bundles are expanded before writing the snapshot.

### MembershipModel Usage

- `MembershipModel.roleId` identifies the assigned role.
- `MembershipModel.permissionsSnapshot` provides the effective permissions for
  feature visibility and organization-scoped application decisions.
- A permission is available only when the membership is active and the exact
  permission exists in the snapshot.
- Pending, suspended, rejected, or resigned memberships have no effective
  organization permissions, regardless of snapshot contents.
- Clients may read their snapshot but may not write it.
- Role assignment and snapshot writes are trusted backend or authorized admin
  operations.

For sensitive writes during synchronization, Firestore rules or trusted backend
code must validate the live role document in addition to membership status.
This prevents a stale snapshot from retaining a permission that was revoked.

## Permission Evaluation

Access is granted only when all conditions are true:

1. The user is authenticated.
2. The membership belongs to the authenticated user.
3. The membership belongs to the requested organization.
4. The membership status is `active`.
5. The requested exact permission exists in the effective permissions.
6. Any resource ownership or workflow-specific conditions also pass.

The engine is deny-by-default. Missing roles, missing snapshots, unknown
permissions, inactive memberships, or cross-organization references deny
access.

Permissions never bypass data-scope checks. For example, `payments.read` in one
organization does not grant access to payments in another organization.

## Permission Synchronization

### Membership Creation or Role Assignment

1. Validate that `roleId` exists in the same organization.
2. Validate every role permission against the server registry.
3. Resolve registered `manage` bundles into atomic permissions.
4. Sort and remove duplicate permission keys.
5. Write `roleId` and `permissionsSnapshot` together through trusted code.
6. Create an audit log containing the actor, old role, new role, and resulting
   snapshot.

### Role Permission Update

1. Validate that the actor has `roles.manage`.
2. Reject unknown permissions and protected platform permissions.
3. Update the role's `permissions` and `updatedAt`.
4. Enqueue a synchronization job for the organization and role.
5. Query memberships in the same organization where `roleId` matches.
6. Recompute snapshots in paginated batches.
7. Record completion, failure, and affected membership counts in audit logs.
8. Retry idempotently until every matching membership has the current resolved
   snapshot.

### Revocation Safety

- Sensitive Firestore writes validate the live role document while a
  synchronization job is pending.
- A removed permission therefore stops authorizing protected writes before all
  cached membership snapshots finish updating.
- Snapshot synchronization remains necessary for application state, offline
  behavior, and efficient reads.

### Reconciliation

A scheduled trusted job periodically recomputes snapshots for active
memberships. It repairs missed triggers, removes unknown keys, and reports
orphaned `roleId` references.

## Custom Roles

Future organization administrators may create custom roles when they have
`roles.manage`.

Custom-role rules:

- Use a generated `roleId` that is unique inside the organization.
- Set `isSystemRole` to `false` permanently.
- Select permissions only from the server-controlled registry.
- A creator cannot grant a permission they are not authorized to delegate.
- Platform-wide `superAdmin` access cannot be included.
- Role creation, permission changes, assignments, and deletion are audited.
- A custom role cannot be deleted while memberships still reference it; those
  memberships must first be reassigned.
- Updating a custom role uses the same synchronization process as a system
  role.
- Custom role names and descriptions support all organization languages through
  localized maps.

## Relationships

- One organization owns zero or more roles.
- One role belongs to exactly one organization.
- One role may be referenced by many memberships in the same organization.
- One membership references exactly one `roleId` in V1.
- `permissionsSnapshot` is derived from the referenced role and permission
  registry.
- Role and membership permission changes produce immutable organization audit
  logs.
- Permission scope never crosses organization boundaries.

## Backward Compatibility and Migration

1. Keep the existing `members.isAdmin` field and current Firestore rules active
   during the compatibility period.
2. Seed system roles before assigning `roleId` values to migrated memberships.
3. Map each legacy administrator to an explicitly selected privileged system
   role; do not infer platform `superAdmin` access from `isAdmin`.
4. Map non-administrators to the `member` system role.
5. Populate `permissionsSnapshot` through trusted migration code.
6. Empty or missing snapshots deserialize as `[]` and do not affect the legacy
   login or admin flow.
7. Run both legacy and V1 authorization paths until organization-scoped rules,
   services, and providers are ready.
8. Replace `isAdmin` checks only in a later implementation task after role and
   snapshot counts have been verified.
9. Do not remove `isAdmin`, legacy `members`, or existing rules in TASK-005.2.
10. TASK-005.2 changes documentation only; it does not change Dart models,
    authentication, providers, routes, screens, or deployed Firestore rules.

## Validation Checklist

- Every membership `roleId` resolves inside its own organization.
- Every role permission exists in the V1 registry.
- Every active membership snapshot equals its role's resolved permissions.
- No inactive membership is authorized by snapshot contents.
- No organization role contains platform-only permissions.
- No custom role grants permissions its creator could not delegate.
- Role changes and synchronization results have corresponding audit logs.
