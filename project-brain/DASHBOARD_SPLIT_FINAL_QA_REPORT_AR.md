# تقرير QA النهائي لفصل لوحتي المجلس وإدارة النظام

التاريخ: 6 سبتمبر 2026
النطاق: `Council Dashboard` و`System Admin Dashboard` فقط.

## 1. الملخص النهائي

اكتملت مراجعة الكود والاختبارات والإصلاحات الحقيقية للوحتي المجلس والنظام. ثبت
الفصل بين سياق المنصة وسياق المجلس، وأُغلقت أربع مشكلات في الحماية والعزل المنطقي
والبحث. لا توجد مشكلة آلية متبقية تمنع اعتماد تنفيذ اللوحتين. بقي الاختبار البصري
على هاتف حقيقي معلقًا فقط لأن `adb devices -l` لم يعرض جهازًا متصلًا.

هذا الحكم يخص تنفيذ Dashboard؛ ولا يلغي موانع إطلاق الإنتاج المستقلة المسجلة
سابقًا، ومنها `BUG-005` الخاص بعدم تطابق Cloud Functions المنشورة.

## 2. نتيجة Council Dashboard

**PASS**

- تعرض بيانات المجلس المختار فقط.
- لا تحتوي إجراءات إنشاء مجلس أو إدارة جميع المجالس أو إعدادات منصة عامة.
- كل Providers الخاصة بالأعداد والحجوزات والإيصالات والرسوم تستقبل
  `organizationId` الحالي.
- النشاط الحديث يرشح الإشعارات وفق `item.organizationId == organizationId`.
- تغيير المجلس ينشئ مفاتيح Provider جديدة، فتظهر حالة التحميل بدل إعادة عرض
  Metrics المجلس السابق.
- سجل التدقيق المفتوح منها يبقى سجل المجلس الحالي، ولا يُعرض كتدقيق عالمي.
- زر الرجوع إلى إدارة النظام يظهر فقط عند `access.isPlatformOwner`.

## 3. نتيجة System Admin Dashboard

**PASS**

- تعرض قائمة المجالس وإحصاءات المنصة الحقيقية فقط.
- لا تراقب `organizationContextProvider` ولا تبني الإحصاءات من المجلس الحالي.
- قرار الدخول يأتي من `systemOwnerAccessProvider` المستقل عن سياق المجلس، ومصدره
  `platform_admins` عبر `PlatformAdminRepository.isActiveSuperAdmin`.
- لا تعرض نشاط مجلس على أنه نشاط عالمي، ولا تعرض بيانات أو أرقامًا وهمية.
- إذا فشل Counts لمجلس واحد، تصبح قيمة الإجراءات المعلقة غير متاحة بدل عرض مجموع
  جزئي على أنه المجموع الكامل.

## 4. الفصل بين System Context وCouncil Context

**PASS آليًا ومن خلال مراجعة المسار**

- `System Dashboard → Open Council` يستدعي
  `selectOrganizationAsSuperAdmin(organizationId)` قبل فتح `councilDashboard`.
- لوحة المجلس تقرأ المجلس الناتج من `organizationContextProvider` وتستخدم معرفه
  في جميع مصادر Dashboard.
- العودة تستخدم `goNamed('adminDashboard')`، ولوحة النظام لا تقرأ سياق المجلس
  المتبقي، لذلك لا تتحول بياناتها إلى بيانات مجلس.
- التكرار الحي A → B → A لم يُنفذ لعدم توفر هاتف وبيانات QA حية في هذه الجولة؛
  تغطي الاختبارات عقود الفصل ومفاتيح العزل.

## 5. نتائج الأدوار

| Role | Council Dashboard | System Dashboard | المسموح / الممنوع | Result |
|---|---|---|---|---|
| `system_owner` | نعم، لمجلس مختار | نعم | إدارة المنصة وفتح مجلس؛ بيانات المجلس تظل محلية | PASS |
| `owner` | نعم ضمن مجلسه | مرفوض | إدارة المجلس حسب الصلاحيات؛ لا إنشاء/إدارة كل المجالس | PASS |
| `chairman` | نعم ضمن مجلسه | مرفوض | وظائف الرئاسة المحلية؛ لا وظائف منصة | PASS |
| `adminManager` | حسب Permissions المجلس | مرفوض | الإدارة المحلية الممنوحة فقط؛ لا وظائف منصة | PASS |
| `financialManager` | الإدارة المالية والمراجعة حسب النموذج الحالي | مرفوض | الرسوم والاشتراكات والإيصالات؛ لا وظائف منصة | PASS |
| `financialReviewer` | مراجعة الإيصالات والصلاحيات الممنوحة فقط | مرفوض | لا يحصل على إدارة الإعدادات المالية أو النظام | PASS |
| `member` | وظائف العضو الآمنة فقط | مرفوض | لا وظائف إدارية حساسة ولا وظائف منصة | PASS |

## 6. Permission Security

**PASS**

- غُطي `system_owner` وجميع الأدوار المحلية في اختبار مصفوفة الصلاحيات.
- لوحة النظام، إنشاء المجلس، وإدارة المجالس لديها Screen Guard مستقل عن إخفاء
  الزر؛ لذلك يُرفض الوصول المباشر لغير `system_owner`.
- بقي تحقق الحفظ في إنشاء المجلس كطبقة دفاع إضافية.
- الشاشات الحساسة المرتبطة من لوحة المجلس تحتفظ بفحوصها الحالية:
  `canManageFinancialSettings` و`canReviewReceipts` و`canChangeRoles`
  و`canManageMembers` و`canReadAudit`.
- أُزيل فحص `fullAccess` المباشر من لوحة المجلس؛ القرار يمر عبر `AdminAccess`،
  فلا يصعّد snapshot قديم ملوث دور `member`.

## 7. Multi-Tenant Isolation

**PASS آليًا / الاختبار الحي معلق**

- Counts والحجوزات والرسوم والإيصالات مفاتيحها `organizationId` الحالي.
- رسوم العضو تستخدم أيضًا `membershipId` الحالي.
- نشاط المجلس مرشح بمعرف المجلس.
- مبدل المجالس للمستخدم العادي لا يقبل إلا المجالس الموجودة في عضوياته النشطة.
- المالك الأعلى يستخدم مسار الاختيار العالمي المخصص ثم يعود إلى مصادر مجلس
  مقيدة بالمعرف المختار.

## 8. Council Switcher

**PASS في الكود والاختبارات العقدية / التفاعل الحي معلق**

- Bottom Sheet قابل للإغلاق بلا اختيار.
- الاختيار الحالي مميز، والتبديل لا يبدأ مرة ثانية أثناء تنفيذ التبديل.
- البحث أصبح يطابق `officialNameArabic` و`officialNameEnglish` و`shortName`.
- المستخدم العادي يرى مجالس عضوياته النشطة فقط، والمالك الأعلى يستخدم المسار
  المخصص له.

## 9. العربية

**PASS آليًا**

- النصوص الجديدة تأتي من ARB.
- اتجاه التطبيق يتغير إلى RTL.
- أسماء المجالس تستخدم الاسم العربي مع fallback موثوق.
- Drawer وBottom Sheets والبطاقات تستخدم Widgets اتجاهية من Flutter.

## 10. English

**PASS آليًا ومراجعة مصدرية**

- النصوص الجديدة تأتي من ARB الإنجليزية.
- الاتجاه LTR.
- الاسم الإنجليزي يستخدم مع fallback للعربي ثم الاسم المختصر.
- العبارات الطويلة داخل البطاقات تستخدم `Expanded` أو `Wrap` و`maxLines` و
  `TextOverflow.ellipsis` حيث يلزم.

## 11. Language Switcher

**PASS**

- نجح سيناريو AR → EN → AR → EN دون Logout أو Crash.
- يتغير RTL/LTR فورًا.
- لا يغيّر المبدل `organizationContextProvider` أو Navigation.
- اختبار `LocaleNotifier` يثبت حفظ `app_locale` واستعادته بعد إنشاء notifier جديد.

## 12. RTL / LTR

**PASS آليًا ومراجعة مصدرية**

- تعتمد اللوحتان على `Localizations.localeOf` و`AlignmentDirectional` عند الحاجة.
- AppBar وDrawer وBottom Sheets تتبع اتجاه `MaterialApp`.
- لم يُضف سهم أو محاذاة ثابتة جديدة تعكس الاتجاه بصورة خاطئة.

## 13. Mobile UI

**PASS للبناء والمراجعة المصدرية / Manual QA Pending**

- الواجهتان تستخدمان `ListView` للتمرير العمودي.
- البطاقات تستخدم `LayoutBuilder` و`Wrap` و`Expanded` وقيود ارتفاع واضحة.
- الأسماء والنصوص الطويلة لها التفاف أو ellipsis.
- الإجراءات السريعة الطويلة في لوحة المجلس قابلة للتمرير أفقيًا عمدًا داخل
  مكوّن محدود الارتفاع، ولا تسبب Overflow للصفحة.
- نجح بناء APK Android Debug.

## 14. Physical Device QA

**Physical device QA: NOT EXECUTED**

نتيجة `adb devices -l` كانت قائمة فارغة. لم تُثبت النسخة ولم تُغير إعدادات جهاز
أو بيانات مستخدم. هذا لا يحول الحكم التقني إلى `NOT READY` وفق متطلبات المرحلة.

## 15. Regression

**PASS**

نجحت مجموعة Flutter الكاملة، بما يشمل اختبارات تسجيل البيانات المالية، عزل
الحجوزات، رفع/فتح الإيصالات، مراجعة الصلاحيات، العملة، التوفر، والدفع الجزئي.
لم تتغير Functions أو Rules في هذه المرحلة؛ لذلك لم تُشغل اختبارات Node ولم يحدث
Deploy.

## 16. iOS Readiness Review

**PASS للكود المشترك**

- لا يوجد `dart:io` أو `Platform.isAndroid` في ملفات Dashboard أو مبدل اللغة أو
  مزود اللغة أو منطق Metrics الجديد.
- لم تُضف حزمة جديدة أو مسار ملفات خاص بـAndroid في Shared Code.
- لم يُنفذ iOS build أو Apple configuration حسب المطلوب.

### iOS Follow-up Tasks

- تشغيل Build وQA فعلي على macOS/Xcode في مرحلة iOS منفصلة.
- مراجعة Safe Areas وأحجام الخطوط على أجهزة iPhone الفعلية.
- التحقق من Firebase/App Check وتوقيع iOS ضمن بوابة إطلاق مستقلة.

## 17. الأخطاء المكتشفة

1. نموذج إنشاء المجلس كان ظاهرًا عبر Route مباشر لغير `system_owner` رغم منع الحفظ.
2. قرار الدخول العالمي كان يمر عبر `adminAccessProvider` الذي يتابع سياق المجلس.
3. لوحة المجلس كانت تفحص `fullAccess` من `permissionsSnapshot` مباشرة، ما يعيد
   احتمال تصعيد عضو ببيانات legacy ملوثة.
4. بحث مبدل المجالس كان يبحث في الاسم المعروض بلغة واحدة فقط.

## 18. الأخطاء التي تم إصلاحها

- إضافة Guard كامل لشاشة إنشاء المجلس وتوحيد Guard إدارة المجالس على
  `systemOwnerAccessProvider`.
- فصل مزود وصول مالك النظام عن `organizationContextProvider`، مع إعادة استخدامه
  داخل `adminAccessProvider` بدل تكرار قراءة المنصة.
- تمرير full access في لوحة المجلس عبر `AdminAccess.isOrgOwner/isChairman`.
- البحث في حقول أسماء المجلس العربية والإنجليزية والمختصرة.
- توسيع اختبار اللغة ليغطي التبديل المتكرر.

## 19. الملفات المعدلة أثناء QA

- `lib/providers/app_providers.dart`
- `lib/presentation/screens/admin/admin_dashboard.dart`
- `lib/presentation/screens/admin/create_organization_screen.dart`
- `lib/presentation/screens/admin/organizations_management_screen.dart`
- `lib/presentation/screens/council/council_dashboard_screen.dart`
- `test/system_admin_dashboard_access_test.dart`
- `test/language_switcher_widget_test.dart`
- `project-brain/04_FEATURES.md`
- `project-brain/05_BUGS.md`
- `project-brain/10_CHANGELOG.md`
- `project-brain/tasks.json`
- `project-brain/PROJECT_DASHBOARD.md` — مولد من `tasks.json`.

## 20. الملفات الجديدة أثناء QA

- `test/dashboard_split_qa_test.dart`
- `project-brain/DASHBOARD_SPLIT_FINAL_QA_REPORT_AR.md`

## 21. المشاكل المتبقية

- Manual QA على هاتف حقيقي، خصوصًا التبديل A → B → A والعربية/الإنجليزية
  والأسماء الطويلة والمسافات.
- موانع إنتاج مستقلة مسجلة سابقًا، وأهمها `BUG-005`؛ لم تُعالج لأنها خارج نطاق
  Dashboard وممنوع النشر في هذه المرحلة.
- لا توجد مشكلة Dashboard آلية معروفة تؤثر على Security أو Permissions أو Tenant
  Isolation أو Navigation أو Localization أو Stability.

## 22. نتائج الأوامر النهائية

- Dart format: **PASS**.
- `flutter gen-l10n`: **PASS**.
- اختبارات QA الموجهة: **26/26 PASS**.
- `flutter analyze`: **PASS — No issues found**.
- `flutter test`: **85/85 PASS**.
- `flutter build apk --debug`: **PASS**.
- APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- `git diff --check`: **PASS**؛ تنبيهات LF/CRLF الخاصة ببيئة Windows فقط.
- Functions/Node: **N/A** — لم تتغير Cloud Functions.
- Firebase deploy / migration / Production writes: **لم تُنفذ**.
- Git commit / push: **لم يُنفذ**.

## 23. المخاطر

- غياب الاختبار البصري الفعلي يعني أن اختلافات جهاز بعينه أو تكبير الخط من
  إعدادات النظام تحتاج تحققًا يدويًا، لكنها ليست Blocker تقنيًا مثبتًا.
- صلاحيات Firestore وFunctions تبقى طبقة الأمان النهائية؛ لم تُضعف أو تتغير في
  هذه المرحلة.

## 24. الخطوة التالية

توصيل هاتف Android مصرح به وتشغيل قائمة QA اليدوية للوحتي النظام والمجلس دون
أي تعديل إنتاجي. لا تبدأ مرحلة أو Feature جديدة ضمن هذه المهمة.

## حكم الجاهزية

READY
