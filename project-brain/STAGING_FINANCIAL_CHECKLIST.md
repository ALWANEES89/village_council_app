# قائمة تجهيز staging للنظام المالي

## إنشاء البيئة

- [ ] إنشاء Firebase project منفصل باسم واضح لا يساوي `alrahmat-console`.
- [ ] تفعيل Auth وFirestore وStorage وFunctions وFCM.
- [ ] إضافة تطبيق Android وتطبيق iOS خاصين بـstaging وملفات إعداد منفصلة.
- [ ] تثبيت Node 20 محليًا وتشغيل اختبارات Functions وEmulator به.

## النشر إلى staging فقط

- [ ] أخذ نسخة احتياطية قبل أي migration.
- [ ] مراجعة project ID مرتين ثم نشر Rules وIndexes وStorage Rules وFunctions إلى staging فقط.
- [ ] انتظار اكتمال بناء كل الفهارس والتحقق من الاستعلامات الفعلية.
- [ ] تشغيل migration بوضع dry-run ومقارنة عدد السجلات وإجماليات الريال والبيسة.
- [ ] تطبيق migration على staging فقط بعد موافقة مستقلة ونسخة احتياطية.

## التحقق

- [ ] اختبار callables للحسابات والإيصالات والبحث والإدارة والحجوزات.
- [ ] اختبار مولد الرسوم وتحديث المتأخرات عبر trigger المجدول الحقيقي.
- [ ] اختبار sweep التخزين الفعلي مع ملفات staging مؤقتة فقط.
- [ ] اختبار حجز عضو وغير عضو والإلغاء و`refundRequired`.
- [ ] تنفيذ قائمة QA الهاتف.
- [ ] تفعيل App Check تدريجيًا وفق خطته ومراقبة المقاييس.

## rollback وشروط الإنتاج

- الاحتفاظ بنسخة Rules/Indexes/Functions السابقة ونسخة Firestore الاحتياطية.
- إيقاف الجدولة الجديدة أولًا عند خلل مالي، وعدم تعديل الأرصدة يدويًا بلا audit.
- لا موافقة على production قبل نجاح Node 20، وEmulator، وstaging، والفهارس، وmigration rehearsal، وQA Android/iOS، ومراجعة مستقلة للإجماليات والصلاحيات.
