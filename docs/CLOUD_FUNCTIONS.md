# CLOUD_FUNCTIONS — الدوال الخادمية

> المجلد: `functions/`. البيئة: Node 20، `firebase-functions` v5 (v2 API)، `firebase-admin` v12. المنطقة: `us-central1`.

## 1. الملفات
```
functions/
├── index.js     # نقطة الدخول: تهيئة admin + الإشعارات + إعادة تصدير audit
├── audit.js     # سجل الأحداث الخادمي (8 مشغّلات)
└── package.json  # engines.node=20, dependencies
```
`index.js` يستدعي `admin.initializeApp()` مرة واحدة، ثم يعيد تصدير مشغّلات `audit.js`:
```js
const auditTriggers = require("./audit");
for (const [name, handler] of Object.entries(auditTriggers)) exports[name] = handler;
```

## 2. دوال الإشعارات
### `onNotificationCreated` (`users/{userId}/notifications/{notificationId}` — onCreate)
- تجمع توكنات FCM للمستلم (`users.fcmTokens[]` + `users.fcmToken` + `members.fcmToken`).
- ترسل عبر `sendEachForMulticast`، وتنظّف التوكنات غير الصالحة من `users.fcmTokens`.

### `sendPushNotification` (`notifications_queue/{docId}` — onCreate) — Legacy
- طابور قديم لم تعد المسارات الحالية تكتب فيه (الاعتماد على `onNotificationCreated`). تُركت مؤقتاً وتُحذف لاحقاً.

## 3. دوال سجل الأحداث (`audit.js`) — 8 مشغّلات
كلها `onDocumentWritten` تحت **`organizations/{organizationId}/...`** (عزل تام، بلا مجلس ثابت):
| الدالة | المسار |
|---|---|
| `auditMembershipWrite` | `.../memberships/{membershipId}` |
| `auditRoleWrite` | `.../roles/{roleId}` |
| `auditMembershipRequestWrite` | `.../membership_requests/{requestId}` |
| `auditTransactionWrite` | `.../transactions/{transactionId}` |
| `auditBookingWrite` | `.../bookings/{bookingId}` |
| `auditSettingsWrite` | `.../settings/{settingId}` |
| `auditFinancialProfileWrite` | `.../financial_profile/{profileId}` |
| `auditOrganizationWrite` | `organizations/{organizationId}` |

### أدوات مشتركة في `audit.js`
- `resolveActor(actorUserId, organizationId)` — يستكمل الاسم/الدور.
- `writeAudit(eventId, entry)` — يكتب السجل (معرّف = `eventId` لعدم التكرار).
- `pick/equal/firstDefined/beforeAfter` — أدوات مساعدة.
- تجاهل مستندات `_meta`، وتجاهل التغييرات غير المهمّة (مثل `updatedAt` فقط).

## 4. مبادئ إلزامية لأي Cloud Function جديدة
1. **العزل:** استخدم `event.params.organizationId` ولا تفترض مجلساً. اكتب أي أثر داخل نفس المجلس.
2. **Idempotency:** استخدم `event.id` كمعرّف عند الكتابة، لتفادي التكرار عند إعادة المحاولة.
3. **لا حلقات:** لا تكتب في مسار يُطلق نفس المشغّل.
4. **Admin SDK يتجاوز القواعد** — تحقّق من صحة المدخلات بنفسك.
5. **الفاعل:** إن كانت العملية حسّاسة، اضمن وجود حقل فاعل (`updatedBy`/…) في المستند من العميل.

## 5. الاختبار المحلي
```bash
cd functions
node --check index.js
node --check audit.js
# (اختياري) المحاكي:
firebase emulators:start --only functions,firestore
```

## 6. النشر (لا تُنفَّذ على الإنتاج الآن)
```bash
cd functions && npm install && cd ..
firebase deploy --only functions --project alrahmat-console
```
> انشر **Functions + Rules معاً** لأن القواعد تمنع كتابة audit_logs من العميل، فيجب أن تكون الدوال حيّة. راجع `DEPLOYMENT_GUIDE.md`.

## 7. المراقبة
- سجلات التنفيذ: Firebase Console → Functions → Logs، أو `firebase functions:log`.
- راقب: نسبة الفشل، زمن التنفيذ، وأخطاء إسناد الفاعل.
