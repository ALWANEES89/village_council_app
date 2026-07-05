# ROLES_AND_PERMISSIONS — نظام الأدوار والصلاحيات

> نموذج صلاحيات معزول لكل مجلس، deny-by-default. المصدر: `organizations/{orgId}/roles/{roleId}` + `permissionsSnapshot` على العضوية.

## 1. المبدأ
- كل مجلس يملك أدواره الخاصة (`roles` subcollection).
- عند إسناد دور لعضو، تُنسخ صلاحيات الدور إلى `membership.permissionsSnapshot` (لقطة محلّاة).
- القواعد والتطبيق يفحصان `permissionsSnapshot` — **لا** يعبر المجالس.
- `superAdmin` صلاحية **منصّة** منفصلة تماماً (`platform_admins`)، لا تُمنح عبر أدوار المجلس.

## 2. الأدوار النظامية (Seed — `OrganizationSeedService.defaultRoles`)
| roleId | الاسم | الصلاحيات (permissions) | priority |
|---|---|---|---|
| `chairman` | رئيس المجلس | `fullAccess` | 100 |
| `adminManager` | مدير إداري | `members.manage/read/approve`, `membershipRequests.review`, `organization.manage`, `settings.manage`, `bookings.read/approve/reject/manage` | 80 |
| `financialManager` | المدير المالي | `payments.manage/approve/reject/read`, `transactions.review`, `receipts.review`, `reports.view` | 70 |
| `financialReviewer` | المراجع المالي | مثل المالي بدون `payments.manage` | 60 |
| `secretary` | أمين السر | `membershipRequests.review`, `announcements.manage`, `notifications.send`, `audit.read` | 50 |
| `member` | عضو | `profile.read`, `payments.read`, `rentals.create`, `bookings.read/create` | 10 |
| — | **superAdmin** (منصّة) | `fullAccess` عبر `platform_admins` | — |

> `fullAccess` صلاحية شاملة تمنح كل شيء داخل المجلس (يستخدمها chairman).

## 3. مصفوفة "من يفعل ماذا"
| العملية | من يملكها |
|---|---|
| قراءة البيانات (عامة للمجلس) | أي عضو نشط في المجلس |
| قراءة الأعضاء | `members.read`/`members.manage` (`canReadMembers`) |
| إضافة/تعديل عضو (حالة/بيانات) | `members.manage` (`canManageMembers`) |
| **تغيير دور/صلاحيات عضو** | **`roles.manage`/`fullAccess` فقط** (`canAssignRoles`) — DEC-004 |
| اعتماد طلبات العضوية | `membershipRequests.review`/`members.approve`/`members.manage` |
| قراءة السجلات المالية | دور مالي أو `receipts.review`/`payments.*` |
| رفع الإيصالات | أي عضو (لنفسه) |
| اعتماد/رفض الإيصالات | دور مالي أو `receipts.review`/`payments.approve`/`payments.reject` |
| إدارة الحجوزات | `chairman`/`adminManager` أو `bookings.approve`/`bookings.manage` |
| تعديل صلاحيات دور | `roles.manage`/`fullAccess` |
| تعديل الإعدادات/الملف المالي | `roles.manage`/`fullAccess` (أو bootstrap) |
| قراءة سجل الأحداث | `roles.manage`/دور مالي/مراجع طلبات/superAdmin (`canReadAudit`) |
| إدارة المجالس (إنشاء/تعديل/أرشفة) | `superAdmin` فقط |

## 4. طبقة التطبيق: `AdminAccess` (`lib/core/auth/admin_access.dart`)
يشتقّ من العضوية المختارة + superAdmin:
- `has(permission)` — يراعي `fullAccess`.
- getters: `canReviewRequests`, `canManageMembers`, `canManageRoles`, `canReviewReceipts`, `canOpenAdmin`, **`canReadAudit`**.
- تُبنى في `adminAccessProvider` من `organizationContext.permissions` + `isSuperAdmin` + `isLegacyAdmin`.

> **القاعدة:** getters الواجهة تعكس قواعد Firestore. أي getter جديد يجب أن يطابق شرط القاعدة المقابلة (مثل `canReadAudit` يطابق قاعدة قراءة audit_logs).

## 5. تدفّق مزامنة الصلاحيات (Snapshot Sync)
1. عند اعتماد طلب عضوية → تُنسخ صلاحيات دور `member` إلى `permissionsSnapshot` (خادمياً/في المعاملة).
2. عند تغيير الدور (`MemberManagementRepository.changeRole`) → تُقرأ صلاحيات الدور الجديد وتُكتب `roleId`+`permissionsSnapshot` معاً + `updatedBy`.
3. تغيير صلاحيات **الدور** نفسه (roles) لا يُحدّث snapshots الأعضاء تلقائياً حالياً — راجع خطة المزامنة في `docs/TASK-005.2_PERMISSION_ENGINE_V1_ARCHITECTURE.md` (Reconciliation عبر مهمة خادمية مستقبلية).

## 5.1 المالك الأعلى (System Owner) وهرمية الملكية — DEC-012
- **مالك المنصّة:** `platform_admins/{uid}.role == 'system_owner'` (status `active`). `isSuperAdmin()` تمنحه كل صلاحيات المنصّة. **يُنشأ فقط من Console/Admin SDK** — لا يمكن لأي مستخدم رفع نفسه من الواجهة.
- **المالك الأساسي داخل المجلس:** عضوية بـ `roleId:'system_owner'`, `role:'owner'`, `isPrimaryOwner:true`, `permissionsSnapshot:['fullAccess']`, `memberNumber:'001'` (رقم للعرض فقط، ليس مصدر صلاحية).
- **الحماية:** عضوية المالك الأساسي لا يعدّلها/يحذفها إلا `isSuperAdmin()` — لا رئيس مجلس ولا مدير إداري يستطيع تخفيضه أو إلغاء عضويته.
- **الهرمية:** المالك الأعلى > رئيس المجلس (`chairman`) > بقية الأدوار. رئيس المجلس يدير مجلسه فقط؛ العضو العادي لا يغيّر الصلاحيات.

## 5.2 نقل رئاسة المجلس (transferCouncilPresident)
- "رئيس المجلس" = الدور `chairman` (بصلاحية fullAccess).
- العملية ترقّي عضواً نشطاً إلى `chairman` وتخفّض الرئيس السابق إلى `member`، **دون المساس بالمالك الأساسي**.
- المسموح لهم: `canAssignRoles` (المالك / `roles.manage` / الأدمن) — عبر زر "تعيين رئيساً للمجلس" في تفاصيل العضو.
- السجل يُكتب خادميًّا (`auditMembershipWrite`)، وإشعار للطرفين.

## 6. إضافة دور جديد (مستقبلاً)
- يُنشأ تحت `organizations/{orgId}/roles/{roleId}` بـ `roles.manage`.
- `isSystemRole=false`، صلاحيات من السجل المعتمد فقط، لا `superAdmin`.
- المنشئ لا يمنح صلاحية لا يملكها.
- لا يُحذف دور تُشير إليه عضويات قبل إعادة إسنادها.
- **يعمل تلقائياً لأي مجلس** دون تعديل كود (Multi-Tenant).

## 7. قواعد إلزامية
- لا تعتمد على `isAdmin` وحده (DEC-002/DEC-006).
- أي صلاحية جديدة: عرّفها بوضوح، اربطها بقاعدة Firestore، وحدّث هذا الملف + `SYSTEM_DECISIONS.md` إن غيّرت المعمارية.
- الصلاحيات مرتبطة بالمجلس الحالي فقط.
