# مراجعة ما قبل النشر: getCouncilDashboardMetrics

التاريخ: 2026-09-07
النطاق: مراجعة أمنية وتقنية مستهدفة للدالة `getCouncilDashboardMetrics` فقط.

## الحكم النهائي

**SAFE TO DEPLOY**

الدالة آمنة للنشر المحدد لهذه الدالة فقط بعد التعديلات والاختبارات أدناه. لم يتم تنفيذ أي نشر أو كتابة Production أو migration أو commit أو push.

الأمر المقترح لاحقًا، بعد إذن صريح:

```powershell
firebase deploy --only functions:getCouncilDashboardMetrics --project alrahmat-console
```

## المكان والتصدير والمنطقة

- التعريف: `functions/financial.js` في `getCouncilDashboardMetricsHandler`.
- التصدير: `exports.getCouncilDashboardMetrics = onCall(sensitiveCallableOptions, ...)`.
- `functions/index.js` يصدّر جميع exports من `financial.js` تلقائيًا، مع استثناء `_test` فقط؛ لذلك لا يوجد export مفقود.
- المنطقة: `us-central1` عبر `sensitiveCallableOptions`، وهي المنطقة الموحدة المستخدمة في Functions الحالية.
- العميل يستعمل `FirebaseFunctions.instance` بلا region مخصص، وهي `us-central1` افتراضيًا؛ يتطابق ذلك مع الدالة.
- تم تحميل الدالة بنجاح في Firebase Emulator تحت `us-central1-getCouncilDashboardMetrics`.

## Authentication

- تستدعي الدالة `requireAuth(request)` أولًا.
- الطلب بلا `request.auth` يرد بـ `unauthenticated`.
- لا توجد مسارات مجهولة أو عامة للدالة.

## organizationId

- الحقل مطلوب ويُقرأ فقط من payload كائن صالح.
- `null` أو payload غير كائن أو حقل مفقود أو نص فارغ أو `/` أو `.` أو `..` يرد بـ `invalid-argument`.
- تم التحقق من وجود مستند المجلس؛ المجلس غير الموجود يرد بـ `not-found` حتى لمالك النظام، بدل إرجاع أصفار مضللة.
- لا تكفي قيمة `organizationId` من العميل وحدها: الوصول يراجع عضوية المستخدم داخل المجلس نفسه أو ملكية نظام موثقة.

## Authorization وTenant Isolation

يسمح فقط لـ:

- `system_owner` النشط على مستوى `platform_admins`، أو توافق `superAdmin` القديم مع `fullAccess: true`.
- العضو النشط في المجلس نفسه ذي أحد الأدوار: `owner`، `council_owner`، `chairman`، `adminManager`، `financialManager`، `financialReviewer`، أو صلاحية snapshot إدارية/مالية/تقارير معتمدة.

لا يسمح للعضو العادي، ولا يتحول `member` إلى إداري إذا احتوى snapshot ملوثًا بقيمة `fullAccess`.

عضوية أو دور في مجلس A لا يجيز تمرير `organizationId` لمجلس B: lookup العضوية يقع تحت `organizations/{organizationId}/memberships` المطلوب نفسه، وقد اختُبر الرفض صراحة.

## Response وعدم تسريب البيانات

الاستجابة الوحيدة هي:

```json
{
  "memberCount": 0,
  "upcomingBookingCount": 0
}
```

لا تعيد أسماء أو userIds أو membershipIds أو أرقام اتصال أو تفاصيل/تواريخ الحجوزات أو رسومًا أو مستندات Firestore. استعلام الحجوزات يستخدم `select("status")` فقط، ثم يعيد عدادًا عدديًا.

## منطق العدادات

### memberCount

- يستخدم Firestore aggregation `count()` على عضويات `status == "active"` فقط.
- لا يشمل العضويات المعلقة أو الموقوفة أو طلبات الانضمام المعلقة.
- لا يوجد double counting لأن كل مستند عضوية فعّال يُعد مرة واحدة.

### upcomingBookingCount

- يحسب الحجوزات ذات الحالة `approved` أو `confirmed` فقط.
- لا يدخل `pending` أو `cancelled` أو `rejected` أو `cancellationRequested`.
- يشمل حجوزات اليوم وحجوزات المستقبل، وهو نفس تعريف `countUpcomingBookings` المستخدم في Dashboard.
- لا يتعامل مع رسوم أو ملكية الحجز أو تفاصيله.

## المنطقة الزمنية

- تُخزَّن تواريخ الحجوزات كبداية اليوم في عُمان (UTC+4).
- عُثر أثناء المراجعة على خلل: المقارنة مع `Timestamp.now()` كانت تستبعد حجز اليوم بعد منتصف الليل.
- تم إصلاحه بدالة `muscatStartOfDayTimestamp` التي تبدأ من 00:00 بتوقيت عُمان، ولذلك يبقى حجز اليوم ظاهرًا طوال اليوم.
- عُمان ثابتة على UTC+4، فلا يوجد تبديل صيفي/شتوي مؤثر في هذا الحساب.

## App Check

- الدالة تستخدم `sensitiveCallableOptions` نفسها الخاصة بالـ callables الحساسة.
- `enforceAppCheck` مفعّل في Production.
- تعطيله يحدث فقط عندما تكون `FUNCTIONS_EMULATOR === "true"`، وهو سلوك محلي مقصود للاختبارات.
- لم يُغيَّر App Check في هذه المرحلة.

## الأداء

- عداد الأعضاء efficient: aggregation count ولا يجلب كل العضويات.
- عداد الحجوزات يقرأ وثائق الحجوزات المستقبلية على صفحات من 250 مع projection لحقل `status` فقط، ويعد حالتي `approved` و`confirmed` في الذاكرة.
- لا يوجد N+1 query.
- المخاطرة المحدودة: تكلفة عداد الحجوزات خطية بعدد الحجوزات المستقبلية للمجلس. هذا مناسب للوضع الحالي، لكنه يستحق مراقبة عند نمو المجلس إلى آلاف الحجوزات مستقبلًا.
- تحويله إلى aggregations حسب الحالة يحتاج استعلامات مركبة/فهرسًا مناسبًا؛ لم يُضف فهرس أو تغيير schema ضمن هذه المراجعة.

## Error Handling وClient Contract

- أخطاء الإدخال والصلاحيات تستخدم `HttpsError` المناسبة: `unauthenticated` و`invalid-argument` و`not-found` و`permission-denied`.
- أخطاء Firestore غير المتوقعة تتحول من callable إلى `internal` ولا ترسل stack trace للعميل.
- لا تسجل الدالة بيانات عضو أو حجز حساسة.
- Flutter يستدعي `getCouncilDashboardMetrics` ويتحقق من الحقلين كأعداد صحيحة غير سالبة.
- عند `function-not-found` أو `permission-denied` أو `unavailable` يعيد repository الاستثناء إلى `FutureProvider`، وتعرض لوحة المجلس «غير متاح» بدل crash أو بيانات مزيفة.

## Runtime وDependencies

- runtime المستهدف في `functions/package.json`: Node 20.
- الحزم المثبتة: `firebase-functions` 5.1.1 و`firebase-admin` 12.7.0.
- `firebase-functions` 5.1.1 يعلن دعم Node `>=14.10.0`؛ لذلك Node 20 المستهدف متوافق.
- ظهر تحذير Emulator لأن جهاز التطوير شغّل Node 24 محليًا. هذا لا يغير runtime المنشور؛ Firebase سيستخدم Node 20 المحدد في `engines`.
- ظهر أيضًا تحذير توصية بالترقية إلى `firebase-functions` أحدث. لم تتم الترقية لأنها خارج النطاق وقد تتضمن breaking changes؛ ليست مانعًا لهذا النشر المحدد بعد نجاح التحميل والاختبارات.

## تعديلات تمت أثناء المراجعة

1. معالجة payload غير الكائن لترد `invalid-argument` بدل خطأ داخلي محتمل.
2. التحقق من وجود المجلس وإرجاع `not-found` بصورة آمنة.
3. تصحيح بداية الفترة القادمة إلى بداية يوم عُمان لتطابق منطق Dashboard.
4. توسيع اختبار Emulator للدالة ليغطي المصادقة، كل الأدوار المطلوبة، العزل، zero data، الإدخالات غير الصالحة، المجلس غير الموجود، حجوزات اليوم، والحالات المستبعدة.

## نتائج الاختبارات

- `node --check financial.js`: PASS.
- `node --check financial_emulator.test.js`: PASS.
- `npm test`: PASS — 26/26.
- Firebase Emulator (Firestore + Storage + Functions): PASS — 43/43.
- سيناريو الدالة المستهدف داخل Emulator: PASS، ويشمل:
  - anonymous → `unauthenticated`
  - ordinary member → `permission-denied`
  - financialManager في A → allowed
  - financialReviewer في A → allowed
  - manager A إلى B → `permission-denied`
  - system_owner → allowed
  - active membership count الصحيح فقط
  - حجوزات اليوم وfuture approved/confirmed فقط
  - cancelled/rejected/pending لا تدخل
  - zero data → `0`, وليس `null`
  - invalid/null/malformed organizationId → `invalid-argument`
  - مجلس غير موجود → `not-found`
- `git diff --check`: PASS. تحذيرات CRLF محلية فقط، بلا أخطاء whitespace.

## المخاطر المتبقية

- لا توجد مخاطر أمنية مانعة للنشر.
- راقب تكلفة/زمن عداد الحجوزات إذا نما عدد الحجوزات المستقبلية للمجلس إلى نطاق كبير جدًا.
- تنفيذ نشر خاص بالدالة فقط يتطلب إذنًا جديدًا، ولم يتم تنفيذه هنا.
