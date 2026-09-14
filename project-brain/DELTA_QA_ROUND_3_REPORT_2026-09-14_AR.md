# تقرير Delta QA — الجولة الثالثة — 2026-09-14

هذا التقرير يسجل النتائج الجديدة فقط، ويعتمد نتائج الجولات السابقة دون إعادة اختبارها.
كل البيانات والتعديلات التشغيلية في هذه الجولة كانت على Firebase Emulator بمشروع
`demo-financial-prestaging` فقط.

## 1. OPEN BUGS FIXED

| السيناريو | النتيجة | الجديد |
|---|---|---|
| Important Alerts لحساب Financial Manager | PASS | أصلح تعارض صلاحية `financialManager` بين Flutter وFirestore. بعد Hot Restart ظهرت «كل الأمور محدثة» بدل خطأ التحميل. |
| توجيه صفوف Important Alerts | PASS | كل صف يحمل الإجراء الخاص بنوعه بدل الاعتماد على index متغير. |
| Financial Review في English/Arabic | PASS | أزيل RTL القسري وكل النصوص العربية الثابتة، واستخدم ARB الحالي. EN ظهر LTR وAR ظهر RTL فعليًا. |
| تحذير ListTile/DecoratedBox في حسابي | PASS | استبدلت الحاوية الملونة بـ `Material` ذي shape وclip. |
| آخر إشعار في الصفحة الشخصية | PARTIAL | اكتشف تسرب إشعار مجلس A أثناء عرض C، وأضيفت فلترة بـ `organizationId`. إعادة التحقق النظيفة تعذرت بسبب cache و`too_many_pings`. |

## 2. NEW TESTS

- اختبار فعلي لـ Important Alerts على حساب Financial Manager.
- اختبار فعلي لشاشة Financial Review بالعربية والإنجليزية فقط.
- fixture لمستخدم واحد في ثلاثة مجالس: مدير مالي في A، عضو في B، مراجع مالي في C.
- تبديل فعلي A → B → C، والتحقق من اسم المجلس والدور ورقم العضوية والرصيد والحجز القادم.
- اختبارات مستهدفة للخادم لدورة الحجز/الدفع الجزئي، الإيصالات، الرسوم المعطلة والصفرية، المصروفات، وعزل مؤشرات Dashboard.
- اختبارات Flutter مستهدفة لتوجيه التنبيهات والتعريب ومنع منح أدوار الملكية.

## 3. NEW FAILURES

| السيناريو | النتيجة | التفاصيل |
|---|---|---|
| آخر إشعار بعد تبديل المجلس | FAIL ثم إصلاح غير مثبت بصريًا | ظهر إشعار `qa_financial_council` في Council C. الكود أصبح يفلتر بالقيمة المختارة، لكن جلسة Firestore الطويلة وصلت `RESOURCE_EXHAUSTED/too_many_pings` وأبقت cache قديمًا. |
| seed النهائي | PARTIAL | كتبت دفعة المجالس الثلاث بنجاح، ثم انتهى السكربت بمهلة انتظار `member_directory` لأحد الأعضاء بسبب تأخر Functions Emulator. |
| Android Back بعد Hot Restart | BLOCKED | خرج إلى Launcher؛ لأن Hot Restart أعاد بناء route كجذر، فلا تصلح هذه المحاولة للحكم على back stack الطبيعي. |

## 4. SECURITY FINDINGS

- **CRITICAL — FIXED:** كان مسار تغيير الدور السريع قادرًا نظريًا على اختيار
  `owner/council_owner/system_owner` إذا وُجدت هذه القوالب. أضيف المنع في UI،
  Repository، وFirestore Rules. نقل الملكية يبقى فقط في المسار الخادمي الذري.
- اختبار Rules المستهدف رفض أدوار الملكية وسمح بدور `adminManager` العادي: PASS.
- القراءة والكتابة العابرة للمجلس في مؤشرات Dashboard والمصروفات: PASS خادميًا.
- ترقية Member فعلية ثم تسجيل دخوله بالدور الجديد لم تكتمل: PARTIAL.

## 5. BOOKING RESULTS

- دورة الخادم: إنشاء → اعتماد → رسم واحد idempotent → دفع جزئي → إكمال → إلغاء آمن: PASS.
- منع التكرار عند تكرار lifecycle: PASS.
- fee mode معطل، ورسم صفر، وsubscription-only: PASS.
- دورة UI جديدة approve/reject من حسابين: لم تكتمل في هذه الجولة، لذلك النتيجة الشاملة PARTIAL.

## 6. RECEIPT/PAYMENT RESULTS

- بقاء الرسوم قابلة للدفع، idempotency، وفوز مراجع واحد عند الاعتماد المتزامن: PASS على Emulator.
- allocation والدفع الجزئي ومنع الدفع الزائد: PASS في الاختبارات المستهدفة.
- رفع attachment ثم approve/reject كامل عبر UI لم ينفذ ببيانات جديدة في هذه الجولة: PARTIAL.

## 7. FINANCIAL CALCULATION RESULTS

- حساب التقرير يفصل income عن expenses ويحافظ على integer baisa: PASS.
- اختبارات المنطق 23/23 شملت paid/pending/outstanding/partial/overdue/exempt: PASS.
- مقارنة أرقام شاشة التقارير بصفقة QA جديدة محسوبة يدويًا عبر UI: لم تكتمل، لذلك النتيجة الشاملة PARTIAL.

## 8. MULTI-COUNCIL RESULTS

- ظهور 3 مجالس لنفس المستخدم: PASS.
- Council A: `financialManager / QA-100`: PASS.
- Council B: `member / QA-B-100`، صفر مستحقات، لا حجز قادم، ولا بطاقة إدارة: PASS.
- Council C: `financialReviewer / QA-C-100`، صفر مستحقات، لا حجز قادم، وبطاقة لوحة المجلس: PASS.
- عزل bookings/charges الظاهر بين A وB وC: PASS.
- عزل آخر إشعار: FAIL ثم تعديل؛ إعادة التحقق على cache نظيف ما زالت مطلوبة.
- الحكم النهائي لهذا الجزء: **PARTIAL / NOT ACCEPTED YET**.

## 9. NAVIGATION/UX RESULTS

- صف التنبيه أصبح يفتح route مطابقًا لنوعه: PASS بالكود والاختبار المستهدف.
- Financial Review EN/LTR وAR/RTL: PASS على المحاكي.
- تحذير Material في `My Account` أصلح؛ بقي تحذير مشابه في Card أخرى يحتاج تحديدًا منفصلًا: PARTIAL.
- مصفوفة Back الكاملة لم تكتمل بسبب Hot Restart وحالة Emulator الطويلة: BLOCKED.

## 10. REMAINING UNTESTED

- Role promotion إيجابية كاملة User A → User B → إعادة تسجيل الدخول.
- إعادة اختبار آخر إشعار في C بعد مسح Firestore cache/تثبيت نظيف.
- Booking approve/reject كامل عبر UI.
- Receipt upload/approve/reject وattachment عبر UI ببيانات الجولة.
- مطابقة أرقام التقرير المرئية يدويًا.
- Expense create من المدير المالي وظهوره في التقرير عبر UI.
- Dashboard cards وBack matrix وبقية عناصر My Account المطلوبة.
- Forgot Password: BLOCKED معماريًا؛ الحسابات تستخدم `@alrahmat.local` ولا يوجد Phone Auth/OTP موثق ومتكامل. الخطة الآمنة: Phone Auth موثق، OTP، callable تغيير كلمة السر، رسائل غير كاشفة للحساب، rate limit/App Check، ثم ربط Login.

## 11. FILES CHANGED

- `firestore.rules`
- `functions/financial_emulator.test.js`
- `functions/scripts/seed-financial-device-qa.js`
- `lib/features/member_management/data/member_management_repository.dart`
- `lib/features/member_management/presentation/member_details_screen.dart`
- `lib/presentation/screens/admin/financial_review_screen.dart`
- `lib/presentation/screens/council/council_dashboard_screen.dart`
- `lib/presentation/screens/member/member_home_screen.dart`
- `lib/presentation/screens/member/my_account_screen.dart`
- `lib/l10n/app_ar.arb`
- `lib/l10n/app_en.arb`
- `test/council_operations_finance_expansion_test.dart`
- `test/permission_policy_test.dart`

## 12. TARGETED TESTS RUN

- Flutter permission/dashboard/localization/notification-scope tests: 15/15 PASS.
- Flutter financial logic: 23/23 PASS.
- Firestore role ownership escalation: 1/1 PASS.
- Firestore dashboard/expense/receipt/booking/fee modes: 5/5 PASS على اسم مشروع QA الصحيح.
- Node financial report arithmetic: 1/1 PASS.
- `flutter analyze`: PASS، بلا ملاحظات.
- `git diff --check`: PASS (تحذيرات CRLF فقط، بلا whitespace errors).

## 13. FINAL VERDICT

**NOT READY**

السبب: شروط القبول النهائية لا تزال تفتقد إثبات UI كامل لترقية الدور، دورة الحجز،
دورة الإيصال، مطابقة أرقام التقرير، كما أن إصلاح عزل «آخر إشعار» يحتاج إعادة تحقق
على cache نظيف. لا يوجد deploy أو تغيير Production أو commit أو push في هذه الجولة.
