# التقرير العربي النهائي — إغلاق مراجعة ما قبل staging الآمنة

**التاريخ:** 15 يوليو 2026
**الفرع:** `main`
**Node:** `v20.20.2`
**بيئة Firebase:** `demo-financial-prestaging` فقط
**الحكم:** نقاط المراجعة الثلاث مغلقة محليًا، وجميع بوابات التحقق المطلوبة ناجحة. لم يُنفذ deploy أو migration أو push.

## 1. الوضع الحالي

- أُضيفت pagination آمنة للرسوم القابلة للدفع ولم يعد أول 50 رسمًا حدًا صامتًا.
- أصبحت قراءة إيصال المراجع تمر عبر callable خادمية تتحقق من العضوية الفعلية عبر `userId` حتى لو اختلف `membershipId` عنه.
- أصبحت إشعارات الإيصالات جزءًا من outbox ذري داخل المعاملة المالية نفسها، مع trigger قابل لإعادة المحاولة وتسليم idempotent.
- أُزيل `.claude/settings.local.json` من Git index، وبقي الملف موجودًا محليًا وignored.
- حالة `TASK-004`: `in_progress` بنسبة 95%. لا تزال QA الأجهزة وstaging وApp Check ورسوم المناسبات خارج هذه الجولة.

## 2. السبب الجذري

1. كان `getPayableCharges` يستخدم `limit(50)` بلا cursor، فيخفي الرسوم التالية.
2. كانت Storage Rules تبحث عن العضوية في مستند معرفه `auth.uid`، بينما النموذج الفعلي يسمح بأن يكون معرف مستند العضوية مختلفًا عن `userId`.
3. كانت الإشعارات تُكتب في batch مستقل بعد نجاح المعاملة المالية؛ لذلك كان فشل batch يترك الحالة المالية صحيحة مع فقد الإشعار.

## 3. الحل

### Pagination

- token مشفر Base64URL ومربوط بإصدار الصيغة و`organizationId` وقائمة `membershipIds` المرتبة.
- cursor مستقل لكل عضوية، وحجم صفحة خادمي أقصاه 50.
- التحقق من scope وبنية token ورفض أي token غير مطابق.
- مستودع Flutter يتابع `nextPageToken` تلقائيًا، ويرفض token مكررًا أو أكثر من 1000 صفحة كحاجز أمان.

### صلاحية الإيصال

- القراءة المباشرة من Storage أصبحت لصاحب الملف فقط.
- `getFinancialReceiptDownloadUrl` يعيد رابط قراءة مدته خمس دقائق بعد التحقق الخادمي من صاحب الإيصال أو صلاحية المراجع عبر استعلام `membershipForUser` الفعلي.
- تتحقق الدالة أيضًا من تطابق المجلس ومعرف المعاملة والدافع ومسار Storage.

### Outbox الإشعارات

- تُنشأ مستندات `organizations/{organizationId}/financial_notification_outbox/{outboxId}` داخل نفس Firestore transaction التي ترسل أو تعتمد أو ترفض الإيصال.
- `deliverFinancialNotificationOutbox` يعمل مع `retry: true` وينقل payload داخل transaction إلى معرف إشعار ثابت.
- إذا تكرر trigger أو حدث retry بعد التسليم، لا يُنشأ إشعار أو Push ثانٍ.
- Firestore Rules تمنع العملاء من قراءة أو كتابة outbox.

## 4. الملفات المتأثرة في جولة الإغلاق

- `functions/financial.js`
- `functions/financial_emulator.test.js`
- `firestore.rules`
- `storage.rules`
- `lib/data/repositories/financial_repository.dart`
- `lib/presentation/screens/admin/financial_review_screen.dart`
- `.claude/settings.local.json` — أزيل من Git index فقط.
- `project-brain/tasks.json`
- `project-brain/08_DATABASE.md`
- `project-brain/10_CHANGELOG.md`
- `project-brain/PROJECT_DASHBOARD.md` — يولده السكربت.
- `project-brain/SECURE_PRE_STAGING_FINAL_REPORT_AR.md`

## 5. نتائج الاختبارات

| البوابة | النتيجة |
|---|---:|
| `node --version` في الطرفية | `v20.20.2` |
| Functions Emulator runtime | `Using node@20 from host` |
| `npm ci` | ناجح، 353 حزمة من lockfile |
| `npm test` | 11 ناجح، 0 فاشل |
| Firebase Emulator الكامل | 17 ناجح، 0 فاشل |
| `flutter analyze` | 0 مشكلة |
| `flutter test` | 22 ناجح، 0 فاشل |
| `node --check` | 7 ملفات ناجحة |
| JSON | 7 ملفات صالحة |
| فحص الأسرار | 60 ملفًا معدّلًا/جديدًا، 0 تطابق |
| `git diff --check` | ناجح، 0 خطأ whitespace |

**مجموع الاختبارات الآلية:** 50 ناجحًا، 0 فاشل.

اختبارات regression الجديدة أثبتت:

- استرجاع 62 رسمًا لعضوية واحدة، ومنها رسوم بعد أول 50.
- نجاح صلاحية المراجع عندما كان `membershipId=reviewer-membership-42` و`userId=reviewer-different`.
- بقاء outbox بحالة pending عند فشل مصطنع، ثم نجاح retry، ثم ثبات مستند إشعار واحد عند إعادة التنفيذ.

## 6. المخاطر والمتبقي

- `firebase-functions` المقفل قديم ويصدر Firebase CLI تحذيرًا؛ ترقيته تغيير مستقل يحتاج مراجعة breaking changes.
- شجرة الاعتماديات المقفلة تصدر تحذيرات deprecation لـ`uuid`؛ لم تُرقّ الحزم في هذه الجولة.
- scheduled triggers نفسها لا تعمل في Emulator دون Pub/Sub Emulator؛ handlers الإنتاجية اختُبرت مباشرة، ويبقى اختبار trigger الحقيقي في staging.
- يلزم QA فعلي على Android وiOS، ثم staging مستقل، وبناء الفهارس، وmigration rehearsal بعد نسخة احتياطية وموافقات منفصلة.
- لم يُفعّل App Check ولم يُبن lifecycle رسوم المناسبات؛ لذلك لا يجوز رفع المهمة إلى 100%.

## 7. الخطوة التالية

1. إنشاء commit محلي فقط بالرسالة المعتمدة بعد مراجعة staged diff.
2. تنفيذ QA الأجهزة وقائمة staging في مشروع مستقل بعد موافقة صريحة.
3. عدم تنفيذ deploy أو migration أو push قبل موافقات مستقلة.

## 8. تأكيدات السلامة

- لم يُستخدم `alrahmat-console`.
- لم يُنفذ deploy أو migration أو push.
- لم تتغير بيانات production أو staging.
- لم يُفعّل الدفع الإلكتروني أو App Check.
- بقي `onlinePaymentsEnabled=false`.
- لم تُضف أسرار أو مفاتيح.
- لم يُمس ملف `.gradle/9.3.0/fileHashes/fileHashes.lock` في هذه الجولة ولم يُجهز للـcommit.
