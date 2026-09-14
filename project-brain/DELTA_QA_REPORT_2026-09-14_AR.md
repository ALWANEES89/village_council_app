# تقرير Delta QA — 2026-09-14

## PREVIOUSLY VERIFIED — NOT RETESTED

اعتمدت Baseline السابق لمسار الانضمام، اللغة، عزل إشعار المجلس، واختبارات Flutter
102/102 وNode 28/28 دون إعادتها. أُعيد فقط ما تأثر بتعديلات هذه الجولة.

## NEW TESTS PERFORMED

| السيناريو | الدور | النتيجة | الدليل | الخلل/الإصلاح |
|---|---|---|---|---|
| إرسال Council Notification من UI | Financial Manager | PASS | رجوع تلقائي للوحة وظهور Recent Activity | أضيف requestId ثابت لإعادة المحاولة الآمنة |
| عدم التكرار وعزل البيانات | Financial Manager | PASS | Broadcast واحد، 5 Notifications، كلها `qa_financial_council` | PASS |
| شاشة المستلم وread/unread | Financial Manager كمستلم | PASS | ظهر الإشعار، والنقر حفظ `status=read` و`readAt` | PASS |
| لغة شاشة الإشعارات | مستخدم EN | FAIL ثم PASS | ظهرت EN/LTR واسم المجلس الإنجليزي بعد الإصلاح | أزيل RTL والنص العربي الثابت |
| Forgot Password | مستخدم غير مسجل | FAIL | لا زر ولا Route ولا Screen؛ Login يعرض إنشاء حساب فقط | ميزة غير مكتملة، لم تُبنَ في QA |
| Role Matrix — Financial Manager | Financial Manager | PASS جزئي | إعدادات/تقارير/مراجعة/مصروفات وإرسال متاحة حسب قدراته | لا صلاحية نظام عامة |
| Role Matrix — Financial Reviewer | Financial Reviewer | PASS | مراجعة وتقارير ومصروفات قراءة؛ لا إعداد رسوم ولا إرسال ولا إضافة مصروف | شاشة المراجعة نفسها غير مترجمة EN |
| Personal مقابل Council | Manager + Reviewer | PASS | Home عرض حساب الشخص، Dashboard عرض 5 أعضاء وحجوزات المجلس | فصل المصادر صحيح |
| Logout | Financial Manager | PASS | عاد إلى Login مع بقاء بيانات التطبيق | PASS |
| مصفوفة الحماية الموجهة | أدوار متعددة | PASS 13/13 | اختبارات policy/system owner/financial settings | العضو لا يرث fullAccess والمراجع لا يعدل الإعدادات |

## REMAINING UNTESTED ITEMS

- UI عملي لأدوار Council Owner/Chairman/Admin Manager/System Owner.
- ترقية User B ثم تسجيل الدخول به، ونقل الملكية.
- مستخدم واحد بثلاثة أدوار في ثلاثة مجالس وتبديل المجلس عبر UI.
- دورات Booking approve/reject الجديدة، وحجوزات free/paid/exempt.
- دورة Receipt approve/reject/full/partial والتحديث المالي الفعلي.
- مطابقة أرقام التقارير المالية ببيانات QA وحركة مصروف جديدة.
- كل Cards وDeep Links وBack في لوحة المجلس.
- بقية عناصر My Account: Contact/About/subscriptions/payments.
- foreground/background Push؛ لا يوجد FCM Emulator كامل.

## NEW BUGS FOUND

1. احتمال تكرار الإشعار عند نجاح الخادم وانقطاع الرد قبل استلام العميل.
2. Notifications Screen كانت تفرض العربية وRTL في وضع English — أُصلحت.
3. Financial Review Screen تعرض العربية في وضع English — مفتوح.
4. Forgot Password غير موجود وظيفيًا في الواجهة — مفتوح.
5. Important Alerts تعرض `Could not load data` لحساب Financial Manager — يحتاج تشخيصًا مستهدفًا.

## FIXES MADE

- أصبح `requestId` إلزاميًا للمستودع وثابتًا طوال عمر نموذج الإرسال.
- ترجمت شاشة الإشعارات وأزيل Directionality القسري، واختير اسم المجلس حسب اللغة.
- أضيفت رسائل AR/EN للتحميل والقراءة وتحديث الإشعار.

## SECURITY FINDINGS

لا يوجد تسرب جديد مثبت. الإرسال بقي مقيدًا بمجلس واحد، والعضو لا يرث
`fullAccess`، والمراجع لا يستطيع تعديل الإعدادات أو المصروفات. اختبارات UI وباقي
عمليات الإدارة المباشرة ما زالت ضمن المتبقي أعلاه.

## FINANCIAL FINDINGS

الفصل بين Home الشخصي وDashboard المجلس صحيح في الحسابين المختبرين. لم تُنفذ بعد
دورة مالية جديدة تسمح بالحكم على الحسابات والتقارير في هذه الجولة.

## RECOMMENDED ADDITIONS

- بناء Forgot Password عبر OTP للهاتف الموثق وربط الدالة
  `resetPasswordWithVerifiedPhone`، بدل بريد `@alrahmat.local` غير القابل للاستلام.
- استكمال Localization لشاشة مراجعة الإيصالات.
- إضافة fixture رسمي متعدد المجالس/الأدوار إلى seed حتى تصبح مصفوفة UI قابلة للتكرار.

## FINAL VERDICT

نطاق التقرير الأصلي للإشعار أصبح READY، لكن جولة Delta الواسعة نفسها ما زالت:

**NOT READY**
