# تقرير جولة إصلاح النظام المالي والاشتراكات

**التاريخ:** 2026-07-15
**المشروع:** `village_council_app`
**حالة المهمة:** `TASK-004` قيد التنفيذ بنسبة **88%**
**قرار الجاهزية:** غير جاهز للنشر الإنتاجي أو لتنفيذ الترحيل الحقيقي قبل إكمال الموانع المذكورة في نهاية التقرير.

## 1. الوضع الحالي والسبب الجذري والحل

أكد الفحص أن الملاحظات الحرجة الأساسية صحيحة: سكربت الترحيل كان يخلط بين الأعداد الصحيحة بالريال والبيسة، ومولد الرسوم كان يتوقف عند 2000 سجل، والتاريخ كان محسوبًا بـUTC رغم جدولة الدالة بتوقيت مسقط، وإرسال إيصال عن عضو آخر كان يغيّر حالة رسمه مباشرة إلى `pendingReview`، والبحث كان يسمح للعميل بقراءة دليل الأعضاء، وعمليات الإدارة المالية كانت تكتب مباشرة من Flutter.

تم فصل المنطق المالي الخالص في `functions/financial_core.js` واستخدامه من كود الإنتاج والاختبارات. كما نُقلت العمليات الحساسة إلى Cloud Functions، وأصبح الإرسال والمراجعة ذريين وقابلين لإعادة المحاولة، وشُددت قواعد Firestore وStorage، وأضيفت اختبارات Emulator تستخدم معالجات الإنتاج الفعلية.

## 2. نتيجة كل ملاحظة من تقرير Claude

| الرمز | التحقق | الإصلاح والحالة | دليل الملف والسطر | الاختبار المثبت |
|---|---|---|---|---|
| C1 | تأكد خطأ تحويل `amount=5` إلى 5 بيسات | أُصلح: فصل `legacyOmaniRialsToBaisa` عن `readBaisaField`، ورفض القيم المفقودة المطلوبة والسالبة وNaN وInfinity، ومنع `--apply` دون مشروع وتأكيد مطابق | `functions/financial_core.js:12`، `functions/financial_core.js:23`، `scripts/migrate-financial-v1.js` | Node: تحويل 5 و10 و5.5، بقاء 5000 بيسة، القيم غير الصالحة، وعدم إنشاء batch في dry-run |
| C2 | تأكد سقف 2000 والمعالجة التسلسلية | أُصلح: pagination حتى النهاية، صفحات 200، تزامن محدود، فشل صريح، إحصاءات، timeout 540 وذاكرة 512MiB و`maxInstances=1` | `functions/financial_core.js:109`، `functions/financial.js:352`، `functions/financial.js:377` | Node: أكثر من صفحة، إعادة المحاولة، وفشل الصفحة الكاملة دون cursor. بقي تشغيل المجدول نفسه عبر Pub/Sub Emulator قبل staging |
| H1 | تأكد خلط UTC مع مسقط | أُصلح: helper موحد لـAsia/Muscat، ومفتاح فترة واستحقاق نهاية يوم مسقط، والتأخير بعد يوم الاستحقاق لا خلاله | `functions/financial_core.js:61`، `functions/financial_core.js:78`، `functions/financial_core.js:94` | Node: 31 يوليو/1 أغسطس و31 ديسمبر/1 يناير، شهري وسنوي، وعدم التأخير في اليوم نفسه |
| H2 | تأكد اختلاف مفاتيح منع التكرار | أُصلح: مفتاح canonical واحد لا يحتوي timestamp، والاشتراك موحد للعضو والنوع والفترة، ويستخدمه المولد والترحيل واليدوي والحجز | `functions/financial_core.js:99`، `functions/financial.js:139`، `scripts/migrate-financial-v1.js` | Node: تطابق مفتاح المولد والترحيل رغم اختلاف المصدر؛ Emulator: اعتماد الحجز المتكرر لا ينشئ رسمًا ثانيًا |
| H3 | تأكد احتمال ملفات إيصال يتيمة | أُصلح جزئيًا: `receiptId` هو معرّف المعاملة، وإعادة الاستدعاء idempotent، وcleanup خادمي يتحقق من المالك والمسار والارتباط ويطبق مهلة أمان 15 دقيقة | `functions/financial.js:648`، `functions/financial.js:927`، `lib/providers/app_providers.dart:309` | Emulator: إعادة إرسال المعاملة نفسها؛ Node: تحليل مسار التخزين. بقي scheduled sweep للملفات القديمة واختبار Storage لحالة timeout الممتدة |
| H4 | تأكدت خطورة ترتيب access calls في استعلام الرسوم | أُصلح: `canManageFinance` أولًا، ومنع كتابة الرسوم من العميل | `firestore.rules:458` | Emulator: مدير مالي يسرد 31 رسمًا، عضو يقرأ رسمه فقط، مستخدم مجلس آخر مرفوض، و`system_owner` مسموح |
| H5 | تأكد عدم ربط رسوم الحجز والمناسبة | أُصلح مسار الحجز الفعلي: إنشاء رسم idempotent بعد `approved`، واختيار رسم العضو/غير العضو، وتحويل الإلغاء المدفوع إلى `refundRequired` | `functions/financial.js:275`، `functions/financial.js:347` | Emulator: إنشاء رسم الحجز، عدم التكرار، وتحويل الرسم المدفوع الملغى إلى `refundRequired`. لا يوجد مسار مناسبات إنتاجي فعلي، لذلك لم يُنشأ كود event ميت؛ كما لا توجد واجهة إلغاء حجز معتمدة حاليًا |
| H6 | تأكد أن الاختبارات كانت تختبر منطقًا غير مستخدم | أُصلح: `financial_core.js` مستخدم من الإنتاج والاختبارات، ومعالجات submit/review/search/booking نفسها تُستدعى في Emulator، وFlutter يستخدم `validateReceiptDraft` و`deriveDashboardState` | `functions/financial_core.js`، `functions/financial.js:648`، `lib/presentation/screens/member/receipt_upload_screen.dart:299`، `lib/presentation/screens/member/member_dashboard.dart:129` | 11 Node + 8 Emulator + 22 Flutter |
| M1 | تأكد إمكان تعليق رسوم الآخرين بإيصال وهمي | أُصلح: الإرسال لا يغيّر الرسم، lock لكل دافع/رسم فقط، حد 10 طلبات/ساعة، انتهاء خلال 48 ساعة، وأول اعتماد صحيح يفوز | `functions/financial.js:648`، `functions/financial.js:821`، `functions/financial.js:948` | Emulator: الرسم يبقى `unpaid` بعد الإرسال، اعتمادان متزامنان يفوز أحدهما فقط، وإعادة الإرسال idempotent |
| M2 | تأكد تسريب دليل الأعضاء وإمكان listing مباشر | أُصلح: منع القراءة المباشرة كليًا، والبحث Cloud Function بحد أدنى 3 وأقصى 10 وحقول عامة فقط، والتحقق من عضوية الدافع النشطة | `firestore.rules:452`، `functions/financial.js:561`، `lib/data/repositories/financial_repository.dart` | Emulator: listing/get للدليل مرفوض، البحث يعيد 10 فقط وبخمسة حقول، حرفان مرفوضان، وعضو مجلس آخر مرفوض. App Check لم يُفرض بعد |
| M3 | تأكد أن الإدارة كانت تكتب مباشرة وأن تدقيق المعاملة مكرر/بحقول قديمة | أُصلح: الإعدادات والباقات والحسابات والرسم اليدوي callables خادمية مع actor من auth وaudit idempotent، وإزالة سجل التدقيق اليدوي المكرر من المراجعة، وتحديث حقول audit | `functions/financial.js:406`، `functions/financial.js:527`، `functions/audit.js`، `firestore.rules:434` | Emulator: العميل، حتى المدير المالي، لا يستطيع كتابة الإعدادات أو الرسوم مباشرة؛ Functions Emulator حمّل مشغلات audit ونفذها دون الخطأ السابق |
| M4 | تأكد timestamp في الرسم اليدوي | أُصلح المفتاح إلى UUID ثابت للطلب، والخادم يستخدم canonical key ويرجع الموجود في إعادة المحاولة | `lib/presentation/screens/admin/financial_management_screen.dart`، `functions/financial.js:527` | Node: canonical idempotency؛ الكتابة الخادمية تمنع التكرار. بقي تحسين بصري إضافي لإظهار spinner داخل الحوار نفسه |
| M5 | تأكد احتمال خلط مدفوعات الآخرين بإجماليات العضو | أُصلح: إجماليات Dashboard من رسوم `membershipId` المستفيد فقط، والمدفوعات التي قام بها الدافع في قسم مستقل، وpending لا يضاف إلى المدفوع | `lib/presentation/screens/member/member_dashboard.dart:103` | Flutter: حالات Dashboard؛ Emulator: إيصال مختلط جزئي للنفس وكامل للمستفيد |
| M6 | تأكد تمرير مبلغ مالي بـdouble عبر GoRouter | أُصلح بنموذج `ReceiptUploadArguments` ومبلغ `int amountDeclaredBaisa` | `lib/data/models/financial_models.dart:28`، `lib/router/app_router.dart:167` | `flutter analyze` بلا أخطاء، وFlutter money tests |
| M7 | تأكد غياب الأرقام والفاصل العربي | أُصلح دعم `٠١٢٣٤٥٦٧٨٩` و`٫` مع رفض أكثر من ثلاث خانات | `lib/data/models/financial_models.dart:66` | Flutter: `٥` و`١٢٫٥٠٠` ورفض `١٫٢٣٤٥` |
| M8 | تأكد بقاء streams بين المجالس | أُصلح بتحويل مزودات النظام المالي إلى `autoDispose.family` وربط مفاتيحها بـorganizationId وmembershipId، مع loading/error الموجودة | `lib/providers/app_providers.dart:194` | `flutter analyze` وFlutter اختبارات عزل المفتاح بين مجلسين. بقي QA تفاعلي سريع أثناء تبديل المجلس على جهاز حقيقي |
| M9 | تأكد وجود BOM في `tasks.json` | ما زال BOM موجودًا (`EF BB BF`) لكن لا يوجد Node parser يقرأ الملف؛ سكربت PowerShell يقرأه صراحة بـUTF-8 ونجح. لم يُعد ترميز الملف آليًا تجنبًا لإتلاف العربية | `project-brain/tasks.json`، `scripts/update-project-dashboard.ps1:7` | `ConvertFrom-Json` نجح وسكربت Dashboard نجح. يمكن إزالة BOM لاحقًا بتحرير UTF-8 موثوق إذا أصبح هناك قارئ Node |
| M10 | تأكد تعارض أسماء الأدوار بين الدستور والتنفيذ | أُضيف توضيح يفصل أسماء الدستور الأصلية عن `roleId` الحالية وعن `superAdmin` القديم دون تغيير بيانات الإنتاج | `project-brain/PROJECT_CONSTITUTION.md`، `AGENTS.md`، `CLAUDE.md` | مقارنة المراجع مع `firestore.rules` و`role_labels.dart` |
| M11 | تأكدت سلامة ملفات التعليمات ووجود قاعدة `node -e` الواسعة | أزيلت كل قواعد `node -e`، وبقيت القواعد المحددة، وأضيف الملف الشخصي إلى `.gitignore`. ملف PDF يطابق blob الأصل في HEAD بالهاش نفسه | `.claude/settings.local.json`، `.gitignore:62`، `AGENTS.md`، `CLAUDE.md` | JSON صالح، بحث `node -e` فارغ، و`git hash-object PROJECT_CONSTITUTION.pdf` يساوي `git rev-parse HEAD:...` (`a6724369...`) |

## 3. مخطط البيانات والتغييرات الأمنية

المسارات الأساسية بقيت تحت `organizations/{organizationId}`:

- `financial_settings/main`
- `subscription_plans/{planId}`
- `member_accounts/{membershipId}`
- `charges/{canonicalChargeId}`
- `transactions/{receiptId}`
- `member_directory/{membershipId}`، خادمي فقط
- `pending_receipt_locks/{payerUserId_chargeId}`، خادمي فقط
- `financial_rate_limits/{payerUserId}`، خادمي فقط
- `audit_logs/{auditId}`، خادمي فقط

أضيفت فهارس الاستعلام canonical للرسوم، وانتهاء المعاملات المعلقة، والبحث، والمعاملات. يجب بناء الفهارس واختبارها على staging قبل الإنتاج.

## 4. الملفات الأساسية الجديدة والمعدلة في جولة الإصلاح

### جديدة

- `functions/financial_core.js`
- `functions/financial_emulator.test.js`
- `project-brain/CODEX_FINANCIAL_FIX_REPORT_AR.md`

### معدلة في الإصلاح

- `functions/financial.js`
- `functions/financial.test.js`
- `functions/audit.js`
- `functions/index.js`
- `functions/package.json`
- `functions/package-lock.json`
- `scripts/migrate-financial-v1.js`
- `firestore.rules`
- `firestore.indexes.json`
- `.claude/settings.local.json`
- `.gitignore`
- `lib/data/models/financial_models.dart`
- `lib/data/repositories/financial_repository.dart`
- `lib/domain/financial/financial_logic.dart`
- `lib/providers/app_providers.dart`
- `lib/router/app_router.dart`
- شاشات العضو والإدارة والمجلس المرتبطة بالملخص والإيصال والرسم اليدوي
- `test/financial_logic_test.dart`
- `AGENTS.md` و`CLAUDE.md` و`project-brain/PROJECT_CONSTITUTION.md`
- `project-brain/tasks.json` و`project-brain/PROJECT_DASHBOARD.md` المولد

تعديل `.gradle/9.3.0/fileHashes/fileHashes.lock` كان موجودًا محليًا قبل الجولة، ولم ألمسه أو أنظفه.

## 5. نتائج الاختبارات

- `flutter analyze`: **0 أخطاء و0 تحذيرات**.
- `flutter test`: **22 ناجح، 0 فاشل**.
- `npm test`: **11 ناجح، 0 فاشل**.
- Firebase Emulator (Functions + Firestore + Storage): **8 ناجح، 0 فاشل**.
  - قواعد العضو والمدير المالي والمالك الأعلى ومجلس آخر.
  - منع listing للدليل ومنع الكتابات المالية المباشرة.
  - البحث الخادمي وحد 10 نتائج.
  - إرسال مختلط، إعادة المحاولة، سباق مديرين، partial، تغير الرصيد وrollback.
  - Storage owner/reviewer isolation.
  - رسم حجز idempotent وحالة `refundRequired`.
- `node --check`: نجح لـ`index.js` و`financial.js` و`financial_core.js` و`audit.js` وسكربت الترحيل.
- JSON: جميع الملفات المعدلة صالحة.
- `git diff --check`: ناجح.
- سكربت Project Dashboard: ناجح؛ النسبة العامة للمشروع **82%**، والمهمة المالية **88%**.

ملاحظة بيئة: المشروع يطلب Node 20، بينما المضيف الحالي Node 24؛ احتاج Functions Emulator إلى `FUNCTIONS_DISCOVERY_TIMEOUT=60`. كما حذر Emulator أن `firebase-functions` قديم، ولم تُرقّ المكتبة لتجنب تغيير معماري غير مطلوب في هذه الجولة.

## 6. ما بقي قبل staging

1. تشغيل scheduled functions على Pub/Sub Emulator فعليًا؛ الاختبارات الحالية تغطي helper الإنتاجية للـpagination والتوقيت، لكن المجدولات تجاهلها Emulator لعدم تشغيل Pub/Sub.
2. إضافة scheduled Storage sweep للملفات اليتيمة الأقدم من المهلة واختبار timeout طويل؛ cleanup اليدوي الآمن موجود.
3. تفعيل App Check للدوال الحساسة بعد إعداد تطبيقات Android/iOS والمفاتيح في Firebase، دون كسر بيئة التطوير.
4. لا يوجد مسار مناسبات إنتاجي؛ `eventBookingFeeBaisa` إعداد فقط حتى يوجد lifecycle حقيقي.
5. مسار إلغاء الحجز المعتمد غير ظاهر في واجهة الإنتاج؛ المشغل يدعم `cancelled` و`refundRequired` عند حدوثه خادميًا.
6. تصميم واضح لحساب رسوم حجز غير العضو؛ الحجز الحالي يسمح به في القواعد لكن النظام المالي قائم أساسًا على `membershipId`.
7. QA على Android وiOS لتبديل مجلسين، RTL، رفع صورة/PDF، debounce، وإعادة المحاولة بعد انقطاع الشبكة.
8. dry-run على نسخة staging ونسخة احتياطية ومراجعة إجماليات التحويل، ثم اختبار بناء الفهارس على staging.
9. مراجعة تحذير ترقية `firebase-functions` وتشغيل الاختبارات على Node 20 المطابق للإنتاج.
10. `.claude/settings.local.json` متتبع أصلًا؛ إضافته إلى `.gitignore` لا تلغي التتبع. الأمر المقترح بعد موافقة منفصلة: `git rm --cached .claude/settings.local.json`.

## 7. أوامر مقترحة لاحقًا — لم تُنفذ

```powershell
# staging dry-run فقط
node scripts/migrate-financial-v1.js --project <staging-project-id>

# بعد نسخة احتياطية ومراجعة التقرير وموافقة صريحة فقط
node scripts/migrate-financial-v1.js --project <staging-project-id> --apply --confirm APPLY:<staging-project-id>

# نشر staging بعد الموافقة فقط
firebase use <staging-project-id>
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
```

لا ينبغي استخدام مشروع الإنتاج في الأوامر أعلاه قبل نجاح staging ومراجعة الأرقام يدويًا.

## 8. تأكيدات السلامة

- **لم يتم تنفيذ Firebase deploy.**
- **لم يتم تنفيذ migration حقيقي أو `--apply`.**
- **لم تتم أي كتابة إلى production أو staging.**
- **لم يتم تنفيذ git commit أو git push.**
- **لم تُحذف تعديلات المستخدم، ولم يُستخدم git reset أو checkout.**
- **لم يُعدّل ملف `.gradle/9.3.0/fileHashes/fileHashes.lock`.**
- **بقي `onlinePaymentsEnabled=false`، ولم تُضف مفاتيح دفع أو أسرار.**

## 9. الخطوة التالية

مراجعة هذا التقرير والتغييرات محليًا، ثم تشغيل QA الأجهزة وPub/Sub/Storage cleanup tests. بعد ذلك فقط يُنشأ مشروع staging أو تُستخدم بيئة staging المعتمدة لتنفيذ dry-run غير كاتب ومراجعة إجماليات الريال/البيسة قبل أي موافقة على الترحيل أو النشر.
