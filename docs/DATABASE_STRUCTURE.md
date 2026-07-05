# DATABASE_STRUCTURE — بنية قاعدة البيانات (Firestore)

> كل المجموعات والحقول. المبدأ: بيانات المجلس **تحت** `organizations/{organizationId}/`؛ المجموعات العليا إمّا خاصة بالشخص/المنصّة أو **إرث قديم** قيد التقاعد.

## 1. المجموعات العُليا (Top-level)

### `organizations/{organizationId}`
مستند المجلس نفسه.
- `organizationId`, `officialNameArabic`, `shortName`, `status` (`active`/`archived`), `profilePublished`, `schemaVersion`, `joinCode?`, `joinQrEnabled`, `createdAt`, `updatedAt`, `createdBy`, `updatedBy?`.

### `users/{userId}` (V2 — حساب الشخص)
- تفضيلات: `preferredLanguage`, `preferredTheme`, `notificationSettings{}`, `privacySettings{}`.
- سياق: `activeOrganizationId`, `primaryOrganizationId`, `fcmToken?`, `fcmTokens[]?`, `updatedAt`.
- **subcollection** `users/{userId}/notifications/{notificationId}`: إشعارات داخلية (`title`, `body`, `type`, `status`, `organizationId`, `createdByUserId`, `createdAt`, `readAt`).
- **subcollection** `users/{userId}/devices/{deviceId}`: أجهزة المستخدم (راجع TASK-005.1).

### `platform_admins/{userId}` (مشرفو المنصّة)
- `role` (`superAdmin`), `status` (`active`), `fullAccess` (bool), `notificationPreferences{}`, `updatedAt`.
- **خاص بالمنصّة** — الاستثناء الوحيد المسموح لمجموعة عليا بلا `organizationId`.

### `member_history/{historyId}` (سجل العضو المعروض)
- `userId`, `type` (`status`/`role`/`organization`/`removed`), `organizationId`, `targetOrganizationId?`, `previousStatus?`, `newStatus?`, `previousRoleId?`, `newRoleId?`, `actorUserId`, `reason?`, `createdAt`.
- منفصل عن audit_logs (DEC-009).

### مجموعات إرثية (Legacy — DEC-006، قيد التقاعد)
- `members/{memberId}`: مصدر تسجيل الدخول الحالي (`isAdmin`, `fcmToken`, بيانات شخصية).
- `payments/{paymentId}`: مدفوعات المجلس الواحد (`memberId`, `organizationId`, `status`, `amountDue/Paid`, `receiptUrl`, `transactionId`).
- `transactions/{transactionId}`: إيصالات المجلس الواحد (النسخة الحديثة أصبحت org-scoped).
- `notifications_queue/{notifId}`: طابور إشعارات قديم (لا يُقرأ من العميل).

## 2. المجموعات الفرعية للمجلس (`organizations/{organizationId}/...`)

### `roles/{roleId}`
- `roleId`, `roleName{ar,en}`, `arabicName`, `englishName`, `description{ar,en}`, `permissions[]`, `isSystemRole`/`systemRole`, `color`, `icon`, `priority`, `createdAt`, `updatedAt`, `createdBy?`, `updatedBy?`.
- الأدوار النظامية: `chairman`, `adminManager`, `financialManager`, `financialReviewer`, `secretary`, `member`.

### `memberships/{userId}`
- `userId`, `organizationId`, `memberNumber`, `roleId`, `status` (`active`/`pending`/`suspended`/`rejected`/`resigned`/`removed`/`cancelled`), `permissionsSnapshot[]`, `isPrimary`.
- الاعتماد: `approvedBy`, `approvedAt`, `joinedAt`, `joinedReason`, `invitedBy?`.
- التغيير: `updatedBy?`, `updatedAt?`, `removedBy?`, `removedAt?`, `leftReason?`.
- بيانات مخزّنة عند الاعتماد: `fullName`, `civilId`, `phone`, `email`, `address`.
- **معرّف المستند = userId** (عضوية واحدة لكل شخص في كل مجلس).

### `membership_requests/{requestId}`  (معرّف المستند = userId)
- `requestId`, `userId`, `organizationId`, `requestedRole` (`member`), `status` (`pending`/`approved`/`rejected`/`cancelled`), `reviewedBy?`, `reviewedAt?`, `rejectionReason?`, `cancelledBy?`, بيانات المتقدّم (`fullName`, `civilId`, `phone`, `email`, `address`), `submittedAt`.

### `transactions/{transactionId}` (الإيصالات المالية — org-scoped)
- `transactionId`, `organizationId`, `userId`, `uploadedByUserId`, `status` (`pendingReview`/`approved`/`rejected`), `reviewStatus`, `reviewedBy?`, `reviewedAt?`, `rejectionReason?`, `amountDeclared?`, `paymentId?`, `receiptUrl`, `receiptStoragePath`, بيانات الملف والعضو، `submittedAt`.
- **قاعدة الملكية:** `userId` و`uploadedByUserId` **يجب** أن يساويا `auth.uid` (تفرضه قواعد Firestore). ملف الإيصال يُخزَّن في Storage تحت `organizations/{orgId}/members/{auth.uid}/receipts/{transactionId}/{fileName}`.

### `bookings/{bookingId}`
- `bookingId`, `organizationId`, `userId`, `membershipId`, `status` (`pending`/`approved`/`rejected`/`cancelled`), `approvedBy?`, `rejectedBy?`, تفاصيل الحجز (`resourceId?`, `startAt?`, `endAt?`, `purpose?`).

### `settings/{settingId}`
- `settingId` ∈ {`organization`, `location_maps`}. حقول: `locale`, `timezone`, `currency`, `countryCode`, `navigationEnabled`, `allowHallRental?`, `phone/email/address?`, إحداثيات الخريطة، `updatedAt`, `updatedBy?`.

### `financial_profile/{profileId}`
- `profileId` = `banking`. حقول: `bankName`, `accountName`, `accountNumber`, `iban`, `swiftCode`, `enabled`, `updatedAt`, `updatedBy?`.

### `counters/{counterId}`
- `counterId` = `memberships`: `lastMemberNumber`, `updatedAt`, `updatedBy`.

### `audit_logs/{auditId}` (سجل الأحداث الخادمي — للقراءة فقط)
- `actorUserId`, `actorName`, `actorRole`, `action`, `targetType`, `targetId`, `organizationId`, `oldValue`, `newValue`, `createdAt`, `source` (`cloud_function`), `platform?`.
- يُكتب حصريّاً من Cloud Functions. راجع `AUDIT_LOGS.md`.

## 3. الفهارس (Indexes)
- الاستعلامات الحالية تستخدم فهارس أحادية الحقل التلقائية (بما فيها `audit_logs orderBy createdAt` + نطاق على نفس الحقل).
- `firestore.indexes.json` يحوي الفهارس المركّبة المطلوبة (مثل collection-group للعضويات). أي استعلام جديد بحقلين مختلفين + ترتيب يتطلب إضافة فهرس هنا.

## 4. قواعد إلزامية لأي مجموعة جديدة
1. ضعها تحت `organizations/{organizationId}/` ما لم تكن خاصة بالمنصّة.
2. ضمّن `organizationId` في المستند (لتسهيل التدقيق/الاستعلام).
3. أضف قاعدة معلّمة `{organizationId}` تتحقق من الصلاحية في نفس المجلس.
4. إن كانت حسّاسة، أضف مشغّل audit خادمي.
5. حدّث هذا الملف + `FIRESTORE_RULES.md`.
