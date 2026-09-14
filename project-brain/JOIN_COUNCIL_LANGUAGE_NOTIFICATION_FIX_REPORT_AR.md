# تقرير إصلاح الانضمام واللغة وتنبيهات المجلس

**التاريخ:** 2026-09-14
**النطاق:** الانضمام إلى المجالس، موضع تغيير اللغة، وإرسال تنبيه المجلس فقط.

## 1. لماذا لم تعد شاشة الانضمام قابلة للوصول؟

كان مسار الشاشة موجودًا، لكن بوابة البداية لم تفرّق بصورة مكتملة بين مستخدم لديه
عضوية نشطة ومستخدم بلا عضوية؛ فكان الثاني يصل إلى تجربة رئيسية غير مناسبة. كما
أن استعلام collection-group لطلبات المستخدم لم تكن له قاعدة `list` مطابقة.

## 2. تجربة المستخدم الجديد الآن

بعد تسجيل الدخول، ينتظر التطبيق نتيجة العضويات. إذا كانت النتيجة ناجحة ولا توجد
عضوية نشطة، يفتح شاشة **Find and Join a Council / ابحث عن مجلس وانضم إليه**.
تعرض بيانات عامة آمنة فقط، وتدعم البحث بالاسم العربي والإنجليزي والاسم المختصر.

## 3. انضمام المستخدم الحالي إلى مجلس إضافي

المستخدم ذو العضوية يدخل الرئيسية طبيعيًا، ويصل إلى الشاشة الموحدة من:
`حسابي ← المجالس والعضويات ← الانضمام إلى مجلس آخر`.

## 4. موضع LanguageSwitcher الآن

يوجد فقط في شاشة تسجيل الدخول، وداخل قسم الحساب في شاشة حسابي.

## 5. تأكيد الإزالة

أزيل من Main Home وCouncil Dashboard وSystem Admin Dashboard ومن رؤوسها وأدراجها.
اختبار عقد المصدر واختبار الواجهات الموجه نجحا.

## 6. السبب الجذري لخطأ Send Notification

وجد تعارض حقيقي في قرار الصلاحية: واجهة Flutter تعتبر
`announcements.manage` مخولة للإرسال، بينما دالة الخادم كانت تقبل
`notifications.send` وبعض أدوار الملكية فقط؛ لذلك يمكن أن يظهر الزر ثم يرفض
الخادم العملية. أثناء QA المحلي ظهرت أيضًا مشكلتان بيئيتان منفصلتان: Android 15
منع cleartext إلى `10.0.2.2` في Debug، ومحاكي الدوال احتاج مهلة اكتشاف أطول.
هذه ليست تغييرات حماية Production.

## 7. الإصلاح

- وحّدت الدالة الخادمية قبول `announcements.manage` مع السياسة التي تستخدمها الواجهة.
- أضيف تحقق لحظة الإرسال من UID والمجلس الحالي والصلاحية، ومنع النقر المزدوج.
- أضيفت رسائل دقيقة لحالات auth/permission/network/App Check/unavailable.
- سمح Debug فقط باتصال cleartext إلى عناوين المحاكي المحلية المحددة.

## 8. صلاحية الإرسال

الخادم يقبل العضوية النشطة المخولة عبر `notifications.send` أو
`announcements.manage`، إضافة إلى أدوار الملكية/الرئاسة المتوافقة الموجودة. العضو
العادي غير مخول. القرار النهائي خادمي ولا يعتمد على إظهار الزر.

## 9. عزل الإشعارات بين المجالس

الدالة تتحقق من العضوية داخل `organizations/{organizationId}` ثم تنشئ البث
وإشعارات المستلمين تحت المجلس نفسه. اختبار Emulator أثبت نجاح مخول مجلس A، ورفض
عضو عادي، ورفض محاولة مخول A الإرسال إلى B، وعدم إنشاء إشعار في B.

## 10. نتيجة Android Emulator

نجح بناء وتثبيت وتشغيل Debug على `Pixel_5_API_35` وربطه حصريًا بمشروع Firebase
الوهمي `demo-financial-prestaging`. لم تُستخدم بيانات Production.

## 11. نتيجة Join Council على Emulator

نجح: الحساب بلا عضوية فتح شاشة البحث، ظهرت نتيجة المجلس، أُرسل الطلب، وتحول الزر
فورًا إلى **بانتظار الموافقة / Pending**، وبقيت الحالة بعد إعادة تشغيل التطبيق.
كما أضيف مدخل حسابي للشاشة حتى لا يُحاصر المستخدم الجديد.

## 12. نتيجة العربية والإنجليزية

نجح التحويل من العربية RTL إلى الإنجليزية LTR داخل حسابي، وتغيرت الواجهة مباشرة.
بعد إغلاق التطبيق وفتحه بقيت الإنجليزية محفوظة عبر `app_locale`. ظهر المحول في
Login وحسابي فقط. بعض بيانات QA نفسها عربية، وهذا محتوى بيانات وليس نص UI ثابتًا.

## 13. الملفات المعدلة في هذه المهمة

- `android/app/src/debug/AndroidManifest.xml`
- `firestore.rules`
- `functions/council_management.js`
- `functions/council_management.test.js`
- `functions/financial_emulator.test.js`
- `functions/scripts/seed-financial-device-qa.js`
- `lib/core/errors/firebase_function_error_message.dart`
- `lib/data/repositories/council_management_repository.dart`
- `lib/features/membership_request/data/membership_request_repository.dart`
- `lib/features/membership_request/presentation/join_request_screen.dart`
- `lib/features/membership_request/providers/membership_request_providers.dart`
- `lib/l10n/app_ar.arb`, `lib/l10n/app_en.arb`
- `lib/presentation/screens/auth/login_screen.dart`
- `lib/presentation/screens/admin/admin_dashboard.dart`
- `lib/presentation/screens/council/council_dashboard_screen.dart`
- `lib/presentation/screens/council/send_council_notification_screen.dart`
- `lib/presentation/screens/member/member_home_screen.dart`
- `lib/presentation/screens/member/my_account_screen.dart`
- `lib/providers/app_providers.dart`
- `test/main_home_account_polish_test.dart`

## 14. الملفات الجديدة

- `android/app/src/debug/res/xml/debug_network_security_config.xml`
- `lib/domain/membership/join_council_routing.dart`
- `test/join_council_language_notification_fix_test.dart`
- هذا التقرير.

## 15. Functions وRules المعدلة

- Function: تعديل محلي في `sendCouncilNotification`، مع اختبارات capability والعزل.
- Rules: قاعدة collection-group ضيقة تسمح للمستخدم المصادق بعمل list لطلبات تحمل
  `resource.data.userId == request.auth.uid` فقط. الكتابة ومراجعة الإدارة بقيتا
  تحت قواعد المجلس الأصلية.

## 16. ما يحتاج Deploy لاحقًا

حتى يعمل إصلاح الإرسال وقراءة حالات الطلبات في Production يلزم لاحقًا، وبعد
موافقة صريحة ومراجعة خطة النشر: نشر `sendCouncilNotification` وFirestore Rules.
لم يحدث deploy أو migration أو كتابة Production في هذه المهمة.

## 17. flutter analyze

**PASS** — لا توجد ملاحظات، بعد آخر مجموعة تغييرات.

## 18. flutter test

**PASS** — الحزمة الكاملة: **102/102**. الاختبارات الموجهة اللاحقة: **11/11**.

## 19. npm test واختبارات Emulator

- `npm.cmd test`: **PASS — 28/28**.
- الحزمة الكاملة السابقة لـFirebase Emulator: **PASS — 46/46**.
- بعد تعديل قاعدة طلبات الانضمام: اختبارا الطلبات الذاتية وعزل إشعار المجلس:
  **PASS — 2/2**.
- إعادة الحزمة الكاملة على projectId مختلف أعطت فشلين بسبب توقع اسم bucket الثابت
  `demo-financial-prestaging`، وليس بسبب منطق التغيير؛ لم تُحتسب كنجاح نهائي جديد.

## 20. نتيجة QA النهائية

نجحت فعليًا على Android Emulator جميع السيناريوهات السابقة، ثم اكتمل Delta QA
للإرسال من الواجهة: رجعت الواجهة إلى لوحة المجلس، وظهر الإشعار في Recent Activity
وشاشة إشعارات المستلم. تحقق Firestore من Broadcast واحد فقط، و5 مستلمين نشطين،
وجميعها تحمل `organizationId=qa_financial_council`. النقر غيّر الحالة إلى `read`.

## المخاطر والخطوة التالية

أضيف معرف idempotency ثابت داخل نموذج الإرسال لمنع التكرار عند انقطاع الرد بعد
نجاح الكتابة. لا يوجد مانع متبقٍ ضمن نطاق التقرير الأصلي، ولذلك الحالة:

**READY**
