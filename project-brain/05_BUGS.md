# سجل الأخطاء

## موانع الجاهزية الإنتاجية — غير مصنفة بعد برقم BUG/TASK

- الحالة: **Code-remediated / Operational verification open**.
- الأولوية: Critical/High.
- تاريخ المراجعة: 2026-07-23.
- أُغلقت محليًا إساءة إنشاء الإشعارات، قراءة `financial_profile` العابرة للمجالس،
  عدم اتساق المالك الأساسي، الكتابة العميلية للحجوزات وغياب slot lock، seed
  التلقائي، غياب kill switches، وfallback توقيع Release إلى debug.
- بقيت موانع لا يمكن إغلاقها في هذه الجولة: جرد/توافق بيانات production، App
  Check metrics/enforcement في Console، Scheduler/Pub/Sub E2E على staging
  منشور، نسخة احتياطية واختبار restore، وAndroid Release موقعة بمفتاح حقيقي.
- الأدلة: Flutter 51/51، Functions 22/22، Emulator 34/34، JSON 5/5،
  `node --check` ‏10/10، وAPK compile غير موقع. التفاصيل والعقود في
  `PRE_PRODUCTION_READINESS_REPORT_AR.md`.
- لم يُنشأ رقم جديد حتى يعتمد تصنيف Project Brain؛ لا يغير ذلك اكتمال
  `BUG-002` أو MAJ-8 أو `TASK-004`.

## قالب خطأ
### BUG-000 — عنوان الخطأ
- الحالة: Open
- الأولوية:
- تاريخ الاكتشاف:
- الوصف:
- السبب الجذري:
- الملفات المتأثرة:
- الحل:
- الاختبارات:
- تاريخ الإغلاق:

### BUG-001 — تعذر إنشاء Signed URL للإيصال داخل Functions Emulator
- الحالة: Closed / Device verified
- الأولوية: High
- تاريخ الاكتشاف: 2026-07-16
- الوصف: فشل فتح PDF من شاشة المراجع برسالة `firebase_functions/internal` داخل Emulator.
- السبب الجذري: بيئة Emulator لا تحتوي service-account `client_email` اللازم لتوقيع Signed URL.
- الملفات المتأثرة: `functions/financial.js`، `lib/data/repositories/financial_repository.dart`، `lib/presentation/screens/admin/financial_review_screen.dart`.
- الحل: bytes خاصة بالـEmulator بعد التفويض الصارم، مع بقاء Signed URL للإنتاج.
- الاختبارات: فتح PDF بصريًا على Samsung من حساب المراجع، و19 اختبار Emulator، واختبارات صاحب الإيصال والمراجع ذي `membershipId` المختلف والعزل بين المجالس والملفات غير الصالحة.
- تاريخ الإغلاق: 2026-07-16.

### BUG-002 — تقويم توفر الحجوزات يفشل لحساب العضو على Android
- الحالة: Closed / Device verified
- الأولوية: High
- تاريخ الاكتشاف: 2026-07-23
- الوصف: تعرض شاشة «حجز المجلس» للحساب ذي العضوية رسالة «تعذر تحميل مواعيد الحجز» بدل التقويم، مع بقاء قائمة حجوزات العضو ظاهرة. تكرر ذلك مرتين على Samsung `SM-S948B`. الحساب الضيف على الجهاز نفسه عرض التقويم والحجز المعتمد بنجاح.
- السبب الجذري: `CouncilBookingScreen` يستخدم `organizationBookingsProvider` عندما توجد `membershipId`، وهذا ينفذ استعلامًا غير مقيّد على جميع حجوزات المجلس. قواعد Firestore تسمح للعضو بقائمة مقيدة بحجوزاته فقط، وتخصص `getBookingAvailability` لعرض التوفر المنقح؛ لذلك يُرفض استعلام العضو كما هو مقصود أمنيًا.
- الملفات المتأثرة: `lib/presentation/screens/member/council_booking_screen.dart`، `lib/providers/app_providers.dart`، `lib/data/repositories/booking_repository.dart`، ومرجع السياسة في `firestore.rules`.
- الحل: أصبح تقويم العضو والضيف يستخدم `bookingAvailabilityProvider`/`getBookingAvailability` دائمًا. بقي `userBookingsProvider` المقيد بـ`userId` لقائمة «حجوزاتي» فقط. لم تتغير Firestore Rules ولم تُمنح العضوية صلاحية list غير مقيدة. أضيف parser منقح يتجاهل أي حقول زائدة ويحوّل `date` و`status` فقط إلى نموذج عرض التقويم.
- الاختبارات: Flutter ‏46/46، Functions ‏17/17 على Node `v20.20.2`، Firebase Emulator ‏23/23 على `demo-financial-prestaging`. تغطي الاختبارات نجاح العضو والضيف، التنقيح إلى `date/status`، عزل المجالس، بقاء list العضو مقيدًا، وحالات loading/empty/error. إعادة Samsung نجحت 2/2؛ ظهر التقويم و«حجوزاتي» وظهر يوم الحجز المعتمد غير متاح دون بيانات شخصية.
- تاريخ الإغلاق: 2026-07-23.
