# MULTI_TENANT_ARCHITECTURE — معمارية تعدّد المؤسسات وعزل المجالس

> المرجع الرسمي لكيفية دعم النظام لعشرات/مئات المجالس داخل **Firebase Project واحد** مع عزل كامل. راجع `SYSTEM_DECISIONS.md` (DEC-001).

## 1. النموذج: Shared Project, Isolated Data
- **مشروع Firebase واحد** (`alrahmat-console`) يخدم كل المجالس.
- كل مجلس = مستند `organizations/{organizationId}` + كل بياناته في **subcollections** تحته.
- العزل يُفرض في **Firestore Security Rules** بالاعتماد على `organizationId` في المسار، وليس على ثقة العميل.

```
organizations/{organizationId}/
 ├── roles/{roleId}
 ├── memberships/{userId}
 ├── membership_requests/{requestId}
 ├── transactions/{transactionId}       # الإيصالات المالية
 ├── bookings/{bookingId}
 ├── settings/{settingId}
 ├── financial_profile/{profileId}
 ├── counters/{counterId}
 └── audit_logs/{auditId}               # سجل أحداث المجلس (معزول)
```

## 2. هوية الشخص مقابل العضوية (Identity vs Membership)
- **الشخص** = `users/{userId}` (حساب واحد، Firebase Auth uid).
- **العضوية** = `organizations/{orgId}/memberships/{userId}` — تربط الشخص بمجلس، بدور وصلاحيات وحالة.
- شخص واحد قد ينتمي لعدّة مجالس عبر عدّة مستندات عضوية. **معرّف مستند العضوية = userId** لضمان عضوية واحدة لكل شخص في كل مجلس.
- الصلاحيات **لا تعبر حدود المجلس**: `payments.read` في مجلس A لا تمنح شيئاً في مجلس B.

## 3. آليات العزل (Isolation Mechanisms)
| الآلية | كيف تعزل |
|---|---|
| **المسار (Path scoping)** | كل قراءة/كتابة تحت `organizations/{orgId}/...`؛ القواعد تربط `organizationId` من المسار |
| **دوال القواعد** | `canManageRoles(orgId)`, `canReviewReceipts(orgId)`, `isOrganizationMember(orgId)` تقرأ عضوية الفاعل **في نفس المجلس فقط** |
| **snapshot الصلاحيات** | `permissionsSnapshot` مخزّن على مستند العضوية داخل المجلس |
| **Cloud Functions** | كل مشغّل يستخدم `event.params.organizationId` ويكتب Audit في **نفس** المجلس |
| **استعلامات collectionGroup** | مقيّدة دائماً بـ `where('userId', == request.auth.uid)` والقواعد تفرض `resource.data.userId == request.auth.uid` |

## 4. لماذا `list` على memberships مقيّد؟
سابقاً كان `allow list: if isAuth()` يسمح لأي مستخدم بتعداد عضويات **كل** المجالس عبر collectionGroup. تم تقييده إلى:
```
allow list: if isAuth() && (
  resource.data.userId == request.auth.uid ||   # عضوياتي أنا
  canReadMembers(organizationId) ||              # مخوّل في هذا المجلس
  isOrganizationMember(organizationId)           # عضو نشط في هذا المجلس
);
```
النتيجة: استعلام collectionGroup غير مقيّد يُرفض؛ لا تعداد عبر المجالس. راجع DEC-005.

## 5. عزل سجل الأحداث (Audit Isolation)
- كل سجل يُكتب في `organizations/{orgId}/audit_logs` — مشتق من `event.params.organizationId`.
- قراءة السجل مقيّدة بـ `isSuperAdmin() || canManageRoles(orgId) || canReviewReceipts(orgId) || canReviewMembershipRequests(orgId)` — كلها تتحقق من عضوية الفاعل **في نفس المجلس**.
- شاشة Audit Viewer تعرض فقط المجالس التي يملك المستخدم صلاحية قراءتها (superAdmin/legacyAdmin يرون الكل).

## 6. إضافة مجلس جديد دون التأثير على غيره
- إنشاء المجلس عبر `OrganizationRepository.bootstrapOrganization` يولّد `organizationId` جديداً ويبذر: الأدوار النظامية، الإعدادات، الملف المالي، والعدّادات — **كلها تحت المجلس الجديد فقط**.
- لا توجد كتابة إلى مجالس أخرى، ولا فهارس/قواعد مخصّصة لكل مجلس (القواعد **عامة معلَّمة بالمسار**، تنطبق تلقائياً على أي `organizationId`).
- التفاصيل في `ORGANIZATION_BOOTSTRAP.md`.

## 7. قابلية التوسّع (Scalability)
- **القواعد لا تكبر مع عدد المجالس** — قاعدة واحدة معلّمة `{organizationId}` تخدم الجميع.
- **الاستعلامات مفهرسة تلقائياً** ضمن كل subcollection؛ لا فهرس مركّب مطلوب للاستعلامات الحالية.
- **Cloud Functions** بلا حالة (stateless) وتتوسّع أفقياً؛ idempotent عبر `event.id`.
- نقطة انتباه مستقبلية: عمليات "عبر كل المجالس" (تقارير المنصّة) يجب أن تُبنى بحذر (collectionGroup + فهارس + صلاحية superAdmin فقط).

## 8. الاستثناء الانتقالي (يجب معرفته)
يوجد حالياً **بذر تلقائي لأول مجلس** باسم ثابت `rahmat_general_council` (عبر `OrganizationSeedService` وقاعدة `isProductionOrganizationBootstrap`). هذا **مخالف مؤقت** لمبدأ "لا Hardcoded Organization" وموثّق في DEC-007 مع خطة استبداله بإنشاء يقوده superAdmin. أي مجلس **جديد** يُنشأ عبر المسار الصحيح (bootstrapOrganization) بلا أي اسم ثابت.

## 9. قواعد إلزامية للميزات الجديدة (Multi-Tenant)
- ابدأ دائماً من `organizationId` المختار (`organizationContextProvider`) — لا تفترض مجلساً.
- ضع أي مجموعة جديدة **تحت** `organizations/{orgId}/` ما لم تكن خاصة بالمنصّة (superAdmin).
- أضف قاعدة معلّمة `{organizationId}` تتحقق من الصلاحية في نفس المجلس.
- إن احتجت audit، اكتبه خادمياً في `organizations/{orgId}/audit_logs`.
- أي استعلام collectionGroup يجب أن يُقيَّد بحقل يفرض ملكية المستخدم.
