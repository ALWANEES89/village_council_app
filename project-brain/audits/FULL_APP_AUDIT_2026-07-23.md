# تدقيق تقني شامل — مجلس الرحمات (Flutter + Firebase)

- **التاريخ:** 2026-07-23
- **المشروع:** village_council_app · **Firebase الإنتاجي:** alrahmat-console · **Android Package:** com.alrahmat.village_council
- **نوع العمل:** تدقيق وتشخيص **للقراءة فقط** — لم تُنفَّذ أي إصلاحات، ولا Deploy، ولا تعديل إنتاج، ولا Git.
- **الحالة:** تقرير مرحلي/نهائي (تُحدَّث نتائج flutter analyze/test عند اكتمالها في الخلفية).

---

## 1) الملخّص التنفيذي

الأخطاء الثلاثة ("تعذر تحميل المواعيد/حجوزاتك/الرسوم المتاحة") ليست خطأً واحداً، بل **سببان جذريان متمايزان**، وكلاهما نتيجة **عدم توافق نسخة الإنتاج مع الخلفية** (App Check + الفهارس/النشر)، وليس خطأً منطقيًا في واجهة Flutter:

1. **(الأقوى، مؤكَّد من الكود) تعارض App Check:** كل دوال Cloud Functions الحسّاسة (الرسوم، مواعيد الحجز، إنشاء حجز، إرسال إيصال...) معرّفة بـ `enforceAppCheck: true`. بينما نسخة Release تستخدم مزوّد `playIntegrity`، ووثيقة الخطة تنص أن App Check **غير مُفعّل ولم تُضف أي مفاتيح/tokens**. فالتطبيق في الإنتاج **لا ينتج App Check token صالحًا → الدوال ترفض كل النداءات** → تفشل **الرسوم** و**مواعيد الحجز**. (يعمل على Emulator لأن مزوّد debug يتجاوز ذلك.)

2. **(محتمل، يحتاج تأكيد من الإنتاج) فهرس/نشر:** "حجوزاتك" استعلام Firestore مباشر (`where userId + orderBy bookingDate desc`) يتطلّب فهرسًا مركّبًا. الفهرس **موجود في `firestore.indexes.json`** لكن يُرجَّح أنه **غير منشور على الإنتاج** → `FAILED_PRECONDITION`.

**هل التطبيق مربوط بالإنتاج؟ نعم، مؤكَّد.** نسخة Release تتصل بـ `alrahmat-console` ولا يمكنها استخدام Emulator إطلاقًا (محمي بـ `kReleaseMode`).

**الخطوة الحرجة:** حسم App Check (تسجيل Play Integrity في Console أو تخفيف الفرض تدريجيًا حسب الخطة) + نشر الفهارس والدوال. **لا يوجد إصلاح ممكن من كود Flutter وحده.**

---

## 2) الأسباب المؤكَّدة (بالملفات والأسطر والنتائج)

### السبب أ — تعارض App Check (يفسّر "الرسوم" و"المواعيد")
- **الكود يفرض App Check:** `functions/financial.js:35`
  ```js
  const sensitiveCallableOptions = { region: "us-central1", enforceAppCheck: true };
  ```
  وتُستخدم في كل الدوال الحسّاسة: `getPayableCharges` (financial.js:1127)، `getBookingAvailability` (financial.js:687)، `createBooking`/`reviewBooking` (production_security.js:655-656)، `submitFinancialReceipt`، `searchCouncilMembers`، ... إلخ.
- **الخطة تقول العكس:** `project-brain/APP_CHECK_ACTIVATION_PLAN.md:27`
  > «الحالة الحالية: `enforceAppCheck` غير مفعّل عمدًا، ولم تُضف أي مفاتيح أو tokens.»
  → **تناقض مباشر**: الكود يفرض App Check، والوثيقة تقول إنه غير مُهيّأ. أي البيئة الإنتاجية بلا تسجيل App Check.
- **العميل في Release يستخدم playIntegrity:** `lib/core/firebase/firebase_app_check_config.dart:16-22`
  ```dart
  const debugProvider = kDebugMode || FirebaseEmulatorConfig.enabled; // false في Release
  androidProvider: debugProvider ? AndroidProvider.debug : AndroidProvider.playIntegrity,
  ```
  دون تسجيل Play Integrity في App Check Console (لا مفاتيح/tokens) → لا token صالح → الدوال ترفض.
- **تأكيد إضافي من الاختبارات:** اختبار الدوال ينجح ويؤكّد السلوك عمدًا:
  > `✔ every sensitive financial and booking callable enforces App Check` (functions npm test: 22 pass / 0 fail).

**مسار "الرسوم المتاحة":** `receipt_upload_screen.dart:119` ← `financial_repository.getPayableCharges` (`financial_repository.dart:236` `httpsCallable('getPayableCharges')`) ← `functions/financial.js:1127` (enforceAppCheck).

**مسار "مواعيد الحجز":** `council_booking_screen.dart:415` (`BookingAvailabilityPanel`) ← `bookingAvailabilityProvider` (`app_providers.dart:82`) ← `booking_repository.getAvailability` (`booking_repository.dart:63` `httpsCallable('getBookingAvailability')`) ← `functions/financial.js:687` (enforceAppCheck).

### السبب ب — "حجوزاتك" استعلام Firestore يحتاج فهرسًا (يُرجَّح أنه غير منشور)
- **مسار "حجوزاتك":** `council_booking_screen.dart:321` ← `userBookingsProvider` (`app_providers.dart:75`) ← `booking_repository.streamForUser` (`booking_repository.dart:48-56`):
  ```dart
  _bookings(organizationId).where('userId', isEqualTo: userId).orderBy('bookingDate', descending: true)
  ```
  → يتطلّب فهرسًا مركّبًا `bookings(userId ASC, bookingDate DESC)`.
- **الفهرس موجود في الملف:** `firestore.indexes.json:176-181`. لكن لا يمكن تأكيد نشره على الإنتاج من هذه الجلسة (لا وصول للإنتاج). غياب النشر ⇒ `FAILED_PRECONDITION: The query requires an index`.
- هذا الاستعلام **لا يمر عبر App Check** (قراءة Firestore مباشرة، والفرض في Console مُطفأ حسب المستخدم)، لذا سببه فهرس/نشر لا App Check.

### حقائق بيئة مؤكَّدة
- **الربط بالإنتاج مؤكَّد:** `.firebaserc` (default: alrahmat-console)، و`FirebaseEmulatorConfig` محمي: `firebase_emulator_config.dart:11` (`bool.fromEnvironment('USE_FIREBASE_EMULATORS')`, افتراضي false) + `:89` (`if (kReleaseMode) throw ...`). فالإصدار الموقّع **لا يمكنه** استخدام Emulator ولا مشروع QA.
- **المنطقة متطابقة:** الدوال `us-central1` (financial.js:35)، والعميل يستخدم `FirebaseFunctions.instance` الافتراضي (us-central1) — **ليست سبب العطل**.
- **البذر التلقائي معطّل في الإنتاج:** `organization_seed_service.dart:34` (`if (!kDebugMode || !FirebaseEmulatorConfig.enabled) return;`) → مجلس الإنتاج `rahmat_general_council` وبياناته (settings/charges/roles) يجب أن تكون **مُنشأة مسبقًا** في الإنتاج (Console/سكربت)، لا من التطبيق.
- **إخفاء السبب الحقيقي:** معالجة الأخطاء تبتلع الكود الأصلي:
  - `receipt_upload_screen.dart:118` يسجّل `error.runtimeType` فقط (لا `code`/`message`).
  - `council_booking_screen.dart:321` و`:414` تستخدم `error: (_, __)` وتتجاهل الخطأ.
  → لا يظهر `unauthenticated`/`failed-precondition` في السجل. (توصية Logging في القسم 8.)

---

## 3) الأسباب المحتملة (لم يمكن تأكيدها بلا وصول للإنتاج)
- **الدوال غير منشورة على الإنتاج:** لو أن `firebase deploy --only functions` لم يُنفَّذ للإنتاج، فالنداءات تُرجع `not-found`/`internal` بدل App Check — نفس الأعراض. المصدر يحوي الدوال، لكن حالة النشر غير قابلة للتأكيد هنا.
- **الفهارس غير منشورة:** يُرجَّح لكن غير مؤكَّد (يحتاج فحص Console → Firestore → Indexes).
- **نقص بيانات المجلس (Bootstrap):** إن كان مجلس الإنتاج بلا `settings`/`charges`، فبعض المسارات ترجع فارغًا لا خطأً (getPayableCharges يرجع `charges: []`)، لكن `getBookingAvailability`/`createBooking` قد تفشل إن غابت إعدادات الحجز. يحتاج فحص بيانات الإنتاج.
- **App Check مسجّل جزئيًا:** لو سُجِّل Play Integrity دون بصمة SHA الصحيحة للإصدار الموقّع، يفشل التحقق أيضًا.

---

## 4) جدول الأعطال (التأثير والأولوية والتصنيف)

| # | العطل (الرسالة) | المسار | التصنيف المرجّح | التأثير | الأولوية |
|---|---|---|---|---|---|
| 1 | تعذر تحميل الرسوم المتاحة | getPayableCharges (callable) | `unauthenticated` (App Check) أو not-found (غير منشور) | يمنع رفع الإيصالات/الدفع كليًا | **حرجة P0** |
| 2 | تعذر تحميل مواعيد الحجز | getBookingAvailability (callable) | `unauthenticated` (App Check) أو not-found | يمنع رؤية أيام الحجز والحجز | **حرجة P0** |
| 3 | تعذر تحميل حجوزاتك | streamForUser (Firestore) | `FAILED_PRECONDITION` (فهرس غير منشور) | يمنع عرض حجوزات العضو | **عالية P1** |
| — | مخاطر مشابهة (كل callables المالية/الحجز) | submitFinancialReceipt, searchCouncilMembers, createBooking, reviewBooking, ... | App Check | يعطّل النظام المالي والحجوزات بالكامل في الإنتاج | **حرجة P0** |

> ملاحظة: الأعطال 1 و2 و«المخاطر المشابهة» لها **نفس السبب الجذري** (App Check) ويُصلَحها إجراء واحد.

---

## 5) هل التطبيق مربوط فعليًا بالإنتاج؟
**نعم، مؤكَّد 100%.** نسخة Release تتصل بـ `alrahmat-console`؛ لا يمكن تفعيل Emulator في Release (حماية `kReleaseMode`)، ولا مشروع QA (`demo-financial-prestaging`) إلا بـ dart-define في بناء debug. لا يوجد أي احتمال أن نسخة الإنتاج تتصل بـ Emulator أو مشروع خاطئ.

---

## 6) عدم التوافق: القواعد/الفهارس/الدوال/البيانات
| العنصر | الحالة في المستودع | الحالة المتوقّعة في الإنتاج | ملاحظة |
|---|---|---|---|
| **App Check** | الكود يفرضه (enforceAppCheck:true) | غير مُسجّل/مُهيّأ (حسب الخطة) | **عدم توافق حرج** — سبب العطلين 1،2 |
| **Firestore Indexes** | `bookings(userId,bookingDate)` موجود (:176-181) | يُرجَّح غير منشور | سبب العطل 3 |
| **Cloud Functions** | موجودة في المصدر (financial/notifications/production_security/audit) | حالة النشر غير مؤكَّدة | يجب التحقق |
| **Firestore Rules** | فيها تعديلات محلية (owner/system_owner) غير منشورة | نسخة أقدم منشورة | ليست سبب هذه الأعطال الثلاثة |
| **بيانات المجلس** | البذر debug فقط | يجب أن تكون منشأة مسبقًا | يحتاج فحص |

---

## 7) خطة الإصلاح (مرتّبة وآمنة — لا تُنفَّذ الآن)
1. **حسم App Check (P0):** قرار بين:
   - (أ) **تسجيل Play Integrity** في App Check Console لـ `com.alrahmat.village_council` (+ بصمات SHA للإصدار الموقّع) وإضافة debug tokens لأجهزة QA — ثم إبقاء `enforceAppCheck: true`. **(الأفضل أمنيًا)**، أو
   - (ب) اتباع الخطة التدريجية: **تخفيف `enforceAppCheck` مؤقتًا** لدوال القراءة منخفضة الخطورة (getPayableCharges/getBookingAvailability) حتى يكتمل تسجيل App Check، ثم إعادة تفعيله — مع إعادة نشر الدوال.
   - في الحالتين: **مزامنة `APP_CHECK_ACTIVATION_PLAN.md` مع واقع الكود** (الوثيقة حاليًا مغلوطة).
2. **نشر الفهارس (P1):** `firebase deploy --only firestore:indexes` → يعالج "حجوزاتك".
3. **التحقق من نشر الدوال (P0):** التأكد أن كل callables المالية/الحجز منشورة على الإنتاج (Console → Functions)، وإلا نشرها.
4. **تحسين تسجيل الأخطاء (P2):** إظهار `FirebaseFunctionsException.code/details` و`FirebaseException.code` بدل الرسالة العامة (انظر القسم 8).
5. **التأكد من بيانات مجلس الإنتاج (P1):** وجود `settings`/`financial_profile`/`roles`/`charges` عبر سكربت إداري (لا بذر من التطبيق).

## 8) الملفات المتوقّع تعديلها في مرحلة الإصلاح
- (إن اختير التخفيف) `functions/financial.js` و`functions/production_security.js` — `enforceAppCheck`.
- `project-brain/APP_CHECK_ACTIVATION_PLAN.md` — مزامنة الحالة الحقيقية.
- تحسين Logging: `lib/presentation/screens/member/receipt_upload_screen.dart` (:118)، `lib/presentation/screens/member/council_booking_screen.dart` (:321,:414)، `lib/data/repositories/booking_repository.dart`، `lib/data/repositories/financial_repository.dart`.
- لا تعديل على `firestore.indexes.json` (موجود) — فقط نشره.

## 9) الاختبارات المطلوبة بعد الإصلاح
- `flutter analyze` + `flutter test` + `cd functions && npm test`.
- يدويًا على بناء Release موقّع بجهاز QA: تحميل الرسوم، مواعيد الحجز، حجوزاتي — دون أخطاء.
- App Check: تسجيل debug token لجهاز QA والتأكد من مرور النداءات.
- Console → Firestore → Indexes: تأكيد اكتمال بناء فهرس `bookings`.

## 10) قائمة ما يحتاج Deploy لاحقًا (لا تُنفَّذ الآن)
- `firebase deploy --only firestore:indexes --project alrahmat-console`
- `firebase deploy --only functions --project alrahmat-console` (بعد حسم App Check)
- **App Check Console:** تسجيل Play Integrity (Android) + App Attest (iOS) — إجراء Console وليس CLI.
- (منفصل، من جلسات سابقة) `firebase deploy --only firestore:rules`، `--only storage` — ليست سبب هذه الأعطال.

---

## 11) نتائج الفحوصات الآمنة
- **functions `npm test`:** ✅ **22 pass / 0 fail** (يتضمّن `every sensitive financial and booking callable enforces App Check`).
- **flutter test:** ✅ **All tests passed (51)** — تشمل `booking_availability_test` و`omr_currency_test`.
- **flutter analyze:** ⚠️ **4 تحذيرات فقط (لا أخطاء)** — كلها عناصر غير مستخدمة (dead code) في `admin_dashboard.dart`: `_StatsCards` (:337)، `_PendingCard` (:463)، `_EmptyPending` (:536)، `_StatsShimmer` (:561). **لا علاقة لها بأعطال الحجوزات/الرسوم** (تنظيف اختياري لاحقًا؛ لم أُعدّلها التزامًا بقيود التدقيق).
- **Git:** لم يُلمس. الحالة عند البدء: `M .claude/settings.json`, `M .gradle/.../fileHashes.lock` فقط (تُركت كما هي).

## 12) فحص أوسع (مخاطر مشابهة)
- **الإشعارات:** تعتمد على `onNotificationCreated` (FCM) — منفصلة عن App Check callables؛ تعمل إن نُشرت الدوال.
- **الدفع عن الآخرين/الاشتراكات/الإيصالات/البحث في الأعضاء:** كلها callables بـ `enforceAppCheck:true` → **ستفشل في الإنتاج بنفس سبب App Check** (نفس الإصلاح يعالجها).
- **العملة العمانية (بيسة/OMR):** اختبارات الدوال تؤكّد صحّتها (تحويل صحيح، ثلاث خانات) — لا مشكلة ظاهرة.
- **العضويات/الأدوار/الصلاحيات:** تعديلات owner/system_owner محلية غير منشورة — لا علاقة بأعطال الحجز/الرسوم.
