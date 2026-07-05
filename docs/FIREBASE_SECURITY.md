# FIREBASE_SECURITY — أمان Firebase (المصادقة + التخزين + أفضل الممارسات)

> نظرة أمنية شاملة. تفاصيل قواعد Firestore في `FIRESTORE_RULES.md`؛ الأدوار في `ROLES_AND_PERMISSIONS.md`.

## 1. Firebase Authentication
- **النموذج:** حساب واحد لكل شخص (Firebase Auth uid).
- **آلية الدخول الحالية:** رقم هاتف + كلمة مرور، عبر `AuthService.signInWithPhoneAndPassword` الذي يشتقّ بريداً من الهاتف. مصدر الدخول الحالي هو مجموعة `members` القديمة (DEC-006).
- **الهوية بعد الدخول:** `users/{uid}` (V2) + عضويات المستخدم عبر collectionGroup مقيّد بـ `userId`.
- **لا كلمات مرور في Firestore:** القواعد ترفض أي مستند يحوي `password`/`passwordHash` (`hasNoPasswordFields`/`hasNoProtectedUserFields`).
- **Custom Claims:** غير مستخدمة حالياً؛ `superAdmin` يُقرأ من `platform_admins`. الترحيل إلى Claims قرار مستقبلي (يحسّن الأداء).

## 2. طبقات الدفاع (Defense in Depth)
1. **الواجهة:** تُخفي الأزرار غير المصرّح بها (مثل "تغيير الصلاحية" مقيّد بـ `canManageRoles`).
2. **Firestore Rules:** الطبقة الحاسمة — تمنع أي عملية غير مصرّح بها حتى لو تخطّى العميل الواجهة.
3. **Cloud Functions (Admin SDK):** العمليات الموثوقة (السجل، الإشعارات) خادمية.
> **قاعدة:** لا تعتمد على الواجهة وحدها إطلاقاً. كل زر إداري يقابله شرط في القواعد.

## 3. Firebase Storage — `storage.rules`
| المسار | القراءة | الكتابة |
|---|---|---|
| `receipts/{memberId}/{paymentId}/{file}` (قديم) | المالك أو الأدمن | المالك فقط، ≤10MB، صور/PDF |
| `users/{userId}/profile/{file}` | أي مستخدم مسجّل | المالك فقط، ≤5MB، صور |
| `organizations/{orgId}/members/{userId}/receipts/{id}/{file}` | المالك أو `isFinanceReviewer(orgId)` | المالك فقط، ≤10MB، صور/PDF؛ **لا حذف** |
- ⚠️ **قاعدة بنيوية إلزامية:** دوال Storage Rules يجب أن تُعرَّف **داخل** `match /b/{bucket}/o` (وليس على مستوى `service`)؛ التعريف الخاطئ **يُفشل تصريف الملف** فيُرفض النشر وتبقى قواعد الإنتاج قديمة (يظهر كـ `firebase_storage/unauthorized` رغم صحّة المسار). تحقّق دائمًا قبل النشر: `firebase deploy --only storage --dry-run`.
- دوال Storage تتحقق عبر `firestore.exists()` قبل `firestore.get()` لتفادي فشل التقييم على مستند مفقود.
- `isFinanceReviewer(orgId)` = أدمن/سوبر أدمن أو عضوية بدور مالي/`receipts.review` — **معزول لكل مجلس**.
- **TODO أمني موثّق:** قراءة الإيصالات عبر `firestore.get` مكلفة/هشّة؛ يُفضّل مستقبلاً Signed URLs أو Cloud Function أو Custom Claims.

### ملكية الإيصال = auth.uid (قاعدة صارمة)
مسار رفع الإيصال `organizations/{orgId}/members/{userId}/receipts/{receiptId}/{fileName}` يشترط `request.auth.uid == userId`، وقاعدة إنشاء معاملة Firestore تشترط `userId == auth.uid && uploadedByUserId == auth.uid`. لذلك **مالك الإيصال هو دائمًا المستخدم المسجّل**؛ لا يجوز الرفع باسم مستخدم آخر.
- التطبيق يشتقّ المالك من `FirebaseAuth.currentUser.uid` في نقطة واحدة (`UploadNotifier.uploadReceipt`) ولا يثق بأي معرّف ممرّر من الشاشات.
- ⚠️ **مزلق تاريخي:** الحسابات القديمة قد يختلف فيها معرّف مستند `members` عن `auth.uid` (fallback عبر الهاتف في `AuthService`). تمرير هذا المعرّف القديم كمالك يسبّب `firebase_storage/unauthorized`. الحل المعتمد: استخدام `auth.uid` حصريًّا.
- مدفوعات العائلة (paidFor) تُنشئ سجلات مرتبطة منفصلة؛ ملف الإيصال نفسه يبقى مملوكًا للرافع (`auth.uid`).

## 4. سلامة سجل الأحداث
- `audit_logs`: `create,update,delete: if false` للعميل — يُكتب فقط من Cloud Functions (Admin SDK). append-only ومقاوم للتلاعب. راجع `AUDIT_LOGS.md`.

## 5. أفضل ممارسات الأمان (Best Practices)
- **Deny-by-default:** أي مسار جديد مرفوض حتى يُصرّح صراحةً (DEC-010).
- **عزل بالمجلس:** كل قاعدة تتحقق من العضوية/الصلاحية في **نفس** `organizationId`.
- **فصل الواجبات:** تغيير الأدوار (`roles.manage`) منفصل عن إدارة الأعضاء (`members.manage`) (DEC-004).
- **حماية الحقول الحسّاسة:** `roleId`/`permissionsSnapshot`/`userId`/`organizationId`/`isAdmin`/`status` لا تُكتب إلا عبر المسار المصرّح.
- **تقييد collectionGroup:** دائماً بحقل يفرض ملكية المستخدم (`userId == request.auth.uid`).
- **لا أسرار في الكود:** مفاتيح Firebase العامة مقبولة؛ لا تضع أسراراً خادمية في الـ client.
- **مراجعة إلزامية:** كل ميزة جديدة تمرّ على مراجعة Rules + Functions + Audit قبل الدمج.

## 6. تهديدات معروفة ومخفَّفة
| التهديد | التخفيف |
|---|---|
| تصعيد صلاحيات (member.manage → fullAccess) | DEC-004 — الدور/الصلاحيات تتطلب roles.manage |
| تسريب بيانات عبر المجالس | DEC-005 — تقييد list/collectionGroup |
| تزوير/حذف السجل | DEC-003 — سجل خادمي append-only |
| انتحال الفاعل في السجل | الفاعل يُشتقّ خادمياً + `updatedBy` موثّق |

## 7. مخاطر متبقية (Residual — موثّقة للمتابعة)
- `platform_admins` و`roles` قابلة للقراءة لأي مستخدم مسجّل (كشف معلومات محدود، TODO في القواعد).
- بيانات PII (الاسم/الرقم المدني/الهاتف) مخزّنة على مستند العضوية؛ أعضاء نفس المجلس قد يقرؤونها (قاعدة `isOrganizationMember`). يُنصح بتقييدها مستقبلاً.
- النظام القديم `members/isAdmin` مسار صلاحية واسع — يُتقاعد وفق DEC-006.
- بذر أول مجلس باسم ثابت (DEC-007) — يُستبدل بإنشاء يقوده superAdmin.
