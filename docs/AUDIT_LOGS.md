# AUDIT_LOGS — سجل الأحداث الخادمي

> سجل تدقيق **خادمي، append-only، معزول لكل مجلس**. يُكتب حصريّاً من Cloud Functions (Admin SDK). العميل ممنوع من الإنشاء/التعديل/الحذف. راجع DEC-003 و`CLOUD_FUNCTIONS.md`.

## 1. الموقع
`organizations/{organizationId}/audit_logs/{auditId}` — كل سجل داخل مجلسه (عزل تام).

## 2. مخطّط السجل (Schema)
| الحقل | الوصف |
|---|---|
| `actorUserId` | معرّف المستخدم المنفِّذ (قد يكون null نادراً) |
| `actorName` | اسم الفاعل (من `users`/`members`/العضوية) |
| `actorRole` | دور الفاعل: `chairman`/`adminManager`/…/`superAdmin`/`legacyAdmin`/`unknown` |
| `action` | نوع العملية (انظر القائمة أدناه) |
| `targetType` | نوع الهدف: `membership`/`role`/`membership_request`/`transaction`/`booking`/`settings`/`financial_profile`/`organization` |
| `targetId` | معرّف الهدف |
| `organizationId` | المجلس (دائماً) |
| `oldValue` | القيم قبل التغيير (لقطة الحقول المتغيّرة) |
| `newValue` | القيم بعد التغيير |
| `createdAt` | serverTimestamp |
| `source` | دائماً `cloud_function` |
| `platform` | إن توفّر في المستند |

## 3. العمليات المسجّلة (Actions)
| المشغّل (audit.js) | المسار | الأحداث |
|---|---|---|
| `auditMembershipWrite` | `.../memberships/{id}` | `membership.created/deleted/role_changed/status_changed/updated` |
| `auditRoleWrite` | `.../roles/{id}` | `role.created/deleted/permissions_changed` |
| `auditMembershipRequestWrite` | `.../membership_requests/{id}` | `membership_request.submitted/approved/rejected/cancelled/reopened` |
| `auditTransactionWrite` | `.../transactions/{id}` | `receipt.submitted/approved/rejected/reviewed` (فاعل `receipt.submitted` = `uploadedByUserId` = `auth.uid`) |
| `auditBookingWrite` | `.../bookings/{id}` | `booking.created/approved/rejected/cancelled` |
| `auditSettingsWrite` | `.../settings/{id}` | `settings.created/updated` |
| `auditFinancialProfileWrite` | `.../financial_profile/{id}` | `financial_profile.created/updated` (بلا قيم سرّية) |
| `auditOrganizationWrite` | `organizations/{id}` | `organization.created/updated/status_changed/deleted` |

## 4. كيف يُحسب الفاعل (actorName/actorRole)؟
مشغّلات الخلفية لا تحمل هوية المنفِّذ (DEC-008)، لذلك:
1. يُشتقّ `actorUserId` من حقول المستند: `approvedBy`/`reviewedBy`/`updatedBy`/`removedBy`/`cancelledBy`/`userId`.
2. `actorName` من `users/{uid}.fullName` → `members/{uid}.fullName` → العضوية.
3. `actorRole`: `platform_admins`(superAdmin) → `memberships.roleId` (نفس المجلس) → `legacyAdmin` → `unknown`.
> لضمان عدم ظهور `unknown` في تعديلات الأدوار/المجلس، يكتب العميل `updatedBy` في: `RoleRepository`, `OrganizationRepository`, وبذر المجلس.

## 5. الخصوصية (Financial Profile)
سجل `financial_profile` **لا** يخزّن القيم السرّية (رقم الحساب/IBAN)، بل قائمة الحقول المتغيّرة + حالة التفعيل فقط.

## 6. عدم التكرار (Idempotency)
معرّف مستند السجل = `event.id` — إعادة تشغيل المشغّل لا تُنشئ سجلاً مكرّراً.

## 7. القراءة والعزل
- قاعدة القراءة: `isSuperAdmin() || canManageRoles(orgId) || canReviewReceipts(orgId) || canReviewMembershipRequests(orgId)` — **لنفس المجلس**.
- **مدير مجلس لا يقرأ سجل مجلس آخر** (لا عضوية له في المسار).
- الكتابة/التعديل/الحذف من العميل = `false`.

## 8. عارض السجل (Audit Viewer)
- الشاشة: `lib/features/audit/presentation/audit_logs_screen.dart` (للقراءة فقط).
- الوصول مقيّد بـ `AdminAccess.canReadAudit`.
- superAdmin/legacyAdmin يرون كل المجالس؛ غيرهم يرون فقط المجالس التي يملكون صلاحية قراءتها (`membershipCanReadAudit`).
- فلاتر: `action`/`actorRole`/`targetType`/نطاق التاريخ/بحث بالاسم؛ وعرض منظّم لـ `oldValue`/`newValue`.

## 9. سجل منفصل: `member_history`
`member_history` (مجموعة عليا) سجل معروض للعضو يُكتب من العميل — منفصل عن التدقيق الأمني (DEC-009).

## 10. عند إضافة عملية حسّاسة جديدة
1. أضف مشغّل `onDocumentWritten` في `functions/audit.js` تحت `organizations/{organizationId}/...`.
2. استخدم `writeAudit(event.id, {...})` بنفس المخطّط.
3. تأكّد أن الكاتب من العميل يضع حقل الفاعل (`updatedBy`/…).
4. حدّث هذا الملف + `CLOUD_FUNCTIONS.md`.
