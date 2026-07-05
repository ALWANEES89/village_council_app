# PRE_DEPLOY_TEST_CHECKLIST — اختبار ما قبل النشر

> نفّذ على **Staging / Emulator** — لا تختبر المحاولات السلبية على الإنتاج. الهدف: لا حساب ينفّذ عملية خارج صلاحياته، ولا وصول عبر المجالس، وكل عملية حسّاسة تُنتج سجل audit صحيحاً.

## 0. التحضير
- [ ] نشر على Staging: `firebase deploy --only functions,firestore:rules`.
- [ ] 4 حسابات في مجلس **A**: عضو، مدير إداري (`adminManager`)، مالي (`financialManager`/`financialReviewer`)، سوبر أدمن.
- [ ] مجلس **B** بمدير مختلف (لاختبار العزل).
- [ ] فتح Firestore Console + Functions Logs للمراقبة.
- [ ] `flutter analyze` نظيف، `node --check` للدوال ناجح.

## 1. عضو عادي (member) — مجلس A
- [ ] الدخول يفتح لوحة العضو (لا لوحة إدارة، لا بطاقة سجل الأحداث).
- [ ] رفع إيصال ينجح → **Audit:** `receipt.submitted`.
- [ ] (سلبي) محاولة تعديل عضويته لـ `fullAccess` → **يُرفض**.
- [ ] (سلبي) كتابة audit_logs يدوياً → **يُرفض**.

## 2. مدير مجلس (adminManager) — مجلس A
- [ ] تظهر: طلبات الانضمام، إدارة الأعضاء، سجل الأحداث.
- [ ] **لا يظهر** زر "تغيير الصلاحية".
- [ ] اعتماد طلب عضوية → **Audit:** `membership_request.approved` + `membership.created`.
- [ ] تعليق/تفعيل عضو → **Audit:** `membership.status_changed`.
- [ ] (سلبي) تعديل `roleId`/`permissionsSnapshot` لعضو مباشرةً → **يُرفض**.

## 3. حساب مالي — مجلس A
- [ ] تظهر مراجعة الإيصالات + سجل الأحداث.
- [ ] اعتماد إيصال → `approved` → **Audit:** `receipt.approved` (الفاعل مالي).
- [ ] رفض إيصال (بسبب) → `rejected` → **Audit:** `receipt.rejected` مع `rejectionReason`.
- [ ] لا تظهر إدارة الأدوار.

## 4. سوبر أدمن
- [ ] شارة Super Admin + بطاقات المجالس/الصلاحيات/سجل الأحداث.
- [ ] تغيير صلاحية عضو → **Audit:** `membership.role_changed` (old/new roleId، الفاعل صحيح).
- [ ] تعديل صلاحيات دور → **Audit:** `role.permissions_changed` (**ليس** unknown).
- [ ] تعديل/أرشفة مجلس → **Audit:** `organization.updated`/`organization.status_changed`.
- [ ] Audit Viewer يعرض **كل المجالس** (A و B).

## 5. العزل بين المجالس 🔒
- [ ] مدير A لا يرى مجلس B في قائمة سجل الأحداث.
- [ ] (سلبي) استعلام `organizations/B/audit_logs` بحساب مدير A → **يُرفض**.
- [ ] (سلبي) `collectionGroup('memberships')` بلا فلتر userId → **يُرفض/فارغ**.
- [ ] عملية في A لا تُنشئ سجلاً في `organizations/B/audit_logs`.

## 6. الحجوزات — مجلس A
- [ ] عضو ينشئ حجزاً → `pending` → **Audit:** `booking.created`.
- [ ] مخوّل يعتمد → `approved` → **Audit:** `booking.approved`.
- [ ] رفض حجز آخر → `rejected` → **Audit:** `booking.rejected`.
- [ ] حساب بلا صلاحية → لا زر اعتماد، ومحاولة مباشرة تُرفض.

## 7. Audit Viewer
- [ ] السجلات مرتّبة (الأحدث أولاً).
- [ ] الفلاتر تعمل: action / actorRole / targetType / التاريخ / بحث بالاسم.
- [ ] توسيع سجل يُظهر old/new + `source=cloud_function`.
- [ ] لا زر تعديل/حذف؛ شارة "للقراءة فقط".
- [ ] لا `actorRole=unknown` في عملية جديدة.

## 8. سلامة السجل (append-only)
- [ ] (سلبي) تعديل سجل audit → **يُرفض**.
- [ ] (سلبي) حذف سجل audit → **يُرفض**.
- [ ] (سلبي) إنشاء سجل audit من العميل → **يُرفض**.

## معايير القبول
- [ ] كل المحاولات السلبية رُفضت.
- [ ] لا وصول عبر المجالس.
- [ ] كل عملية حسّاسة أنتجت سجلاً في المجلس الصحيح بالفاعل الصحيح.
- [ ] Audit Viewer صحيح وللقراءة فقط.
- [ ] `flutter analyze` نظيف.
