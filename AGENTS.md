# AGENTS.md — التعليمات المشتركة لجميع وكلاء البرمجة

هذه التعليمات تنطبق على جميع وكلاء البرمجة المستخدمين داخل هذا المشروع،
بما في ذلك Codex وGitHub Copilot وأي Agent آخر يدعم AGENTS.md.

على الوكيل قراءة هذه التعليمات وتطبيقها قبل تنفيذ أي مهمة داخل المشروع.
> **المرجع الأعلى لطريقة العمل:**
> `project-brain/PROJECT_CONSTITUTION.md`
>
> اقرأ الدستور أولًا عند الحاجة، ولا تكرر محتواه هنا.
>
> هذا الملف يحتوي القواعد الثابتة المشتركة لوكلاء البرمجة مثل Codex.
> `CLAUDE.md` هو المرجع المقابل لـ Claude Code.
>
> **أي قاعدة مشتركة يتم تغييرها هنا يجب مزامنتها مع `CLAUDE.md` حتى لا تتعارض التعليمات.**
>
> إذا تعارض هذا الملف مع `PROJECT_CONSTITUTION.md`، فإن الدستور هو المرجع الأعلى.

---

# 1. طريقة العمل الأساسية

صاحب المشروع سيرسل أوامر برمجية متتالية ومباشرة، مثل:

* أضف ميزة.
* عدل شاشة.
* أصلح خطأ.
* غير صلاحية.
* أضف حقلًا.
* أصلح Firebase.
* عدل Provider أو Repository.
* افحص ميزة.
* اختبر سيناريو.

لا تطلب منه في كل مرة شرح طريقة التنفيذ أو الاختبار.

اعتبر كل رسالة جديدة **مهمة برمجية** ضمن المشروع الحالي.

أنت مسؤول عن تحديد:

* أين تبحث.
* ما الملفات المرتبطة.
* أقل نطاق لازم للتعديل.
* الاختبارات المناسبة.
* هل يحتاج تشغيل التطبيق.
* هل يحتاج الهاتف الحقيقي.
* هل يحتاج فحص Firebase أو Rules أو Functions.
* متى تعتبر المهمة ناجحة.

الأولوية:

1. صحة الحل.
2. سلامة البيانات والمشروع.
3. تنفيذ المطلوب كاملًا.
4. تقليل استهلاك Codex والسياق.
5. سرعة الإنجاز.
6. عدم تكرار العمل بلا داعٍ.

---

# 2. أسلوب التنفيذ الاقتصادي عالي الإنتاجية

## قاعدة مهمة

**لا تفحص المشروع كاملًا عند كل أمر.**

ابدأ بأصغر نطاق ممكن.

التدرج المفضل:

`الملف المباشر`
→ `الملفات المرتبطة`
→ `Provider / Repository / Service`
→ `Firebase / Rules / Functions`
→ `Architecture الأوسع`

وسع نطاق التحقيق فقط إذا لم يكن المستوى الحالي كافيًا.

## عند وصول مهمة جديدة

حدد نوعها أولًا، مثل:

* UI
* Flutter/Dart
* Riverpod
* Navigation
* Firebase Auth
* Firestore
* Storage
* Cloud Functions
* Notifications
* Financial
* Bookings
* Roles/Permissions
* Project Brain
* Build/Android

ثم ابحث فقط في الملفات المرتبطة مباشرة.

## لا تفعل الآتي بدون حاجة

* قراءة مجلدات المشروع كاملة.
* طباعة ملفات كبيرة كاملة في Terminal.
* إعادة قراءة نفس الملف مرارًا.
* إعادة شرح بنية المشروع بعد كل أمر.
* تشغيل اختبارات المشروع كاملة بعد كل تعديل صغير.
* تنفيذ build كامل بعد كل تعديل.
* تشغيل `flutter clean` بلا سبب.
* تنزيل dependencies من جديد بلا سبب.
* قراءة `adb logcat` بالكامل بلا فلترة.
* إصلاح مشاكل جانبية غير مرتبطة بالمهمة.

---

# 3. الاستفادة من السياق السابق

لا تبدأ كل مهمة من الصفر.

استفد مما تم اكتشافه خلال الجلسة الحالية عن:

* بنية المشروع.
* الملفات المهمة.
* Providers.
* Repositories.
* Models.
* Firestore paths.
* Cloud Functions.
* Roles.
* Permissions.
* Financial architecture.
* Booking architecture.
* المشاكل التي تم إصلاحها.
* القرارات المعمارية السابقة.

إذا كانت رسالة المستخدم الجديدة امتدادًا للمهمة السابقة، تعامل معها كـ continuation واستفد من السياق الحالي.

لا تعيد تنفيذ عمليات البحث نفسها ما لم يتغير الكود أو تظهر حاجة جديدة.

---

# 4. وصف المشروع

`village_council_app` تطبيق Flutter لإدارة **مجالس متعددة**.

كل مجلس يمثل Organization مستقلة.

التقنيات الأساسية:

* Flutter
* Dart
* Riverpod
* go_router
* Firebase Auth
* Firestore
* Firebase Storage
* Firebase Cloud Messaging
* Cloud Functions — Node 20

**Firebase هو مصدر البيانات الحقيقي.**

لا تستخدم:

* Mock
* Dummy data
* local-only implementations

في ميزات الإنتاج إلا للاختبارات أو بيئات التطوير المصرح بها.

---

# 5. تعدد المجالس Multi-Tenant

**كل عملية يجب أن تكون مقيّدة بـ `organizationId`.**

المسارات الأساسية تحت:

`organizations/{organizationId}/...`

استخدم:

* `organizationId`
* `membershipId`
* `userId`

بصورة صحيحة حسب نوع العملية.

`organizationContextProvider` هو سياق المجلس الحالي في Flutter.

ممنوع:

* خلط بيانات مجلسين.
* استخدام `memberId` وحده في استعلام متعدد المجالس.
* عرض بيانات المجلس السابق أثناء تغيير organization context.
* تمرير بيانات مالية أو حجوزات أو إيصالات بين مجالس مختلفة.

البيانات التالية مستقلة لكل مجلس:

* العضويات.
* الصلاحيات.
* الحسابات المالية.
* الرسوم.
* الاشتراكات.
* الحجوزات.
* الإيصالات.
* الإعدادات.

---

# 6. Firebase

عند إضافة Collection أو Document path جديد، افحص عند الحاجة:

* Firestore Rules
* Storage Rules
* Firestore indexes
* Cloud Functions
* organization isolation

ممنوع استخدام:

`allow read, write: if true`

في الإنتاج.

لا تثق ببيانات العميل في العمليات الحساسة.

العمليات الحساسة يجب أن تكون خادمية عندما يكون ذلك مناسبًا.

استخدم:

* server timestamps.
* Firestore transactions.
* idempotency.
* validation server-side.

عند الحاجة.

**لا تنفذ `firebase deploy` دون إذن صريح.**

لا تنفذ migration على الإنتاج بدون:

1. Backup.
2. Dry-run.
3. مراجعة النتيجة.
4. موافقة صريحة.

إذا ظهر خطأ Firebase، لا تفترض أن الكود هو السبب الوحيد.

تحقق من:

* Rules.
* Indexes.
* Functions deployment.
* App Check.
* Region.
* Authentication.
* organizationId.
* permissions.

---

# 7. Firebase App Check

فرّق دائمًا بين:

* Debug/Development
* Production
* Google Play / Play Integrity

إذا ظهر:

`App Check 403`
أو
`App attestation failed`

لا تعطل حماية الإنتاج مباشرة.

حدد السبب أولًا.

يمكن استخدام App Check Debug Provider في بيئة التطوير إذا كان ذلك مناسبًا.

لا تغير إعدادات App Check production دون سبب موثق وموافقة عند الحاجة.

---

# 8. الأدوار والصلاحيات

المالك الأعلى:

`system_owner`

وله:

`fullAccess`

صلاحيات المجلس تأتي من:

* Membership.
* Role.
* `permissionsSnapshot`.

لا تعتمد على إخفاء UI كحماية.

تحقق من الصلاحيات في الطبقات المناسبة، مثل:

* UI
* Providers/Services
* Repository
* Cloud Functions
* Firestore Rules

حسب طبيعة العملية.

الأدوار الحالية تشمل:

* `system_owner`
* `owner`
* `council_owner`
* `chairman`
* `adminManager`
* `financialManager`
* `financialReviewer`
* `member`

`superAdmin` توافق قديم داخل `platform_admins` وليس Membership Role جديدًا.

حافظ على استقلال الدور بين المجالس.

لا تغيّر دورًا أو صلاحية حساسة بدون:

* validation.
* audit.
* إشعار عند الحاجة.

---

# 9. النظام المالي

**استخدم البيسة كعدد صحيح `int`.**

`1 OMR = 1000 baisa`

اعرض المبالغ بثلاث خانات عشرية باستخدام:

`formatBaisa`

لا تستخدم `double` للحسابات المالية الجديدة.

الحقول الجديدة يجب أن تستخدم النهج الحديث مثل:

`amountBaisa`

بدل تمثيلات مالية legacy إلا عند قراءة بيانات قديمة أو migration.

كل البيانات المالية مقيّدة بـ:

* organizationId.
* membershipId عند الحاجة.
* userId عند الحاجة.

يجب منع:

* القيم السالبة.
* الدفع الزائد.
* الاعتماد المزدوج.
* إنشاء نفس الرسم مرتين.
* double allocation.
* cross-council payments.

التسديد الجزئي يجب أن يحدث بصورة صحيحة:

* paid.
* remaining.
* status.

عمليات:

* approval.
* rejection.
* allocation.

يجب أن تكون خادمية وذرية عندما تتطلب ذلك.

حافظ على توافق legacy data حتى اكتمال migration.

**رفع الإيصال هو وسيلة الدفع الفعالة حاليًا.**

`onlinePaymentsEnabled = false`

لذلك:

**لا تظهر ولا تفعّل الدفع الإلكتروني حاليًا.**

لا تخزن:

* Payment provider secrets.
* API secrets.
* Bank credentials.

داخل Flutter أو Firestore.

---

# 10. الدفع عن الآخرين

يسمح بالدفع عن:

* النفس.
* عضو آخر.
* عدة أعضاء.

لكن فقط **داخل نفس المجلس**.

البحث عن المستفيدين يكون داخل الأعضاء النشطين ويعرض أقل بيانات تعريف لازمة.

لا تنزل قائمة أعضاء المجلس كاملة بلا حاجة.

مبلغ الإيصال يجب أن يساوي:

`sum(allocations)`

بالضبط.

الخادم يعيد التحقق من:

* beneficiary.
* organization.
* membership.
* charges.
* remaining balances.
* amount.
* duplicate operations.

الإشعارات تصل عند الحاجة إلى:

* الدافع.
* المستفيدين.

ممنوع:

* overpayment.
* duplicate payment.
* duplicate approval.

---

# 11. الحجوزات والرسوم

رسوم:

* `booking`
* `event`

تنشأ عند نقطة العمل الصحيحة مع idempotency.

إعداد المجلس قد يكون:

* `free`
* `subscription`
* `booking`
* `subscriptionAndBooking`

رسوم:

* العضو.
* غير العضو.

مستقلة.

لا تنشئ رسم حجز قبل تحقق الحالة المطلوبة.

الإلغاء أو الرفض يجب أن يعالج الرسم بصورة موثقة ومتسقة.

عند تعديل Booking flow افحص حسب الحاجة:

* availability.
* conflict prevention.
* fees.
* permissions.
* Functions.
* Firestore.
* indexes.
* cancellation behavior.

---

# 12. Flutter وRiverpod

عند تعديل:

* async operations.
* navigation.
* state.
* lifecycle.

راقب خصوصًا:

* `mounted`
* `context.mounted`
* `setState after dispose`
* `ref.watch`
* `ref.read`
* `ref.listen`
* Provider lifecycle
* Navigator after `await`
* GoRouter after `await`

لا تعمل refactor واسعًا لمجرد احتمال وجود مشكلة.

أصلح فقط المشاكل المرتبطة بالمهمة أو التي تمنعها.

---

# 13. واجهة المستخدم

العربية وRTL هما الأساس.

يجب أن تكون النصوص العربية:

* سليمة.
* واضحة.
* بدون encoding corruption.

استخدم:

* Theme المشروع.
* Components الموجودة.
* تصميم متجاوب.
* loading state.
* empty state.
* error state.

راعِ:

* أحجام الهواتف المختلفة.
* سهولة الاستخدام.
* عدم تسرب بيانات المجلس السابق أثناء تغيير السياق.

---

# 14. الهاتف الحقيقي هو بيئة الاختبار الأساسية

في التطوير اليومي لهذا المشروع:

**الهاتف الحقيقي المتصل بالكمبيوتر هو جهاز الاختبار الأساسي.**

لا تستخدم Android Emulator إلا إذا طلب المستخدم ذلك صراحة أو احتاج الاختبار جهازًا/إصدار Android مختلفًا.

تحقق عند الحاجة باستخدام:

```powershell
adb devices
flutter devices
```

استخدم أثناء التطوير:

* `flutter run`
* Hot Reload
* Hot Restart

كلما كانت كافية.

لا تعيد:

* build APK.
* install APK.

بعد كل تعديل إذا كان Hot Reload أو Hot Restart يكفي.

## متى تستخدم الهاتف؟

استخدم الاختبار الفعلي على الهاتف خصوصًا عند تعديل:

* UI.
* Navigation.
* Login.
* Forms.
* Runtime permissions.
* Firebase.
* Save/update/delete.
* Subscriptions.
* Payments.
* Receipts.
* Bookings.
* Notifications.
* App Check.
* Device-specific behavior.

إذا كانت عدة تعديلات مترابطة في نفس الشاشة، أكملها أولًا ثم اختبر السيناريو كاملًا مرة واحدة بدل إعادة التشغيل بعد كل سطر.

---

# 15. قراءة Logs

استخدم Logs بصورة موجهة.

لا تقرأ `adb logcat` كاملًا إلا إذا كانت المشكلة تتطلب ذلك.

ركز على:

* Flutter.
* Dart.
* Firebase.
* Firestore.
* FirebaseFunctions.
* AppCheck.
* AndroidRuntime.
* package الخاص بالتطبيق.

إذا ظهر خطأ:

1. حدد الخطأ الحقيقي.
2. حدد السبب الجذري.
3. نفذ أقل تعديل آمن.
4. أعد الاختبار الذي فشل.
5. لا تعيد دورة فحص المشروع كاملة بدون حاجة.

---

# 16. Git وسلامة الملفات

ابدأ كل مهمة مهمة بـ:

```powershell
git status --short --branch
```

أو ما يعادلها.

حافظ على تعديلات المستخدم الحالية.

ممنوع بدون إذن:

* `git reset --hard`
* destructive checkout.
* حذف ملفات المستخدم.
* حذف untracked files الخاصة بالمستخدم.

لا تعدل generated files أو cache بلا حاجة.

لا تعمل:

* commit.
* push.

إلا بطلب صريح.

راجع:

```powershell
git diff
```

قبل التسليم عندما تكون هناك تعديلات برمجية.

اترك الملف المحلي التالي كما هو ولا تنظفه تلقائيًا:

`.gradle/9.3.0/fileHashes/fileHashes.lock`

لا تجعل ملفات غير مرتبطة تدخل ضمن التعديل الحالي.

---

# 17. الأسرار والخصوصية

لا تضف إلى المشروع:

* service-account keys.
* API secrets.
* tokens.
* local_keys.
* Bank credentials.
* ملفات Excel حساسة.
* بيانات شخصية غير ضرورية.

لا تطبع أسرارًا أو بيانات حساسة داخل Logs.

استخدم Secret Manager للأسرار الخادمية عند الحاجة مستقبلًا.

راجع `.gitignore` عند إضافة أي ملف قد يحتوي بيانات حساسة.

---

# 18. استراتيجية الاختبار الذكية

الهدف هو تحقيق جودة عالية بدون استنزاف وقت أو رصيد Codex بلا حاجة.

## المرحلة الأولى — بعد التعديل

نفذ formatter على الملفات المعدلة فقط:

```powershell
dart format <modified files>
```

## المرحلة الثانية — Static Analysis

شغّل:

```powershell
flutter analyze
```

مرة مناسبة بعد اكتمال مجموعة التعديلات المترابطة.

لا تشغله بعد كل تغيير صغير داخل نفس المهمة.

## المرحلة الثالثة — الاختبارات المرتبطة

ابدأ بأصغر اختبار يغطي التغيير.

مثال:

* Financial change → financial tests.
* Booking change → booking tests.
* Repository change → repository-related tests.
* Function change → function tests.

## المرحلة الرابعة — Full Test Suite

إذا كان:

* التغيير واسعًا.
* التغيير يمس عدة وحدات.
* هناك احتمال regression.
* الدستور يفرض ذلك.
* المهمة لن تعتبر مكتملة بدونه.

شغّل:

```powershell
flutter test
```

إذا كان التغيير في Functions:

```powershell
node --check functions/<modified-file>.js
```

ثم الاختبارات المرتبطة.

وعند الحاجة:

```powershell
cd functions
npm test
```

**إذا كان `PROJECT_CONSTITUTION.md` يفرض فحصًا أوسع من هذه السياسة، اتبع الدستور.**

لا تستخدم سياسة تقليل الاستهلاك كسبب لتجاوز اختبار إلزامي.

---

# 19. Firebase / Rules Testing

إذا تم تعديل:

* Firestore Rules.
* Storage Rules.
* Firebase Functions.
* indexes.
* security boundaries.

اختبرها محليًا أو في staging عندما يكون ذلك ممكنًا.

لا تنشر Production بغرض الاختبار.

تحقق من JSON والفهارس والملفات ذات العلاقة.

---

# 20. تعريف اكتمال المهمة

لا تعتبر المهمة `done` لمجرد أن الكود تم تعديله.

الاكتمال يعتمد على طبيعة المهمة.

قد يتطلب:

* format.
* analyze.
* targeted tests.
* full tests.
* Functions tests.
* تشغيل التطبيق.
* اختبار الهاتف.
* Firebase validation.
* logs.
* Rules validation.
* `git diff`.

لكن لا تحول كل تعديل صغير إلى QA شامل غير مبرر.

**يجب أن يكون مستوى الاختبار متناسبًا مع مستوى الخطر والتأثير.**

إذا بقي:

* Integration test أساسي.
* QA أساسي.
* خطأ يمنع السيناريو.
* security issue.
* data integrity issue.

فلا تعتبر المهمة مكتملة.

---

# 21. التعامل مع المشاكل الجانبية

إذا اكتشفت مشكلة أثناء تنفيذ مهمة أخرى:

## أصلحها إذا:

* تمنع المهمة الحالية.
* سبب مباشر للمشكلة.
* إصلاحها صغير وآمن ومرتبط مباشرة.

## لا توسع المهمة إذا:

* المشكلة مستقلة.
* تحتاج refactor واسع.
* تحتاج تغيير معماري.
* تحتاج migration.
* تحتاج Production changes.

في هذه الحالات سجلها في التقرير فقط.

---

# 22. Project Brain

`project-brain/tasks.json`

هو **مصدر حالة المهام**.

`project-brain/PROJECT_DASHBOARD.md`

ملف مولد.

**لا تعدله يدويًا.**

بعد تعديل `tasks.json` شغّل:

```powershell
.\scripts\update-project-dashboard.ps1
```

نسب الإنجاز يجب أن تكون حقيقية ومبنية على الاختبار الفعلي.

لا تخزن تفاصيل يومية أو مؤقتة داخل:

* `AGENTS.md`
* `CLAUDE.md`

المعلومات المتغيرة مكانها داخل:

`project-brain/`

---

# 23. متى تحتاج إذن المستخدم؟

اطلب الإذن قبل:

* `firebase deploy`
* migration حقيقي
* تعديل بيانات Production
* حذف بيانات Production
* `git commit`
* `git push`
* حذف ملفات
* أوامر Git المدمرة
* إضافة مكتبة كبيرة
* تغيير معماري خارج نطاق الطلب
* إدخال Payment Provider حقيقي
* التعامل مع مفاتيح أو أسرار
* أي عملية غير قابلة للتراجع بشكل آمن

لا يحتاج إذنًا إضافيًا:

* قراءة الملفات.
* البحث داخل المشروع.
* تعديل الملفات المطلوبة لتحقيق الأمر الحالي.
* formatter.
* analyze.
* الاختبارات المحلية غير المدمرة.
* تشغيل التطبيق على الهاتف.
* قراءة logs.
* dry-run لا يكتب بيانات حقيقية.

لا تطلب موافقة بعد كل مرحلة عادية من المهمة.

إذا كانت المهمة مصرحًا بها، أكمل التنفيذ حتى أقصى حد آمن.

---

# 24. إدارة استهلاك Codex

تعامل مع رصيد Codex كموارد مهمة.

قلل الاستهلاك الناتج عن:

* إعادة قراءة الملفات.
* البحث الشامل المتكرر.
* outputs ضخمة.
* تقارير طويلة أثناء التنفيذ.
* full builds المتكررة.
* full test suites غير الضرورية.
* تكرار نفس التحقيق.
* تحليل المشروع كاملًا عند كل رسالة.

ركز الاستهلاك على:

* فهم المشكلة.
* قراءة الملفات المطلوبة فقط.
* تنفيذ الحل.
* كشف الأخطاء.
* اختبار السيناريو.
* التحقق من عدم حدوث regression مرتبط.

**لا تقلل الجودة أو الأمان فقط من أجل توفير الرصيد.**

---

# 25. أسلوب التواصل أثناء العمل

لا تقدم خطة طويلة في كل مهمة.

في المهمة الطبيعية:

`افهم`
→ `ابحث`
→ `نفذ`
→ `اختبر`
→ `أبلغ بالنتيجة`

إذا كانت المشكلة كبيرة، يمكن إعطاء تحديث قصير عن أهم اكتشاف.

لا تطبع كل أمر Terminal في التقرير النهائي.

لا تكرر نفس المعلومات التي عرفها المستخدم سابقًا.

---

# 26. التقرير النهائي

اجعل التقرير مختصرًا في المهام اليومية.

استخدم الشكل التالي:

## تم

ما تم تنفيذه فعليًا.

## الملفات

الملفات المعدلة أو الجديدة المهمة فقط.

## التحقق

* Format: PASS / N/A
* Analyze: PASS / FAIL / N/A
* Tests: عدد الناجح والفاشل أو N/A
* Phone test: PASS / FAIL / N/A
* Firebase/Functions: PASS / FAIL / N/A

## السبب الجذري

يذكر فقط عندما تكون المهمة إصلاح مشكلة.

## المتبقي

المشاكل أو الخطوات التي لم تكتمل فقط.

## المخاطر

فقط إذا توجد مخاطر حقيقية.

## الخطوة التالية

خطوة واحدة أو عدة خطوات ضرورية، دون تنفيذ نشر غير مصرح به.

إذا كان `PROJECT_CONSTITUTION.md` يطلب بنية تقرير إضافية، أضفها.

لا تكتب تقريرًا مطولًا إلا إذا طلب المستخدم ذلك.

---

# 27. بنية المشروع المختصرة

| المسار                             | المحتوى                                                       |
| ---------------------------------- | ------------------------------------------------------------- |
| `lib/data/models/`                 | النماذج مثل `financial_models.dart` و`transaction_model.dart` |
| `lib/data/repositories/`           | الوصول إلى Firestore وFunctions                               |
| `lib/domain/`                      | منطق خالص قابل للاختبار                                       |
| `lib/presentation/screens/`        | الشاشات مثل `member/` و`admin/`                               |
| `lib/providers/app_providers.dart` | مزودات Riverpod                                               |
| `lib/router/app_router.dart`       | `go_router`                                                   |
| `functions/`                       | Cloud Functions                                               |
| `scripts/`                         | الأدوات الإدارية وسكربتات المشروع                             |
| `project-brain/`                   | الذاكرة الرسمية وحالة المشروع                                 |
| `docs/`                            | التوثيق المرجعي                                               |

مشروع Firebase الافتراضي:

`alrahmat-console`

المنطقة الموحدة للدوال:

`us-central1`

**أي Cloud Function جديدة يجب أن تصدر من:**

`functions/index.js`

وإلا لن يتم نشرها.

---

# 28. القاعدة التنفيذية النهائية

صاحب المشروع يحدد:

**ماذا يريد.**

وأنت تحدد تلقائيًا:

* أين تبحث.
* ماذا تقرأ.
* ماذا تعدل.
* ما الاختبار المناسب.
* هل تحتاج الهاتف.
* هل تحتاج Logs.
* هل تحتاج Firebase checks.
* هل تحتاج فحصًا أوسع.

الهدف هو أن يستطيع صاحب المشروع إرسال أوامر برمجية قصيرة ومتتالية طوال اليوم، وأن يتم تنفيذها بكفاءة عالية دون إعادة شرح قواعد العمل في كل مرة.

**لا تبدأ من الصفر في كل مهمة.
لا تفحص كل شيء بلا داعٍ.
لا تضحي بالأمان من أجل السرعة.
ولا تستهلك رصيد Codex في عمليات لا تضيف قيمة حقيقية.**
