# تقرير مراجعة الجاهزية قبل الإنتاج

**التاريخ:** 23 يوليو 2026
**النطاق:** فحص وتوثيق فقط، دون Deploy أو Migration أو اتصال تشغيلي ببيانات الإنتاج
**HEAD المفحوص:** `6ad9e18c976a28d2d5cb27f2eb5f5c0f85581979`
**الفرع:** `main` مطابق لـ`origin/main` عند بدء التدقيق
**بيئة الاختبار:** `demo-financial-prestaging` عبر Firebase Emulator فقط
**القرار:** **NO-GO للإنتاج**

## تحديث المعالجة الأمنية — 23 يوليو 2026

أُنجزت معالجة الموانع القابلة للإغلاق محليًا في الكود والقواعد، وأُعيدت البوابات على
`demo-financial-prestaging` وFirebase Emulator فقط. يبقى القرار **NO-GO** لأن الأدلة
التشغيلية التي تتطلب Console أو نسخة بيانات معزولة أو مفتاح توقيع حقيقي لم تُنفذ.

### موانع أُغلقت في الكود وباختبارات محلية

- **إساءة استخدام الإشعارات:** أُغلق إنشاء وحذف إشعارات المستخدم وطابور
  `notifications_queue` أمام العميل. لا يرسل Trigger إلا مستندًا يحمل provenance
  خادميًا ويرتبط مساره بالمستلم ومعرف الإشعار. تحديث العميل محصور في `status=read`
  و`readAt` فقط. أزيل writer القديم من `NotificationService`.
- **الملف المالي العابر للمجالس:** قراءة `financial_profile` الكامل أصبحت للمالك
  الأعلى أو لصاحب صلاحية مالية في المجلس نفسه فقط. العضو العادي، عضو مجلس آخر،
  الضيف، وغير الموثق مرفوضون. لم يُنشأ مسار عام يكشف البنك أو IBAN.
- **المالك الأساسي:** التعريف القانوني هو عضوية نشطة تحمل
  `isPrimaryOwner=true` أو `roleId/role` بقيمة `owner` أو `council_owner`؛ أما
  `system_owner` فهو دور منصة مستقل في `platform_admins`. أضيف إسقاط خادمي أدنى
  `member_access/{userId}` حتى لا يُفترض تطابق `membershipId` مع `userId`، مع
  fallback مقيد للوثيقة القديمة `memberships/{uid}`. النقل الوحيد للملكية callable
  ذري ومحمي بمالك المنصة؛ العميل لا يستطيع حذف المالك أو تعليقه أو خفضه.
- **تعارض الحجوزات:** الإنشاء والمراجعة أصبحا callable خادميين، والكتابة العميلية
  محظورة. القفل الحتمي SHA-256 يشمل المجلس ضمن مساره ثم المورد واليوم والبداية
  والنهاية. معاملتان متوازيتان تنتجان فائزًا واحدًا، والإلغاء يحرر القفل بشرط
  ملكيته للحجز. فحص توافق إضافي يمنع الاصطدام بحجز legacy نشط بلا `slotKey`.
  التوفر يجلب نطاقًا زمنيًا بصفحات 200 دون حد 100، ولا يعيد هوية أو هاتفًا أو
  إيصالًا أو مبلغًا.
- **Organization Bootstrap:** لم يعد بدء التطبيق يستدعي seed. `ensureSeeded`
  يرفض إلا في Debug مع علم Emulator صريح. الإنشاء والإصلاح أصبحا callables
  محميين بـ`system_owner`، ويبنيان البنية المعتمدة بصورة idempotent؛ Rules لا تحتوي
  استثناء bootstrap للعميل.
- **المجدولات:** الدوال الأربع لها kill switch مشترك ومفتاح مستقل، والحالة
  الافتراضية عند غياب الإعداد هي disabled، وdry-run هو الافتراضي حتى يضبط
  `FINANCIAL_SCHEDULE_DRY_RUN=false`. السجل يقتصر على `task/runId/result/counts`
  دون بيانات شخصية.
- **Android signing configuration:** أزيل fallback إلى debug. يقرأ Release
  `android/key.properties` المستبعد أو متغيرات `VC_RELEASE_*` فقط، وأضيف مثال بلا
  أسرار. عند غيابها يُنتج artifact غير موقع للتحقق من التجميع ولا يصلح للنشر.

### موانع ما زالت مفتوحة تشغيليًا

1. **CRITICAL — توافق بيانات الإنتاج:** لم يُقرأ `alrahmat-console`. أداة الجرد
   read-only جاهزة ومقفلة افتراضيًا أمام الإنتاج، لكن لا يمكن إثبات schema أو
   الحجوزات legacy أو الحاجة النهائية للترحيل قبل جرد مصرح لنسخة معزولة ومراجعته.
2. **CRITICAL — توقيع Android:** لا يوجد keystore إنتاج حقيقي محليًا. نجح تجميع
   `app-release.apk` غير موقع بحجم `60,813,208` بايت، وأثبت `apksigner` أنه غير
   موقع؛ لا توجد بعد AAB/APK إنتاجية موقعة أو بصمة SHA-256 معتمدة.
3. **HIGH — App Check:** العميل مهيأ لـPlay Integrity في Android Release وDebug
   في Debug/Emulator، والدوال الحساسة تحمل `enforceAppCheck=true`. يبقى تسجيل
   التطبيق وSHA-256 ومراقبة metrics وفرض staging ثم production في Console، لذلك
   لا يُعد المانع مغلقًا تشغيليًا.
4. **HIGH — Scheduler/Pub/Sub E2E:** منطق البوابات وdry-run مختبر محليًا، لكن
   Trigger Scheduler/Pub/Sub لم يُختبر على staging منشور.
5. **HIGH — نسخة احتياطية واسترجاع:** لم يُنفذ export أو restore rehearsal، وهو
   شرط قبل أي Rules/Functions/Migration نافذة إنتاجية.

### نتائج البوابات بعد المعالجة

- Flutter tests: **51/51**.
- Functions unit tests على Node `v20.20.2`: **22/22**.
- Firestore/Storage Emulator على `demo-financial-prestaging`: **34/34**.
- اختبار JSON: **5/5**؛ 15 ملفًا صالحًا و3 placeholders legacy مستثناة كما هي.
- `node --check`: **10/10**.
- `flutter analyze`: صفر أخطاء و**4 تحذيرات `unused_element` قديمة** في
  `admin_dashboard.dart`؛ لم تُحذف Widgets الأربعة.
- `git diff --check`: ناجح.
- فحص الأسرار: صفر سر عالي الثقة ضمن الإضافات الحالية. مفاتيح Firebase client
  API الموجودة في ملفات الإعداد المتتبعة سابقة لهذه الجولة وتبقى مخاطرة Console
  تتطلب التحقق من API restrictions، وليست سرًا خادميًا جديدًا.
- Release compile: نجح بعد `flutter clean` وظهر APK غير موقع؛ لم يُثبت على هاتف
  ولم يُرفع. مراجع `H:\sdk` المتبقية موجودة في `buildlog.txt` وسجلات قديمة بتاريخ
  25 يونيو فقط، ولم تُنشئ محاولة البناء الجديدة سجل خطأ جديدًا.

لم تُنشأ MAJ/TASK جديدة لأن Project Brain لا يحتوي تصنيفًا معتمدًا لهذه الجولة؛
تبقى `TASK-004` وMAJ-8 و`BUG-002` مكتملة، ويُقترح اعتماد مهمة مستقلة للجاهزية
التشغيلية قبل أي نشر.

## 1. الوضع الحالي

- MAJ-8 و`BUG-002` و`TASK-004` مكتملة ضمن نطاق التطوير والـQA السابق، ولا يتغير ذلك بهذا التدقيق.
- بوابات المنطق المالي والحجز الحالية خضراء، لكن الجاهزية التشغيلية والأمنية للإنتاج ليست مكتملة.
- لم تُقرأ بيانات `alrahmat-console` ولم يمكن، تبعًا لذلك، إثبات مخطط البيانات الفعلي أو اكتمال الترحيل أو سياسات App Check وAuth وAPI-key restrictions في Console.
- لم تُنشأ مهمة أو معلم جديد؛ الموانع أدناه مقترحة لمهمة مستقلة بعد المراجعة، دون رقم حتى يعتمد التصنيف.

## 2. الموانع الحرجة — مرتبة حسب الشدة

### CRITICAL-1 — إنشاء الإشعارات من العميل قابل للإساءة

- `firestore.rules:370-384` يسمح لأي مستخدم موثّق بإنشاء مستند إشعار لأي `userId` إذا مرر مجلسًا موجودًا و`createdByUserId` يساوي هويته.
- `functions/index.js:25-130` يرسل FCM تلقائيًا لكل مستند جديد؛ لذلك يمكن تحويل الثغرة إلى إغراق Push وتكلفة Functions/FCM وإزعاج مستخدمين خارج مجلس المرسل.
- يوجد TODO أمني صريح في القواعد لنقل fan-out إلى Cloud Functions وإغلاق create من العميل.
- App Check غير مفعّل، فلا توجد طبقة مقاومة إضافية للطلبات الآلية.
- **شرط الإغلاق:** نقل إنشاء الإشعارات الحساسة إلى خادم يتحقق من المجلس والصلاحية والمستلم، إغلاق client create، وإضافة اختبارات إساءة وعزل.

### CRITICAL-2 — قراءة مالية عابرة للمجالس

- `firestore.rules:425-431` يسمح لأي مستخدم موثّق بقراءة `organizations/{organizationId}/financial_profile/{profileId}`.
- المستند `banking` مهيأ لحقول البنك واسم الحساب ورقم الحساب وIBAN؛ السماح الحالي لا يشترط عضوية المجلس.
- **شرط الإغلاق:** تقييد القراءة بعضوية المجلس أو صلاحية مالية موثقة، مع اختبار مستخدم موثّق من مجلس آخر.

### CRITICAL-3 — حماية المالك والعضوية غير متسقة مع صيغ البيانات المدعومة

- `membershipIsPrimaryOwner` في `firestore.rules:45-51` لا يعتبر `roleId=owner` أو `roleId=council_owner` ولا `role=council_owner` مالكًا محميًا عند غياب `isPrimaryOwner=true`.
- قواعد الصلاحيات الإدارية تقرأ غالبًا مستند العضوية بالمسار `memberships/{auth.uid}`، بينما التطبيق والدوال يدعمان أن يختلف `membershipId` عن `userId`.
- النتيجة المحتملة: مالك legacy غير محمي من تعديل/حذف مدير أعضاء، أو مدير/مراجع صالح يفقد صلاحيات Rules رغم نجاح التفويض داخل Functions.
- لا توجد تغطية Emulator لمالك بصيغة `roleId=owner` دون العلم، ولا لمراجع ذي `membershipId` مختلف في list المباشر للإيصالات.
- **شرط الإغلاق:** توحيد عقد الهوية أو إضافة مرجع عضوية قابل للتحقق في Rules، توسيع حماية المالك لكل الصيغ المعتمدة، واختبارات سلبية قطعية.

### CRITICAL-4 — توافق بيانات الإنتاج والترحيل غير مثبت

- لم يُسمح بجرد production، لذلك لا يمكن تحديد وجود `payments`/`transactions` legacy أو نقص `member_accounts` و`member_directory` و`charges`.
- `scripts/migrate-financial-v1.js` يغطي memberships وtop-level payments، لكنه لا يثبت backfill للحجوزات المعتمدة القديمة أو جميع معاملات legacy.
- dry-run نفسه يقرأ قاعدة البيانات، لذلك لم يُشغّل على `alrahmat-console` في هذه الجولة.
- لا يوجد manifest دائم لكل كتابة migration ولا سكربت تراجع متماثل؛ الاسترجاع الدقيق لا يمكن ضمانه بالاعتماد على import وحده.
- **الحكم:** الترحيل **محتمل/مشروط بالبيانات، ولا يمكن اعتباره غير مطلوب** قبل جرد نسخة staging معزولة وdry-run ومراجعة الإجماليات.

### CRITICAL-5 — Android Release موقّع بمفتاح Debug

- `android/app/build.gradle.kts` يربط build type `release` بـ`signingConfigs.getByName("debug")`.
- لا يوجد `android/key.properties` أو keystore إصدار محلي، ولم يُكشف أو يُطلب أي مفتاح.
- هذه البنية غير مقبولة كتوقيع إنتاج أو Play rollout.
- **شرط الإغلاق:** إعداد upload/app signing رسمي خارج Git، توثيق الاسترداد والصلاحيات، والتحقق من SHA-256 دون نشر المفتاح.

### HIGH-1 — سلامة حجز اليوم ليست ذرية على الخادم

- اعتماد الحجز يتم من Flutter بكتابة مباشرة إلى Firestore؛ Rules تتحقق من الانتقال `pending -> approved` لكنها لا تتحقق من تعارض التاريخ.
- `getBookingAvailability` يعرض حتى 100 حجز فقط في الشهر ولا يطبق pagination.
- لا توجد transaction/canonical slot تمنع مديرين من اعتماد حجزين لليوم/الفترة نفسها.
- **شرط الإغلاق:** اعتماد خادمي ذري بمفتاح slot أو transaction، منع التعارض، وإزالة حد الـ100 أو إضافة pagination/تجميع أيام.

### HIGH-2 — App Check غير موجود في العميل وغير مفروض في الدوال

- لا توجد حزمة `firebase_app_check` في `pubspec.yaml` ولا تهيئة عميل.
- كل callables تستخدم `{ region: "us-central1" }` دون `enforceAppCheck`.
- المصادقة والتفويض الخادميان موجودان في النظام المالي، لكنهما لا يمنعان أتمتة الإساءة من عميل غير أصلي بحساب صالح.
- مع وجود تدفقات مالية وإيصالات وبحث وإشعارات، الغياب **مانع في الحالة الحالية** وليس مخاطرة مقبولة حتى تُغلق CRITICAL-1 وتنجح مرحلة metrics ثم enforcement تدريجيًا.

### HIGH-3 — bootstrap إنتاجي تلقائي من تطبيق Release

- `lib/main.dart` يستدعي `OrganizationSeedService.instance.start()` دائمًا.
- الخدمة تحاول إنشاء مجلس الإنتاج وأدواره وإعداداته عند دخول مستخدم إذا لم يوجد المستند، وRules تحتوي استثناء bootstrap لأي مستخدم موثّق يطابق البيانات الثابتة.
- العملية idempotent إذا كان المجلس موجودًا، لكنها كتابة إنتاج تلقائية وغير مناسبة لمسار تشغيل تطبيق عام.
- **شرط الإغلاق:** نقل bootstrap إلى إجراء إداري صريح ومراجع أو قيده ببيئة/صلاحية خادمية، ومنع العميل العام من إنشاء baseline الإنتاج.

### HIGH-4 — المجدولات لم تُختبر end-to-end ولا تملك kill switch

- توجد أربع scheduled functions. Emulator تجاهل triggers لغياب Pub/Sub Emulator؛ اختُبرت handlers الإنتاجية مباشرة ونجحت.
- نشر functions سيُنشئ الجداول فورًا، ولا يوجد feature flag لتعطيل توليد الرسوم أو expiry/cleanup أثناء التحقق الأولي.
- **شرط الإغلاق:** اختبار Scheduler/Pub/Sub في staging حقيقي، وتوفير آلية إيقاف أو نشر المجدولات منفصلة بعد التحقق من البيانات.

### HIGH-5 — بوابة Release build غير ناجحة

- المحاولة الأولى لـ`flutter build apk --release --no-pub` انتهت بمهلة 6 دقائق دون APK.
- سجل Kotlin كشف incremental caches تشير إلى مسار قديم `H:\sdk\...` وتعارض تسجيل storage.
- محاولة ثانية بتعطيل incremental وdaemon لهذه العملية فقط انتهت بمهلة 10 دقائق، ولم ينتج `app-release.apk`.
- لم يُنفذ `clean` ولم تُحذف cache التزامًا بقيود الجولة.
- **شرط الإغلاق:** بيئة بناء نظيفة/CI قابلة لإعادة الإنتاج، APK/AAB حديث، فحص التوقيع والـmanifest وhash، ثم smoke test Release على staging.

## 3. مخاطر غير مانعة منفردة

- `.firebaserc` يضع `alrahmat-console` كـdefault؛ أي أمر Firebase بلا `--project` خطر تشغيلي. يجب أن تمنع الـrunbook ذلك.
- `firebase-functions@5.1.1` يعمل على Node 20 ونجحت الاختبارات، لكن Firebase CLI يحذر أنه قديم. الترقية مؤجلة لمهمة مستقلة كما طلبت هذه الجولة.
- callables ومعظم Firestore triggers لا تحدد timeout/memory/maxInstances؛ قد تظهر مخاطر تكلفة أو burst. المجدولات فقط محددة بـ540 ثانية و512MiB و`maxInstances=1`.
- `onNotificationCreated` يمسك خطأ الإرسال ولا يعيد رميه، لذلك فشل FCM قد يُفقد دون retry. أما outbox المالي فله `retry: true` وidempotency.
- `sendPushNotification` legacy ما زالت منشورة مع قناة قديمة، ويجب إثبات عدم وجود writers قبل حذفها في مهمة لاحقة.
- مسار Storage القديم `receipts/{memberId}/...` يستخدم `allow write` للمالك، و`write` تشمل update/delete؛ يجب تحديد هل ما زال مستخدمًا قبل production.
- التطبيق مضبوط على `version: 1.0.0+1` واسم Android الظاهر ما زال `village_council_app`.
- لا توجد إعدادات minify/shrink أو ملف ProGuard مخصص؛ ليست مانعًا وظيفيًا لكنها قرار Release غير موثق.
- توجد ملفات MainActivity في حزمتين، والـmanifest يستخدم الحزمة الصحيحة؛ الملف الآخر غير مستخدم ويحتاج مراجعة مستقلة لا حذفًا في هذا التدقيق.
- API keys الخاصة بعملاء Firebase موجودة في ملفات الإعداد الثلاثة المتوقعة. هي معرفات عميل وليست service-account secrets، لكن قيود API/SHA في Console لم يمكن التحقق منها.
- يوجد مجلد `local_keys/` محلي ignored، ولم تُقرأ محتوياته. بعض السكربتات الإدارية تملك fallback لمسار داخله؛ يجب منع fallback في runbook واستخدام اعتماد صريح فقط.

## 4. مراجعة النظام المالي والحجوزات

### أدلة ناجحة

- التخزين والحساب الماليان يستخدمان أعدادًا صحيحة بالبيسة، والعرض بثلاث خانات للريال العُماني.
- submit/review يتحققان من مجموع allocations، ملكية المجلس والمستفيد، الرصيد قبل السداد، منع الدفع الزائد، وحالة الرسم.
- الاعتماد والرفض والتوزيع داخل Firestore transaction؛ إعادة الاعتماد تُرفض.
- locks ومحدد المعدل يمنعان تعليق الرسم والتكرار، وexpiry يفك الأقفال.
- الدفع الجزئي والجماعي وعن الآخرين مغطى، مع عزل membership والمجلس.
- رسوم العضو والضيف مستقلة، والحجز الملغى يحول المدفوع/الجزئي إلى `refundRequired` ولا يدعي استردادًا تلقائيًا.
- تقويم التوفر يعيد `date/status` فقط، و«حجوزاتي» تبقى query مقيدة بالمستخدم.

### فجوات الإنتاج

- فجوة التعارض الذري للحجز وحد 100 نتيجة موضحة في HIGH-1.
- `eventBookingFeeBaisa` ما زال إعدادًا دون lifecycle إنتاجي موثق؛ ليس ضمن MAJ-8 المنجزة لكنه لا يجوز عرضه كميزة إنتاج مكتملة.
- التوافق مع الرسوم/المعاملات legacy يتوقف على الجرد والترحيل المشروط.

## 5. مكونات النشر الفعلية

| المكوّن | الموجود | حالة الجاهزية |
|---|---|---|
| Firestore Rules | `firestore.rules` | NO-GO بسبب CRITICAL-1/2/3 وفجوات legacy |
| Firestore Indexes | 23 composite index، دون field overrides | جاهزة للإنشاء المسبق، يلزم انتظار build والتحقق |
| Storage Rules | `storage.rules` | المسار الجديد جيد؛ legacy يحتاج قرارًا واختبارًا |
| Cloud Functions | 35 export في `us-central1` | المنطق مختبر؛ App Check/limits/schedules تمنع الإنتاج |
| Scheduled Functions | 4 | handlers مختبرة، triggers غير مختبرة end-to-end |
| FCM | trigger جديد + trigger legacy وقنوات Android | يعمل في QA؛ fan-out client security مانع |
| Android | `com.alrahmat.village_council`, `1.0.0+1` | Debug-signed ولا يوجد artifact Release |
| Secrets/env | لا Secret Manager secrets معرفة؛ env اختياري للتنظيف | Console configuration وkey restrictions غير متحقق منها |

### Cloud Functions inventory

- 16 callable.
- 4 scheduled: 02:00، 02:30، 03:15 يوميًا، وexpiry كل 60 دقيقة، كلها `Asia/Muscat` و`us-central1` و512MiB و540s و`maxInstances=1`.
- 12 `onDocumentWritten` و3 `onDocumentCreated`.
- retry صريح فقط لـ`deliverFinancialNotificationOutbox`.
- Runtime: Node 20؛ الاختبارات شُغلت على `v20.20.2`.
- متغير اختياري: `FINANCIAL_RECEIPT_ORPHAN_HOURS`، والافتراضي الآمن 48 ساعة ضمن مجال 24–720.
- لا توجد مفاتيح دفع أو service-account JSON أو secrets خادمية متتبعة.

## 6. Android Release Readiness

| البند | النتيجة |
|---|---|
| applicationId/namespace | `com.alrahmat.village_council` ومتطابق مع Android Firebase client |
| versionCode/versionName | `1` / `1.0.0` |
| Firebase Release target | ملفات العميل تشير إلى `alrahmat-console`؛ Emulator مرفوض في release |
| التوقيع | **Debug signing — مانع** |
| keystore/key.properties | غير موجودين محليًا ومتجاهلين في Git كما ينبغي |
| الصلاحيات | INTERNET، POST_NOTIFICATIONS، VIBRATE فقط في main manifest |
| الإشعارات | default channel `vc_high_sv`، والقنوات منشأة في التطبيق |
| R8/ProGuard | لا إعداد minify/shrink صريح ولا ملف قواعد مخصص |
| Release build | **غير مكتمل؛ Timeout مرتين، لا APK** |

## 7. App Check وSecrets وConsole configuration

- App Check: غير مهيأ في العميل وغير مفروض على callables؛ NO-GO في الوضع الحالي.
- التفعيل الصحيح يجب أن يبدأ metrics في staging ثم Play Integrity، ثم enforcement تدريجي. Auth والتفويض الخادمي لا يُخففان عند التراجع.
- لا private keys أو GitHub/AWS tokens أو IBAN في الشجرة الحالية.
- توجد ثلاثة ملفات إعداد عميل Firebase تحوي client API keys المتوقعة: Android وiOS و`firebase_options.dart`. يجب التحقق لاحقًا من API restrictions وSHA fingerprints في Console.
- لا يوجد ملف اعتماد حساس متتبع. `local_keys/` محلي وignored ولم يُفتح.
- إعدادات Auth providers، authorized domains، APNs، FCM credentials، budgets/alerts، Scheduler API، Artifact Registry cleanup، وStorage soft-delete غير ممثلة بالكامل في Git وتحتاج checklist Console مصرحًا بها.

## 8. نتائج البوابات الحالية

| البوابة | النتيجة |
|---|---|
| `flutter test` | **46/46 ناجح** |
| `flutter analyze --no-pub` | **0 أخطاء، 4 تحذيرات قديمة** (`unused_element`) |
| `npm test` / Node 20.20.2 | **17/17 ناجح** |
| Firebase Emulator | **23/23 ناجح** على `demo-financial-prestaging` فقط |
| `node --check` | **11/11 ناجح** |
| JSON validator tests | **5/5 ناجح** |
| JSON repository | 15 صالحًا + 3 legacy placeholders مستثناة، 0 خطأ |
| Emulator ports بعد الاختبار | مغلقة |
| Release APK | **فشل البوابة: Timeout مرتين، لا artifact** |
| secret scan | 0 private keys، 0 service-account files، 0 GitHub/AWS tokens، 0 IBAN |

ملاحظة: تحذير CLI لترقية `firebase-functions` سُجل فقط ولم تُغير الحزمة.

## 9. التوافق والترحيل المقترح دون تنفيذ

البيانات المتأثرة المحتملة:

- `organizations/*/memberships/*` → `member_accounts` و`member_directory`.
- top-level `payments/*` → `organizations/{organizationId}/charges/*` بالبيسة.
- top-level وorganization transactions للتوافق التاريخي.
- الحجوزات المعتمدة القديمة التي قد تحتاج backfill رسوم بقرار مستقل.
- `financial_settings/main` و`subscription_plans` قبل تشغيل مولد الاشتراكات.

التحقق المطلوب:

1. export مشفر ومكتمل، ثم restore إلى مشروع staging معزول.
2. inventory للحقول والعدادات والقيم المالية والحالات والمجالس دون PII في التقرير.
3. dry-run صريح على staging، ومطابقة مجموع الريال قبل/البيسة بعد، ومراجعة skipped records.
4. اختبار idempotency بإعادة dry-run/apply على staging.
5. إضافة manifest للوثائق المنشأة/المعدلة وخطة إزالة دقيقة قبل أي apply إنتاجي.

## 10. القرار والخطوة التالية

**NO-GO.** نجاح MAJ-8 لا يعادل جاهزية production؛ الموانع تخص الأمن والتشغيل والبيانات والتوقيع.

**الخطوة الواحدة المقترحة:** مراجعة هذا التقرير واعتماد نطاق مهمة مستقلة لإغلاق CRITICAL-1 إلى CRITICAL-5 أولًا، دون نشر، ثم إعادة التدقيق بالكامل.

## 11. مراجع رسمية

- App Check callable enforcement: https://firebase.google.com/docs/app-check/cloud-functions
- Firestore managed export/import: https://firebase.google.com/docs/firestore/manage-data/export-import
- إدارة ونشر Functions على دفعات محددة: https://firebase.google.com/docs/functions/manage-functions
- حماية كائنات Storage وsoft delete/versioning: https://docs.cloud.google.com/storage/docs/object-versioning

## 12. تأكيدات السلامة

- لم يُنفذ `firebase deploy`.
- لم يُنفذ migration أو dry-run على production.
- لم تُقرأ أو تُكتب بيانات `alrahmat-console` تشغيلًا.
- لم تُغير IAM أو Secrets أو dependencies.
- لم يُثبت APK على الهاتف.
- لم يُنشأ Commit أو Push.
