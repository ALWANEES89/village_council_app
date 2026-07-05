# TASK-005.1: Identity and Device Management Architecture

## Firestore Structure

```text
users/{userId}
  devices/{deviceId}

organizations/{organizationId}
  memberships/{userId}

notifications_queue/{notificationJobId}
```

## User Document

Path: `users/{userId}`

### Preference Fields

- `preferredLanguage: string` - language code such as `ar` or `en`.
- `preferredTheme: string` - `system`, `light`, or `dark`.
- `notificationSettings: map`
  - `pushEnabled: boolean`
  - `paymentUpdates: boolean`
  - `membershipUpdates: boolean`
  - `rentalUpdates: boolean`
  - `announcements: boolean`
  - `events: boolean`
  - `marketing: boolean`
  - `quietHoursEnabled: boolean`
  - `quietHoursStart: string?`
  - `quietHoursEnd: string?`
- `privacySettings: map`
  - `profileVisibility: string` - `organization`, `adminsOnly`, or `private`.
  - `showPhoneToMembers: boolean`
  - `showMemberships: boolean`
  - `allowAnalytics: boolean`
  - `allowAiProcessing: boolean`
- `updatedAt: timestamp`

User preferences are account-wide defaults. Device language and notification
settings may override them for one installation.

## Device Subcollection

Path: `users/{userId}/devices/{deviceId}`

### Device Fields

- `deviceId: string`
- `userId: string`
- `platform: string` - `android`, `ios`, `web`, `windows`, or `macos`.
- `manufacturer: string?`
- `model: string?`
- `deviceName: string?`
- `operatingSystem: string`
- `appVersion: string`
- `firebaseInstallationId: string?`
- `fcmToken: string?`
- `languageCode: string`
- `timezone: string`
- `lastLoginAt: timestamp`
- `lastSeenAt: timestamp`
- `createdAt: timestamp`
- `isActive: boolean`
- `isTrusted: boolean`
- `notificationsEnabled: boolean`

### Device Identity

- `deviceId` is a stable, installation-scoped identifier generated and stored
  locally by the application.
- The document ID equals the `deviceId` field.
- `firebaseInstallationId` identifies the Firebase app installation; it is not
  a user account identifier.
- Reinstalling the application may create a new device document.
- The same physical device used by two user accounts has one device document
  under each user's path.

## Membership Document Additions

Path: `organizations/{organizationId}/memberships/{userId}`

- `permissionsSnapshot: list<string>` - effective permissions copied from the
  assigned role when the role or membership changes.
- `joinedReason: string?`
- `invitedBy: string?` - inviting user or membership identifier.
- `leftReason: string?`

Existing membership documents remain valid because these fields default to an
empty list or `null` in `MembershipModel`.

## Relationships

- One user can own zero or more device documents.
- Every device belongs to exactly one user through its path and `userId` field.
- One Firebase installation has one current FCM token; token rotation updates
  only the matching device document.
- A user's devices are independent of memberships in multiple organizations.
- `permissionsSnapshot` is derived from the membership's organization role.
- `invitedBy` references the actor responsible for an invitation.
- Notification queue jobs can target a user, one device, or selected devices.
- Administrative device trust or revocation changes create audit-log records.

## Multiple-Device Handling

1. A recognized installation updates its existing device document.
2. A new installation creates a document with its new `deviceId`.
3. `lastLoginAt` updates after login; `lastSeenAt` updates while active.
4. FCM token rotation updates only the matching device document.
5. Only documents with `isActive == true` represent active device sessions.
6. `isTrusted` is independent from login state and changes only through an
   explicit trust or revocation workflow.
7. Stale or invalid devices are deactivated rather than immediately deleted so
   audit history is retained.

## Logout From One Device

Logout affects only the current `deviceId`:

1. Set the current device's `isActive` to `false`.
2. Set `notificationsEnabled` to `false`.
3. Remove or set its `fcmToken` to `null`.
4. Update `lastSeenAt`.
5. Clear the local Firebase session and locally stored device context.

Other devices and their Firebase sessions remain active. `isTrusted` can remain
unchanged so the installation may be recognized later. A remote-revocation
workflow may set both `isActive` and `isTrusted` to `false`.

TASK-005.1 defines this future lifecycle without changing the current logout or
authentication implementation.

## Push Notification Targeting

Trusted backend code creates jobs in `notifications_queue`; clients do not send
FCM messages directly.

### Current Device

- Read `users/{userId}/devices/{currentDeviceId}`.
- Require an active device, enabled notifications, and a valid `fcmToken`.
- Render content using the device's `languageCode` and `timezone`.

### All Devices

- Query the user's active, notification-enabled devices.
- Create one delivery job per distinct valid FCM token.
- Render each job using its device language and timezone.

### Selected Devices

- Resolve only the requested device IDs under the target user.
- Validate ownership, activity, notification preference, and token presence.
- Create one delivery job for every valid selected device.

Duplicate tokens are sent only once. Permanent invalid-token responses clear
the token and disable notifications for that device.

## Security Boundaries

- Users may read and register devices only under their own user path.
- Clients cannot change `userId` or `deviceId` after device creation.
- FCM tokens are not exposed through organization or member queries.
- Administrative trust or remote-revocation operations require permission and
  audit logging.
- Notification workers use trusted server credentials.

## Migration Notes

1. Keep `members/{memberId}.fcmToken` while current login and notification code
   depends on it.
2. Backfill user preferences with `preferredLanguage: "ar"`,
   `preferredTheme: "system"`, current notification behavior, and conservative
   privacy defaults.
3. Do not create a device from a legacy token without a reliable `deviceId`.
4. In a later service migration, register the current installation after login
   and dual-write refreshed tokens to the legacy member and device documents.
5. Move delivery to device documents only after device and legacy-token counts
   have been reconciled.
6. Retire `members.fcmToken` only after all supported clients have upgraded.
7. Backfill membership additions with `permissionsSnapshot: []` and nullable
   reason fields, then populate permissions using trusted role synchronization.
8. Authentication credentials, login lookup, routes, providers, and screens
   remain unchanged in TASK-005.1.

## Backward Compatibility

- `MemberModel.fcmToken` remains available.
- `AuthService.updateFcmToken` remains unchanged.
- The current authentication flow does not invoke device registration.
- Existing membership documents deserialize without the new fields.
- No Flutter screens, routes, providers, or authentication services change.
