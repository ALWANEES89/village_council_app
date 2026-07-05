# PROJECT_ARCHITECTURE — الهيكل المعماري للنظام

> **قرار المشروع النهائي:** هذا ليس تطبيق مجلس واحد، بل **منصة SaaS متعددة المؤسسات (Multi-Tenant Platform)** تدير عشرات/مئات المجالس من خلال **Firebase Project واحد** مع **عزل كامل** بين كل المجالس. راجع `SYSTEM_DECISIONS.md` (DEC-001).

## 1. نظرة عامة
منصة لإدارة المجالس/الجمعيات: الأعضاء، العضويات، الأدوار والصلاحيات، المدفوعات والإيصالات، الحجوزات، الإشعارات، وسجل الأحداث — كلها معزولة لكل مجلس.

## 2. التقنيات (Stack)
| الطبقة | التقنية |
|---|---|
| الواجهة | Flutter (Dart) — Arabic-first / RTL |
| إدارة الحالة | Riverpod |
| التنقّل | GoRouter (`lib/router/app_router.dart`) |
| المصادقة | Firebase Authentication |
| قاعدة البيانات | Cloud Firestore |
| التخزين | Firebase Storage |
| الخادم | Cloud Functions (Node 20, `firebase-functions` v5) |
| الإشعارات | Firebase Cloud Messaging (FCM) |

## 3. طبقات التطبيق (Client)
```
lib/
├── main.dart                     # تهيئة Firebase + Seed + Notifications + RTL
├── router/app_router.dart        # كل المسارات + حماية إعادة التوجيه
├── core/
│   ├── auth/admin_access.dart     # نموذج الصلاحيات المشتقّة (canReadAudit, canManageRoles...)
│   ├── context/organization_context.dart  # المجلس المختار الحالي
│   └── theme/app_theme.dart
├── data/
│   ├── models/                    # PaymentModel, TransactionModel, MembershipModel, ...
│   ├── repositories/              # منطق الوصول للبيانات (org-scoped)
│   └── services/                  # AuthService, FirestoreService, StorageService, NotificationService, OrganizationSeedService
├── providers/app_providers.dart   # مزوّدات Riverpod العامة
├── features/                      # وحدات مستقلة (feature-first)
│   ├── membership_request/
│   ├── member_management/
│   └── audit/                     # شاشة سجل الأحداث
└── presentation/screens/          # شاشات مصادقة/عضو/إدارة/مؤسسة
```

**مبدأ التصميم:** feature-first + Clean-ish separation (Screen → Provider → Repository → Firestore). كل Repository يعمل ضمن `organizationId` (باستثناء المجموعات القديمة/العامة الموثّقة في `DATABASE_STRUCTURE.md`).

## 4. الطبقة الخلفية (Firebase)
```
Firestore
 ├── organizations/{organizationId}/...   # كل بيانات المجلس (معزولة)
 ├── users/{userId}                        # حساب الشخص (V2)
 ├── platform_admins/{userId}              # مشرفو المنصّة (superAdmin)
 └── members/, payments/, transactions/    # إرث المجلس الواحد (Legacy — قيد التقاعد)

Cloud Functions (us-central1)
 ├── onNotificationCreated                 # إرسال FCM عند إشعار داخلي
 ├── sendPushNotification                  # (Legacy) طابور الإشعارات
 └── audit* (8 triggers)                   # سجل الأحداث الخادمي
```

## 5. تدفّق البيانات النموذجي (مثال: رفع إيصال)
1. العضو يرفع ملف الإيصال → Firebase **Storage** (`organizations/{org}/members/{uid}/receipts/...`).
2. يُنشئ مستند **transaction** تحت `organizations/{org}/transactions/{id}` بحالة `pendingReview`.
3. **Cloud Function** `auditTransactionWrite` تُنشئ `receipt.submitted` في `organizations/{org}/audit_logs`.
4. المراجع المالي يعتمد/يرفض → تحديث المستند → CF تُنشئ `receipt.approved`/`receipt.rejected`.
5. إشعار داخلي للعضو → `onNotificationCreated` ترسل FCM.

## 6. المبادئ المعمارية الإلزامية (لكل تطوير قادم)
1. المشروع منصة **Multi-Tenant** (عشرات/مئات المجالس، مشروع Firebase واحد).
2. **لا Hardcoded Organization** داخل الكود (الاستثناء الانتقالي الوحيد موثّق في DEC-007).
3. كل البيانات معزولة بـ `organizationId`.
4. كل Firestore Rules تعتمد على `organizationId`.
5. كل Cloud Function تعمل داخل نطاق `organizations/{organizationId}/...`.
6. كل Audit Logs معزولة لكل مجلس.
7. كل الصلاحيات مرتبطة بالمجلس الحالي فقط.
8. أي ميزة جديدة تعمل مباشرة مع عشرات/مئات المجالس **دون تعديل الكود**.
9. التفكير في Scalability + الأداء + الأمان من البداية.
10. كل التعديلات متوافقة مع المستقبل (إضافة مجالس/أدوار/وحدات دون إعادة تصميم).

## 7. تعريف "الميزة المكتملة" (Definition of Done)
أي ميزة لا تُعتبر مكتملة إلا بعد:
- تحديث الوثائق المرتبطة بها.
- تحديث `SYSTEM_DECISIONS.md` إن أثّرت على المعمارية.
- مراجعة Firestore Rules.
- مراجعة Cloud Functions.
- مراجعة Audit Logs.
- التأكد من عدم كسر دعم تعدّد المجالس.

## 8. وثائق مرجعية
`MULTI_TENANT_ARCHITECTURE.md` · `DATABASE_STRUCTURE.md` · `FIRESTORE_RULES.md` · `ROLES_AND_PERMISSIONS.md` · `AUDIT_LOGS.md` · `CLOUD_FUNCTIONS.md` · `ORGANIZATION_BOOTSTRAP.md` · `SYSTEM_DECISIONS.md`
