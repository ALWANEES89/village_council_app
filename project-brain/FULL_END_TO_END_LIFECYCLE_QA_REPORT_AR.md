# FULL END-TO-END LIFECYCLE QA REPORT

## EXECUTIVE SUMMARY

هذه الجولة كانت مخصصة لاختبار دورة حياة المستخدم كاملة من إنشاء الحساب حتى العضوية والحجوزات والإيصالات والمالية والإشعارات.

تم إيقاف الاختبارات الكتابية قبل تنفيذ أي Write لأن:

- منافذ Firebase Emulator المطلوبة (`9099`, `8080`, `5001`, `9199`) غير مشغلة.
- `.firebaserc` يحدد المشروع `alrahmat-console`، وهو مشروع Firebase فعلي وليس Emulator.
- تفعيل Emulator في التطبيق يتطلب Build flags صريحة (`USE_FIREBASE_EMULATORS=true` و`FIREBASE_PROJECT_ID=demo-financial-prestaging`) ولم تكن مفعلة في النسخة الحالية.

**BLOCKED: SAFE QA WRITE ENVIRONMENT REQUIRED**

لم يتم إنشاء مستخدم أو مجلس أو عضوية أو حجز أو إيصال أو تنبيه، ولم يتم تغيير دور أو بيانات Production.

- Total scenarios: 22
- Steps executed: 5 خطوات تحقق أمني وبيئي فقط
- Passed: 0 سيناريوهات E2E
- Failed: 0
- Blocked: 22
- P0: 0
- P1: 0
- P2: 0
- P3: 0
- P4: 0

## DEVICE & ENVIRONMENT

- Emulator requested: `Pixel_5_API_35`
- Previous available emulator: Android 15 / API 35
- Current Firebase Emulator services:
  - Auth `9099`: CLOSED
  - Firestore `8080`: CLOSED
  - Functions `5001`: CLOSED
  - Storage `9199`: CLOSED
- Production/default Firebase project in `.firebaserc`: `alrahmat-console`
- QA project identifier expected by the app's safety guard: `demo-financial-prestaging`

## CURRENT WORKTREE STATE

تم تنفيذ هذه الجولة دون تعديل Source Code ودون `format` أو `analyze` أو `deploy` أو `commit` أو `push`.

يوجد Worktree واسع التعديلات مسبقًا. لم يتم استخدام:

- `git reset`
- `git checkout`
- `git restore`
- حذف ملفات
- حذف بيانات أو Clear App Data

الملف الجديد المسموح به في هذه الجولة هو هذا التقرير فقط.

## SAFETY CHECKS

| Check | Result | Evidence |
|---|---|---|
| Firebase Emulator Auth | BLOCKED | Port 9099 closed |
| Firebase Emulator Firestore | BLOCKED | Port 8080 closed |
| Firebase Emulator Functions | BLOCKED | Port 5001 closed |
| Firebase Emulator Storage | BLOCKED | Port 9199 closed |
| Safe QA project/build flags | BLOCKED | Current defaults point to `alrahmat-console` |

## SCENARIO 1 — NEW USER

### Step 1

- Action: فتح Login بدون جلسة قديمة.
- Expected: ظهور شاشة الدخول وإمكانية Register/OTP.
- Actual: BLOCKED؛ لا يمكن إنشاء حساب آمن بدون Emulator أو QA منفصلة.
- Result: BLOCKED

### Step 2

- Action: إنشاء USER_A والتحقق من OTP وvalidation.
- Expected: حساب QA جديد.
- Actual: لم ينفذ؛ قد يكتب في Production.
- Result: BLOCKED

## SCENARIO 2 — JOIN COUNCIL

- Action: البحث عن QA Council وإرسال طلب انضمام.
- Expected: طلب Pending واحد دون تكرار.
- Actual: BLOCKED؛ يتطلب إنشاء مستخدم وبيانات مجلس.
- Result: BLOCKED

## SCENARIO 3 — MEMBER EXPERIENCE

- Action: فحص Home وBookings وPayments وReceipts وNotifications وAccount بعد العضوية.
- Expected: وصول العضو لبياناته فقط.
- Actual: BLOCKED؛ لا توجد USER_A آمنة.
- Result: BLOCKED

## SCENARIO 4 — BOOKING SUBMIT

- Action: إنشاء حجز بتاريخ متاح.
- Expected: `pending` ويظهر في My Bookings.
- Actual: BLOCKED؛ لا كتابة Production.
- Result: BLOCKED

## SCENARIO 5 — BOOKING APPROVE

- Action: فتح ADMIN_A والموافقة على الحجز.
- Expected: `approved` وإشعار للمستخدم.
- Actual: BLOCKED؛ لا يوجد ADMIN_A أو QA Council آمن.
- Result: BLOCKED

## SCENARIO 6 — BOOKING REJECT

- Action: رفض حجز Pending.
- Expected: `rejected` وإشعار وظهور الحالة في My Bookings.
- Actual: BLOCKED.
- Result: BLOCKED

## SCENARIO 7 — BOOKED DATE CONFLICT

- Action: إرسال طلب إضافي في يوم محجوز.
- Expected: تحذير وتبقى الحالة Pending ولا تعتمد تلقائيًا.
- Actual: BLOCKED.
- Result: BLOCKED

## SCENARIO 8 — BOOKING CANCELLATION

- Action: طلب إلغاء حجز Approved واعتماد الإلغاء.
- Expected: تحديث الحالة وتحرير التاريخ حسب القاعدة.
- Actual: BLOCKED.
- Result: BLOCKED

## SCENARIO 9 — FREE BOOKING

- Action: إنشاء حجز مجاني والموافقة عليه.
- Expected: amount يساوي صفرًا ولا ينشأ Charge غير لازم.
- Actual: BLOCKED؛ لا تغيير إعدادات مالية على Production.
- Result: BLOCKED

## SCENARIO 10 — PAID BOOKING

- Action: إنشاء حجز مدفوع والموافقة عليه.
- Expected: إنشاء Charge صحيح بـ `amountBaisa` وظهوره في Payments.
- Actual: BLOCKED.
- Result: BLOCKED

## SCENARIO 11 — RECEIPT UPLOAD

- Action: رفع ملف إيصال QA.
- Expected: Receipt Pending Review مرتبط بالمجلس والرسم الصحيح.
- Actual: BLOCKED؛ لا رفع Storage أو Firestore على Production.
- Result: BLOCKED

## SCENARIO 12 — RECEIPT APPROVE

- Action: اعتماد الإيصال من ADMIN_A أو FINANCE_A.
- Expected: تحديث المدفوع والمتبقي وTimeline وإشعار المستخدم.
- Actual: BLOCKED.
- Result: BLOCKED

## SCENARIO 13 — RECEIPT REJECT

- Action: رفع إيصال ثانٍ ورفضه.
- Expected: Rejected مع سبب وإشعار وعدم احتساب Paid.
- Actual: BLOCKED.
- Result: BLOCKED

## SCENARIO 14 — MEMBER PROMOTION

- Action: ترقية USER_A إلى `adminManager` أو دور محلي مناسب.
- Expected: تحديث Role/Permissions دون منحه system_owner.
- Actual: BLOCKED؛ تغيير الأدوار كتابة حساسة.
- Result: BLOCKED

## SCENARIO 15 — ADMIN EXPERIENCE

- Action: فحص Council Dashboard وإدارة الأعضاء والحجوزات والإيصالات.
- Expected: ظهور الوظائف حسب الصلاحيات.
- Actual: BLOCKED؛ لا توجد حسابات QA.
- Result: BLOCKED

## SCENARIO 16 — COUNCIL DASHBOARD

- Action: اختبار كل Cards والروابط والبيانات.
- Expected: لا Dead Cards وتوجيه صحيح.
- Actual: BLOCKED.
- Result: BLOCKED

## SCENARIO 17 — NOTIFICATIONS

- Action: إرسال تنبيه QA والتحقق من وصوله لـUSER_A فقط.
- Expected: organizationId صحيح وعدم وصوله لمجلس آخر.
- Actual: BLOCKED؛ إرسال Notification كتابة Production.
- Result: BLOCKED

## SCENARIO 18 — IMPORTANT ALERTS

- Action: فتح التنبيهات المهمة ومعالجة عناصرها.
- Expected: وجهات صحيحة وتحديث القائمة بعد المعالجة.
- Actual: BLOCKED؛ يحتاج بيانات Pending آمنة.
- Result: BLOCKED

## SCENARIO 19 — RECENT ACTIVITY

- Action: فتح Activity للحجز والإيصال والعضوية والتنبيه.
- Expected: Deep link صحيح وسياق المجلس صحيح.
- Actual: BLOCKED.
- Result: BLOCKED

## SCENARIO 20 — FINANCIAL REPORT

- Action: مقارنة Total Collected وOutstanding وRevenue وExpenses وNet Position.
- Expected: تطابق الحساب اليدوي.
- Actual: BLOCKED؛ لا يمكن إنشاء Dataset QA أو تعديل مصروفات.
- Result: BLOCKED

## SCENARIO 21 — MULTI-TENANT

- Action: تبديل USER_A بين Council A وCouncil B ثم العودة.
- Expected: عزل Home وBookings وPayments وNotifications وDashboard.
- Actual: BLOCKED؛ لا توجد QA councils آمنة.
- Result: BLOCKED

## SCENARIO 22 — LOGOUT/LOGIN/RESTART

- Action: Logout/Login وإعادة تشغيل التطبيق.
- Expected: بقاء العضوية والدور واللغة والمجلس والإشعارات والحجوزات.
- Actual: BLOCKED؛ يعتمد على بيانات السيناريوهات السابقة.
- Result: BLOCKED

## FINAL PASS MATRIX

| Scenario | Steps | Passed | Failed | Blocked | Result |
|---|---:|---:|---:|---:|---|
| New user | 2 | 0 | 0 | 2 | BLOCKED |
| Join council | 1 | 0 | 0 | 1 | BLOCKED |
| Member experience | 1 | 0 | 0 | 1 | BLOCKED |
| Booking submit | 1 | 0 | 0 | 1 | BLOCKED |
| Booking approve | 1 | 0 | 0 | 1 | BLOCKED |
| Booking reject | 1 | 0 | 0 | 1 | BLOCKED |
| Date conflict | 1 | 0 | 0 | 1 | BLOCKED |
| Cancellation | 1 | 0 | 0 | 1 | BLOCKED |
| Free booking | 1 | 0 | 0 | 1 | BLOCKED |
| Paid booking | 1 | 0 | 0 | 1 | BLOCKED |
| Receipt upload | 1 | 0 | 0 | 1 | BLOCKED |
| Receipt approve | 1 | 0 | 0 | 1 | BLOCKED |
| Receipt reject | 1 | 0 | 0 | 1 | BLOCKED |
| Member promotion | 1 | 0 | 0 | 1 | BLOCKED |
| Admin experience | 1 | 0 | 0 | 1 | BLOCKED |
| Council dashboard | 1 | 0 | 0 | 1 | BLOCKED |
| Notifications | 1 | 0 | 0 | 1 | BLOCKED |
| Important alerts | 1 | 0 | 0 | 1 | BLOCKED |
| Recent activity | 1 | 0 | 0 | 1 | BLOCKED |
| Financial report | 1 | 0 | 0 | 1 | BLOCKED |
| Multi-tenant | 1 | 0 | 0 | 1 | BLOCKED |
| Logout/Login/Restart | 1 | 0 | 0 | 1 | BLOCKED |

## SEVERITY COUNTS

- P0: 0
- P1: 0
- P2: 0
- P3: 0
- P4: 0

لا يمكن تصنيف Bugs وظيفية من دورة E2E لم تبدأ بسبب Safety Block.

## TOP 20 BUGS

لا توجد قائمة Bugs مؤكدة في هذه الجولة؛ لم يتم تنفيذ سيناريوهات الكتابة أو دورة الحياة المطلوبة.

## WHAT CODEX SHOULD FIX FIRST

لا توجد إصلاحات Source Code ناتجة عن هذه الجولة. الخطوة الأولى المطلوبة قبل إعادة QA:

1. توفير Firebase Emulator Suite تعمل على المنافذ 9099 و8080 و5001 و9199، أو توفير QA Firebase project منفصل ومصرح.
2. تشغيل التطبيق مع Build flags الآمنة:
   - `USE_FIREBASE_EMULATORS=true`
   - `FIREBASE_EMULATOR_HOST=10.0.2.2` للمحاكي
   - `FIREBASE_PROJECT_ID=demo-financial-prestaging`
3. تهيئة Seed آمن لـ`QA Council` وUSER_A وADMIN_A وFINANCE_A داخل Emulator/QA فقط.
4. إعادة تنفيذ السيناريوهات 1–22 وتسجيل Firestore/Storage state بعد كل Write.

## REQUIRED TO RESUME

- تأكيد أن النسخة المتصلة ليست `alrahmat-console`.
- تشغيل Emulator Suite أو تقديم QA project منفصل.
- توفير حسابات QA أو Seed script آمن.
- توفير ملف إيصال اختبار محلي غير حساس.
- عدم تنفيذ أي Firebase deploy أو Production migration.

## ADDENDUM — LOCAL EMULATOR RERUN

تم تشغيل Firebase Emulator Suite محليًا وبشكل منفصل عن Production باستخدام المشروع:
`demo-financial-prestaging`.

### Environment verification

| Service | Result |
|---|---|
| Auth emulator `9099` | PASS |
| Firestore emulator `8080` | PASS |
| Functions emulator `5001` | PASS؛ تم تحميل الدوال ومن ضمنها `bootstrapOrganization` و`createBooking` |
| Storage emulator `9199` | PASS |
| Flutter emulator build flags | PASS؛ ظهر وسم `بيئة اختبار محلية` داخل التطبيق |

تمت تهيئة بيانات QA داخل Emulator فقط:

- `USER_A` — `qa-user-a`
- `ADMIN_A` — `qa-admin-a`
- `FINANCE_A` — `qa-finance-a`
- `QA Council A` — `qa_council_a`
- `QA Council B` — `qa_council_b`
- عضويات الإدارة والمالية والصلاحيات الأساسية للمجلسين

### UI execution status

تم فتح التطبيق على `Pixel_5_API_35` والتقاط شاشة الدخول المحلية:
[qa-login-emulator.png](./e2e-qa-screenshots/qa-login-emulator.png)

تعذر إكمال دورة الـ E2E من خلال واجهة الهاتف في هذه الجولة بسبب عطل قابل للتكرار أثناء تشغيل واجهة Debug:

1. التطبيق دخل في `ANR` (`village_council_app isn't responding`) بعد إعادة تشغيله من الجهاز.
2. بعد الاستعادة ظهرت شاشة الدخول المحلية، لكن إدخال رقم الهاتف عبر Android input injection لم يحافظ على قيمة الحقل بصورة مستقرة؛ كان الحقل يعيد القيمة أو يعتبرها غير مكتملة قبل الضغط على تسجيل الدخول.
3. لذلك لم يتم احتساب أي سيناريو وظيفي على أنه `PASS` أو `FAIL` بالحدس، ولم يتم تنفيذ كتابات إضافية من الواجهة.

### Updated result

- Emulator safety: **PASS**
- QA seed: **PASS**
- Source code changes: **NONE**
- Production writes/deploys: **NONE**
- E2E scenarios completed: **0**
- E2E scenarios blocked by device/UI execution: **22**
- Confirmed new functional bugs: **0**

### Required next action

إعادة تشغيل الجولة عبر جلسة Flutter/DTD تفاعلية مستقرة أو عبر اختبار تكامل Flutter مخصص للـ Emulator بدل Android input injection. لا يلزم تعديل Source Code اعتمادًا على هذه الجولة وحدها؛ خطأ الـ ANR وإعادة ضبط حقل الهاتف يحتاجان أولًا إلى trace كامل من جلسة Flutter تفاعلية قبل اقتراح إصلاح.
