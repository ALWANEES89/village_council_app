# تقرير جولة ما قبل staging للنظام المالي

التاريخ: 15 يوليو 2026
المشروع: `village_council_app`
حالة المهمة المالية: `in_progress` بنسبة **92%**
الحكم الحالي: الإصلاحات المحلية واجتياز Emulator ناجحان، لكن النظام **ليس جاهزًا للنشر إلى production**، ولا تزال هناك بوابات إلزامية قبل staging وproduction.

## 1. ملخص ما نُفّذ

- فُصل جسم مولد رسوم الاشتراكات اليومي وجسم تحديث المتأخرات في handler إنتاجية مسماة؛ الـtrigger والاختبار يستدعيان الدالة نفسها، دون نسخة منطق اختبار موازية.
- اختُبر المولد على Firestore Emulator باستخدام 205 حسابات، وصفحات حجمها 50، وفشل مؤقت في صفحة وسطية، ثم إعادة محاولة كاملة دون إنشاء رسوم مكررة.
- اختُبر احتساب نهاية الشهر والسنة بتوقيت `Asia/Muscat`، وعدم تحويل الرسم إلى `overdue` في يوم استحقاقه نفسه.
- أُنشئ scheduled sweep خادمي للملفات المؤقتة في Storage بمهلة افتراضية 48 ساعة قابلة للضبط عبر `FINANCIAL_RECEIPT_ORPHAN_HOURS`.
- يدقق sweep المسار والـmetadata ووقت إنشاء Storage الخادمي، ويستخدم pagination، ولا يحذف الملف المرتبط بأي معاملة محفوظة، ولا يحذف عند فشل Firestore أو نقص metadata.
- أضيف دعم رسوم حجز غير العضو دون إنشاء عضوية وهمية: `accountType=guest`، و`membershipId=null`، والهوية المالية هي Firebase Auth `userId`.
- يقرأ الخادم العضوية والإعدادات عند اعتماد الحجز؛ العضو النشط يأخذ رسم العضو، وغير العضو يأخذ رسم غير العضو، ولا رسم في `free` أو `subscription` فقط أو عند المبلغ صفر.
- أضيفت callables محدودة لعرض رسم حجز المستأجر وإرسال إيصال لرسم حجزه فقط. لا يستطيع المستأجر البحث في دليل الأعضاء أو الدفع عن رسوم الأعضاء.
- أضيفت شاشة للمستأجر تعرض الرصيد والحالة ورفع صورة/PDF وسجل المعاملة، مع بقاء الدفع الإلكتروني مخفيًا.
- أضيف مسار إلغاء آمن: إلغاء مباشر لـ`pending`، و`cancellationRequested` للحجز المعتمد، وقبول/رفض إداري ذري، وتحويل الرسم غير المدفوع إلى `cancelled` والمدفوع أو الجزئي إلى `refundRequired` دون استرداد وهمي أو حذف سجلات.
- أضيفت واجهة صاحب الحجز لطلب الإلغاء، وواجهة الإدارة لقبول الطلب أو رفضه، مع منع المعالجة المزدوجة بواسطة Firestore transaction.
- قُيدت قراءة حجوزات المستأجر ورسومه بمعرف المستخدم والمجلس، وأضيف callable لتوفر الأيام يعيد التاريخ والحالة فقط بدل تنزيل بيانات حجوزات الآخرين.
- أضيف إعداد Flutter آمن للـEmulator عبر `dart-define`، ولا يعمل تلقائيًا ولا يقبل release، ويشترط host صريحًا، ويعرض شريط «بيئة اختبار محلية» في debug فقط.
- أضيفت خطة App Check، وقائمة QA الهاتف، وقائمة staging، وسكربت تحقق staging غير كاتب يرفض `alrahmat-console` صراحة.
- أضيفت `.nvmrc` بقيمة 20، وتأكد أن `functions/package.json` يحدد Node 20.
- أزيل BOM من `project-brain/tasks.json`، وأصبح JSON يُقرأ مباشرة دون معالجة خاصة.
- حُدثت مهمة النظام المالي إلى 92% وشُغّل مولد لوحة المشروع؛ النسبة الكلية المولدة 83%، ومهمتان مكتملتان من أربع.

## 2. الدوال المجدولة

### مولد الرسوم

- handler الإنتاجية: `generateSubscriptionChargesHandler` في `functions/financial.js` قرب السطر 525.
- trigger: `generateSubscriptionChargesDaily` قرب السطر 549.
- يعالج collection group `member_accounts` حتى نهاية الصفحات، بحجم 200 افتراضيًا وتزامن محدود.
- يستخدم `ensureSubscriptionCharge` نفسه المستخدم في trigger الحساب المالي، ومفتاح idempotency canonical.
- يعيد إحصاءات `scanned` و`outcomes` ولا يسجل أسماء أو هواتف أو بريدًا أو معرفات حسابات في سجل الملخص.
- اختبار Emulator مر على 205 حسابات، وفشل بعد الصفحة الأولى، ثم أعيد التشغيل وأصبح عدد الرسوم 205 فقط، وأعادت المحاولة التالية 205 نتيجة `exists`.

### تحديث المتأخرات

- handler الإنتاجية: `markFinancialChargesOverdueHandler` قرب السطر 558.
- trigger: `markFinancialChargesOverdue` قرب السطر 584.
- المقارنة تعتمد يوم مسقط، وليس الساعة أو يوم UTC؛ لا يصبح الرسم متأخرًا في يوم الاستحقاق نفسه.
- اختُبرت ليلة 31 ديسمبر/1 يناير، كما تغطي اختبارات core حدود 31 يوليو/1 أغسطس والدورات الشهرية والسنوية.

### الفجوة الصريحة

Firebase Emulator تجاهل scheduled triggers لعدم وجود Pub/Sub Emulator، وظهر ذلك صراحة في السجل. لذلك لم يُختبر استدعاء Cloud Scheduler/Pub/Sub نفسه. اختُبرت **نفس handler الإنتاجية** مباشرة ضد Firestore Emulator، وليست helper بديلة. يلزم اختبار trigger الحقيقي في staging بعد النشر.

## 3. تنظيف إيصالات Storage اليتيمة

- الدالة: `cleanupOrphanReceiptsHandler` قرب السطر 1232.
- trigger: `cleanupOrphanFinancialReceipts` قرب السطر 1317، يوميًا 03:15 بتوقيت مسقط، `timeoutSeconds=540` وذاكرة `512MiB` و`maxInstances=1`.
- المسارات المقبولة فقط: `organizations/{organizationId}/members/{uploaderUid}/receipts/{receiptId}/{fileName}`.
- metadata المطلوبة: `temporaryUpload=true` و`receiptId` و`uploaderUid` و`organizationId` و`uploadedAt`، مع مطابقة كاملة للمسار.
- يعتمد شرط العمر على `uploadedAt` وعلى `timeCreated` الخادمي معًا؛ لا يستطيع العميل تعجيل الحذف بتزوير وقت قديم.
- الملفات الحديثة، والمرتبطة بمعاملة `pending` أو `approved` أو `rejected`، والناقصة metadata، وحالات فشل قراءة Firestore لا تُحذف.
- يعالج Storage بصفحات ويحمي من تكرار page token، وإعادة التشغيل idempotent.
- اختبار Emulator غطى أكثر من صفحة، وحذف ملف قديم غير مرتبط، وحماية الحديث وثلاث حالات معاملات، ونقص metadata، وفشل Firestore، وإعادة التشغيل.
- scheduled trigger نفسه لم يعمل لغياب Pub/Sub Emulator؛ اختُبرت handler الإنتاجية نفسها مع Storage وFirestore Emulator.

## 4. رسوم حجز غير الأعضاء

مخطط رسم الحجز أصبح يدعم:

```text
organizations/{organizationId}/charges/{chargeId}
  accountType: member | guest
  userId: Firebase Auth uid
  membershipId: membership id للعضو، أو null للمستأجر
  bookingId: booking id
  organizationId
  chargeType: booking
  sourceId: bookingId
  idempotencyKey: canonical deterministic key
```

- لا توجد عضوية وهمية.
- يشترط الحجز مستخدم Firebase Auth معروفًا.
- يقرأ `membershipForUser` خادميًا ثم يعيد قراءة العضوية داخل transaction قبل اختيار الرسم.
- المفتاح canonical يحافظ على مفاتيح الأعضاء القديمة، ويستخدم هوية `guest:{userId}` للمستأجر.
- `feeMode=free` و`feeMode=subscription` والمبلغ صفر لا تنشئ رسمًا.
- إعادة اعتماد الحجز لا تنشئ رسمًا ثانيًا.
- Firestore Rules تسمح للمستأجر بقراءة رسمه فقط، ولا تمنحه حساب عضو أو دليل الأعضاء.
- `submitGuestBookingReceipt` يقبل رسم الحجز المملوك للمستخدم نفسه فقط، ويمنع تمرير رسم عضو أو مجلس آخر أو دفع زائد.
- اعتماد الإيصال يستخدم مسار المراجعة الذري نفسه، ويحدث الرسم جزئيًا أو كليًا ويرسل الإشعارات.

اختبارات Emulator أثبتت رسم العضو 2500 بيسة، ورسم غير العضو 4000 بيسة، والخصوصية بين المستخدمين والمجالس، وعدم الإنشاء في الوضع المجاني أو المبلغ صفر، والتسديد الجزئي، ومنع بحث المستأجر في الدليل، ومنع دفعه عن رسم عضو.

## 5. إلغاء الحجز

- `pending`: المالك فقط يلغي مباشرة.
- `approved`: يتحول إلى `cancellationRequested` ولا يلغى ماليًا بصمت.
- الإدارة ذات `bookings.manage` أو `bookings.approve` أو full access تقبل أو ترفض.
- الرفض يعيد الحجز إلى `approved` ولا يغير الرسم.
- القبول يحول الرسم غير المدفوع إلى `cancelled`، وأي رسم `partial` أو `paid` إلى `refundRequired`.
- لا يحدث استرداد تلقائي، ولا حذف لـcharge أو transaction.
- كل قرار ينتج audit خادميًا وإشعارًا لصاحب الحجز.
- سباق مديرين: transaction واحدة فقط تنجح، والثانية تتلقى `failed-precondition`.
- لا تتاح معالجة الطلب نفسه مرتين، ولا يستطيع مستخدم آخر طلب الإلغاء.
- توفر التاريخ يتغير فقط بعد وصول الحجز إلى `cancelled` المعتمد، وليس عند مجرد طلب الإلغاء.

اختُبرت حالات pending، وطلب إلغاء approved، والرفض، وقبول رسم غير مدفوع، وقبول رسم جزئي وتحويله إلى `refundRequired`، وسباق مديرين، ومحاولة مستخدم آخر.

## 6. رسوم المناسبات

جرى البحث في `lib` و`functions` والقواعد. لا يوجد lifecycle إنتاجي واضح لإنشاء/حجز مناسبة مالية؛ الموجود هو حقل الإعداد وبعض سجلات عامة باسم events لا تمثل مسار حجز مناسبة قابلًا للربط المالي. لم يُضف كود ميت. يبقى `eventBookingFeeBaisa` محفوظًا وغير مستخدم حتى بناء lifecycle فعلي وتحديد نقطة إنشاء/رفض/إلغاء المناسبة. لهذا السبب لا تعتبر الميزة مكتملة ولا تصبح المهمة 100%.

## 7. App Check

- أُنشئت `project-brain/APP_CHECK_ACTIVATION_PLAN.md`.
- حصرت الخطة دوال البحث، والرسوم القابلة للدفع، وإرسال ومراجعة الإيصالات، والإدارة المالية، والحجز والإلغاء، والتنظيف.
- توثق Android Play Integrity وiOS App Attest/DeviceCheck وdebug tokens للتطوير وEmulator والتفعيل التدريجي والـrollback.
- لم يُضف token أو مفتاح.
- لم يُفعّل `enforceAppCheck=true`، ولم يتغير سلوك الإنتاج الحالي.
- جميع الدوال الحساسة ما زالت تتحقق من Auth والمجلس والملكية والصلاحية خادميًا دون الاعتماد على App Check.

## 8. Node 20 وحزم Functions

- `functions/package.json` يحتوي `engines.node = 20`.
- أضيفت `.nvmrc` بقيمة `20`.
- لم يوجد `nvm` أو `fnm` أو `Volta` أو Node 20 مثبتًا محليًا.
- Node الموجود هو `v24.18.0`؛ لذلك اختبارات Functions وEmulator الحالية ناجحة وظيفيًا لكنها **ليست دليل التوافق النهائي مع Node 20**.
- لم يُثبت إصدار عالمي ولم تُرقّ الحزم.
- Firebase Functions Emulator حذر من اختلاف Node 20 عن Node 24.
- الإصدار المقفل لـ`firebase-functions` هو 5.1.1 وتظهر أداة Firebase رسالة أنه قديم. يجب تنفيذ ترقية منفصلة في فرع مستقل، مع مراجعة breaking changes واختبارات Node 20 وEmulator؛ لم تُنفذ الترقية في هذه الجولة.

## 9. QA الهاتف وبيئة Emulator في Flutter

- الملف `lib/core/firebase/firebase_emulator_config.dart` يقرأ:
  - `USE_FIREBASE_EMULATORS=true`
  - `FIREBASE_EMULATOR_HOST`
  - منافذ Auth وFirestore وFunctions وStorage الاختيارية.
- يفشل startup بوضوح إذا طُلب Emulator بلا host.
- يرفض Emulator في release.
- لا يوجد LAN IP ثابت ولا تعطيل SSL للإنتاج.
- `10.0.2.2` مدعوم بتمريره من الأمر، والهاتف الحقيقي يستخدم LAN IP يمرر من الأمر.
- Notification/FCM initialization لا يعمل في وضع Emulator حتى لا يصل إلى خدمة FCM غير المحاكية.
- يظهر شريط debug «بيئة اختبار محلية» ولا يظهر في release.
- أُنشئت `project-brain/FINANCIAL_DEVICE_QA_CHECKLIST.md` بكل السيناريوهات المطلوبة وتحذير Huawei P40.
- لم يُشغل `flutter run` ولم يُستخدم هاتف أو بيانات إنتاج.

## 10. تجهيز staging

- أُنشئت `project-brain/STAGING_FINANCIAL_CHECKLIST.md`.
- أُنشئ `scripts/validate-financial-staging.ps1`؛ يطلب project ID صريحًا، ويرفض `alrahmat-console` قبل أي اتصال، ولا ينفذ deploy أو migration أو project switch، ويتحقق فقط من الملفات وCLI والحساب وظهور مشروع staging.
- اختُبر حاجز الإنتاج محليًا وأثبت رفض `alrahmat-console`.
- أضيفت فهارس حجوزات المستخدم حسب التاريخ، وتوفر الحجز حسب الحالة والتاريخ.
- لم يُنشأ مشروع staging ولم تُبن الفهارس ولم يُنشر شيء.

## 11. إعدادات Claude وGit

- `.claude/settings.json` صالح ويحتوي قواعد أوامر محددة، ولا توجد قاعدة عامة `node -e`.
- `.claude/settings.local.json` صالح، ولا تظهر فيه أنماط أسرار معروفة، ولا توجد قاعدة `Bash(node -e ...)`.
- الملف المحلي موجود في `.gitignore`.
- الملف **ما زال tracked في Git** من تاريخ سابق؛ لم يُنفذ `git rm --cached` التزامًا بالحدود.
- الأمر المقترح لاحقًا بعد مراجعة المستخدم:

```powershell
git rm --cached .claude/settings.local.json
```

- أضيف `.firebase-cli-config/` إلى `.gitignore`؛ استُخدم محليًا فقط لتجاوز منع قراءة config الشخصي أثناء Emulator، ولا يحتوي تغييرات مشروع أو deploy.
- ملف `.gradle/9.3.0/fileHashes/fileHashes.lock` كان معدّلًا قبل الجولة وبقي دون تعديل أو تنظيف من Codex.

## 12. الملفات المعدلة أو المنشأة في هذه الجولة

### Functions وFirebase

- `functions/financial.js`
- `functions/financial_core.js`
- `functions/financial_emulator.test.js`
- `firestore.rules`
- `storage.rules`
- `firestore.indexes.json`

### Flutter

- `lib/core/firebase/firebase_emulator_config.dart` — جديد.
- `lib/data/models/booking_model.dart`
- `lib/data/repositories/booking_repository.dart`
- `lib/data/services/storage_service.dart`
- `lib/presentation/screens/member/council_booking_screen.dart`
- `lib/presentation/screens/member/guest_booking_receipt_screen.dart` — جديد.
- `lib/presentation/screens/admin/booking_requests_review_screen.dart`
- `lib/providers/app_providers.dart`
- `lib/router/app_router.dart`
- `lib/main.dart`

### التشغيل والتوثيق

- `.nvmrc` — جديد.
- `.gitignore`
- `scripts/validate-financial-staging.ps1` — جديد.
- `project-brain/APP_CHECK_ACTIVATION_PLAN.md` — جديد.
- `project-brain/FINANCIAL_DEVICE_QA_CHECKLIST.md` — جديد.
- `project-brain/STAGING_FINANCIAL_CHECKLIST.md` — جديد.
- `project-brain/tasks.json`
- `project-brain/PROJECT_DASHBOARD.md` — مولد بواسطة السكربت، لا تعديل يدوي.
- `project-brain/CODEX_PRE_STAGING_REPORT_AR.md` — هذا التقرير.

بقية الملفات الظاهرة في `git status` تشمل أعمال المرحلة المالية السابقة وتعديلات مستخدم محلية؛ حُفظت ولم يُستخدم reset أو checkout.

## 13. نتائج الاختبارات

| الاختبار | النتيجة |
|---|---:|
| `dart format` للملفات المعدلة | ناجح |
| `flutter analyze` | ناجح، 0 مشكلة |
| `flutter test` | 22 ناجح، 0 فاشل |
| `npm.cmd test` | 11 ناجح، 0 فاشل |
| Firebase Emulator: Functions + Firestore + Storage | 14 ناجح، 0 فاشل |
| scheduled production handlers ضد Firestore Emulator | ناجح ضمن اختبارات Emulator |
| Storage sweep production handler ضد Storage/Firestore Emulator | ناجح ضمن اختبارات Emulator |
| `node --check` لملفات Functions وmigration | ناجح، 0 خطأ |
| JSON: indexes وfirebase وtasks وإعدادات Claude | صالح |
| `git diff --check` | ناجح، لا أخطاء whitespace |
| حاجز سكربت staging ضد `alrahmat-console` | ناجح: رفض المشروع |

المجموع العددي للاختبارات: **47 ناجح، 0 فاشل**.
ملاحظة مهمة: شُغلت اختبارات Node على Node 24 لعدم توفر Node 20، ويجب تكرارها على Node 20 قبل staging. trigger المجدول نفسه لم يعمل في Emulator لغياب Pub/Sub، بينما handler الإنتاجية نفسها اختُبرت.

## 14. النسبة الحقيقية للمهمة

النسبة: **92%، والحالة `in_progress`**.

لم تُرفع إلى 100% لأن المتبقي ليس تجميليًا:

- تشغيل Functions وEmulator على Node 20.
- QA فعلي على Android وiOS/جهاز مناسب.
- إنشاء مشروع staging مستقل ومراجعة إعداداته.
- نشر الفهارس إلى staging وانتظار بنائها واختبار الاستعلامات.
- تشغيل migration dry-run ثم rehearsal على staging بعد نسخة احتياطية وموافقة مستقلة.
- اختبار Cloud Scheduler/Pub/Sub trigger الحقيقي بعد نشر staging.
- تفعيل App Check تدريجيًا في staging ثم التحقق من Android وiOS.
- بناء lifecycle المناسبات قبل تفعيل رسومها.
- مراجعة مستقلة لإصدار `firebase-functions` وخطة ترقيته.

## 15. ما بقي قبل staging

1. توفير Node 20 محليًا ثم إعادة `npm test` وEmulator.
2. إنشاء Firebase staging منفصل وإضافة تطبيقات staging.
3. تنفيذ قائمة staging، ونشر القواعد والفهارس والدوال إلى staging فقط بعد موافقة صريحة.
4. انتظار الفهارس واختبار الاستعلامات الفعلية.
5. تشغيل migration dry-run ومقارنة أعداد السجلات وإجماليات الريال والبيسة.
6. تنفيذ QA الهاتف عبر Emulator config الجديد.
7. اختبار scheduled triggers وStorage sweep trigger فعليًا في staging.

## 16. ما بقي قبل production

- نجاح staging كامل وmigration rehearsal والنسخة الاحتياطية والـrollback drill.
- مراجعة أمنية مستقلة لقواعد Firestore وStorage وcallables.
- تفعيل App Check تدريجيًا ومراقبة المقاييس.
- نجاح Push على جهاز يدعم Google Play Services وعلى iOS.
- توقيع QA على الحسابات متعددة المجالس والحجوزات والإلغاء والإيصالات الجماعية.
- قرار واضح بشأن lifecycle المناسبات وترقية `firebase-functions`.
- موافقة صريحة مستقلة على deploy وعلى migration production.

## 17. أوامر مستقبلية مقترحة — لم تُنفذ

### Node 20

```powershell
# بعد تثبيت مدير إصدارات بموافقة المستخدم
nvm use 20
node --version
cd functions
npm ci
npm test
cd ..
```

### Emulator

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:PATH="$env:JAVA_HOME\bin;$env:PATH"
firebase emulators:exec --project demo-financial-prestaging --only firestore,storage,functions "cd functions && npm run test:emulator"
```

### تحقق staging غير الكاتب

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-financial-staging.ps1 -ProjectId <STAGING_PROJECT_ID>
```

### migration dry-run على staging فقط

```powershell
node .\scripts\migrate-financial-v1.js --project <STAGING_PROJECT_ID>
```

### نشر staging بعد موافقة صريحة فقط

```powershell
firebase deploy --project <STAGING_PROJECT_ID> --only firestore:rules,firestore:indexes,storage,functions
```

### تطبيق migration على staging بعد نسخة احتياطية وموافقة مستقلة فقط

```powershell
node .\scripts\migrate-financial-v1.js --project <STAGING_PROJECT_ID> --apply --confirm APPLY:<STAGING_PROJECT_ID>
```

## 18. تأكيدات السلامة

- **لم يتم تنفيذ Firebase deploy.**
- **لم يتم تنفيذ migration حقيقي.**
- **لم تتغير بيانات production أو staging.**
- **لم يُستخدم `alrahmat-console` لأي اختبار كتابة.**
- **لم يتم إنشاء مشروع staging أو الكتابة إليه.**
- **لم يتم تنفيذ git commit أو git push.**
- **لم يُستخدم git reset أو checkout أو git rm --cached.**
- **لم يُفعّل أي مزود دفع، وبقي `onlinePaymentsEnabled=false`.**
- **لم تُضف أسرار أو tokens أو مفاتيح دفع.**
- **لم يُشغل التطبيق على هاتف متصل.**
