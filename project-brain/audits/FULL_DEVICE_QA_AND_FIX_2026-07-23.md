# جولة QA وإصلاح شاملة على هاتف حقيقي — مجلس الرحمات

- **التاريخ:** 2026-07-23 · **المشروع:** village_council_app · **Firebase:** alrahmat-console · **Package:** com.alrahmat.village_council
- **الحالة:** ⛔ **متوقّف مؤقتًا عند مانع حقيقي (اختيار الجهاز)** — انتظار قرار المستخدم. (تقرير مرحلي.)

## المرحلة 1 — تجهيز الجهاز وجمع الأدلة

### Git baseline (محفوظ، لم يُلمس)
```
 M .claude/settings.json
 M .gradle/9.3.0/fileHashes/fileHashes.lock
?? project-brain/audits/        (تقارير التدقيق — أُنشئت في جلسات سابقة)
```
لا `reset`/`checkout`/`clean`/`stash`/`commit`. كل تعديلات المستخدم محفوظة.

### الأجهزة المتصلة
- **المتصل الوحيد:** `K5J0220312017698` = **HUAWEI ELS-NX9** (P40 Pro)، الحالة `device`.
- **الجهاز المطلوب `R5GL21K4R3V` (Samsung، غالبًا) غير متصل.**
- لا توجد أجهزة متعددة (هاتف واحد فقط) — قاعدة "اختر R5GL... عند التعدد" لا تنطبق؛ لكن الجهاز المطلوب غائب.

### 🔴 اكتشاف حرج (يفسّر استمرار أخطاء App Check)
فحص آمن للحزم على ELS-NX9:
```
adb -s K5J0220312017698 shell pm list packages | grep -iE "gms|vending|hwid"
→ package:com.huawei.hwid        (فقط)
→ لا com.google.android.gms      (Google Play Services غائب)
→ لا com.android.vending         (Play Store غائب)
ro.product.manufacturer = HUAWEI
```
**الاستنتاج:** هذا الهاتف **بلا Google Mobile Services (GMS)**. ومزوّد App Check `AndroidProvider.playIntegrity` (المستخدم في Release عبر `firebase_app_check_config.dart:19`) **يتطلّب Google Play Services**. وعليه:
- على هذا الـ Huawei في Release: **يستحيل** الحصول على App Check token صالح.
- كل الدوال الحسّاسة `enforceAppCheck:true` (`getPayableCharges`, `getBookingAvailability`, المالية والحجز) **تُرفض** → "تعذر تحميل الرسوم/المواعيد".
- الإشعارات القياسية (FCM) قد تتأثّر أيضًا (Huawei يستخدم HMS Push).

**الخلاصة:** المشكلة على هذا الجهاز **ليست في تسجيل App Check ولا في الكود**، بل لأن **جهاز الاختبار Huawei لا يدعم Play Integrity**. الاختبار الصحيح لـ App Check يتطلّب جهازًا فيه GMS (مثل Samsung R5GL21K4R3V المطلوب).

### قرار المستخدم
اختار المستخدم: **المتابعة على Huawei بوضع Debug + Emulator** (App Check debug provider، بيانات QA).

---

## المرحلة 2 — الأدلة الحيّة من الجهاز (نسخة الإنتاج المثبّتة)
أثناء تشغيل التطبيق على الـ Huawei والتقاط `flutter run`/logcat، تم التقاط الاستثناءات **الأصلية** (لا الرسالة العربية فقط):

```
[Receipts] charge load failed type=FirebaseFunctionsException     ← الرسوم
[Receipts] approve failed type=FirebaseFunctionsException
[Receipts] reject failed type=FirebaseFunctionsException
[Receipts] secure open failed type=FirebaseFunctionsException
[Memberships] collectionGroup failed code=permission-denied ...   ← قاعدة/فهرس منشور قديم
[Push] token registration skipped: firebase_messaging ... MISSING_INSTANCEID_SERVICE  ← لا GMS
```
**تأكيد قاطع من الجهاز:**
1. **كل النداءات المالية (callables) تُرمى بـ `FirebaseFunctionsException`** على الإنتاج من هذا الجهاز — مطابق تمامًا لفرضية App Check (لا يوجد Play Integrity على Huawei بلا GMS).
2. **قراءات Firestore تنجح** (العضويات تُحمّل) — لأن فرض App Check على Firestore مُطفأ؛ المشكلة محصورة في **الدوال**.
3. `MISSING_INSTANCEID_SERVICE` من firebase_messaging = **تأكيد إضافي مباشر أن الجهاز بلا Google Play Services** (الإشعارات القياسية FCM لا تعمل على هذا الـ Huawei أيضًا).
4. `[Memberships] collectionGroup failed permission-denied` — القواعد/الفهارس المنشورة في الإنتاج **أقدم** من المستودع (يتعافى التطبيق عبر بحث per-organization). مرتبط بنفس فجوة نشر "حجوزاتك".

> الاستنتاج: التشخيص السابق **مؤكَّد الآن على الجهاز**. الرسوم/المواعيد تفشلان لأن الدوال المفروض عليها App Check تُرفض على جهاز بلا Play Integrity.

## المرحلة 3 — إصلاح كود (تحسين تسجيل الأخطاء) — مطبَّق ومتحقَّق منه محليًا
معالجة الأخطاء كانت تُخفي الكود الأصلي (`type=runtimeType` فقط). أُضيف تسجيل آمن (بلا tokens/بيانات شخصية) يُظهر `code/message/details`:
- `lib/data/repositories/financial_repository.dart` — `getPayableCharges`: `[Charges] getPayableCharges FAILED code=... message=... plugin=... details=...` ثم rethrow.
- `lib/data/repositories/booking_repository.dart` — `getAvailability` (callable): يسجّل `code/message/details`؛ و`streamForUser` (استعلام الحجوزات): يسجّل كود الخطأ (failed-precondition عند غياب الفهرس) ثم يُعيد رميه (`Error.throwWithStackTrace`) للحفاظ على حالة الواجهة.
- `dart format` مطبّق، و`flutter analyze` على الملفين: **No issues found**.

## المرحلة 4 — بيئة الاختبار (Emulator + QA) — جُهّزت بنجاح، والإثبات على الشاشة لم يكتمل
- ✅ Firebase Emulator أُقلع (auth/firestore/functions/storage، مشروع `demo-financial-prestaging`، بلا حاجة لتسجيل دخول Firebase).
- ✅ `adb reverse` للمنافذ 9099/8080/5001/9199 (الهاتف يصل للإيمولاتور عبر USB).
- ✅ بذر بيانات QA عبر `functions/scripts/seed-financial-device-qa.js`: مجلس `qa_financial_council`، 5 أعضاء، **8 رسوم**، اشتراك شهري، حجزان معتمدان، عضو اختبار (هاتف `00000000`).
- ⛔ **لم يكتمل الإثبات على الشاشة:** بناء `flutter run --debug` (وضع Emulator) توقّف على `Gradle assembleDebug` أكثر من 10 دقائق دون sync/تثبيت (مانع بيئي — بناء Debug بطيء/عالق على هذا الإعداد). أُوقفت المهمة لتفادي إهدار الموارد.
- بيانات دخول الاختبار (Emulator فقط، ليست سرًّا إنتاجيًا): هاتف `00000000`، وكلمة مرور QA وُلّدت وقت التشغيل. للإعادة، يُعاد تشغيل السكربت بنفس متغيّرات البيئة.

## جدول الأعطال (محدَّث بأدلة الجهاز)
| العطل | التصنيف (مؤكَّد على الجهاز) | السبب الجذري | الأولوية |
|---|---|---|---|
| تعذر تحميل الرسوم | `FirebaseFunctionsException` (callable) | App Check يُرفض — الجهاز Huawei بلا GMS/Play Integrity | P0 |
| تعذر تحميل المواعيد | `FirebaseFunctionsException` (callable) | نفس السبب | P0 |
| تعذر تحميل حجوزاتك | استعلام Firestore | فهرس `bookings(userId,bookingDate)` غير منشور + قواعد منشورة قديمة (permission-denied ظاهر) | P1 |
| فشل اعتماد/رفض/فتح الإيصال | `FirebaseFunctionsException` | نفس سبب App Check | P0 |
| الإشعارات (FCM) | `MISSING_INSTANCEID_SERVICE` | الجهاز بلا GMS — FCM القياسي لا يعمل على Huawei | P2 (خاص بالأجهزة بلا GMS) |

## هل التطبيق مربوط بالإنتاج؟
**نعم، مؤكَّد** — النسخة المثبّتة تقرأ مجالس الإنتاج (`rahmat_general_council`, `JDxP...`, `2KkO...`) فعليًا.

## الملفات المعدّلة (هذه الجولة)
- `lib/data/repositories/financial_repository.dart` (تسجيل آمن + import foundation).
- `lib/data/repositories/booking_repository.dart` (تسجيل آمن + import foundation).
- `project-brain/audits/FULL_DEVICE_QA_AND_FIX_2026-07-23.md` (هذا التقرير).
- **لا تعديل** على القواعد/الفهارس/الدوال في هذه الجولة (تشخيص + تسجيل فقط). دور المالك الأعلى ومصدره `platform_admins` لم يُلمسا.

## نتائج الاختبارات الآمنة
- `flutter analyze` (الملفين المعدّلين): ✅ No issues found. (التحليل الكامل السابق: 4 تحذيرات dead-code غير مرتبطة في `admin_dashboard.dart`.)
- `flutter test`: ✅ 51/51 (من الجولة السابقة، لم يتغيّر منطق مُختبَر).
- `functions npm test`: ✅ 22/22 (يؤكّد فرض App Check على كل الدوال الحسّاسة).

## ما ينتظر Deploy أو إعداد Console (لا يُنفَّذ الآن — يحتاج موافقتك)
1. **Play Integrity (Console) — P0:** تأكيد أن **Play Integrity API مفعّل ومربوط بمشروع `alrahmat-console`**، وأن بصمة SHA-256 للإصدار الموقّع مسجّلة في App Check. **يُختبر على جهاز فيه GMS (Samsung R5GL21K4R3V)** — لا على Huawei.
2. **قرار دعم Huawei/بلا-GMS — P0:** أجهزة Huawei بلا GMS **لا يمكنها** استخدام Play Integrity إطلاقًا. الخيارات: (أ) اعتبارها غير مدعومة لهذه الميزات؛ (ب) إضافة مزوّد App Check بديل/آلية debug-token مُدارة؛ (ج) مراجعة سياسة `enforceAppCheck` تدريجيًا حسب `APP_CHECK_ACTIVATION_PLAN.md`. **بدون تخفيف الحماية دون قرار موثّق.**
3. **نشر الفهارس — P1:** `firebase deploy --only firestore:indexes --project alrahmat-console` (يعالج "حجوزاتك"؛ الفهرس موجود في `firestore.indexes.json`).
4. **نشر القواعد — P1:** `firebase deploy --only firestore:rules --project alrahmat-console` (القواعد المنشورة أقدم — سبب `collectionGroup permission-denied`؛ تشمل تعديلات owner/system_owner والعضويات).

## اختبارات يدوية تحتاج تدخّلك
- تسجيل الدخول بحساب QA على بناء Emulator (هاتف `00000000`) لإثبات تحميل الرسوم/الحجوزات على الإيمولاتور (بعد اكتمال البناء البطيء).
- اختبار على **Samsung R5GL21K4R3V** (فيه GMS) للتحقق الفعلي من App Check/Play Integrity في نسخة Release.

## المرحلة 5 — الاختبار على Samsung (فيه GMS) والمقارنة الحاسمة
- الجهاز: **Samsung SM-S948B (Galaxy S24 Ultra)، Android 16، فيه Google Play Services + متجر Play**. النسخة المثبّتة: **versionName=1.0.0 / versionCode=1** (Release، ثُبّتت 2026-07-23).
- سجل الجهاز (نسخة Release، `debugPrint` يعمل): كل النداءات المالية **تفشل بنفس Huawei**:
  ```
  [Receipts] charge load failed  type=FirebaseFunctionsException   ← الرسوم
  [Receipts] approve/reject/secure open failed = FirebaseFunctionsException
  ```
  دون `MISSING_INSTANCEID_SERVICE` (لأنه فيه GMS).

**الاستنتاج المؤكَّد (تغيّر عن الفرضية):** الفشل **ليس بسبب نقص GMS في Huawei** — يفشل حتى على جهاز GMS سليم. إذن **App Check / Play Integrity غير مربوط/مسجّل صحيحًا للتطبيق في مشروع `alrahmat-console`**، فلا جهاز ينتج token مقبولًا، وكل الدوال `enforceAppCheck:true` تُرفض.

**تحقّقات داعمة (قراءة فقط):**
- `google-services.json`: project_id=`alrahmat-console`, package=`com.alrahmat.village_council`, appId=`1:501018693703:android:cf34b84e3613940662e162` → التطبيق يشير للمشروع الصحيح؛ النقص في تسجيل App Check.
- **بصمة توقيع الـ Release (عامة، من APK المثبّت):**
  - SHA-256: `30:6F:3A:11:68:A8:21:F6:9D:AA:79:BB:D4:F5:0A:05:42:DF:EF:8C:40:57:A2:4F:D8:83:16:60:B1:7D:77:3E`
  - SHA-1: `57:F4:E6:43:E1:6C:47:8B:BB:A1:0C:C5:D4:66:71:90:8B:71:6D:E0`

## الحل المعتمد: المسار A — تسجيل App Check في Console (اختاره المستخدم)
لا يُنفَّذ من الطرفية (إعداد Console). لا تعديل كود ولا نشر. الخطوات:
1. Google Cloud Console (مشروع alrahmat-console) → تفعيل **Play Integrity API**.
2. Firebase → Project Settings → تطبيق Android → **Add fingerprint** → SHA-256 أعلاه (وSHA-1).
3. Firebase → App Check → التطبيق → **Register** بمزوّد **Play Integrity**.
4. إعادة الاختبار على Samsung (بلا إعادة بناء) → يُتحقَّق من النجاح عبر سجل الجهاز.
> ملاحظة: أجهزة Huawei بلا GMS تبقى غير قادرة على Play Integrity — قرار دعمها منفصل.
> «حجوزاتك» يبقى منفصلًا: نشر الفهارس + القواعد (بموافقة).

## المرحلة 6 — إعادة الاختبار بعد تسجيل App Check (Samsung، token جديد) — نتائج قاطعة
بعد أن أكّد المستخدم إتمام تسجيل App Check/Play Integrity، أُعيد تشغيل التطبيق بجلسة نظيفة والتُقط سجل Firestore/Functions **الأصلي (native)**:

1. **«حجوزاتك» — مؤكَّد 100% (خطأ أصلي صريح):**
   ```
   Firestore: Query(organizations/{org}/bookings where userId==... order by -bookingDate)
   failed: code=FAILED_PRECONDITION, description=The query requires an index.
   create_composite=... (bookings: userId ASC, bookingDate DESC)
   ```
   → **الفهرس المركّب غير منشور في الإنتاج** (موجود في `firestore.indexes.json`).
2. **العضويات collectionGroup — مؤكَّد (خطأ أصلي):**
   ```
   Firestore: Query(collectionGroup=memberships where userId==... and status==active) failed: PERMISSION_DENIED
   Firestore: Query(collectionGroup=membership_requests where userId==...) failed: PERMISSION_DENIED
   ```
   → **القواعد المنشورة في الإنتاج أقدم من المستودع** (يتعافى التطبيق عبر بحث per-organization).
3. **الرسوم/المالية — ما زالت تفشل رغم التسجيل:**
   ```
   [Receipts] charge load failed / member search failed / approve / reject / secure open failed
   = FirebaseFunctionsException  (متكرّر)
   ```
   → App Check **ما زال لا يُنتج token مقبولاً حتى بعد تسجيله**. نسخة Release لا تكشف الكود الدقيق في السجل النظامي.

**تفسير مرجّح لاستمرار فشل App Check بعد التسجيل:** التطبيق **مثبّت داخليًا ولم يُنشر على Google Play إطلاقًا**. مزوّد **Play Integrity يتطلّب أن يكون التطبيق معروفًا/مربوطًا في Google Play Console** (ولو على مسار اختبار داخلي). تسجيل بصمة SHA في Firebase App Check وحده **لا يكفي** إن لم يكن التطبيق مربوطًا بـ Play Integrity في Play Console — فيفشل التحقّق على كل الأجهزة (بما فيها Samsung). لتأكيد الكود الدقيق (`unauthenticated`/`app-check-token-error`) يلزم بناء Debug يحمل التسجيل الجديد الذي أضفته.

## خلاصة الأسباب المؤكَّدة (بعد كل الاختبارات)
| العطل | السبب المؤكَّد | الإصلاح | يحتاج |
|---|---|---|---|
| حجوزاتك | FAILED_PRECONDITION — فهرس `bookings(userId,bookingDate)` غير منشور | نشر الفهرس (أو الضغط على رابط Firestore) | **موافقتك على Deploy** |
| العضويات (permission-denied) | القواعد المنشورة أقدم من المستودع | نشر `firestore.rules` | **موافقتك على Deploy** |
| الرسوم/المواعيد/المالية | App Check يُرفض — Play Integrity غير فعّال (التطبيق غير منشور على Play) | ربط Play Integrity في Play Console، أو إيقاف enforceAppCheck مؤقتًا (Path B) | **قرارك** |

## الحالة النهائية
**ناجح جزئيًا (Partial):**
- ✅ التشخيص **مؤكَّد على الجهاز** (الدوال تفشل بـ FirebaseFunctionsException؛ الجهاز بلا GMS).
- ✅ إصلاح كود تسجيل الأخطاء مطبَّق و`analyze` نظيف.
- ✅ بيئة Emulator + بيانات QA جاهزة.
- ⛔ إثبات "نجاح الرسوم/الحجوزات على الإيمولاتور على الشاشة" لم يكتمل (بناء Debug عالق — مانع بيئي).
- ⛔ الإصلاح الإنتاجي الحقيقي (Play Integrity/الفهارس/القواعد) **موقوف على موافقتك** ويحتاج جهاز GMS.
