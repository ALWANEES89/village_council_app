# TASK-005: Multi-Organization Authentication and Membership Migration

## Current Architecture

- Firebase Authentication signs users in with the existing phone-derived email.
- `AuthService` resolves the signed-in account by querying the top-level
  `members` collection using the normalized phone number.
- `MemberModel` currently combines person-level identity fields with
  organization-specific membership fields.
- Existing providers and screens depend on `memberNumber`, `status`, `isAdmin`,
  and `joinDate` being present on `MemberModel`.

## Target Architecture

- Firebase Authentication continues to represent one person account.
- A person-level user document is stored at `users/{userId}`.
- Organizations are stored at `organizations/{organizationId}`.
- Memberships are stored at
  `organizations/{organizationId}/memberships/{userId}`.
- The membership document ID is the `userId`, making membership unique for each
  user within an organization.
- Organization roles are referenced by `roleId`; authorization no longer relies
  on the legacy `isAdmin` flag.
- Membership approval is represented by `status`, `approvedBy`, and
  `approvedAt`.
- A user's preferred organization is represented by `isPrimary`. Backend writes
  must ensure that no user has more than one active primary membership.

## Migration Phases

### Phase 1 — Model Foundation

- Add `MembershipModel` without changing authentication, routing, providers, or
  screens.
- Keep all existing `MemberModel` fields and Firestore serialization intact.
- Treat `MemberModel.id` as the legacy `userId` during migration.

### Phase 2 — Seed the First Organization

- Create the initial council at `organizations/{organizationId}`.
- Create role documents for `chairman`, `financialManager`,
  `financialReviewer`, `secretary`, and `member`.
- Decide which existing administrator receives the initial privileged role.

### Phase 3 — Backfill Users and Memberships

For every legacy `members/{memberId}` document:

1. Create or merge `users/{memberId}` with person-level fields such as
   `fullName`, `civilId`, `phone`, and notification preferences.
2. Create
   `organizations/{organizationId}/memberships/{memberId}`.
3. Copy `memberNumber`, `status`, and `joinDate` into the membership.
4. Map `isAdmin == true` to the selected privileged `roleId`; otherwise use
   `member`.
5. Set `isPrimary` to `true` for the initial organization.
6. Set approval metadata for already-active legacy members using a designated
   migration actor.
7. Record an audit log for every migrated membership.

The backfill must be idempotent and must not delete or rewrite legacy member
documents.

### Phase 4 — Security Rules and Indexes

- Add organization-scoped membership rules.
- Allow users to read their own memberships.
- Allow authorized organization roles to review and manage memberships.
- Prevent clients from assigning roles, approving themselves, or changing
  `isPrimary` without a trusted transaction.
- Add a collection-group index for memberships by `userId` and `status`.
- Keep existing `members` rules active during the compatibility period.

### Phase 5 — Dual-Read Services

- Keep the existing Firebase Authentication sign-in operation unchanged.
- After sign-in, resolve `users/{authUid}` and query the user's memberships.
- Fall back to the existing `members` phone lookup while migration is
  incomplete.
- Return one organization directly when exactly one active membership exists.
- Return multiple active memberships for the future organization selector.
- Return pending membership state when no active membership exists.
- Continue updating the legacy FCM token until device tokens are moved to user
  device documents.

### Phase 6 — Provider and Routing Cutover

- Introduce separate providers for the authenticated user, available
  memberships, and selected organization.
- Resolve permissions from the selected membership role.
- Keep the existing dashboard routes operational until the organization context
  is available everywhere.
- Implement organization selection and pending-request screens in a later UI
  task.

### Phase 7 — Organization-Scoped Data

- Add `organizationId` and membership identifiers to payments, transactions,
  rentals, notifications, and audit records.
- Move queries from global member scope to selected-organization scope.
- Replace `isAdmin` checks with role permissions only after rules and providers
  have been migrated.

### Phase 8 — Legacy Retirement

- Verify that every authenticated account has a user document and at least one
  migrated membership where applicable.
- Remove the phone-based legacy member fallback only after production
  verification.
- Stop writing organization-specific fields to `members`.
- Remove legacy fields and the `members` collection in a separate, versioned
  migration.

## Login Compatibility

- TASK-005 does not change `AuthService`, Firebase Authentication credentials,
  login routes, or current providers.
- The top-level `members` collection remains the login source in this phase.
- Existing screens continue to receive the same `MemberModel` contract.

## Device Management Extension

TASK-005.1 extends the identity architecture with per-user device documents,
account preferences, membership permission snapshots, and staged FCM token
migration. See `TASK-005.1_DEVICE_MANAGEMENT_ARCHITECTURE.md`. The extension
does not change the authentication or screen migration sequence in this plan.

## Permission Engine Extension

TASK-005.2 defines organization roles, permission naming, membership permission
snapshots, synchronization, custom roles, and the staged replacement of legacy
`isAdmin`. See `TASK-005.2_PERMISSION_ENGINE_V1_ARCHITECTURE.md`. This extension
changes documentation only and does not activate the new authorization path.

## Validation and Rollback

- Compare legacy member counts with migrated user and membership counts.
- Verify exactly one membership per user per organization.
- Verify no user has more than one active primary membership.
- Verify role mappings and approval metadata before enabling new rules.
- Roll back service reads to legacy `members` without deleting V2 documents if
  a later migration phase fails.
