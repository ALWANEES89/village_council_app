# تقرير تنفيذ المرحلة الأولى — لوحة المجلس

تاريخ التنفيذ: 2026-09-06

## النطاق

تم تنفيذ لوحة مجلس محدد بتصميم Mobile First دون البدء في لوحة إدارة النظام، ودون إضافة أي وظيفة عالمية مثل إنشاء المجالس أو إدارة جميع المجالس داخل لوحة المجلس.

## Localization قبل التعديل

- لم يكن المشروع يستخدم Flutter Localization القياسي.
- كان `main.dart` يفرض اتجاه RTL على التطبيق كاملًا.
- لم يوجد Locale Provider أو Language Switcher عام.
- كانت `shared_preferences` موجودة مسبقًا ولكنها لم تكن مستخدمة لحفظ لغة الواجهة.

## Localization بعد التعديل

- تمت إضافة `flutter_localizations` وآلية `gen-l10n` القياسية.
- تمت إضافة ملفات ARB للعربية والإنجليزية وكل النصوص الجديدة في لوحة المجلس.
- أصبح `MaterialApp` يحدد الاتجاه تلقائيًا: العربية RTL والإنجليزية LTR.
- تستخدم أسماء المجالس `officialNameArabic` أو `officialNameEnglish` حسب اللغة، مع fallback آمن دون ترجمة اسم أدخله المستخدم آليًا.
- تمت مواءمة `intl` إلى `0.20.2`، وهو الإصدار الذي يفرضه Flutter SDK مع `flutter_localizations`.

## Language Switcher

- زر اللغة ظاهر في AppBar وفي Drawer.
- يفتح Bottom Sheet يعرض العربية وEnglish مع علامة على اللغة الحالية.
- تتغير اللغة والاتجاه فورًا دون تسجيل خروج.
- تحفظ اللغة محليًا بالمفتاح `app_locale` داخل SharedPreferences.
- اللغة الافتراضية عند عدم وجود تفضيل سابق هي العربية.

## لوحة المجلس

- Header حديث يعرض اسم المجلس وشعاره عند توفره واسم المستخدم ودوره ورقم العضو.
- أربع بطاقات إحصائية من البيانات الفعلية:
  - الأعضاء النشطون.
  - الحجوزات القادمة المعتمدة.
  - الإيصالات بانتظار المراجعة.
  - الاشتراكات ذات الرصيد المستحق.
- الأقسام الرئيسية:
  - العمل اليومي.
  - المالية.
  - إدارة المجلس.
- إجراءات سريعة مبنية على الصلاحيات.
- تنبيهات حقيقية للحجوزات المعلقة والإيصالات المعلقة والاشتراكات المتأخرة.
- آخر الأنشطة مأخوذة من إشعارات المستخدم ومفلترة بـ`organizationId` للمجلس الحالي فقط.
- حالات Loading وEmpty وError موجودة دون أرقام وهمية.
- Drawer مخصص للموبايل ولا يوجد Sidebar أو NavigationRail أو تنفيذ Web/Desktop.

## Council Switcher

- يظهر زر تغيير المجلس فقط عندما يكون للمستخدم أكثر من مجلس متاح.
- العضو العادي يرى العضويات النشطة الخاصة به فقط.
- مالك النظام يرى المجالس المسموح له إدارتها وفق آلية المنصة الحالية.
- القائمة Bottom Sheet وتحتوي على بحث باسم المجلس.
- العضو يستخدم `selectOrganization` مع `organizationId + userId + membershipId`.
- مالك النظام يستخدم `selectOrganizationAsSuperAdmin`.
- جميع Providers في اللوحة يعاد ربطها تلقائيًا بمعرف المجلس الجديد، ولا يتم الاحتفاظ بإحصاءات المجلس السابق.

## الصلاحيات وأمان المسارات

- استُخدمت `AdminAccess` و`permissionsSnapshot` الحاليان، دون إنشاء أدوار جديدة.
- تظهر وظائف الأعضاء والمالية والمراجعة والصلاحيات والسجل حسب القدرات الفعلية.
- تم الحفاظ صراحة على `canManageFinancialSettings` كمصدر قرار الإدارة المالية.
- تمت إضافة تحقق داخل شاشة إدارة الصلاحيات نفسها، وليس إخفاء الزر فقط.
- شاشات إدارة الأعضاء والإيصالات والحجوزات والطلبات والتدقيق كانت تحتوي تحققًا داخليًا مسبقًا.
- شاشة سجل النشاط تبدأ بالمجلس الحالي عند فتحها من لوحة المجلس.

## Routes

- لم تتم إضافة أو تغيير أسماء Routes.
- أعيد استخدام `councilDashboard` والمسارات الحالية للخدمات.
- لم يتم تعديل `adminDashboard` ولم يبدأ تنفيذ System Admin Dashboard.

## الملفات المعدلة

- `pubspec.yaml`
- `pubspec.lock`
- `lib/main.dart`
- `lib/providers/app_providers.dart`
- `lib/presentation/screens/council/council_dashboard_screen.dart`
- `lib/presentation/screens/admin/roles_management_screen.dart`
- `lib/features/audit/presentation/audit_logs_screen.dart`

## الملفات الجديدة

- `l10n.yaml`
- `lib/l10n/app_ar.arb`
- `lib/l10n/app_en.arb`
- `lib/l10n/generated/app_localizations.dart`
- `lib/l10n/generated/app_localizations_ar.dart`
- `lib/l10n/generated/app_localizations_en.dart`
- `lib/providers/locale_provider.dart`
- `lib/presentation/widgets/language_switcher.dart`
- `lib/domain/dashboard/council_dashboard_metrics.dart`
- `test/locale_provider_test.dart`
- `test/language_switcher_widget_test.dart`
- `test/council_dashboard_metrics_test.dart`
- `project-brain/COUNCIL_DASHBOARD_IMPLEMENTATION_REPORT_AR.md`

## نتائج التحقق

- Dart format: PASS.
- `flutter analyze`: PASS — No issues found.
- الاختبارات المستهدفة: PASS.
- `flutter test`: PASS — 73 اختبارًا، 0 فشل.
- `git diff --check`: PASS؛ ظهرت تحذيرات CRLF المحلية فقط دون أخطاء whitespace.
- Android debug build: PASS.
- APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- الهاتف الفعلي: N/A — لم يظهر أي جهاز في `adb devices` وقت الاختبار، لذلك لم يتم تثبيت النسخة أو إجراء QA بصري على هاتف حقيقي.

## المشاكل أو القيود المتبقية

- شاشة التقارير المالية وإعدادات المجلس الكاملة ليستا منفذتين أصلًا؛ تظهران فقط لمن يملك الصلاحية برسالة أن الخدمة قيد التجهيز.
- لم توجد شاشة مستقلة للحساب البنكي وطرق الدفع، ولذلك لم تتم إضافة رابط وهمي لها.
- الشاشات القديمة التي تفتح من اللوحة ما زال كثير منها عربيًا فقط؛ الترجمة الكاملة لها خارج نطاق إعادة تصميم لوحة المجلس الحالية.
- يلزم اختبار بصري على هاتف حقيقي عند إعادة توصيله، خصوصًا أطوال النصوص الإنجليزية وفتح Drawer وCouncil Switcher.

## iOS المؤجل

لم يتم تعديل Apple Signing أو APNs أو Apple Pay أو App Check الخاص بـiOS أو entitlements أو Info.plist. الكود المشترك المضاف يعتمد على Flutter APIs وحزم تدعم Android وiOS.

## تأكيد العمليات المحظورة

لم يتم تنفيذ commit أو push أو deploy أو migration، ولم يتم تعديل بيانات Production أو App Check أو Firestore schema.
