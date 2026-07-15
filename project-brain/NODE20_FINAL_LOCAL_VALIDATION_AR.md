# تقرير التحقق المحلي النهائي باستخدام Node 20

**التاريخ:** 15 يوليو 2026
**الفرع:** `main`
**النتيجة النهائية:** متوقف قبل إنشاء الـ commit المحلي لأن بوابة Node.js 20 لم تصبح قابلة للتنفيذ داخل البيئة الحالية.

## 1. الخلاصة التنفيذية

بدأت الجولة بفحص تعليمات المشروع، التقارير السابقة، حالة Git، الفروق الحالية، والملفات غير المتتبعة. حافظت على جميع التغييرات المالية والأمنية الموجودة ولم أستخدم أوامر Git مدمّرة.

تعذر اعتماد الجولة نهائيًا للأسباب الآتية:

1. الإصدار المتاح على الجهاز هو `v24.18.0`، ولا توجد نسخة Node 20 محلية عبر `nvm` أو `fnm` أو Volta أو Docker أو Podman أو ذاكرة `npx` المحلية.
2. حُددت النسخة الرسمية المحمولة `v20.20.2` وملف checksums الرسمي، لكن اتصال PowerShell بـ `nodejs.org` محجوب داخل البيئة، كما رفضت سياسة المتصفح المحلية تنزيل الملف. لذلك لم يمكن تنزيل الأرشيف والتحقق من SHA-256 وتشغيله.
3. بوابة Flutter الرسمية لم تكتمل لأن Flutter SDK موجود خارج المسار القابل للكتابة. مشغل Flutter يحاول إنشاء `flutter.bat.lock` و`bin/cache/lockfile` و`libimobiledevice.stamp` داخل SDK، وهو ما تمنعه صلاحيات البيئة الحالية.
4. تعذر تعديل Git index لإيقاف تتبع `.claude/settings.local.json` لأن `.git/index.lock` غير قابل للإنشاء في هذه البيئة.

بناءً على الشروط الصريحة، **لم أنشئ commit محليًا** ولم أستخدم Node 24 كدليل نهائي لتوافق Functions.

## 2. حالة Node.js 20

- `functions/package.json` يحدد `engines.node = 20`.
- `.nvmrc` يحتوي `20`.
- إصدار Node الفعلي المتاح: `v24.18.0`.
- النسخة الرسمية المستهدفة: `node-v20.20.2-win-x64.zip`.
- قيمة SHA-256 المنشورة في `SHASUMS256.txt` الرسمي:
  `dc3700fdd57a63eedb8fd7e3c7baaa32e6a740a1b904167ff4204bc68ed8bf77`.
- فشل التنزيل عبر PowerShell بسبب حظر الاتصال الخارجي.
- فشل التنزيل عبر المتصفح بسبب سياسة الأمان المحلية للتنزيل.
- لم يُنفذ `npm ci` تحت Node 20.
- لم تُشغّل Functions أو Firebase Emulator تحت Node 20.

هذه النتيجة تعني أن شرط إثبات `node --version` بقيمة تبدأ بـ `v20` داخل الاختبارات وداخل Functions Emulator **غير محقق**.

## 3. نتائج الاختبارات

### اختبارات اجتازت

| البوابة | النتيجة | التفاصيل |
|---|---:|---|
| فحص تنسيق Dart | ناجح | 27 ملفًا، 0 ملف احتاج تعديلًا |
| `dart analyze --fatal-infos` | ناجح | 0 مشكلة |
| اختبارات Functions المساعدة | ناجح تكميليًا فقط | 11 ناجح، 0 فاشل تحت Node 24 |
| اختبارات Firebase Emulator | ناجح تكميليًا فقط | 14 ناجح، 0 فاشل تحت Node 24 على `demo-financial-prestaging` |
| `node --check` | ناجح تكميليًا فقط | 7 ملفات JavaScript، 0 فاشل تحت Node 24 |
| التحقق من JSON | ناجح | 7 ملفات، 0 فاشل |
| `git diff --check` | ناجح | لا توجد أخطاء whitespace |
| فحص أنماط الأسرار في الملفات المتغيرة | ناجح | 61 ملفًا، 0 تطابق لأنماط المفاتيح الخاصة أو tokens |

إجمالي اختبارات Node/Emulator المنفذة تكميليًا: **25 ناجحًا، 0 فاشل**. هذه الأرقام لا تستبدل بوابة Node 20 المطلوبة.

### بوابات لم تكتمل

| البوابة | الحالة | السبب |
|---|---|---|
| `npm ci` على Node 20 | غير منفذ | Node 20 غير متاح والتنزيل الرسمي محجوب |
| `npm test` على Node 20 | غير منفذ | نفس المانع |
| Emulator على Node 20 | غير منفذ | Functions Emulator أكد أنه استخدم Node 24 من المضيف |
| `flutter analyze` من Flutter CLI | غير معتمد | مشغل Flutter يحتاج كتابة lock/stamp خارج workspace |
| `flutter test` | غير منفذ | نفس مانع Flutter SDK |

أظهر Emulator صراحة التحذير التالي بمعناه: الإصدار المطلوب 20 لا يطابق الإصدار العام 24، ولذلك استخدم Node 24 من المضيف. كما أوضح أن scheduled triggers نفسها لم تعمل لعدم وجود Pub/Sub Emulator؛ الاختبارات استدعت handlers الإنتاجية ذاتها ضد Firestore Emulator.

## 4. نتيجة المراجعة المالية والأمنية

تمت مراجعة التنفيذ الفعلي في القواعد والدوال والمستودعات والشاشات، وليس التقارير فقط.

### ما ظهر سليمًا في المراجعة والاختبارات الحالية

- تقييد البيانات المالية بمسار `organizations/{organizationId}` والتحقق الخادمي من المجلس والمستفيد.
- منع القراءة والكتابة المباشرة للبيانات المالية الحساسة في Firestore Rules.
- منع listing المباشر لـ `member_directory`، وفرض البحث الخادمي بعد ثلاثة أحرف وبحد أقصى 10 نتائج في `functions/financial.js:748`.
- التحقق من المبلغ المعلن ومجموع allocations ومنع تكرار الرسم والدفع الزائد في `functions/financial.js:947`.
- الاعتماد والرفض داخل Firestore transaction مع إعادة قراءة الأرصدة ومنع الاعتماد المكرر في `functions/financial.js:1118`.
- pagination للدوال المجدولة واستخدام توقيت `Asia/Muscat` في `functions/financial.js:525`.
- دعم رسوم حجز العضو والضيف وحالة `refundRequired` وعدم تنفيذ استرداد تلقائي.
- تنظيف الإيصالات المؤقتة القديمة مع metadata والتحقق من الارتباط وعدم الحذف عند خطأ Firestore في `functions/financial.js:1232`.
- بقاء `onlinePaymentsEnabled=false` و`onlinePaymentProvider=null`، وعدم تفعيل `enforceAppCheck`.
- رفض وضع Emulator في release، وطلب host صريح عند تفعيله في `lib/core/firebase/firebase_emulator_config.dart`.
- الحسابات الجديدة تستخدم أعدادًا صحيحة بالبيسة، واختبارات تحويل المبالغ والتسديد الجزئي نجحت ضمن المجموعة المتاحة.

### نقاط يجب إغلاقها قبل staging

1. `getPayableCharges` يضع حدًا صامتًا قدره 50 رسمًا لكل عضوية في `functions/financial.js:810`. قد يخفي رسومًا مفتوحة قديمة؛ يلزم pagination أو حد موثق مع اختبار يتجاوز 50 رسمًا.
2. صلاحية قراءة الإيصال للمراجع المالي في `storage.rules:105` تفترض أن معرف مستند العضوية يساوي `auth.uid`، بينما `membershipForUser` الخادمية تدعم `membershipId` مختلفًا عن `userId`. يلزم اختبار Emulator بمعرفين مختلفين، ثم توحيد نموذج العضوية أو تمرير القراءة عبر callable/Signed URL موثوق.
3. إشعارات إرسال الإيصال واعتماده تُكتب بعد اكتمال المعاملة المالية في batch مستقل. إذا نجحت المعاملة وفشل batch، قد تصبح الحالة المالية صحيحة مع فقد إشعار، وقد لا تعيد المحاولة إنشاءه. يلزم outbox أو trigger خادمي idempotent واختبار failure/retry.

لم تُعدّل هذه النقاط في هذه الجولة لأن بوابات Node 20 وFlutter غير متاحة، ولا يجوز إدخال إصلاحات مالية جديدة دون تشغيل مجموعة الاختبارات المطلوبة كاملة.

## 5. Firebase Emulator

- المشروع المستخدم: `demo-financial-prestaging` فقط.
- الخدمات: Firestore وStorage وFunctions Emulator.
- النتيجة التكميلية تحت Node 24: 14 ناجحًا، 0 فاشل.
- شملت المجموعة: العزل بين المجالس، قواعد العضو والمدير، البحث، منع الكتابة المباشرة، Storage Rules، سباق الاعتماد، rollback، pagination لأكثر من 200 حساب، توقيت مسقط، رسوم العضو والضيف، الإلغاء و`refundRequired`، وتنظيف الملفات اليتيمة.
- لم تُستخدم بيانات إنتاج أو staging.
- لم تعمل scheduled triggers عبر Pub/Sub Emulator؛ اختُبرت handlers الإنتاجية نفسها.

## 6. Git والـ commit

- الفرع الحالي: `main`.
- لم يُستخدم `git add -A`.
- لا توجد ملفات staged.
- لم يُنشأ commit، وبالتالي لا يوجد commit hash.
- رسالة الـ commit المطلوبة محفوظة للجولة التالية بعد نجاح البوابات:
  `feat(finance): complete secure pre-staging workflow`
- محاولة `git rm --cached .claude/settings.local.json` فشلت قبل تغيير الفهرس بسبب منع إنشاء `.git/index.lock`.
- الملف `.claude/settings.local.json` ما زال موجودًا محليًا وما زال tracked، ويوجد له نمط ignore صحيح في `.gitignore`.
- الأمر المطلوب لاحقًا في بيئة تسمح بكتابة Git index:
  `git rm --cached -- .claude/settings.local.json`
- ملف `.gradle/9.3.0/fileHashes/fileHashes.lock` بقي كما هو، ولم يُعدّل في هذه الجولة ولم يُضف إلى staging area.
- `.firebase-cli-config/` و`firestore-debug.log*` مستبعدان عبر `.gitignore`.

## 7. الملفات داخل الـ commit

لا توجد ملفات داخل commit لأن commit لم يُنشأ ولم تُجتز بوابات Node 20 وFlutter.

## 8. الملفات المتبقية خارج الـ commit

بقيت جميع تغييرات النظام المالي وFirebase والاختبارات والتوثيق خارج commit. تشمل المجموعات الرئيسة:

- `functions/financial.js` و`functions/financial_core.js` واختباراتهما.
- `firestore.rules` و`storage.rules` و`firestore.indexes.json`.
- نماذج ومستودعات وشاشات النظام المالي والحجوزات في `lib/`.
- إعداد Emulator الآمن في `lib/core/firebase/`.
- سكربت migration وسكربت فحص staging.
- وثائق Project Brain وقوائم QA وApp Check وstaging.
- `AGENTS.md` و`CLAUDE.md` و`.nvmrc`.
- هذا التقرير.

سبب الاستبعاد: لا يجوز إنشاء commit محلي وفق طلب المهمة قبل نجاح Node 20 وEmulator وFlutter بالكامل، كما أن Git index غير قابل للكتابة في البيئة الحالية.

## 9. حالة Project Brain

- بقيت المهمة المالية `TASK-004` بالحالة `in_progress` ونسبة **92%**.
- لم تُرفع إلى 100% بسبب Node 20 وQA الهاتف وstaging وApp Check ورسوم المناسبات واختبار trigger المجدول الحقيقي.
- شُغل `scripts/update-project-dashboard.ps1` بنجاح.
- النسبة الكلية التي عرضها Dashboard: 83%، والمهام المكتملة 2 من 4.

## 10. الخطوة المحلية التالية

شغّل الجولة التالية في بيئة تسمح بالوصول إلى `nodejs.org` وبالكتابة إلى Flutter SDK و`.git`، ثم:

1. نزّل Node 20 الرسمي المحمول خارج المستودع وتحقق من SHA-256.
2. اجعل PATH المؤقت يبدأ بمجلد Node 20، وتأكد من `node --version` داخل shell وداخل Emulator.
3. نفّذ `npm ci` و`npm test` واختبارات Emulator على المشروع الوهمي فقط.
4. نفّذ `flutter analyze` و`flutter test`.
5. أغلق نقاط المراجعة الثلاث أعلاه باختبارات regression.
6. نفّذ `git rm --cached -- .claude/settings.local.json`.
7. راجع الملفات staged بمسارات صريحة، ثم أنشئ commit المحلي المطلوب دون push.

## 11. التأكيدات الصريحة

- لم يُنفذ Firebase deploy.
- لم يُنفذ migration حقيقي أو dry-run على مشروع متصل.
- لم يُستخدم مشروع الإنتاج `alrahmat-console` في أي اختبار كتابة.
- لم تُنشأ أو تُعدّل بيئة staging.
- لم تتغير بيانات production أو staging.
- لم يُنفذ git commit أو git push.
- لم يُستخدم git reset أو checkout أو clean.
- لم يُفعّل App Check.
- لم يُفعّل أي مزود دفع إلكتروني.
- بقي `onlinePaymentsEnabled=false`.
- لم تُضف أسرار أو tokens أو مفاتيح.
- لم تُرقّ أي حزمة.
