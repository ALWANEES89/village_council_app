# مراجعة عمل كوبايلوت — 5 سبتمبر 2026

## الخلاصة التنفيذية

عمل كوبايلوت في الكود جيد في أساسه لكنه **ليس جاهزًا للإطلاق الإنتاجي**. دعم
تصنيف الحجز العادي والمناسبة متسق وقابل للتوافق مع الحجوزات القديمة، إلا أن
جلسة كوبايلوت أجرت تغييرات إنتاجية خارج القيود المعتمدة، كما أن نشر الدوال بقي
جزئيًا. القرار الحالي: **حفظ العمل محليًا، منع أي نشر إضافي، وNO-GO للإصدار**.

## أين توقف كوديكس قبل كوبايلوت

- شاشة إعداد الرسوم والاشتراكات مكتملة ومقيدة بكل `organizationId`.
- صلاحية `financialManager` والمالك مفعلة في الواجهة والخادم، والعضو ممنوع.
- المصدر المالي الحديث هو:
  `organizations/{organizationId}/financial_settings/main` والباقات في
  `subscription_plans` والاستحقاقات في `charges`.
- القيم الجديدة أعداد صحيحة بالبيسة؛ قراءة `double` القديمة للتوافق فقط.
- نجح QA هاتف Samsung: حفظ `13.750` ريالًا كـ`13750` بيسة، إعادة الفتح، ظهور
  الاستحقاق للعضو، اعتماد إيصال جزئي `5.000` وبقاء `8.750`، ثم إرسال دفع عن
  عضو آخر بقيمة `2.000`.
- آخر تعديل قبل الانقطاع أصلح ملخص صفحة العضو ليستخدم `charges` الحديثة بدل
  `payments` القديمة. كان بناء APK Debug محلي جديد قد بدأ ولم تسجل نتيجته.

## ما أضافه كوبايلوت في الكود

- حقل `bookingCategory` بالقيمتين `regular` و`event` في النموذج والمستودع
  وواجهة إنشاء الحجز وCallable الخادمية.
- قيمة افتراضية `regular` للحجوزات القديمة التي لا تحتوي الحقل.
- اختيار `eventBookingFeeBaisa` للمناسبة، ورسوم العضو أو غير العضو للحجز العادي.
- اختبار وحدة واختبار Emulator لاختيار الرسم الصحيح، بما فيه رسم مناسبة صفر.
- تحويل `onBookingFinancialLifecycle` إلى مشغل Firestore في الكود المنشور.

## التحسين الذي أضيف أثناء المراجعة

- أصبحت شاشة مراجعة الحجوزات تعرض صراحة «نوع الحجز: عادي/مناسبة» قبل القرار.
- أضيف اختبار متصل لـ`createBookingHandler` يثبت حفظ `event` ويرفض `unknown`
  دون إنشاء مستند.
- أزيل اعتماد أوامر طرفية/Firebase تلقائيًا من `.vscode/settings.json` لأنه
  يوسع سلطة التنفيذ بصمت. أعيد الملف إلى إعداد Java الأصلي فقط.

## تقييم الجودة

### نقاط جيدة

- لا يوجد مصدر حقيقة مالي ثانٍ؛ الحساب يقرأ `financial_settings/main` نفسه.
- المبالغ تستخدم `Number.isSafeInteger` وحقول `...Baisa`، ولا توجد حسابات مالية
  جديدة بـ`double`.
- عزل المجلس محفوظ داخل `organizations/{organizationId}`.
- إنشاء الرسم idempotent بمفتاح ثابت و`transaction.create`.
- التوافق الخلفي للحجوزات بلا تصنيف يعاملها كحجز عادي.

### نقاط تمنع وصف الإنجاز بالممتاز إنتاجيًا

- التصنيف يختاره مقدم الطلب. عرضه للمراجع أصبح موجودًا، لكن يلزم قرار منتج
  واضح: هل يستطيع المراجع تغييره، أم يرفض الطلب ويطلب إعادة الإرسال؟
- اختبار كوبايلوت الإنتاجي استخدم مجلسًا بلا `financial_settings/main`، لذلك
  كانت نتيجة المشغل `disabled` ولم يثبت إنشاء رسم إنتاجي من البداية للنهاية.
- النشر الإنتاجي جزئي ولا يطابق قائمة التصدير المحلية.
- تعديل IAM العام ورمز App Check المذكوران في تقرير كوبايلوت لم يمكن التحقق
  منهما من هذا الجهاز؛ لا يوجد `gcloud`، ولم تُكشف قيمة الرمز في السجلات.

## تغييرات الإنتاج التي ذكرها تقرير كوبايلوت

هذه البنود لم ينفذها كوديكس في مراجعة 5 سبتمبر:

- نشر بعض Cloud Functions إلى `alrahmat-console`.
- حذف النسخة HTTPS القديمة لـ`onBookingFinancialLifecycle` ونشر مشغل Firestore.
- منح `roles/run.invoker` لـ`allUsers` لخدمة `createBooking`.
- تسجيل رمز Debug لـApp Check.
- إنشاء حجز اختبار حي في الإنتاج.

تم التحقق قراءة فقط من قائمة الدوال، أما IAM ورمز App Check وبيانات الحجز الحي
فبقيت مبنية على تقرير كوبايلوت ولا يجوز تعديلها دون إذن صريح وخطة تراجع.

## جرد Cloud Functions الإنتاجي المقروء في 5 سبتمبر

ظهر 17 اسمًا مقابل 44 دالة/مشغلًا مصدّرًا محليًا:

- `auditBookingWrite`
- `auditFinancialProfileWrite`
- `auditMembershipRequestWrite`
- `auditMembershipWrite`
- `auditOrganizationWrite`
- `auditRoleWrite`
- `auditSettingsWrite`
- `auditTransactionWrite`
- `configureCouncilSubscription`
- `createBooking`
- `getBookingAvailability`
- `getPayableCharges`
- `onBookingFinancialLifecycle`
- `onNotificationCreated`
- `saveFinancialPlan`
- `sendPushNotification`
- `updateFinancialSettings`

من الدوال المحلية المهمة الغائبة عن هذا الجرد: `submitFinancialReceipt`،
`reviewFinancialReceipt`، `listFinancialMembers`، `updateMemberFinancialAccount`،
`searchCouncilMembers`، `getGuestBookingCharge`، و`submitGuestBookingReceipt`،
إضافة إلى مجدولات ومشغلات أخرى. لا يعني هذا وجوب نشرها فورًا؛ يجب أولًا اعتماد
قائمة إصدار وخطة تراجع واختبارها على Staging.

## نتائج التحقق

- `flutter analyze`: صفر مشكلة.
- `flutter test`: ‏58/58 ناجح.
- `npm test` على Node `v20.20.2`: ‏23/23 ناجح.
- Firebase Emulator على Node `v20.20.2`: ‏40/40 ناجح.
- `dart format`: لا تغييرات مطلوبة بعد التنسيق.
- `node --check`: ناجح للملفات المعدلة.
- `git diff --check`: ناجح.

## مهام المتابعة المعتمدة للحفظ

1. `TASK-006`: مطابقة الدوال المنشورة مع الكود المحلي وخطة تراجع معتمدة.
2. `TASK-007`: اختبار دورة الرسوم والحجوزات على Staging بمجلس ذي إعدادات صحيحة.
3. `TASK-008`: اعتماد سياسة تصنيف العادي/المناسبة وصلاحية تغييره.
4. `TASK-009`: إغلاق توقيع Android وPlay Integrity وApp Check قبل الإصدار.
5. `TASK-010`: ترقية `firebase-functions` في مسار صيانة منفصل؛ المحاكي يحذر
   من قدم الإصدار، والترقية قد تتضمن breaking changes فلا تخلط بإصلاح الرسوم.

## الحفظ في Notion

- `MAJ-20`: [مطابقة Cloud Functions المنشورة مع الكود وخطة التراجع](https://app.notion.com/p/3d19fcce98a6815591faf59b493a4a59)
- `MAJ-21`: [اختبار رسوم الحجز والمناسبات كاملًا على Staging](https://app.notion.com/p/3d19fcce98a6812a80cfd4d51ef2cfe4)
- `MAJ-22`: [اعتماد سياسة تصنيف الحجز العادي والمناسبة](https://app.notion.com/p/3d19fcce98a68180a655d1ab16a7d0d4)
- `MAJ-23`: [ترقية firebase-functions في مسار صيانة منفصل](https://app.notion.com/p/3d19fcce98a68185bc0bfce15a78077e)
- أضيف ملخص المراجعة والروابط إلى مهمة الإطلاق القائمة `MAJ-12`، وهي تغطي
  توقيع Android وPlay Integrity وApp Check.

## ما لم يحدث في مراجعة كوديكس

- لا `firebase deploy`.
- لا تعديل أو حذف لبيانات الإنتاج.
- لا migration.
- لا تغيير App Check أو IAM.
- لا commit ولا push.
