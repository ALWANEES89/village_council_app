# FIRESTORE_RULES — شرح قواعد الأمان

> الملف الفعلي: `firestore.rules`. هذه الوثيقة تشرح النية والدوال. **كل قاعدة معلّمة بـ `{organizationId}` تنطبق تلقائياً على أي مجلس** — لا حاجة لتعديلها عند إضافة مجالس (Multi-Tenant).

## 1. الدوال المساعدة (Helpers)
| الدالة | المعنى |
|---|---|
| `isAuth()` | مستخدم مسجّل |
| `isOwner(uid)` | المستخدم الحالي = uid |
| `isSuperAdmin()` | `platform_admins/{uid}` بدور `superAdmin` + `active` + `fullAccess` |
| `isAdmin()` | superAdmin **أو** `members/{uid}.isAdmin==true` (إرث قديم — DEC-006) |
| `canManageRoles(orgId)` | superAdmin أو عضوية نشطة بـ `fullAccess`/`roles.manage` |
| `canManageMembers(orgId)` | isAdmin أو `fullAccess`/`members.manage` |
| `canReadMembers(orgId)` | canManageMembers أو `members.read` |
| `canReviewMembershipRequests(orgId)` | isAdmin أو `fullAccess`/`membershipRequests.review`/`members.approve`/`members.manage`... |
| `canReviewReceipts(orgId)` | superAdmin أو دور مالي (`chairman`/`financialManager`/`financialReviewer`) أو `receipts.review`/`payments.approve`/`payments.reject` |
| `canReviewBookings(orgId)` | superAdmin أو `chairman`/`adminManager` أو `bookings.manage`/`bookings.approve` |
| `isOrganizationMember(orgId)` | عضوية نشطة في المجلس |
| **`canAssignRoles(orgId)`** | isAdmin أو canManageRoles — **الوحيد** المخوّل بتغيير الدور/الصلاحيات (DEC-004) |
| **`membershipPrivilegeFieldsUnchanged()`** | يمنع تغيير `roleId`/`permissionsSnapshot`/`userId`/`organizationId` في تحديث بصلاحية members.manage |
| **`hasNoPrivilegedPermissions(perms)`** | يمنع منح صلاحيات مرتفعة عبر مسار اعتماد العضوية |
| `isProductionOrganizationBootstrap(orgId)` | بذر المجلس الأول فقط (DEC-007) |

## 2. قواعد رئيسية (org-scoped)

### `organizations/{organizationId}`
- `read`: أي مسجّل. `create`: superAdmin أو bootstrap. `update,delete`: superAdmin.

### `organizations/{orgId}/roles/{roleId}`
- `read`: أي مسجّل. `create/update/delete`: `canManageRoles(orgId)` (أو bootstrap للأدوار النظامية).

### `organizations/{orgId}/memberships/{membershipId}`
- `list`: **مقيّد** — `userId==self ∨ canReadMembers ∨ isOrganizationMember` (DEC-005).
- `read`: نفسه أو مخوّل أو عضو نشط.
- `create`: `canAssignRoles` **أو** مسار اعتماد (مراجع الطلبات، `roleId=='member'`، بلا صلاحيات مرتفعة، وتحوّل الطلب pending→approved).
- `update`: `canAssignRoles` (تغيير كامل) **أو** `canManageMembers && membershipPrivilegeFieldsUnchanged()` (حالة/بيانات فقط) **أو** مسار الاعتماد المقيّد.
- `delete`: `canManageMembers`.

### `organizations/{orgId}/membership_requests/{requestId}`
- `read`: صاحب الطلب أو مراجع الطلبات.
- `create`: صاحبه فقط (`requestId==uid`, `requestedRole=='member'`, `status=='pending'`).
- `update`: مراجع (pending→approved/rejected بحقول محدّدة) أو صاحبه (إلغاء/إعادة تقديم بشروط).

### `organizations/{orgId}/transactions/{transactionId}`
- `read`: صاحبه أو مراجع مالي. `create`: صاحبه (`status=='pendingReview'`). `update`: مراجع مالي. `delete`: ممنوع.

### `organizations/{orgId}/bookings/{bookingId}`
- `read`: أي مسجّل. `create`: صاحبه (عضوية نشطة أو تفعيل تأجير القاعة). `update`: `canReviewBookings` (اعتماد/رفض بحقول محدّدة). `delete`: ممنوع.

### `organizations/{orgId}/settings|financial_profile|counters`
- `read`: أي مسجّل (settings/financial) — counters للمراجعين. `create/update`: `canManageRoles` (أو bootstrap). `delete`: مقيّد/ممنوع.

### `organizations/{orgId}/audit_logs/{auditId}`
- `read`: superAdmin أو canManageRoles أو canReviewReceipts أو canReviewMembershipRequests **لنفس المجلس**.
- `create,update,delete`: **`false`** — خادمي فقط (DEC-003).

## 3. المجموعات العُليا
- `members` (إرث): العضو يقرأ نفسه؛ الأدمن يدير. لا كلمات مرور. العضو يعدّل `fcmToken`/`photoUrl` فقط.
- `users`: المالك يقرأ/يعدّل (بلا حقول محمية)؛ حقول محدّدة للمراجعين. `users/{uid}/notifications`: المالك يقرأ/يعلّم كمقروء؛ الإنشاء بشروط.
- `platform_admins`: قراءة لأي مسجّل (TODO تقييد)؛ إنشاء/حذف ممنوع؛ تحديث تفضيلات الإشعارات لصاحبه superAdmin فقط.
- `member_history`: قراءة لصاحبه/المخوّل؛ إنشاء بشرط `actorUserId==uid`؛ لا تعديل/حذف من العميل.
- `payments`/`transactions` (إرث): العضو يقرأ ماله؛ المراجع/الأدمن يديران.

## 4. حماية عزل المجالس في القواعد
- كل دالة صلاحية تأخذ `organizationId` وتقرأ عضوية الفاعل **في نفس المسار** — لا صلاحية تعبر المجالس.
- `list`/collectionGroup مقيّدة بملكية المستخدم (DEC-005).

## 5. الاختبار والنشر
- التحقق: `firebase deploy --only firestore:rules --dry-run --project <id>` (يتطلب `firebase login`).
- **لا تُنشر على الإنتاج دون اجتياز `PRE_DEPLOY_TEST_CHECKLIST.md`.**

## 6. عند إضافة ميزة
- أضف قاعدة معلّمة `{organizationId}`، deny-by-default، تحقّق الصلاحية في نفس المجلس، ثم حدّث هذا الملف.
