# EXECUTIVE SUMMARY

- تم تشغيل التطبيق بنجاح على Android Emulator.
- التطبيق أقلع بصيغة Debug ووصل إلى الشاشة الرئيسية بحساب جلسة موجودة مسبقًا.
- عدد المسارات المكتشفة: 35 مسارًا معرفًا في `lib/router/app_router.dart`، إضافة إلى المسار الجذري.
- الشاشات المختبرة فعليًا: 5 شاشات/مسارات رئيسية (الرئيسية، الحساب، الحجوزات، المدفوعات، الإشعارات).
- الشاشات غير المختبرة: 30 مسارًا تقريبًا، بسبب عدم توفر حسابات/بيانات أدوار إضافية آمنة وعدم تنفيذ أي كتابة في Production.
- P0: 0
- P1: 1
- P2: 2
- P3: 2
- P4: 1

# DEVICE & BUILD

- Emulator: Pixel_5_API_35 / `emulator-5554`
- Android: 15
- API level: 35
- Resolution: 1080x2340
- Build: PASS
- Install and launch: PASS
- Flutter VM service: started successfully
- Debug App Check token was requested by the application.

# CURRENT WORKTREE STATE

تم الحفاظ على الـworktree كما هو ولم يتم تعديل أي Source Code أو تنفيذ Git destructive command.

- توجد تعديلات مسبقة واسعة في المشروع قبل بدء QA.
- توجد ملفات متتبعة معدلة وملفات جديدة غير متتبعة.
- لم يتم تنفيذ commit أو push أو deploy أو migration أو حذف بيانات.
- الملفات المسموح بها التي أضيفت أثناء هذه المهمة:
  - `project-brain/FULL_APP_EMULATOR_QA_REPORT_AR.md`
  - `project-brain/qa-screenshots/`

# SCREEN INVENTORY

| Screen | Route | Role | Tested? | Result |
|---|---|---|---|---|
| Login | `/login` | All | لا | NOT TESTED؛ جلسة emulator كانت مسجلة مسبقًا |
| OTP | `/otp` | All | لا | NOT TESTED؛ لا تنفيذ Auth فعلي |
| Register | `/register` | New user | لا | NOT TESTED |
| Organization selector | `/organizations` | Member | جزئي | ظهرت العضويات الموجودة أثناء الإقلاع |
| Join request | `/join-request`, `/join` | Member | لا | NOT TESTED؛ لا إرسال طلب Production |
| Personal Home | `/member-home` | Member | نعم | تعمل مع ملاحظات الأداء والسجل |
| My Account | `/account` | Member | نعم | ظهرت بيانات الحساب والعضوية |
| Notifications | `/notifications` | Member | نعم | القائمة والرسائل ظهرت |
| Notification settings | `/notifications/settings` | Member | لا | NOT TESTED |
| Member dashboard | `/dashboard` | Member | لا | NOT TESTED |
| Council dashboard | `/council` | Council roles | لا | NOT TESTED |
| Council bookings | `/council/bookings` | Council roles | جزئي | شاشة الحجوزات ظهرت من التنقل، مع خطأ تحميل مواعيد |
| Important alerts | `/council/alerts` | Council roles | لا | NOT TESTED |
| Send council notification | `/council/notifications/send` | Council roles | لا | لا إرسال فعلي |
| Financial report | `/council/finance/report` | Finance roles | لا | NOT TESTED |
| Expenses | `/council/finance/expenses` | Finance roles | لا | لا إنشاء مصروف |
| Upload receipt | `/upload-receipt` | Member | لا | لا رفع بيانات Production |
| Council booking | `/rentals` | Member/Guest | جزئي | تم الوصول إلى شاشة الحجز من Home |
| Receipt history | `/receipts/history` | Member | لا | NOT TESTED |
| Guest receipt | `/booking/guest-receipt` | Guest | لا | NOT TESTED |
| Transaction timeline | `/transaction/:id` | Member/Admin | لا | NOT TESTED |
| System admin dashboard | `/admin` | system_owner | لا | لم يتم فتحه دون مسار آمن مستقل |
| Create organization | `/admin/organizations/create` | system_owner | لا | لم يتم إنشاء مجلس |
| Organizations management | `/admin/organizations` | system_owner | لا | NOT TESTED |
| Roles management | `/admin/roles` | Admin | لا | NOT TESTED |
| Admin review | `/admin/review/:id` | Finance roles | لا | NOT TESTED |
| Financial review | `/admin/financial-review` | Finance roles | لا | NOT TESTED |
| Financial management | `/admin/financial-management` | Finance roles | لا | NOT TESTED |
| Membership requests review | `/admin/membership-requests` | Admin | لا | NOT TESTED |
| Booking requests review | `/admin/booking-requests` | Admin | لا | NOT TESTED |
| Member management | `/admin/members` | Admin | لا | NOT TESTED |
| Audit logs | `/admin/audit` | Admin | لا | NOT TESTED |
| Member details | `/admin/members/:userId` | Admin | لا | NOT TESTED |
| Member permissions | `/admin/members/:userId/permissions` | Admin | لا | NOT TESTED |

# ROLE MATRIX

| Role | Visible | Accessible | Denied | Status |
|---|---|---|---|---|
| member | Home, bookings, payments, notifications, account | نعم جزئيًا | غير مختبر | TESTED PARTIALLY |
| chairman | - | - | - | NOT TESTED |
| owner/council_owner | - | - | - | NOT TESTED |
| financialManager | - | - | - | NOT TESTED |
| financialReviewer | - | - | - | NOT TESTED |
| adminManager | - | - | - | NOT TESTED |
| system_owner | ظهرت عضوية system_owner في السجل | غير مختبر عبر لوحة النظام | - | NOT TESTED |

# DETAILED ISSUES

## QA-001

- Severity: P1
- Screen: Firebase-backed startup / membership loading
- Role: Member with existing session
- Steps: تشغيل التطبيق على emulator مع App Check production enforcement.
- Expected: تكتمل طلبات Firebase بشكل طبيعي.
- Actual: `App attestation failed` مع HTTP 403، ثم استخدام placeholder token.
- Evidence: سجل emulator يعرض `Error getting App Check token ... code: 403 body: App attestation failed`.
- Logs: `copilot-detached-4-1789177988646-c0e37ce9-5615-4e0f-94e0-54af618be18c.log` قرب السطر 84.
- Suspected component: Firebase App Check configuration for Debug emulator.
- Suggested fix direction: ضبط Debug App Check allow-list أو بيئة QA منفصلة. لم يتم التنفيذ.

## QA-002

- Severity: P2
- Screen: Home / membership loading
- Role: Member
- Steps: تشغيل التطبيق ومراقبة تحميل العضويات.
- Expected: استخدام مسار قراءة مصرح به دون أخطاء متكررة.
- Actual: Firestore collection-group query تفشل بـ `PERMISSION_DENIED` ثم يعمل fallback ويحمّل العضويات.
- Evidence: `Listen for Query ... collectionGroup=memberships ... failed: Missing or insufficient permissions`.
- Suspected component: Firestore rules أو الاستعلام collection-group.
- Suggested fix direction: مراجعة قواعد collection-group والاستعلام البديل. لم يتم التنفيذ.

## QA-003

- Severity: P2
- Screen: Home / organization selector
- Role: Member
- Steps: تشغيل الشاشة التي تعرض بطاقات/قوائم العضويات.
- Expected: لا تظهر Flutter framework assertions.
- Actual: تكرار رسالة `ListTile background color or ink splashes may be invisible`.
- Evidence: Flutter exception في السجل مع DecoratedBox وListTile.
- Suspected component: ListTile داخل DecoratedBox ذي خلفية مباشرة.
- Suggested fix direction: إضافة Material محلي حول ListTile أو إزالة الخلفية الوسيطة. لم يتم التنفيذ.

## QA-004

- Severity: P2
- Screen: Home / organization selector
- Role: Member
- Steps: تشغيل الشاشة على 1080x2340.
- Expected: لا يوجد overflow.
- Actual: `A RenderFlex overflowed by 48 pixels on the right`.
- Evidence: سجل Flutter قرب السطر 129.
- Suspected component: Row أو نص طويل في بطاقة العضوية/اختيار المجلس.
- Suggested fix direction: مراجعة constraints وFlexible/overflow في العنصر المتسبب. لم يتم التنفيذ.

## QA-005

- Severity: P3
- Screen: App startup and Home
- Role: Member
- Steps: تشغيل التطبيق على emulator.
- Expected: استجابة أولية سلسة.
- Actual: skipped frames متعددة، منها 61 و94 و263 و224 frame.
- Evidence: `Skipped ... frames! The application may be doing too much work on its main thread`.
- Suspected component: startup Firebase/listener work أو بناء قوائم كبيرة.
- Suggested fix direction: profiling لاحقًا وعدم اعتبارها فشلًا وظيفيًا. لم يتم التنفيذ.

## QA-006

- Severity: P4
- Screen: Android platform integration
- Role: All
- Steps: تشغيل التطبيق على Android 15.
- Expected: لا تحذيرات تكامل مؤثرة.
- Actual: تحذير `OnBackInvokedCallback is not enabled`.
- Evidence: Android log.
- Suspected component: Android manifest/platform back callback configuration.
- Suggested fix direction: مراجعة إعداد Android 13+ عند الحاجة. لم يتم التنفيذ.

# LOCALIZATION QA

- Home وAccount وNotifications ظهرت بالعربية وRTL.
- ظهرت بعض قيم الحالات بالإنجليزية مثل `cancelled`, `rejected`, `approved`, و`active`.
- لم يتم اختبار التبديل إلى English لأن الاختبار الحالي بدأ بجلسة قائمة ولم يتم تغيير إعدادات Production.
- لم يتم رصد قص نص واضح من accessibility tree، لكن يوجد overflow مسجل يجب فحصه بصريًا.

# NAVIGATION QA

- Home، Account، Payments، Notifications أمكن الوصول إليها.
- Bookings فتحت شاشة حجوزات مستقلة وتعرض زر الرجوع.
- لا يمكن اعتبار كل عناصر bottom navigation مختبرة بالكامل لأن التنقل بعد دخول شاشة الحجوزات لم يعد يعرض الشريط نفسه.
- لم يتم اختبار Android Back لكل المسارات.

# MULTI-TENANT QA

- الجلسة تحتوي على 4 عضويات نشطة في مجالس مختلفة.
- ظهرت العضويات بالمعرّفات:
  - `rahmat_general_council`
  - `JDxPUEmnPN3tYMyGEVcp`
  - `2KkO3hNOMiiQBy175CmU`
  - `org_b60a943da4d846e9b8d3fe73c08af979`
- لم يتم تبديل المجلس A → B → A بشكل كامل، لذلك لا يوجد إثبات كامل لعدم تسرب البيانات.
- لم يتم تنفيذ أي كتابة أو حجز أو دفع أثناء الاختبار.

# AUTH QA

- جلسة Auth موجودة مسبقًا واستمرت بعد تشغيل emulator.
- Login وOTP وRegister غير مختبرة.
- ظهر App Check 403، وهو منفصل عن Auth لكنه يؤثر على طلبات Firebase.

# BOOKINGS QA

- شاشة حجوزات المستخدم ظهرت وبها حجوزات بحالات مختلفة.
- ظهرت حالات `cancelled`, `rejected`, `approved`.
- شاشة الحجز تعرض رسالة: `تعذر تحميل مواعيد الحجز. حاول مرة أخرى.` في إحدى مراحل التنقل.
- لم يتم إنشاء أو تعديل أو إلغاء أي حجز.

# FINANCIAL QA

- شاشة ملخص الحساب أظهرت:
  - إجمالي الرسوم: 36.000 ريال عُماني
  - إجمالي المدفوع: 1.000 ريال عُماني
  - المتبقي: 35.000 ريال عُماني
  - قيد المراجعة: 0.000 ريال عُماني
- ظهرت عملية رفع إيصال.
- لم يتم رفع إيصال أو اعتماد/رفض أو إنشاء رسم.

# NOTIFICATIONS QA

- مركز الإشعارات فتح بنجاح.
- ظهرت قائمة إشعارات تتعلق بالحجوزات والرسوم والإيصالات.
- لم يتم اختبار فتح كل deep link أو وضع القراءة لكل عنصر.

# ADMIN QA

- لم يتم فتح مسارات الإدارة ضمن هذه الجولة لأن الاختبار لم يتضمن تخمين أو إنشاء credentials.
- لم يتم اختبار إنشاء مجلس، إدارة المجالس، الأدوار، المراجعة المالية، أو طلبات العضوية.

# SYSTEM ADMIN QA

- السجل يثبت أن الحساب يملك `system_owner` داخل عضوية موجودة.
- لم يتم تنفيذ عمليات System Admin الكتابية.
- لوحة النظام ومسارات إدارة المجالس غير مختبرة بصريًا في هذه الجولة.

# UNTESTED ITEMS

- Login language switcher وvalidation.
- Register وOTP.
- Join Council وطلب الانضمام.
- English/LTR.
- System Admin screens.
- Council Dashboard وAlerts.
- Roles and permission matrix لجميع الأدوار.
- Full multi-tenant switching.
- Receipt review and financial management.
- Send notification.
- Empty/error/retry states لكل المسارات.
- Back navigation الكامل.

# TOP 10 PRIORITIES

1. حل App Check 403 في بيئة QA دون تعطيل حماية Production.
2. مراجعة `PERMISSION_DENIED` لاستعلام collection-group memberships.
3. إصلاح RenderFlex overflow بمقدار 48 بكسل.
4. معالجة تحذير ListTile داخل DecoratedBox.
5. التحقيق في فترات skipped frames أثناء startup.
6. إعادة اختبار شاشة الحجز ورسالة تعذر تحميل المواعيد بعد استقرار الاتصال.
7. اختبار تبديل المجالس الأربعة والتحقق من عزل البيانات.
8. إجراء QA منفصل لحساب system_owner على لوحة الإدارة.
9. اختبار الترجمة الإنجليزية وRTL/LTR.
10. تنفيذ جولة QA ثانية للحالات الفارغة والأخطاء وإعادة المحاولة.

# EVIDENCE

- Screenshot: `project-brain/qa-screenshots/home.png`
- Emulator log: `C:\Users\alwan\AppData\Local\Temp\copilot-detached-4-1789177988646-c0e37ce9-5615-4e0f-94e0-54af618be18c.log`
- Routes source: `lib/router/app_router.dart`
