# DEVELOPER_GUIDE — دليل المطوّر

> مرجع المطوّر للعمل على المنصّة وفق الدستور: Clean Architecture · SOLID · Multi-Tenant · Documentation-First. اقرأ أولاً `PROJECT_ARCHITECTURE.md` و`SYSTEM_DECISIONS.md`.

## 1. الفلسفة
- كل قرار مبني على: Enterprise · Multi-Tenant · Clean Architecture · SOLID · Security-First · Scalability-First · Maintainability · Extensibility · Auditability · Performance · Documentation-First.
- `docs/` هو **المرجع الرسمي الوحيد**. أي تعديل في الكود يُحدَّث في الوثائق فوراً.

## 2. بنية المشروع
```
lib/
├── core/         # auth (AdminAccess), context (OrganizationContext), theme
├── data/         # models · repositories · services  (طبقة الوصول للبيانات)
├── providers/    # مزوّدات Riverpod العامة
├── features/     # وحدات مستقلة feature-first (audit, member_management, membership_request)
├── presentation/ # الشاشات (auth/member/admin/organization)
└── router/       # GoRouter
functions/        # Cloud Functions (index.js + audit.js)
docs/             # الوثائق الرسمية
```
**تدفّق الطبقات:** Screen → Provider (Riverpod) → Repository → Firestore/Storage. لا تتخطَّ الطبقات (لا Firestore مباشرة في الشاشة).

## 3. مبادئ SOLID عملياً هنا
- **S:** كل Repository يخدم مجموعة واحدة؛ كل Service مسؤولية واحدة.
- **O/L:** أضف وحدات/أدوار جديدة دون تعديل القائم (feature-first + أدوار بيانات).
- **I:** واجهات صغيرة (providers محدّدة الغرض).
- **D:** الشاشات تعتمد على providers مجرّدة لا على تنفيذ Firestore.

## 4. قواعد Multi-Tenant الإلزامية للكود
1. ابدأ دائماً من `organizationId` المختار عبر `organizationContextProvider` — **لا تفترض مجلساً**.
2. أي مجموعة جديدة تحت `organizations/{organizationId}/...` ما لم تكن خاصة بالمنصّة (superAdmin).
3. أي استعلام `collectionGroup` يُقيَّد بـ `where('userId', isEqualTo: currentUser)`.
4. لا `Hardcoded Organization` (الاستثناء الوحيد الانتقالي: DEC-007).
5. مرّر `actorUserId` لأي عملية حسّاسة (لتغذية سجل التدقيق الخادمي).

## 5. كيف تضيف ميزة جديدة (Workflow إلزامي)
1. **صمّم** ضمن `organizationId`؛ راجع إن كانت تؤثّر على المعمارية → قرار في `SYSTEM_DECISIONS.md`.
2. **الكود:** feature-first (`lib/features/<name>/{data,providers,presentation}`) + repository org-scoped.
3. **القواعد:** أضف قاعدة معلّمة `{organizationId}`، deny-by-default، تتحقق من الصلاحية في نفس المجلس. حدّث `FIRESTORE_RULES.md` + `DATABASE_STRUCTURE.md`.
4. **Audit:** إن كانت حسّاسة، أضف مشغّل `onDocumentWritten` في `functions/audit.js` يكتب في `organizations/{orgId}/audit_logs`. حدّث `AUDIT_LOGS.md` + `CLOUD_FUNCTIONS.md`.
5. **الصلاحيات:** اربطها بـ `AdminAccess`/permission؛ حدّث `ROLES_AND_PERMISSIONS.md`.
6. **الواجهة:** اعرض الأزرار بحسب الصلاحية (لا تعتمد على الإخفاء وحده).
7. **التوثيق التلقائي:** حدّث `USER_MANUAL`/`ADMIN_MANUAL`/`DEVELOPER_GUIDE` + `ROADMAP.md` + `CHANGELOG.md`.
8. **التحقق:** `flutter analyze` + `node --check functions/*.js` + مراجعة Rules/Functions/Security/Multi-Tenant.

## 6. تعريف "الميزة المكتملة" (Definition of Done)
✅ الكود · ✅ الوثائق · ✅ ROADMAP · ✅ CHANGELOG · ✅ SYSTEM_DECISIONS (إن لزم) · ✅ مراجعة Firestore Rules · ✅ مراجعة Cloud Functions · ✅ مراجعة Security · ✅ مراجعة Multi-Tenant · ✅ `flutter analyze`.

## 7. المعايير البرمجية
- Dart: اتبع `analysis_options.yaml`؛ `flutter analyze` يجب أن يكون **نظيفاً** قبل أي دمج.
- تسمية واضحة، دوال صغيرة، بلا منطق في الشاشة.
- النصوص العربية UTF-8؛ خطّط للتوطين (ar/en) مستقبلاً.
- لا تكسر الدخول الحالي؛ حافظ على التوافق الخلفي (DEC-006).

## 8. الاختبار
- `flutter test` للوحدات.
- Firebase Emulator Suite للقواعد/الدوال: `firebase emulators:start --only firestore,functions`.
- المحاولات السلبية (تصعيد صلاحيات، عبور مجالس) تُختبر على المحاكي/Staging — **لا الإنتاج**.

## 9. Git والإصدارات
- فرع لكل ميزة؛ رسالة commit تصف "لماذا".
- كل دمج يوثّق في `CHANGELOG.md`.

## 10. ممنوعات
- Hardcoded Organization · كسر Multi-Tenant · كتابة audit من العميل · النشر على الإنتاج.
