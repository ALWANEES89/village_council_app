# CHANGELOG

> سجل التغييرات المهمّة. صيغة التاريخ: YYYY-MM-DD. أي تغيير معماري يُربط بقرار في `SYSTEM_DECISIONS.md`.

## [Unreleased] — 2026-07-03

### إصلاح (Fix) — استخدام isSystemOwner فعليًا + عرض الدور بالعربي + فتح المجلس
- **firestore.rules:** `isSystemOwner()` أصبحت الدالة الأساسية ومستخدمة صراحةً في مسارات `memberships` (list/read/create/update/delete) و`audit_logs` و`transactions` (Global Override للمالك الأعلى على كل المجالس)؛ حُذفت الدوال غير المستخدمة `isPlatformAdmin`/`isSignedIn` (سبب تحذير Unused function). حماية المالك الأساسي محفوظة (لا يعدّله/يحذفه إلا system_owner).
- **عرض الدور بالعربي:** `core/auth/role_labels.dart` (خريطة مركزية) — لا يُعرض `system_owner` خام؛ يظهر "المالك الأعلى". طُبِّق في: شاشة العضويات (member_home)، اختيار المجلس، تفاصيل العضو، قائمة الأعضاء.
- **فتح المجلس (canOpenCouncil):** `OrganizationContext.selectOrganization` لم تعد تفشل عند غياب مستند الدور (roleId=system_owner بلا role doc) — تبني دورًا اصطناعيًا والصلاحيات من `permissionsSnapshot`، فيفتح المالك مجلسه.
- **Debug logs:** عند فتح المجلس (`[Council] open ...`) وفي تفاصيل العضو/اللوحة (`[Access] ...`).
- **Breaking Changes:** لا. **التحقق:** `flutter analyze` نظيف.

### أداة (Tooling) — سكربت تثبيت المالك الأعلى
- **الملف الجديد:** `scripts/bootstrap_system_owner.js` (Admin SDK، لمرة واحدة).
- **الغرض:** تعيين `3PpbBzCACsh8PphpbN5Gp1keolF3` مالكاً أعلى (`system_owner`) في `alrahmat-console` / `rahmat_general_council`.
- **الأمان:** يتحقق من projectId؛ يتحقق من وجود العضوية؛ يكشف تعارض 001 ويتوقّف حتى `--confirm-transfer`؛ يكتب عبر `merge`؛ يدعم `--dry-run`. لا يُشغَّل من التطبيق.
- **التحقق:** `node --check` ناجح، `flutter analyze` نظيف. (يُشغَّل بمفتاح service account من قِبَل المسؤول.)

### ميزة (Feature) — خدمة صلاحيات مركزية + محرّر صلاحيات + اللوحة الذهبية للمالك
- **الوصف:** توحيد قرارات الصلاحيات في `AdminAccess` (Access Control Service) بدوال: `isSystemOwner`/`isPlatformAdmin`/`isOrgOwner`/`isChairman`/`canAccessGoldenAdminPanel`/`canManageMembers`/`canChangeRoles`/`canTransferCouncilManager`/`canSuspendMembers`/`canCancelMemberships`/`canViewAuditLogs`/`canEditMember`. شاشة **تعديل صلاحيات العضو** (دور + صلاحيات مخصّصة). عرض عضوية المالك باللون **السماوي (cyan)**.
- **إصلاح ظهور اللوحة الذهبية:** `isActiveSuperAdmin` صارت تعترف بـ `role='system_owner'` → المالك تظهر له اللوحة. `canAccessGoldenAdminPanel` موسّعة (مالك/رئيس/مدير/صلاحيات) ولا تظهر للعضو العادي.
- **الملفات:** `core/auth/admin_access.dart` (مركزية)، `data/models/membership_model.dart` (+role,+isPrimaryOwner)، `data/repositories/platform_admin_repository.dart` (system_owner)، `providers/app_providers.dart` (تعبئة الحقول)، `features/member_management/.../member_permissions_screen.dart` (جديد)، `member_management_repository.dart` (`updateMemberPermissions`)، `member_details_screen.dart` (+محرّر/+بانر مالك/+سجلّات)، `member_list_screen.dart` (لون المالك)، `admin_dashboard.dart` (سجلّات)، `router/app_router.dart` (مسار المحرّر).
- **firestore.rules:** `platform_admins` صار `get` ذاتي فقط + `list:false` + لا create/delete من العميل؛ دوال `isSignedIn`/`isSystemOwner`.
- **الأمان:** محرّر الصلاحيات يستخدم مفاتيح **dotted** التي تفرضها القواعد فعليًّا (لا camelCase صوريّة)؛ يمنع إسناد `system_owner` من التطبيق؛ يحمي المالك الأساسي.
- **سجلّات تطوير مؤقتة (debug فقط)** في لوحة الإدارة وتفاصيل العضو (`assert`، تُزال في release).
- **Breaking Changes:** لا. **التحقق:** `flutter analyze` نظيف.

### ميزة (Feature) — المالك الأعلى (System Owner) + حماية المالك + نقل رئاسة المجلس
- **الوصف:** حساب صاحب المشروع (العضوية 001) يصبح المالك الأعلى فوق رئيس المجلس؛ لا يمكن لأحد تخفيضه/حذفه؛ وميزة نقل رئاسة المجلس. راجع **DEC-012**.
- **الملفات المعدّلة:**
  - `firestore.rules`: `isSuperAdmin` تشمل `system_owner`؛ دوال `isPlatformAdmin`/`isOrgOwner`/`membershipIsPrimaryOwner`؛ `canAssignRoles` تشمل مالك المجلس؛ حماية المالك الأساسي في `memberships` update/delete.
  - `lib/features/member_management/data/member_management_repository.dart`: `transferCouncilPresident` (ترقية/تخفيض + حماية المالك + إشعارات؛ السجل خادميّ).
  - `lib/features/member_management/presentation/member_details_screen.dart`: زر "تعيين رئيساً للمجلس" (يظهر للمالك فقط)، ورسائل خطأ ودّية بدل `permission-denied`.
- **الأمان:** يعتمد على `platform_admins`+`roleId`+`fullAccess`+`status` (لا boolean قابل للتزوير). أول تعيين للمالك **يدويّ من Console/Admin SDK فقط** (لا من الواجهة). Multi-Tenant غير متأثّر (كل شيء org-scoped).
- **يتطلّب:** تعيين المالك يدويًّا في Console + إعادة نشر `firestore.rules`.
- **Breaking Changes:** لا (إضافات متوافقة خلفيًا).
- **التحقق:** `flutter analyze` نظيف.

### إصلاح خطأ حرج (Bug Fix) — بنية storage.rules تُفشل التصريف فيبقى النشر قديمًا
- **الأعراض:** `[firebase_storage/unauthorized]` عند رفع الإيصال **رغم** أن `auth.uid == userId` والمسار صحيح (تأكّد بالتشغيل الفعلي على جهاز؛ فشل الصورة و PDF ومجلسين مختلفين). ورافقه `[Memberships] collectionGroup permission-denied`.
- **السبب الجذري الحقيقي:** الدوال المساعدة (`isAdmin`/`isSuperAdmin`/`isFinanceReviewer`/`hasFinanceMembership`) كانت مُعرّفة على مستوى `service` **خارج** `match /b/{bucket}/o`. في Storage Rules يجب تعريف الدوال **داخل** كتلة match؛ وإلا **يفشل تصريف الملف** → يُرفض النشر → تبقى قواعد الإنتاج **قديمة لا تعرف مسار `organizations/{org}/members/{uid}/receipts/...`** → رفض. (رفض Firestore collectionGroup مؤشّر موازٍ على أن القواعد المنشورة قديمة.)
- **الإصلاح:** نقل الدوال الأربع **داخل** `match /b/{bucket}/o` ليصبح الملف قابلًا للتصريف والنشر. **لم تُفتح أي صلاحية ولم يُستخدم `allow true`** (الشروط كما هي).
- **الملفات المعدّلة:** `storage.rules`.
- **يتطلّب نشرًا:** لا يمكن لأي تعديل كود إصلاح رفض من طبقة القواعد؛ يجب **نشر** `storage.rules` (و`firestore.rules`) لتفعيل الإصلاح. (لم يُنشر في هذه الجلسة.)
- **Security:** لا تراجع؛ القواعد تبقى مقيّدة (المالك فقط + الحجم + النوع).
- **Breaking Changes:** لا.
- **التحقق:** `flutter analyze` نظيف؛ تحقّق التصريف عبر `firebase deploy --only storage --dry-run` بعد `firebase login`.

### إصلاح (Bug Fix) — ملكية الإيصال = auth.uid (دفاع في العمق)
- **السبب:** مسار الرفع وحقول المعاملة كانت تستخدم معرّفًا ممرّرًا من الشاشة قد يساوي **معرّف `members` القديم** المختلف عن `auth.uid` (fallback عبر الهاتف في `AuthService`). قواعد Storage/Firestore تشترطان الملكية == `auth.uid`.
- **الإصلاح:** اشتقاق المالك حصريًّا من `FirebaseAuth.currentUser.uid` في `UploadNotifier.uploadReceipt` + سطور تشخيص (debug) تؤكّد ذلك. لم يكن هو السبب لهذا المستخدم (كان `match=true`) لكنه إصلاح لازم لحسابات قديمة أخرى.
- **الملفات المعدّلة:** `lib/providers/app_providers.dart`.
- **الوثائق:** `FIREBASE_SECURITY.md` · `DATABASE_STRUCTURE.md` · `AUDIT_LOGS.md` · `ROADMAP.md`.

---


### الأمان (Security)
- **إصلاح تصعيد صلاحيات حرج:** تغيير `roleId`/`permissionsSnapshot` للعضوية أصبح يتطلب `roles.manage`/`fullAccess` فقط؛ `members.manage` يدير الحالة/البيانات دون لمس الصلاحيات. (DEC-004)
- **إغلاق تسريب بين المجالس:** تقييد `list` على `memberships` من `isAuth()` إلى (self ∨ canReadMembers ∨ isOrganizationMember). (DEC-005)
- **سلامة السجل:** `audit_logs` و`member_history` — الفاعل يجب أن يساوي المستخدم الحالي؛ ومنع انتحال الفاعل.
- **مواءمة الواجهة:** زر "تغيير الصلاحية" في تفاصيل العضو مقيّد الآن بـ `canManageRoles`.

### سجل الأحداث الخادمي (Audit — Cloud Functions)
- إضافة `functions/audit.js` بـ **8 مشغّلات** `onDocumentWritten` (memberships, roles, membership_requests, transactions, bookings, settings, financial_profile, organizations). (DEC-003)
- مخطّط غنيّ: `actorUserId/actorName/actorRole/action/targetType/targetId/organizationId/oldValue/newValue/createdAt/source=cloud_function/platform`.
- Idempotency عبر `event.id`.
- إزالة كل كتابات `audit_logs` من العميل (financial approve، membership_request approve، organization bootstrap+repair).
- قاعدة `audit_logs`: `create,update,delete: if false` (خادمي فقط، append-only).

### توثيق الفاعل (Actor Attribution) — (DEC-008)
- `RoleRepository.create/update` و`OrganizationRepository.update/setArchived` تكتب `updatedBy`/`createdBy`.
- تمرير `actorUserId` من: roles_management_screen، create_organization_screen، organizations_management_screen.
- بذر المجلس (`bootstrapOrganization` + `OrganizationSeedService`) يختم `createdBy`/`updatedBy` على المجلس/الأدوار/الإعدادات/الملف المالي.

### الواجهة (UI)
- **شاشة Audit Viewer** جديدة (`lib/features/audit/`): للقراءة فقط، معزولة لكل مجلس، مع فلاتر (action/actorRole/targetType/date-range/بحث بالاسم) وعرض منظّم لـ old/new.
- مسار `/admin/audit`، وبطاقة في لوحة الإدارة مقيّدة بـ `AdminAccess.canReadAudit`.

### التوثيق (Docs)
- إنشاء مجلد `docs/` الرسمي (المعمارية، الأمان، القواعد، الأدوار، السجل، Multi-Tenant، البذر، النشر، النسخ الاحتياطي، القرارات...).
- اعتماد `SYSTEM_DECISIONS.md` كمرجع إلزامي للقرارات المعمارية.

### الحوكمة (Governance) — الدستور الرسمي
- **الملفات المعدّلة:** `docs/DEVELOPER_GUIDE.md`, `docs/INSTALLATION_GUIDE.md`, `docs/USER_MANUAL.md`, `docs/ADMIN_MANUAL.md`, `docs/CLIENT_IMPLEMENTATION_GUIDE.md`, `docs/ROADMAP.md` (جديدة)؛ `docs/README.md`, `docs/SYSTEM_DECISIONS.md`, `docs/CHANGELOG.md` (محدّثة).
- **السبب:** اعتماد المشروع رسمياً كمنصّة Enterprise Multi-Tenant SaaS مع حوكمة Documentation-First (self-documenting).
- **أُضيف:** 6 وثائق رسمية مطلوبة؛ قرار **DEC-011** (الدستور)؛ تحديث الفهرس.
- **Breaking Changes:** لا (توثيق وحوكمة فقط).
- **الحالة:** `flutter analyze` نظيف؛ لم يُعدّل كود؛ لم يُنشر على الإنتاج.

### الحالة
- `flutter analyze`: نظيف. `node --check` للدوال: ناجح.
- **لم يُنشر على الإنتاج.** كل التغييرات محلية بانتظار اجتياز `PRE_DEPLOY_TEST_CHECKLIST.md`.

---

## قالب إدخال جديد
```
## [الإصدار] — YYYY-MM-DD
### Security
### Features
### Fixes
### Docs
### Breaking Changes  (مع ربط SYSTEM_DECISIONS)
```
