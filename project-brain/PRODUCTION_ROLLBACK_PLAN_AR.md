# خطة التراجع الإنتاجي — مسودة غير منفذة

**الحالة:** خطة مستقبلية فقط؛ لا يوجد نشر أو تغيير production في جولة إعدادها.
**المبدأ:** التراجع مكوّن بمكوّن، مع وقف الضرر أولًا وحفظ الأدلة، ودون حذف بيانات أو وظائف عشوائيًا.

## تحديث تغطية التراجع — 23 يوليو 2026

لم تُنفذ هذه الخطة. قبل أول نشر يجب حفظ SHA وحزمة القواعد والدوال والتطبيق
والإعدادات، ثم اختبار السيناريوهات الآتية على staging معزول:

- **الإشعارات:** أبقِ client create مغلقًا حتى أثناء incident. أوقف writer/trigger
  المتأثر أو أعد نشر نسخته السابقة، ولا تفتح `notifications_queue`. احتفظ بمعرفات
  الإشعار وحالة التسليم دون token أو payload حساس، ثم أعد الإرسال فقط بمفتاح
  idempotency وبعد تحديد المستلمين.
- **العضوية والمالك:** لا تحذف `member_access` جماعيًا. عند فشل projection أوقف
  تغيير الأدوار، أصلح الإسقاط من العضويات الأصلية خادميًا، وطابق المالك الأساسي
  قبل استئناف الإدارة. نقل الملكية لا يُعكس بتعديل عميل؛ يستعمل callable ذريًا
  موثقًا أو استعادة مستهدفة من manifest.
- **الحجوزات والقفل:** أوقف create/review callables المتأثرة، ولا تحذف
  `booking_slots` حسب التاريخ فقط. القفل يُحذف فقط إذا كان `bookingId` يطابق
  الحجز الملغى. استعادة حجز legacy أو تراجع migration يتطلب manifest يربط كل
  slot بحجزه، ثم فحص التعارض قبل فتح التوفر.
- **App Check:** عند false-positive واسع، أوقف enforcement للدالة المتأثرة فقط
  من Console وفق موافقة incident، مع بقاء Auth/authorization/Rules. لا تدخل
  bypass دائمًا ولا تحذف registrations. أصلح Release ثم أعد metrics قبل الفرض.
- **المجدولات:** أول إجراء هو إعادة `FINANCIAL_SCHEDULES_ENABLED=false`، مع إبقاء
  المفاتيح الفردية false وdry-run true. احفظ `runId` والcounts، ثم استرجع فقط
  الوثائق المدرجة في manifest؛ لا تعكس الرسوم أو الحالات باستعلام واسع.
- **Bootstrap:** callable idempotent، لذلك لا تحذف مجلسًا أُنشئ جزئيًا. أوقف
  bootstrap/repair، افحص `organization_bootstrap_requests`، ثم أكمل الوثائق
  الناقصة أو استعدها بصورة مستهدفة بعد معرفة requestId.
- **Migration:** `rollback-financial-v1.js` dry-run افتراضيًا ويقبل manifest
  محليًا مستبعدًا. يمنع apply إذا غاب manifest أو تغيرت الوثيقة بعد migration؛
  الاسترجاع من export إلى مشروع recovery يسبق أي كتابة مستهدفة.
- **Android:** أوقف staged rollout. لا يمكن downgrade إلى versionCode أقل؛ ابنِ
  hotfix من المصدر السابق بنفس signing identity وبـversionCode أعلى. فقدان مفتاح
  upload يعالج عبر إجراء Play Console الرسمي ولا يُعوّض بمفتاح debug.

## 1. شروط صلاحية الخطة

قبل أي نشر يجب حفظ:

- SHA/tag للإصدار السابق والجديد.
- نسخ rules/indexes/functions السابقة والجديدة.
- Firestore export ناجح ومختبر الاسترجاع.
- سياسة Storage soft delete/versioning ونسخة objects إن لزم.
- Auth export مشفر.
- manifest للـmigration بكل document path ونوع العملية والقيمة السابقة/الجديدة أو مرجع النسخة الاحتياطية.
- أسماء Cloud Scheduler jobs وCloud Run revisions وFunctions revisions.
- versionCode/AAB certificate وPlay rollout ID.

إذا غاب manifest الترحيل أو restore test، يمنع apply ولا يُعوّض ذلك بهذه الخطة.

## 2. محفزات التراجع العامة

- تسرب بين مجلسين أو وصول غير مخول إلى بيانات مالية/إيصال.
- تغيير primary owner أو role/permissions دون إذن.
- دفع زائد/مكرر، اعتماد مزدوج، أو فرق إجماليات.
- تضاعف رسوم الاشتراك/الحجز أو تنفيذ scheduled job بأرقام غير متوقعة.
- ارتفاع 5xx/permission-denied/App Check rejection بما يتجاوز الحد المعتمد.
- إشعارات تصل لمستخدم خاطئ أو ارتفاع invocation/cost بصورة شاذة.
- crash/ANR أو فشل login واسع في إصدار Android.

## 3. الاستجابة الفورية

1. أوقف التقدم في runbook وأعلن incident owner والوقت.
2. احفظ logs وoperation IDs وrelease SHAs دون PII.
3. أوقف staged rollout للتطبيق.
4. أوقف/عطّل المجدول المتسبب إن كان الضرر مستمرًا، ثم لا تشغله يدويًا.
5. لا تخفف Rules إلى `allow read, write: if true` ولا تعطل Auth كحل سريع.
6. اختر تراجع المكوّن الأدنى الذي يوقف الضرر.

## 4. تراجع Firestore Rules

- أعد نشر ملف rules السابق المحفوظ من tag المعروف، بمشروع صريح.
- لا تعتمد على Console history وحدها؛ طابق hash الملف قبل النشر.

مثال مستقبلي:

```powershell
git show '<PREVIOUS_RELEASE_TAG>:firestore.rules' > '<TEMP_REVIEW_PATH>\firestore.rules'
# بعد مراجعة الفرق ووضع الملف السابق في حزمة rollback معتمدة:
firebase deploy --project alrahmat-console --only firestore:rules
```

بعد التراجع:

- اختبر deny/allow matrix.
- تحقق أن old app وnew app لا يملكان كتابة مالية مباشرة.
- إذا كان الخلل تسربًا، أبق التطبيق/الميزة موقوفة حتى تحليل الأثر.

## 5. تراجع Storage Rules

- أعد نشر `storage.rules` السابق المعروف.
- تحقق owner/reviewer/cross-tenant فورًا.
- إذا حُذفت objects، استخدم soft delete أو generation/version المحدد لاستعادتها؛ لا تستبدل كل bucket بلا inventory.
- لا تجعل الإيصالات عامة أثناء التراجع.

## 6. تراجع Firestore Indexes

- وجود index إضافي لا يغير البيانات؛ اتركه مؤقتًا بدل حذفه أثناء incident.
- إذا كان استعلام التطبيق الجديد يعتمد index وفشل، أوقف rollout أو أعد نشر نسخة app/functions السابقة.
- حذف index يتم في نافذة cleanup لاحقة فقط بعد إثبات عدم وجود query تعتمد عليه.

## 7. تراجع Cloud Functions

الطريقة الأساسية: إعادة نشر source الإصدار السابق، بأسماء functions المتأثرة فقط، لا كل المشروع دفعة واحدة.

```powershell
firebase deploy `
  --project alrahmat-console `
  --only functions:<AFFECTED_FUNCTION_1>,functions:<AFFECTED_FUNCTION_2>
```

- استخدم tag سابق وlockfile مطابقًا وNode 20.
- لا تحذف function جديدة فورًا إذا كان old app قد يستدعيها؛ يمكن إبقاؤها مع تعطيل المسار عبر rules/feature gate مصمم مسبقًا.
- تحقق من region `us-central1` كي لا تنشئ نسخة موازية في region أخرى.
- راقب invocation والـ5xx بعد إعادة النشر.

### FCM والإشعارات

- أغلق client create في Rules إذا كان سبب الحادث spam.
- أعد نشر trigger السابق أو أوقف trigger المتأثر وفق runbook معتمد.
- لا تحذف notifications أو tokens جماعيًا.
- invalid tokens تنظف تدريجيًا؛ لا تطبع token في logs.

### App Check

- عند false-positive واسع، عطّل enforcement للدالة المتأثرة فقط مؤقتًا مع بقاء Auth/authorization وRules.
- لا تلغ App Check registrations أو مفاتيح التطبيق أثناء incident.
- حل تهيئة العميل ثم أعد metrics/enforcement تدريجيًا.

## 8. تراجع Scheduled Functions

- أوقف Cloud Scheduler job المتسبب أولًا لمنع دورة جديدة.
- سجل آخر run وcounts والوثائق المتأثرة.
- أعد نشر handler السابقة أو الإصدار المصحح، ثم اختبر staging.
- لا تستأنف الجدول حتى مطابقة البيانات.

حالات خاصة:

- **مولد الرسوم:** لا تحذف رسومًا حسب التاريخ فقط؛ استخدم `idempotencyKey` و`createdBy` وmanifest وتحقق من عدم وجود معاملات مرتبطة.
- **mark overdue:** استرجع status السابق من manifest/backup، لا تعمم `unpaid` على كل السجلات.
- **expire receipts:** لا تعيد `pending` إذا انتهت المعاملة أو عولجت؛ طابق locks/transactions ذريًا.
- **orphan cleanup:** استعد object generation من soft delete/versioning؛ لا يمكن تعويض ملف بلا نسخة.

## 9. تراجع تطبيق Android

- أوقف staged rollout فورًا.
- المستخدمون الذين ثبتوا versionCode جديدًا لا يمكن إعادتهم تلقائيًا إلى versionCode أقل.
- الحل الآمن إصدار hotfix بنفس signing identity وبـversionCode أعلى، مبني من source السابق مع أقل تعديل توافق مطلوب.
- أبق backend متوافقًا مع N وN-1 طوال نافذة rollout.
- لا تغيّر package name أو signing key كتراجع.

## 10. تراجع Migration

### قاعدة حاكمة

لا يوجد حاليًا rollback script أو manifest كافٍ؛ لذلك أي production apply قبل إنشائه واختباره هو **ممنوع**.

الخطة المطلوبة قبل apply:

1. manifest يسجل كل path: create/merge، الحقول السابقة، migrationVersion، والمصدر legacy.
2. dry-run وapply وrollback على clone staging.
3. تحقق أن rollback لا يحذف رسومًا أو معاملات أنشئت بعد migration.
4. نافذة توقف writers أو watermark يفصل بيانات ما قبل/بعد migration.

طرق الاسترجاع:

- restore من Firestore export إلى مشروع recovery للتحليل أولًا.
- targeted restore/cleanup وفق manifest؛ managed import وحده لا يضمن إزالة documents الجديدة التي أنشأتها migration.
- إعادة حساب إجماليات كل مجلس بالبيسة ومطابقتها مع baseline قبل فتح التطبيق.

ممنوع:

- حذف كل documents ذات `migrationVersion=1` بلا فحص العلاقات.
- إعادة import عمياء فوق قاعدة نشطة.
- تشغيل migration مرة أخرى لمحاولة «الإصلاح» قبل فهم الفرق.

## 11. استرجاع Firestore وStorage وAuth

### Firestore

- استخدم operation ناجحة ومحددة من managed export.
- اختبر الاسترجاع إلى مشروع معزول قبل production.
- اعلم أن export قد يتضمن تغييرات حدثت أثناء تشغيله؛ استخدم maintenance window أو PITR snapshot time إذا كان متاحًا.
- import ملغى قد يترك writes تمت بالفعل؛ الإلغاء لا يعيد الحالة السابقة.

### Storage

- استخدم object generation/soft-deleted generation المحدد.
- استعد ملفات الإيصالات المتأثرة فقط، وراجع metadata والمسار والمالك.
- راقب تكلفة الاحتفاظ بالإصدارات وطبّق lifecycle بعد انتهاء incident، لا أثناءه.

### Authentication

- Auth export حساس ومشفر؛ الاستيراد إجراء مستقل عالي الخطورة.
- لا تستورد المستخدمين جماعيًا بسبب خلل تطبيق أو Rules.
- استخدمه فقط عند فقد/فساد Auth مثبت وبخطة hash parameters موثقة.

## 12. التحقق بعد التراجع

- local/remote release SHA موثق.
- Rules matrix ناجحة.
- مجلسان معزولان.
- primary owner وsystem owner صحيحان.
- لا إشعارات عابرة للمستخدمين.
- لا رسوم أو allocations أو balances سالبة/مكررة.
- `refundRequired` وlocks وpending transactions متناسقة.
- error rate والتكلفة عادا إلى baseline.
- سجل incident وسبب التراجع والبيانات المتأثرة دون PII.

## 13. قرار الإغلاق

لا يغلق incident لمجرد عودة الواجهة. يلزم:

- إثبات سلامة البيانات.
- توثيق root cause.
- بوابات regression.
- خطة إعادة نشر جديدة مستقلة.
- موافقة مالك النظام والمالك التشغيلي.

## 14. مراجع رسمية

- Firestore export/import والعمليات طويلة المدى: https://firebase.google.com/docs/firestore/manage-data/export-import
- إدارة Functions والنشر المحدد: https://firebase.google.com/docs/functions/manage-functions
- App Check enforcement والتراجع التدريجي: https://firebase.google.com/docs/app-check/cloud-functions
- Storage object versioning/soft delete: https://docs.cloud.google.com/storage/docs/object-versioning

## 15. تأكيد عدم التنفيذ

- لم تُوقف jobs إنتاجية.
- لم تُعد نشر rules/functions.
- لم تُسترجع بيانات أو objects أو users.
- لم يُنفذ أي أمر من الأمثلة أعلاه.
