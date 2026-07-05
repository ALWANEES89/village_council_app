# ORGANIZATION_BOOTSTRAP — إنشاء مجلس جديد

> كيف يُنشأ مجلس مكتمل البنية دون التأثير على بقية المجالس (Multi-Tenant).

## 1. مساران للبذر
### أ) إنشاء مجلس جديد (المسار الصحيح المعتمد)
`OrganizationRepository.bootstrapOrganization` (يستدعيه `create_organization_screen` للسوبر أدمن):
1. يولّد `organizationId` جديداً (`_organizations.doc()`).
2. في **معاملة واحدة** يكتب تحت المجلس الجديد فقط:
   - مستند المجلس (`status:active`, `profilePublished:true`, `schemaVersion:1`, `createdBy`).
   - `financial_profile/banking` (بيانات بنك افتراضية، `enabled:false`, `updatedBy`).
   - `settings/organization` + `settings/location_maps` (`updatedBy`).
   - كل الأدوار النظامية الستّة (`roles/*`, `createdBy`/`updatedBy`).
   - مستندات `_meta` للمجموعات (memberships/membership_requests/announcements/events/rentals/rental_resources).
   - اختياري: عضوية المنشئ كـ `chairman` (`assignCreatorAsChairman`).
3. **لا كتابة إلى أي مجلس آخر** — عزل تام.

### ب) بذر المجلس الأول (استثناء انتقالي — DEC-007)
`OrganizationSeedService` يبذر تلقائياً مجلساً باسم ثابت `rahmat_general_council` عند دخول أول أدمن قديم، ويعيّن أول أدمن كـ `chairman`. **هذا مخالف مؤقت لمبدأ "لا Hardcoded Organization"** ويُستبدل مستقبلاً بإنشاء يقوده superAdmin (راجع DEC-007).

## 2. قواعد Firestore الداعمة
- `create` على `organizations/{id}`: `isSuperAdmin()` أو `isProductionOrganizationBootstrap(id)` (للمجلس الأول فقط).
- بذر الأدوار/الإعدادات/الملف المالي: `canManageRoles(id)` أو ضمن bootstrap للمجلس الأول.
- كل القواعد **معلّمة `{organizationId}`** فتنطبق تلقائياً على أي مجلس جديد **دون تعديل قواعد**.

## 3. دورة حياة العضوية داخل المجلس
1. مستخدم يقدّم `membership_request` (`requestedRole:'member'`, `status:'pending'`).
2. مراجع يعتمد → تُنشأ `memberships/{userId}` بدور `member` + `permissionsSnapshot` من دور member + `approvedBy`.
3. مزامنة تلقائية: عداد `counters/memberships` يمنح `memberNumber`.
4. تغيير الدور لاحقاً يتطلب `roles.manage`/`fullAccess`.

## 4. إضافة مجلس جديد دون كسر النظام — Checklist
- [ ] الإنشاء عبر `bootstrapOrganization` فقط (لا كتابة يدوية بمعرّف ثابت).
- [ ] التأكد أن كل المجموعات تحت `organizations/{newId}/`.
- [ ] عدم لمس بيانات/قواعد المجالس الأخرى (القواعد عامة، لا تُعدّل).
- [ ] تعيين مسؤول أولي (chairman) للمجلس الجديد.
- [ ] التحقق أن سجل الأحداث بدأ يظهر أحداث المجلس الجديد فقط.

## 5. مبدأ Scalability
- إضافة المجلس رقم 100 لا تتطلب أي تغيير في القواعد أو الدوال — فقط بيانات جديدة تحت معرّف جديد.
- الدوال والقواعد **بلا حالة ومعلّمة بالمسار** → تخدم أي عدد من المجالس.

## 5.1 تثبيت المالك الأعلى (Bootstrap System Owner)
سكربت إداري لمرة واحدة: `scripts/bootstrap_system_owner.js` (Admin SDK — **لا يُشغَّل من التطبيق**).
- يتحقق `projectId == alrahmat-console` (يتوقّف إن اختلف).
- يتحقق من وجود عضوية المالك في `organizations/rahmat_general_council/memberships/{uid}` (يتوقّف إن غابت).
- يكشف تعارض `memberNumber/memberNo == "001"` على UID آخر؛ يتوقّف ويطبع تقريراً ما لم يُمرَّر `--confirm-transfer` (حينها ينقل 001 للمالك ويُفرِّغه من الحساب القديم).
- ينشئ/يحدّث `platform_admins/{uid}` (`role:system_owner`) وعضوية المالك (`roleId:system_owner`, `role:owner`, `isPrimaryOwner:true`, `permissionsSnapshot` كامل) عبر `merge` (لا يحذف حقولاً).
- التشغيل: اضبط `GOOGLE_APPLICATION_CREDENTIALS` على مفتاح service account، ثم `node scripts/bootstrap_system_owner.js` (أو `--dry-run` للمعاينة).

## 6. تقاعد الاستثناء (خطة DEC-007)
1. إضافة تدفّق "إنشاء أول مجلس" يقوده superAdmin من الواجهة.
2. إزالة `OrganizationSeedService` التلقائي والمعرّف الثابت.
3. إزالة قاعدة `isProductionOrganizationBootstrap`.
4. توثيق التغيير في `SYSTEM_DECISIONS.md` و`CHANGELOG.md`.
