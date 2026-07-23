# دليل تشغيل النشر الإنتاجي — مسودة غير منفذة

**الحالة:** غير مصرح بالتنفيذ؛ يستخدم فقط بعد تحول تقرير الجاهزية إلى GO.
**المشروع الإنتاجي:** `alrahmat-console`
**المنطقة:** `us-central1`
**قاعدة السلامة:** لا تعتمد مطلقًا على default في `.firebaserc`؛ كل أمر يجب أن يحمل project ID صريحًا ويُراجَع بواسطة شخصين.

## تحديث ما قبل التشغيل — 23 يوليو 2026

هذا القسم يصف ما جُهز محليًا؛ **لم يُنفذ أي أمر أدناه**. يبقى الدليل محظورًا حتى
تحول تقرير الجاهزية إلى GO.

### App Check بالتدرج

1. تسجيل تطبيق Android ذي `applicationId=com.alrahmat.village_council` وإضافة
   SHA-256 لشهادة upload المعتمدة، دون نسخ مفتاح أو token إلى Git.
2. بناء نسخة staging موقعة بهوية staging وتشغيل Play Integrity، ثم مراقبة App
   Check metrics للطلبات الشرعية والفاشلة مدة متفقًا عليها.
3. تفعيل enforcement على callables الحساسة في staging فقط والتحقق من المالية
   والحجوزات والإشعارات والعضو والضيف. كود هذه الدوال يطلب الآن
   `enforceAppCheck=true`.
4. معالجة false positives، ثم طلب موافقة مستقلة قبل تسجيل production أو فرضه.
5. يمنع استخدام Debug provider في Release أو إدخال debug token ثابت في Git.

### تشغيل المجدولات وإيقافها

تستخدم الدوال ملف Firebase dotenv محليًا مستبعدًا من Git؛ القالب الآمن هو
`functions/.env.example`. عند غياب أي قيمة تكون الكتابة متوقفة، وdry-run مفعّل.

المفاتيح:

- `FINANCIAL_SCHEDULES_ENABLED`: بوابة مشتركة؛ يجب أن تبقى `false` أول نشر.
- `FINANCIAL_SCHEDULE_DRY_RUN`: تبقى `true` حتى اعتماد counts من staging.
- `FINANCIAL_SCHEDULE_GENERATE_SUBSCRIPTIONS_ENABLED`.
- `FINANCIAL_SCHEDULE_MARK_OVERDUE_ENABLED`.
- `FINANCIAL_SCHEDULE_CLEANUP_ORPHANS_ENABLED`.
- `FINANCIAL_SCHEDULE_EXPIRE_RECEIPTS_ENABLED`.

ترتيب التفعيل: انشر وهي كلها disabled، تحقق من وجود jobs دون تشغيل يدوي، فعّل
مهمة واحدة في staging مع dry-run، وتحقق من `task/runId/status=dry-run/writes=0`،
ثم اسمح بالكتابة لها وحدها على بيانات staging صناعية وراجع counts. عند الشذوذ
أعد البوابة المشتركة إلى `false` وانشر إعداد
الإيقاف المعتمد؛ لا تشغّل الوظيفة يدويًا لمحاولة التعويض.

### جرد البيانات والترحيل

أداة الجرد `scripts/inspect-firestore-readiness.js` read-only وتطبع counts وحالات
schema فقط. ترفض الإنتاج افتراضيًا. تشغيلها على production يحتاج تصريحًا منفصلًا
وعَلَمين صريحين موثقين داخل السكربت؛ لا تستخدمهما قبل نسخ احتياطي ومراجعة الأمر.
ابدأ دائمًا على clone/staging معزول، ثم راجع:

- عضويات `membershipId != userId`، وأدوار owner legacy.
- حجوزات نشطة بلا `bookingDay/resourceId/slotKey` أو تعارض slot.
- الرسوم والحسابات والدليل المالي والمعاملات legacy حسب المجلس.
- أي اختلافات schema دون طباعة اسم أو هاتف أو IBAN أو مبالغ فردية.

`migrate-financial-v1.js` يعمل dry-run افتراضيًا ويولّد manifest before/after داخل
`migration-manifests/` المستبعد. أي apply ممنوع بلا manifest وموافقة ونسخة
احتياطية. التراجع المتماثل هو `rollback-financial-v1.js` ويُختبر على clone أولًا.

### Android Release

- لا يوجد fallback إلى debug signing. وفر محليًا `android/key.properties` أو
  متغيرات `VC_RELEASE_STORE_FILE`, `VC_RELEASE_STORE_PASSWORD`,
  `VC_RELEASE_KEY_ALIAS`, `VC_RELEASE_KEY_PASSWORD` وفق `key.properties.example`.
- قبل التوقيع: اعتمد versionName/versionCode بدل القيمة الحالية `1.0.0+1`، وثّق
  مالك المفتاح والاسترجاع وSHA-256، ثم ابنِ AAB في بيئة نظيفة قابلة لإعادة الإنتاج.
- artifact المحلي الحالي غير موقع ومخصص لإثبات compile فقط؛ يمنع تثبيته أو رفعه.
- R8/ProGuard غير مفعّل مخصصًا، وMainActivity الفعلي يتبع namespace الحالي؛ لا
  تغيّر أيًا منهما دون فشل build موثق ومهمة مستقلة.

### ترتيب النشر المقترح وشروط التوقف

1. نسخة احتياطية واختبار restore، ثم inventory على clone: توقف عند أي تعارض غير
   مفسر أو غياب manifest.
2. Indexes: انتظر اكتمال البناء وتحقق من الاستعلامات على staging.
3. Functions وهي مقفلة مجدوليًا، مع App Check على staging: توقف عند 5xx أو رفض
   عميل شرعي أو انحراف counts.
4. Firestore Rules ثم Storage Rules في staging: نفذ مصفوفة السماح/المنع كاملة،
   خصوصًا الإشعارات والملف المالي والمالك والحجوزات.
5. إن احتاجت البيانات migration، نفذها في نافذة مستقلة بعد backup وdry-run؛ لا
   تجمعها مع أول نشر Rules/Functions.
6. Android signed staging ثم smoke QA؛ بعد جميع الموافقات فقط يكون production
   rollout تدريجيًا. لا يُحذف مسار legacy في نافذة الإطلاق الأولى.

## 1. شروط البدء الإلزامية

يُمنع بدء هذا الدليل ما لم تتحقق جميع الشروط:

- إغلاق كل CRITICAL/HIGH blocker في `PRE_PRODUCTION_READINESS_REPORT_AR.md` وإعادة البوابات.
- Commit مراجع وموقع/tagged، وشجرة Git نظيفة باستثناء ملفات محلية معلنة.
- نجاح APK/AAB Release موقّع رسميًا، وتطابق package وSHA وFirebase app.
- نجاح staging حقيقي، بما في ذلك Scheduler/Pub/Sub وApp Check metrics ثم enforcement المخطط.
- جرد بيانات production مصرح به من snapshot/clone، وقرار migration مكتوب.
- نسخة احتياطية مكتملة ومتحقق من قابليتها للاسترجاع.
- نافذة صيانة، مالك قرار GO، مالك rollback، قناة تواصل، وحدود زمنية للتوقف.
- budgets/alerts وquotas وbilling/APIs المطلوبة للدوال المجدولة وFirestore export مؤكدة.

## 2. متغيرات الجلسة المقترحة

الأوامر أدناه أمثلة مستقبلية **ولم تُنفذ**. لا تستخدم قيمة ضمنية:

```powershell
$ProductionProject = 'alrahmat-console'
$ExpectedProject = 'alrahmat-console'
$ReleaseCommit = '<FULL_APPROVED_COMMIT_SHA>'
$BackupBucket = 'gs://<DEDICATED-BACKUP-BUCKET>/<UTC-TIMESTAMP>'

if ($ProductionProject -ne $ExpectedProject) {
  throw 'Production project mismatch.'
}
if ((git rev-parse HEAD).Trim() -ne $ReleaseCommit) {
  throw 'Git HEAD does not match the approved release commit.'
}
```

لا تُضبط `GOOGLE_APPLICATION_CREDENTIALS` على fallback داخل `local_keys`. استخدم هوية تشغيل قصيرة العمر ومصرحًا بها، ولا تطبع token أو مسار مفتاح في التقرير.

## 3. Preflight غير كاتب

بعد موافقة مستقلة على قراءة إعدادات production فقط:

```powershell
git status --short --branch
git log -3 --oneline --decorate
firebase --version
firebase projects:list
firebase use
```

شروط التوقف:

- HEAD أو tag غير مطابق.
- ظهور ملفات staged أو تغييرات كود غير معتمدة.
- جلسة Firebase لا تعرض المشروع المتوقع.
- نقص billing أو API أو quota أو صلاحية backup.
- أي اختلاف غير موثق بين ملفات Firebase المحلية والمنشورة.

## 4. النسخ الاحتياطي قبل النشر

### 4.1 Firestore

Managed export المقترح بعد الموافقة:

```powershell
gcloud firestore export $BackupBucket `
  --database='(default)' `
  --project=$ProductionProject
```

ثم سجل operation ID وتحقق حتى `SUCCESS`. التصدير يكلف read لكل document وليس snapshot لحظيًا تامًا؛ استخدم نافذة هادئة أو PITR timestamp عند توفره، ثم اختبر restore إلى مشروع معزول.

### 4.2 Authentication

```powershell
firebase auth:export '<ENCRYPTED-LOCAL-OR-SECURE-BUCKET-PATH>' `
  --project $ProductionProject `
  --format=json
```

ملف Auth شديد الحساسية: يُشفر، يقيد الوصول إليه، لا يدخل Git، ويُتلف وفق retention policy بعد التحقق.

### 4.3 Storage

- تحقق أولًا من soft-delete retention أو Object Versioning على bucket.
- التقط inventory بأسماء/أعداد وأجيال objects دون محتوى إيصالات في التقرير.
- إن كانت السياسة غير كافية، انسخ إلى bucket احتياطي مستقل مع retention lock مناسب بعد موافقة منفصلة.
- لا تغير versioning ثم تحذف/تستبدل مباشرة؛ وثائق Google تشير إلى انتظار انتشار الإعداد.

### 4.4 إعدادات قابلة لإعادة البناء

- احتفظ بنسخة release من `firestore.rules` و`storage.rules` و`firestore.indexes.json` وFunctions source وlockfiles.
- صدّر/وثق Auth providers وauthorized domains وApp Check registrations وSHA fingerprints وFCM/APNs وScheduler jobs وruntime env دون أسرار.
- سجل أسماء الدوال والجدولة والregion والruntime قبل النشر.

شروط التوقف: backup ناقص، operation غير ناجح، restore test غير ناجح، أو لا توجد صلاحية استرجاع مثبتة.

## 5. ترتيب النشر الآمن

### المرحلة 1 — الفهارس فقط

```powershell
firebase deploy `
  --project $ProductionProject `
  --only firestore:indexes
```

- انتظر حتى تصبح كل الفهارس المطلوبة `READY`.
- نفذ read-only query smoke checks المصرح بها.
- لا تنشر التطبيق أو قواعد تعتمد على فهرس ما زال building.

**توقف إذا:** فشل index، تجاوز build النافذة، أو ظهر حذف index غير مخطط.

### المرحلة 2 — Functions غير المجدولة على دفعات

انشر additive callables/triggers المطلوبة في مجموعات لا تتجاوز 10، وبأسماء صريحة. لا تنشر المجدولات بعد:

```powershell
firebase deploy `
  --project $ProductionProject `
  --only functions:<NAME_1>,functions:<NAME_2>
```

الترتيب الداخلي المقترح:

1. callables القراءة المنقحة: availability، payable charges، receipt access.
2. callables الكتابة المالية بعد App Check: submit/review/config/cancellation.
3. audit وdirectory وbooking lifecycle triggers.
4. financial notification outbox وFCM trigger بعد إغلاق client fan-out.

بعد كل دفعة:

- افحص revision health وerror rate والlatency وcold starts وinvocation count.
- نفذ canary بحسابات production اختبارية مصرح بها داخل مجلس اختبار مخصص فقط.
- تحقق من عزل مجلسين ورفض غير المخول.

**توقف إذا:** 401/403 غير متوقعة، 5xx، تضاعف invocation، إنذارات تكلفة، كتابة مالية غير متوقعة، أو إشعار يصل لمستلم خاطئ.

### المرحلة 3 — Storage Rules

بعد إثبات أن فتح الإيصال للمراجع يمر عبر callable الآمن وأن legacy path محسوم:

```powershell
firebase deploy `
  --project $ProductionProject `
  --only storage
```

تحقق من:

- owner upload/read.
- reviewer access عبر callable فقط.
- منع مستخدم مجلس آخر.
- منع update/delete للمسار الجديد.
- قرار موثق للمسار legacy.

### المرحلة 4 — Firestore Rules

بعد إصلاح قواعد الإشعارات وfinancial profile والمالك وعقد membership:

```powershell
firebase deploy `
  --project $ProductionProject `
  --only firestore:rules
```

تحقق فورًا من matrix:

- `system_owner` global override.
- primary owner محمي بكل الصيغ المعتمدة.
- chairman/admin/financial roles بحدود مجلسهم.
- العضو يرى نفسه و«حجوزاتي» فقط.
- الضيف يرى حجزة/رسمه فقط.
- لا client write للمستندات المالية أو notification fan-out.

### المرحلة 5 — Migration إن أثبت dry-run ضرورتها

لا تُنفذ migration لمجرد وجود السكربت. الترتيب:

1. restore backup إلى staging معزول.
2. dry-run ومراجعة counts/totals/skips.
3. apply staging ثم إعادة apply لإثبات idempotency.
4. اعتماد manifest والتراجع.
5. backup production جديد مباشرة قبل apply.
6. موافقة مكتوبة مستقلة على الأمر النهائي.

مثال dry-run staging فقط:

```powershell
node .\scripts\migrate-financial-v1.js `
  --project '<REAL-STAGING-PROJECT-ID>'
```

مثال production **بعد الموافقات فقط**:

```powershell
node .\scripts\migrate-financial-v1.js `
  --project $ProductionProject `
  --apply `
  --confirm "APPLY:$ProductionProject"
```

**توقف إذا:** skipped غير مفسر، فرق إجماليات، negative/unsafe integer، duplication، أو غياب manifest.

### المرحلة 6 — Scheduled Functions أخيرًا

انشر كل scheduled function منفردة بعد تأكيد البيانات:

- `generateSubscriptionChargesDaily`
- `markFinancialChargesOverdue`
- `cleanupOrphanFinancialReceipts`
- `expirePendingFinancialReceipts`

بعد النشر:

- تحقق من job وtimezone وservice identity.
- شغّل manual invocation على staging فقط قبل production.
- في production راقب أول دورة؛ لا تشغّل يدويًا دون موافقة.
- طابق counts مع توقعات الجرد، ولا تسمح بتشغيل المولد قبل تثبيت settings/plans/accounts.

### المرحلة 7 — Android Release أخيرًا

- AAB موقّع upload key الرسمي، وPlay App Signing مفعل وموثق.
- versionCode أعلى من أي إصدار منشور.
- فحص certificate SHA وpackage وFirebase project وApp Check token.
- نشر internal/closed track أولًا ثم staged rollout صغير.
- راقب crash-free users وANR وAuth وFunctions/Firestore errors وFCM.

**توقف/أوقف rollout إذا:** crash/ANR يتجاوز الحد المعتمد، فشل Auth/App Check، permission-denied واسع، أو خلل مالي/عزل.

## 6. Post-deploy verification

نفذ بالترتيب وببيانات اختبار إنتاجية مصرح بها فقط:

1. login وفتح مجلس واحد ثم التبديل إلى مجلس ثانٍ دون تسرب.
2. صلاحيات system owner/primary owner/manager/member/guest.
3. availability و«حجوزاتي» وحجز/اعتماد واحد بلا تعارض.
4. رسم عضو ورسم ضيف ومبلغ بالبيسة يعرض بثلاث خانات.
5. إيصال صغير وهمي مصرح به: رفع، مراجعة، رفض، partial، approve، ومنع double approval.
6. cancellation و`refundRequired` دون استرداد تلقائي.
7. FCM إلى المستلم الصحيح فقط، ومنع إنشاء إشعار غير مخول.
8. audit append-only وسلامة actor/organizationId.
9. مراقبة logs دون PII أو receipt URLs/tokens.

## 7. بوابات القرار أثناء النافذة

- مالك النشر يعلن GO لكل مرحلة منفصلة.
- أي blocker يفعّل `PRODUCTION_ROLLBACK_PLAN_AR.md` للمكوّن المتأثر فقط.
- لا تواصل إلى المرحلة التالية بحجة أن rollback متاح.
- لا تُحذف functions أو indexes قديمة في نفس نافذة الإطلاق؛ cleanup في نافذة لاحقة بعد الاستقرار.

## 8. ما لم يُنفذ في إعداد هذا الدليل

- لا backup/export.
- لا deploy.
- لا migration/dry-run production.
- لا IAM/Secrets/App Check changes.
- لا Play Console upload.
